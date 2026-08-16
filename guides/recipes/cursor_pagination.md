# Cursor pagination

A cursor contains the order values of one row. Paging forward means asking for
the rows that come after those values.

The examples use six pets: three named Ada, aged 3, 5 and 7, then Bo aged 1, and
Cy and Dee with no age at all.

## Trade-offs

Offset and page pagination count rows from the start of the result set, so a
page depends on how many rows come before it. A cursor names a position instead,
which gives it three advantages:

- Paging is stable. An insert or a delete before the current position does not
  move the rows after it, so no row is skipped or repeated between two requests.
- Every page costs the same. The database compares the order values against the
  cursor and reads `first + 1` rows, which an index on the order fields serves
  directly, while `OFFSET 10_000` reads and discards ten thousand rows first.
- A page is one query instead of two, because there is no count query.

The last one is also what you give up. `meta.total_count` and `meta.total_pages`
are `nil`, and there is no page number and no way to jump to one, since a cursor
is a position and not an index. You can use `Flop.count/3` if you need the
number, but you cannot easily get a page number from the cursor and the
count.

```elixir
{:ok, {pets, meta}} = Flop.validate_and_run(Pet, params, for: Pet)
count = Flop.count(Pet, meta.flop, for: Pet)
```

## Parameters

Cursor pagination has four parameters. `first` and `after` page forward, `last`
and `before` page backward. The cursors come from the metadata of the previous
request. The parameters are based on the
[GraphQL Cursor Connection Specification, section 4](https://relay.dev/graphql/connections.htm#sec-Arguments).

```elixir
{:ok, {pets, meta}} =
  Flop.validate_and_run(Pet, %{first: 2, order_by: [:name, :id]}, for: Pet)

{:ok, {next_pets, next_meta}} =
  Flop.validate_and_run(
    Pet,
    %{first: 2, after: meta.end_cursor, order_by: [:name, :id]},
    for: Pet
  )
```

Both cursors are exclusive: the row a cursor points at is not repeated on the
adjacent page.

`meta.has_next_page?` costs no second query. Flop asks the database for one row
more than requested and checks whether it arrived. `has_previous_page?` is not
read from the data at all when paging forward: it is `true` whenever `after` was
set. Paging backward with `last` and `before` reverses this, so
`has_previous_page?` comes from the extra row and `has_next_page?` from the
presence of `before`.

## The order clause decides the cursor

A cursor holds the fields in the order clause, so the combination of order field
values must be unique across the table. In our example, `name` is not unique, so
using it as the only order field leads to unstable pagination.

```elixir
%{first: 2, order_by: [:name]}
```

| page | rows | cursor |
|---|---|---|
| 1 | Ada 3, Ada 5 | `%{name: "Ada"}` |
| 2 | Bo 1, Cy | |

The third Ada is gone. Page 2 asks for the rows after the name "Ada", and all
three Adas share that name. Six rows go in, five come out, and nothing in the
metadata says so.

This is why Flop appends the primary key to every order. The same walk returns
every row, and the parameters stay as they were:

| page | rows |
|---|---|
| 1 | Ada 3, Ada 5 |
| 2 | Ada 7, Bo 1 |
| 3 | Cy, Dee |

The appended fields are the schema's `:tiebreaker`. They are not part of the
`Flop` struct, so they never appear in the query parameters, but they do appear
in every cursor. `Flop.ordering/2` returns the order that is applied.

Change the direction, name other fields, or turn the tiebreaker off when the
order is already unique:

```elixir
@derive {Flop.Schema,
         filterable: [],
         sortable: [:id, :name],
         tiebreaker: {:primary_key, :desc}}
```

> #### Tiebreaker fields have to be selected {: .warning}
>
> The tiebreaker is read from the returned record like any other order field,
> so a query that selects a subset of the fields has to include it.

This is also why `Flop.push_order/3`, and the table component in `Flop.Phoenix`
that uses it, put a newly selected field in front of the existing order instead
of replacing it. Replacing the order could drop the field that made it unique.

## Nullable fields

Nullable columns are supported.

```elixir
%{first: 2, order_by: [:age]}
```

| page | `:asc` | `:desc` |
|---|---|---|
| 1 | Bo 1, Ada 3 | Cy, Dee |
| 2 | Ada 5, Ada 7 | Ada 7, Ada 5 |
| 3 | Cy, Dee | Ada 3, Bo 1 |

The plain order directions `:asc` or `:desc` leave the placement of null values
to the database. PostgreSQL sorts nulls last ascending and first descending,
while SQLite and MySQL do the opposite. The four explicit directions
`:asc_nulls_first`, `:asc_nulls_last`, `:desc_nulls_first` and
`:desc_nulls_last` mean the same on every database.

The cursor comparison has to match the sort, so Flop needs to know which way
the database sorts before it can build a cursor query with a plain direction.
It determines this from the repo, which means cursor pagination with `:asc` or
`:desc` raises when no repo can be resolved.

## Reading the cursor value

Flop reads the cursor value of each order field from the returned row with
`Flop.Schema.get_field/2`. For a field of the schema this is the struct field of
the same name, and there is nothing to configure.

A join field is read through its `path`, which defaults to `[binding, field]`.
Every step of the path has to lead to a single record rather than a list, so a
`belongs_to` or a `has_one` works and a `has_many` does not. A value selected
into a virtual field needs `path` pointing at that field.

A custom field is read through its `path` as well, which defaults to the field
name. Since a custom field is an expression and not a column, you have to select
it yourself, usually by merging the same dynamic that `field_dynamic` returns
into a virtual field.

```elixir
Pet
|> select_merge(^%{age_score: CustomFields.age_score(factor: 2)})
|> Flop.validate_and_run(params, for: Pet)
```

> #### Cursor values have to be selected {: .warning}
>
> Flop adds the `WHERE` and `ORDER BY` clauses, but the `SELECT` is your
> responsibility. If a cursor value is missing from the row, pagination breaks,
> and unless an unloaded association is involved, it does so silently.

If the query selects something other than the schema struct, pass a
`cursor_value_func` that knows the shape. A map with the order fields as
top-level keys works without one.

```elixir
Flop.validate_and_run(query, params,
  for: Pet,
  cursor_value_func: fn %{pet: pet}, order_by ->
    Map.take(pet, order_by)
  end
)
```

Compound and alias fields cannot be ordered by at all when using cursor
pagination, since neither is a column. `Flop.validate/2` returns an error naming
the fields.

```elixir
[order_by: [
  {"cursor pagination is not supported for compound and alias fields",
   [unsupported_fields: [:rank]]}
]]
```

## Cursor values and types

A cursor is `:erlang.term_to_binary/1` with Base64 on top, so the values inside
it keep their type. A `DateTime` in an order field survives the round trip and
needs nothing from you, and the cursor itself is a plain string.

On the way back in, Flop casts every cursor value with the Ecto type of its
order field, and rejects the cursor if a value does not cast.

```elixir
[after: [{"is invalid", []}]]
```

Cursors are also rejected if their size exceeds `max_cursor_size`, which
defaults to 8192 bytes, or if the Erlang term is compressed or contains unsafe
data.

## Stale and invalid cursors

Nothing binds a cursor to the row it came from. Flop compares values, so:

- Deleting the row a cursor points at changes nothing. The next page still
  starts after the same values.
- Editing a row's order values moves it. It can turn up on a page you already
  saw, or vanish from the pages that are left.
- A cursor remains valid across inserts.

A cursor that does not fit the current parameters is rejected. That happens when
a client keeps a cursor after changing the sort, so that its fields no longer
match the order clause:

```elixir
[after: [{"does not match order fields", []}]]
```

## Relay connections

The GraphQL Cursor Connection Specification also describes the response format,
and `Flop.Relay` produces it from a result.

```elixir
{:ok, result} = Flop.validate_and_run(Pet, params, for: Pet)
connection = Flop.Relay.connection_from_result(result)
```

You can use `Flop.Relay.edges_from_result/2` and
`Flop.Relay.page_info_from_meta/1` if you assemble the connection yourself, for
example to add fields to an edge. For the `absinthe_relay` side, see the Relay
and Absinthe section of the README.
