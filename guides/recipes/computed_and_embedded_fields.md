# Computed and embedded fields

Flop applies filter and order parameters to columns. Sometimes the value you
want to filter or order by is not a column: it is the result of a SQL function,
a value inside a JSON document, a field of an embedded schema, or a column cast
as a different type.

We can solve this by adding a lateral join on a subquery that selects the
computed value and configuring a join field for it.

Lateral joins are supported by PostgreSQL and MySQL. SQLite does not support
them.

## Query

This query adds an inner lateral join that selects the lowercased name into a
virtual field.

```elixir
import Ecto.Query

query =
  from p in MyApp.Pet,
    inner_lateral_join: c in fragment("SELECT lower(?) AS name_lower", p.name),
    on: true,
    as: :computed,
    select_merge: %{name_lower: c.name_lower}
```

The select assumes that the schema declares the field with
`field :name_lower, :string, virtual: true`.

You only need to select the value if you want to apply cursor pagination and
sort by it, since Flop extracts the cursor value from the result set. With a
custom `cursor_value_func`, you can select it in any shape.

## Ecto schema

In the Ecto schema, you define a join field that points at the binding of the
lateral join and mark it as filterable and sortable.

```elixir
use Flop.Schema

@flop_options [
  filterable: [:name_lower],
  sortable: [:name_lower],
  adapter_opts: [
    join_fields: [
      name_lower: [
        binding: :computed,
        field: :name_lower,
        path: [:name_lower],
        ecto_type: :string
      ]
    ]
  ]
]
```

The `path` option tells Flop where to read the value from the returned struct
when it builds a pagination cursor. Without it, Flop looks under
`[binding, field]`, which is where a join on an association puts the value. A
lateral join has no association, so the path points at the virtual field
instead.

## Built query

When you run `Flop.validate_and_run(query, params, for: MyApp.Pet)`, Flop adds
`where` and `order by` clauses depending on the given parameters.

```sql
SELECT p0."id", p0."name", f1."name_lower"
FROM "pets" AS p0
INNER JOIN LATERAL (SELECT lower(p0."name") AS name_lower) AS f1 ON TRUE
WHERE (f1."name_lower" LIKE $1)
ORDER BY f1."name_lower" DESC
LIMIT $2
```

The same approach works for any expression the database can evaluate per row,
including `unaccent(?)`, `?::text` and `tsvector` expressions.

## Query plans

A lateral join that references nothing but the parent row does not cost anything
at run time. PostgreSQL flattens it away, so the query plan looks exactly the
same as if you had used the expression directly in the `WHERE` clause.

```text
-- lateral join
Seq Scan on pets p0  (cost=0.00..10.45 rows=1 width=8)
  Filter: (lower((name)::text) ~~ '%geo%'::text)

-- plain where clause
Seq Scan on pets p0  (cost=0.00..10.45 rows=1 width=8)
  Filter: (lower((name)::text) ~~ '%geo%'::text)
```

The same holds for ordering.

It also means that a functional index can be used with lateral join.

```sql
CREATE INDEX pets_name_lower_idx ON pets (lower(name));
```

```text
Index Scan using pets_name_lower_idx on pets p0
  (cost=0.29..8.30 rows=1 width=8)
  Index Cond: (lower((name)::text) = 'pet500'::text)
```

## JSONB and embedded schema fields

If you need to filter or sort on fields within a JSONB column, including
embedded fields using `embeds_one`, you can add a lateral join here as well and
use any of the available JSON operators.

```elixir
query =
  from p in MyApp.Pet,
    inner_lateral_join:
      c in fragment("SELECT ? ->> 'nickname' AS nickname", p.profile),
    on: true,
    as: :profile_fields
```

```elixir
join_fields: [
  nickname: [
    binding: :profile_fields,
    field: :nickname,
    ecto_type: :string
  ]
]
```

A compound field may list join fields, so one parameter can search several
values of the document or of multiple documents at once.

```elixir
join_fields: [
  nickname: [binding: :profile_fields, field: :nickname, ecto_type: :string],
  city: [binding: :profile_fields, field: :city, ecto_type: :string]
],
compound_fields: [
  nickname_or_city: [:nickname, :city]
]
```

`Flop.named_bindings/3` reports the binding of a join field that sits inside a
compound field, so `Flop.with_named_bindings/4` adds the lateral join for a
filter on the compound field as well. Custom fields cannot be part of a compound
field.

Since `->>` returns text, a field that is not a string needs to be cast in the
fragment, and the `ecto_type` has to match that cast.

```elixir
query =
  from p in MyApp.Pet,
    inner_lateral_join:
      c in fragment("SELECT (? ->> 'age')::int AS age", p.profile),
    on: true,
    as: :profile_fields,
    select_merge: %{age: c.age}
```

```elixir
join_fields: [
  profile_age: [
    binding: :profile_fields,
    field: :age,
    path: [:age],
    ecto_type: :integer
  ]
]
```

An `embeds_many` field is a JSON array. Expanding it with `jsonb_array_elements`
returns one row per element, which duplicates the parent row and skews both the
total count and the page size, so aggregate the elements in the subquery
instead. The subquery already runs once per parent row, so a plain aggregate
returns a single row and needs no `GROUP BY`.

```elixir
query =
  from p in MyApp.Pet,
    inner_lateral_join:
      c in fragment(
        """
        SELECT bool_or(t.value ->> 'name' = 'best in show') AS has_award
        FROM jsonb_array_elements(?) AS t
        """,
        p.awards
      ),
    on: true,
    as: :awards
```

```elixir
join_fields: [
  has_award: [
    binding: :awards,
    field: :has_award,
    ecto_type: :boolean
  ]
]
```

An empty or `NULL` array yields a single row with `NULL` in it, so the inner
join does not drop the parent row. `count(*)` and `max(...)` work the same way
if you want to filter or sort by the number of elements or by the largest value
among them.

## Complete example

```elixir
defmodule MyApp.Pet do
  use Ecto.Schema
  use Flop.Schema

  @flop_options [
    filterable: [:name_lower],
    sortable: [:name, :name_lower],
    default_order: %{
      order_by: [:name],
      order_directions: [:asc]
    },
    adapter_opts: [
      join_fields: [
        name_lower: [
          binding: :computed,
          field: :name_lower,
          path: [:name_lower],
          ecto_type: :string
        ]
      ]
    ]
  ]

  schema "pets" do
    field :name, :string
    field :name_lower, :string, virtual: true
  end
end

defmodule MyApp.Pets do
  import Ecto.Query

  alias MyApp.Pet

  def list_pets(params) do
    query =
      from p in Pet,
        inner_lateral_join:
          c in fragment("SELECT lower(?) AS name_lower", p.name),
        on: true,
        as: :computed,
        select_merge: %{name_lower: c.name_lower}

    Flop.validate_and_run(query, params, for: Pet)
  end
end
```
