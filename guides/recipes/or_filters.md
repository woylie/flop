# Filters with OR

Flop combines filters with `AND`. There is no parameter format for an `OR`
between two filters, but a compound field or a custom field can cover a lot of
cases.

## The same value across several fields

A compound field applies one filter value to several fields, and the `_or`
operators combine the parts with `OR`.

```elixir
@derive {Flop.Schema,
         filterable: [:name_or_species],
         sortable: [:name],
         adapter_opts: [
           compound_fields: [name_or_species: [:name, :species]]
         ]}
```

```elixir
%{filters: [%{field: :name_or_species, op: :ilike_or, value: "ada dog"}]}
```

The value is split on whitespace, and a row matches if any word matches any of
the fields. `:ilike_and` requires every word to match, in any of the fields.

Compound fields only work with string columns.

## Different conditions

A compound field always applies the same comparison to every field it lists. For
an `OR` between conditions that differ, we can add a custom field. Its filter
function receives the value and builds the `where` clause itself, so it can use
`or`.

```elixir
defmodule MyApp.Filters do
  import Ecto.Query

  def cheap_or_cat(query, %Flop.Filter{value: value}, _opts) do
    %{"max_price" => max_price, "species" => species} = value

    where(query, [p], p.price <= ^max_price or p.species == ^species)
  end
end
```

```elixir
adapter_opts: [
  custom_fields: [
    cheap_or_cat: [
      filter: {MyApp.Filters, :cheap_or_cat, []},
      ecto_type: :map,
      operators: [:==]
    ]
  ]
]
```

```elixir
%{
  filters: [
    %{
      field: :cheap_or_cat,
      op: :==,
      value: %{"max_price" => 10, "species" => "cat"}
    }
  ]
}
```

The `ecto_type` describes the filter value, which is a map here. The function
ignores the operator, and `operators: [:==]` keeps the parameters from offering
comparisons that have no effect.

## Building the condition dynamically

`:in` covers a list of values on one field, and a compound field covers one
string comparison on several fields. Neither covers a list of values on several
fields, and neither works when the number of conditions is only known at run
time. `Ecto.Query.dynamic/2` builds such a condition.

```elixir
defmodule MyApp.Filters do
  import Ecto.Query

  def any_name(query, %Flop.Filter{value: values}, _opts)
      when is_list(values) do
    condition =
      Enum.reduce(values, dynamic(false), fn value, acc ->
        dynamic([p], ^acc or p.name == ^value or p.nickname == ^value)
      end)

    where(query, ^condition)
  end
end
```

```elixir
custom_fields: [
  any_name: [
    filter: {MyApp.Filters, :any_name, []},
    ecto_type: {:array, :string},
    operators: [:==]
  ]
]
```

`dynamic(false)` is the neutral element of `or`: a list with one value produces
one condition, and an empty list matches nothing.
