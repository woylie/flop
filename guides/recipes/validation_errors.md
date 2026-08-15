# Validation errors

`Flop.validate/2` and `Flop.validate_and_run/3` return
`{:error, %Flop.Meta{}}` for invalid parameters. The errors are in
`meta.errors`, and the parameters that produced them are in `meta.params`.

## The shape

`meta.errors` is a keyword list in the format of
`Ecto.Changeset.traverse_errors(changeset, & &1)`: a key per parameter, and a
list of `{message, opts}` tuples per key.

```elixir
params = %{limit: 5_000, order_by: [:species]}
{:error, meta} = Flop.validate(params, for: MyApp.Pet)
```

```elixir
meta.errors == [
  limit: [
    {"must be less than or equal to %{number}",
     [validation: :number, kind: :less_than_or_equal_to, number: 1000]}
  ],
  order_by: [
    {"has an invalid entry",
     [
       validation: :subset,
       enum: [:name, :age, :mood, :owner_name, :owner_age]
     ]}
  ]
]
```

The message holds `%{key}` placeholders and the options hold the values to
interpolate. The options also name what would have been accepted: an `order_by`
error lists the sortable fields, an unknown filter field lists the filterable
fields, and an operator error lists the operators the field allows.

```elixir
params = %{filters: [%{field: :age, op: :ilike, value: 1}]}
{:error, meta} = Flop.validate(params, for: MyApp.Pet)

meta.errors[:filters] == [
  [
    op: [
      {"is invalid",
       [
         allowed_operators: [
           :==, :!=, :empty, :not_empty, :<=, :<, :>=, :>, :in, :not_in
         ]
       ]}
    ]
  ]
]
```

`meta.params` holds the parameters as they were passed, normalized to string
keys, and is only set when validation failed.

```elixir
meta.params == %{
  "filters" => [%{"field" => :age, "op" => :ilike, "value" => 1}]
}
```

## Filter errors

`meta.errors[:filters]` has one of two shapes:

- If there is an issue with the filters value itself, the value is a list of
  `{message, opts}` tuples.
- If there is an issue with individual filters, the value is a list with one
  entry per filter.

### Errors on the filter list itself

This happens if the value isn't a list, or if the list has more items than
`max_filters` allows.

```elixir
params = %{filters: for(_ <- 1..26, do: %{field: :name, op: :==, value: "a"})}
{:error, meta} = Flop.validate(params, for: MyApp.Pet)

meta.errors[:filters] == [
  {"must have at most %{count} items",
   [count: 20, validation: :length, kind: :max]}
]
```

```elixir
{:error, meta} = Flop.validate(%{filters: ""}, for: MyApp.Pet)

meta.errors[:filters] == [
  {"is invalid", [validation: :embed, type: {:array, :map}]}
]
```

The two shapes never mix, so `per_filter?/1` below only looks at the first
entry.

### Filter errors line up with filter parameters

Filters are a list, so their errors are a list of lists. The two lists have the
same length and the same order, and a filter without errors holds an empty list.

```elixir
params = %{
  filters: [
    %{field: :name, op: :==, value: "Ada"},
    %{field: :age, op: :==, value: "old"},
    %{field: :name, op: :==, value: "Bo"}
  ]
}

{:error, meta} = Flop.validate(params, for: MyApp.Pet)

meta.errors[:filters] == [[], [value: [{"is invalid", []}]], []]
```

We can zip the two lists to say which filter went wrong.

```elixir
defmodule MyApp.FlopErrors do
  def filter_errors(%Flop.Meta{} = meta) do
    filters = Map.get(meta.params, "filters", [])
    errors = Keyword.get(meta.errors, :filters, [])

    if is_list(filters) and per_filter?(errors) do
      filters
      |> Enum.zip(errors)
      |> Enum.flat_map(fn {filter, filter_errors} ->
        Enum.flat_map(filter_errors, fn {key, messages} ->
          Enum.map(messages, fn message ->
            %{
              field: filter["field"],
              op: filter["op"],
              value: filter["value"],
              key: key,
              message: translate(message)
            }
          end)
        end)
      end)
    else
      []
    end
  end

  defp per_filter?([first | _]), do: is_list(first)
  defp per_filter?([]), do: true

  defp translate({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", stringify(value))
    end)
  end

  defp stringify(value) when is_list(value),
    do: Enum.map_join(value, ", ", &to_string/1)

  defp stringify(value), do: to_string(value)
end
```

`translate/1` does the interpolation that every Ecto error message needs. Route
it through Gettext instead if the messages are user-facing in more than one
language.

`stringify/1` is needed because some option values are lists. `enum` and
`allowed_operators` hold lists of atoms, and `to_string/1` raises on those.

## Dropping bad parameters instead

An API that would rather serve a page than an error can set
`replace_invalid_params: true`. Flop then discards what it cannot use and
returns `{:ok, flop}`.

```elixir
params = %{limit: 5_000, filters: [%{field: :age, op: :==, value: "old"}]}
opts = [for: MyApp.Pet, replace_invalid_params: true]

{:ok, flop} = Flop.validate(params, opts)

{flop.limit, flop.filters} == {50, []}
```

The limit falls back to the default rather than to the maximum, and the invalid
filter is gone. Nothing reports what was dropped.

## Raising instead

`Flop.validate!/2` and `Flop.validate_and_run!/3` raise
`Flop.InvalidParamsError`, which holds the same `errors` and `params`.

```elixir
Flop.validate!(%{limit: 5_000}, for: MyApp.Pet)
** (Flop.InvalidParamsError) invalid Flop parameters
```

Flop does not depend on Plug, so nothing maps that exception to a status code.
In a Phoenix application, you can implement the `Plug.Exception` protocol to
turn a `Flop.InvalidParamsError` exception into a 400 response instead of a 500.

```elixir
defimpl Plug.Exception, for: Flop.InvalidParamsError do
  def status(_), do: 400
  def actions(_), do: []
end
```
