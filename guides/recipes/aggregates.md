# Aggregates and grouped queries

The query Flop builds can be reused for aggregates, and a grouped query can be
passed to Flop like any other.

## An aggregate over the filtered rows

A total for the whole filtered set, rather than for the current page, needs the
filters without the limit. `Flop.filter/3` applies the filter parameters and
nothing else.

```elixir
def list_pets(params) do
  opts = [for: Pet]

  with {:ok, flop} <- Flop.validate(params, opts) do
    {pets, meta} = Flop.run(Pet, flop, opts)
    total = Pet |> Flop.filter(flop, opts) |> Repo.aggregate(:sum, :price)

    {:ok, {pets, meta, total}}
  end
end
```

The sum covers every pet that matches the filters. `Repo.aggregate/3` also takes
`:count`, `:avg`, `:min` and `:max`.

If you pass the query returned by `Flop.query/3` instead, the aggregate is
computed over one page, since that query includes the limit and the offset.

## Grouped queries

Group and select in the query you pass to Flop.

```elixir
query =
  from p in Pet,
    group_by: p.species,
    select: %{species: p.species, total: sum(p.price)}

Flop.validate_and_run(query, %{page: 1, page_size: 10}, for: Pet)
```

Filters apply before the grouping, since Flop adds them to the `WHERE` clause.
`meta.total_count` is the number of groups, because Flop counts a grouped query
over a subquery.

## Sorting by an aggregate

Name the aggregate in the select clause with `Ecto.Query.API.selected_as/2` and
declare it as an alias field.

```elixir
use Flop.Schema

@flop_options [
  filterable: [:species],
  sortable: [:species, :total],
  adapter_opts: [alias_fields: [:total]]
]
```

```elixir
query =
  from p in Pet,
    group_by: p.species,
    select: %{
      species: p.species,
      total: p.price |> sum() |> selected_as(:total)
    }

params = %{order_by: [:total], order_directions: [:desc]}

Flop.validate_and_run(query, params, for: Pet)
```

An alias field cannot be filtered on, because PostgreSQL does not allow a select
alias in a `WHERE` clause, and it cannot be used as an order field with cursor
pagination. Use page or offset pagination when the order is an aggregate.

To sort a list of records by an aggregate of their children instead of grouping
them, use a lateral join, as in the [to-many joins recipe](to_many_joins.md).
