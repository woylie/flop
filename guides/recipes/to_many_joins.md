# Joins on to-many associations

A join on a `has_many` or `many_to_many` association returns one row per
matching child. Flop applies filters, ordering, counting and pagination to those
rows, so a pet with three matching toys is three rows in the page and counts
three times in the total.

The examples below use pets and toys, where Alpha has three toys named "ball"
and one named "rope", Bravo has one "ball", and Charlie has one "rope".

## Duplicate rows

```elixir
defmodule MyApp.Pet do
  use Ecto.Schema

  @derive {Flop.Schema,
           filterable: [:name, :toy_name],
           sortable: [:name],
           adapter_opts: [
             join_fields: [
               toy_name: [binding: :toys, field: :name, ecto_type: :string]
             ]
           ]}

  schema "pets" do
    field :name, :string
    has_many :toys, MyApp.Toy
  end
end
```

```elixir
query =
  from p in MyApp.Pet,
    as: :pet,
    inner_join: t in assoc(p, :toys),
    as: :toys

params = %{filters: [%{field: :toy_name, op: :==, value: "ball"}]}

Flop.validate_and_run(query, params, for: MyApp.Pet)
```

Two pets have a ball, and the query returns four rows: Alpha three times and
Bravo once. `meta.total_count` is 4, and `meta.total_pages` is derived from that
count, so it is wrong as well.

## Filtering with EXISTS

Instead of joining, we can ask whether a matching child exists. This needs no
join, so nothing is duplicated.

```elixir
defmodule MyApp.Filters do
  import Ecto.Query

  def toy_name(query, %Flop.Filter{value: value}, _opts) do
    where(
      query,
      [p],
      exists(
        from t in MyApp.Toy,
          where: t.pet_id == parent_as(:pet).id and t.name == ^value,
          select: 1
      )
    )
  end
end
```

```elixir
adapter_opts: [
  custom_fields: [
    toy_name: [
      filter: {MyApp.Filters, :toy_name, []},
      ecto_type: :string
    ]
  ]
]
```

The subquery refers to the outer row with `parent_as(:pet)`, so the query needs
`as: :pet` on its source. The same filter now returns two rows and a total count
of 2.

## Distinct rows

If the query needs the join for other reasons, `distinct: true` removes the
duplicates. Ecto counts a distinct query over a subquery, so the count is
correct as well.

```elixir
query =
  from p in MyApp.Pet,
    as: :pet,
    inner_join: t in assoc(p, :toys),
    as: :toys,
    distinct: true
```

It comes with one restriction. PostgreSQL requires every `ORDER BY` expression
of a `SELECT DISTINCT` to appear in the select list, so ordering by a joined
column fails:

```text
ERROR 42P10 (invalid_column_reference) for SELECT DISTINCT,
ORDER BY expressions must appear in select list
```

Passing a separate `count_query` corrects the count and leaves the duplicates in
the page, so it is not an alternative.

Use `distinct: true`, not `distinct` with expressions. The latter builds
`DISTINCT ON`, and Ecto adds those expressions to the `ORDER BY` in front of the
order parameters. The requested order then only breaks ties, and cursor
pagination repeats rows without an error, because Flop compares the order fields
while the rows arrive in another order.

## Sorting on children

A pet with three toys has three toy names, so ordering by a to-many join field
is ambiguous. Aggregate the children instead. A lateral join with an aggregate
returns one row per parent.

```elixir
toy_stats =
  from t in MyApp.Toy,
    where: t.pet_id == parent_as(:pet).id,
    select: %{toy_count: count(t.id)}

query =
  from p in MyApp.Pet,
    as: :pet,
    inner_lateral_join: s in subquery(toy_stats),
    on: true,
    as: :toy_stats,
    select_merge: %{toy_count: s.toy_count}
```

```elixir
join_fields: [
  toy_count: [
    binding: :toy_stats,
    field: :toy_count,
    path: [:toy_count],
    ecto_type: :integer
  ]
]
```

With `toy_count` as a virtual field on the schema, ordering by it returns Alpha
with 4, Bravo with 1 and Charlie with 1, and the total count is 3. `min` and
`max` work the same way.

## Cursor pagination

Ordering by a to-many join field also breaks the cursors. Flop reads the cursor
value by following `path` through the returned struct, and a `has_many` step is
a list instead of a row, so the value is `nil`. Flop skips `nil` cursor fields
and compares the remaining order fields, which skips rows. Ordering by
`[:toy_name, :name]` with `first: 2`, the first page holds two of Alpha's four
rows, and the next page starts after the name "Alpha".

The aggregate above works with cursors, since it is one value per parent and
part of the select clause.

## Preloads

A preload does not remove the duplicates. Ecto nests the children of the
repeated rows into one struct per parent, so the page looks correct while
everything else still applies to the joined rows.

```elixir
preload(query, [toys: t], toys: t)
```

- `meta.total_count` is still 4.
- The limit applies to the joined rows, so a page size of 2 returns one pet with
  two of its three matching toys.
- The preloaded children are the joined rows, so Alpha comes back with three
  toys named "ball" and without its rope.

Preloading without the binding loads the association in a query of its own,
which keeps it complete, but the same pet is then in the page three times.
Combine it with `distinct: true`.

```elixir
preload(query, :toys)
```

## Which one to use

Which method works best depends on what you filter or order by:

- Filtering on a child while paging over the parents: a custom field with
  `EXISTS`.
- You already need the join in the query anyway, for a select or a preload:
  `distinct: true`, ordering by columns of the parent.
- Ordering or filtering by something derived from the children, such as how many
  there are or the largest value: an aggregate in a lateral join.

A join field on the child table is not an option for the first case. It names a
binding, so the join has to be in the query, and the join is what duplicates the
rows. Flop also builds the condition itself, as a comparison on the joined
column, and `EXISTS` is not a comparison.

Cursor pagination works with all three, as long as the order fields come from
the parent row or from the aggregate. A to-many join field in the order clause
never works with cursors, whichever setup you pick.

The complete example below uses the first option, since it is the common case.

## Complete example

```elixir
defmodule MyApp.Pet do
  use Ecto.Schema

  @derive {Flop.Schema,
           filterable: [:name, :toy_name],
           sortable: [:name],
           default_order: %{
             order_by: [:name],
             order_directions: [:asc]
           },
           adapter_opts: [
             custom_fields: [
               toy_name: [
                 filter: {MyApp.Filters, :toy_name, []},
                 ecto_type: :string
               ]
             ]
           ]}

  schema "pets" do
    field :name, :string
    has_many :toys, MyApp.Toy
  end
end

defmodule MyApp.Filters do
  import Ecto.Query

  def toy_name(query, %Flop.Filter{value: value}, _opts) do
    where(
      query,
      [p],
      exists(
        from t in MyApp.Toy,
          where: t.pet_id == parent_as(:pet).id and t.name == ^value,
          select: 1
      )
    )
  end
end

defmodule MyApp.Pets do
  import Ecto.Query

  alias MyApp.Pet

  def list_pets(params) do
    query =
      from p in Pet,
        as: :pet,
        preload: :toys

    Flop.validate_and_run(query, params, for: Pet)
  end
end
```
