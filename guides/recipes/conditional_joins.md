# Conditional joins

Flop does not add joins to your query. A join field points at a named binding,
and that binding has to be present in the query you pass to Flop. The
straightforward way is to add every join up front, but then, the database will
join tables that most requests neither filter nor order by.

With `Flop.with_named_bindings/4`, you pass a function that knows how to add
each binding, and Flop applies it only for the bindings the given parameters
need.

## Query

In this example, we are going to add a `join_assocs/2` function to the schema
module. Each binding is covered by its own function clause.

```elixir
defmodule MyApp.Pet do
  use Ecto.Schema

  import Ecto.Query

  # ...

  def join_assocs(query, :owner) do
    join(query, :left, [pet: p], o in assoc(p, :owner), as: :owner)
  end

  def join_assocs(query, :breed) do
    join(query, :left, [pet: p], b in assoc(p, :breed), as: :breed)
  end
end
```

The function takes the query and the name of a binding and returns the query
with that binding added. It has the same arguments and the same return value as
the one you pass to `Ecto.Query.with_named_binding/3`.

We are using a left join here, because an inner join would drop every pet
without an owner or breed.

`Flop.with_named_bindings/4` needs a validated `Flop` struct, so validate the
parameters first and run the query in a second step.

```elixir
def list_pets(params) do
  opts = [for: Pet]

  with {:ok, flop} <- Flop.validate(params, opts) do
    Pet
    |> from(as: :pet)
    |> Flop.with_named_bindings(flop, &Pet.join_assocs/2, opts)
    |> Flop.run(flop, opts)
  end
end
```

Aliasing the source with `as: :pet` lets the callback refer to it by name.

## Required bindings

`Flop.with_named_bindings/4` determines the bindings with
`Flop.named_bindings/3`, which you can also call on its own. It returns:

- the binding of every join field in the filters or in the order clause
- the bindings of the join fields inside a compound field
- the bindings you configured with the `bindings` option of a custom field

Filters with a `nil` value are left out, and Flop casts a blank string to `nil`,
so an empty input in a filter form does not result in a binding.

The callback has to handle every binding in that list. If a join field points at
the source binding, add a clause that returns the query unchanged.

```elixir
def join_assocs(query, :pet), do: query
```

## Joins you always need

Some joins are needed regardless of the parameters, because the select clause or
a preload uses them. Add those first and let Flop add the rest.

```elixir
def list_pets(params) do
  opts = [for: Pet]

  with {:ok, flop} <- Flop.validate(params, opts) do
    Pet
    |> from(as: :pet)
    |> join_required_assocs([:owner])
    |> Flop.with_named_bindings(flop, &Pet.join_assocs/2, opts)
    |> preload([owner: o], owner: o)
    |> Flop.run(flop, opts)
  end
end

defp join_required_assocs(query, bindings) do
  Enum.reduce(bindings, query, fn binding, query ->
    Ecto.Query.with_named_binding(query, binding, &Pet.join_assocs/2)
  end)
end
```

`Ecto.Query.with_named_binding/3` returns the query unchanged if the binding is
already there, and `Flop.with_named_bindings/4` goes through it, so a binding
you added yourself is not added a second time.

## Intermediate joins

A nested association needs the join in between. The callback can add it by
calling itself through `Ecto.Query.with_named_binding/3`.

```elixir
def join_assocs(query, :owner) do
  join(query, :left, [pet: p], o in assoc(p, :owner), as: :owner)
end

def join_assocs(query, :address) do
  query
  |> Ecto.Query.with_named_binding(:owner, &join_assocs/2)
  |> join(:left, [owner: o], a in assoc(o, :address), as: :address)
end
```

The same check applies here, so the intermediate join is added once, no matter
how many of the requested fields sit behind it.

## Joins that also select

A callback can do more than join. The lateral join for a computed field also
selects the value, which is then only in the result when the binding is needed.

```elixir
def join_assocs(query, :computed) do
  from p in query,
    inner_lateral_join: c in fragment("SELECT lower(?) AS name_lower", p.name),
    on: true,
    as: :computed,
    select_merge: %{name_lower: c.name_lower}
end
```

Here `name_lower` is `nil` on the returned structs when neither the filters nor
the order refer to it. If you use the value outside of Flop, for example to
display it, add the join unconditionally instead.

Lateral joins are supported by PostgreSQL and MySQL. SQLite does not support
them.

## Counting

With page or offset pagination, Flop counts with the query you pass it, so the
count query has the same conditional joins. It counts without the order clause,
so the joins that only the order needs do nothing for the count.

`order: false` gives you the bindings for the filters only. Build a second query
with it and pass it as `count_query`.

```elixir
def list_pets(params) do
  opts = [for: Pet]

  with {:ok, flop} <- Flop.validate(params, opts) do
    base = from(Pet, as: :pet)

    query = Flop.with_named_bindings(base, flop, &Pet.join_assocs/2, opts)

    count_query =
      Flop.with_named_bindings(
        base,
        flop,
        &Pet.join_assocs/2,
        Keyword.put(opts, :order, false)
      )

    Flop.run(query, flop, Keyword.put(opts, :count_query, count_query))
  end
end
```

## Complete example

```elixir
defmodule MyApp.Pet do
  use Ecto.Schema

  import Ecto.Query

  use Flop.Schema

  @flop_options [
    filterable: [:name, :owner_name, :breed_name],
    sortable: [:name, :owner_name, :breed_name],
    default_order: %{
      order_by: [:name],
      order_directions: [:asc]
    },
    adapter_opts: [
      join_fields: [
        owner_name: [
          binding: :owner,
          field: :name,
          ecto_type: :string
        ],
        breed_name: [
          binding: :breed,
          field: :name,
          ecto_type: :string
        ]
      ]
    ]
  ]

  schema "pets" do
    field :name, :string

    belongs_to :owner, MyApp.Owner
    belongs_to :breed, MyApp.Breed
  end

  def join_assocs(query, :owner) do
    join(query, :left, [pet: p], o in assoc(p, :owner), as: :owner)
  end

  def join_assocs(query, :breed) do
    join(query, :left, [pet: p], b in assoc(p, :breed), as: :breed)
  end
end

defmodule MyApp.Pets do
  import Ecto.Query

  alias MyApp.Pet

  def list_pets(params) do
    opts = [for: Pet]

    with {:ok, flop} <- Flop.validate(params, opts) do
      Pet
      |> from(as: :pet)
      |> Flop.with_named_bindings(flop, &Pet.join_assocs/2, opts)
      |> Flop.run(flop, opts)
    end
  end
end
```
