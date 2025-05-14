# Partial UUID Filter

Flop attempts to cast filter values as the type of the underlying Ecto schema
field. If the value cannot be cast, an error is returned for that filter value,
or if the `replace_invalid_params` option is set, the invalid filter will be
removed from the query.

In the case of binary IDs (UUIDs), this means that the user has to pass
the full ID to apply a filter on the ID column. In some cases, you may prefer
to allow users to search for partial UUIDs. You can achieve this by defining a
custom filter.

## Filter Module

First, we add a generic custom filter function for partial UUID matches to a
separate module.

```elixir
defmodule MyApp.Filters do
  import Ecto.Query

  def partial_uuid_filter(q, %Flop.Filter{value: value}, opts) do
    field = Keyword.fetch!(opts, :field)

    case Ecto.Type.cast(Ecto.UUID, value) do
      {:ok, id} ->
        where(q, [r], field(r, ^field) == ^id)

      :error ->
        term = "%#{String.trim(value)}%"
        where(q, [r], ilike(type(field(r, ^field), :string), ^term))
    end
  end
end
```

The function takes an Ecto query and a `Flop.Filter` struct as
values. It also accepts a `field` option, which must be set to the Ecto schema
field on which this filter is applied. This way, we can reuse the custom
filter for filtering on foreign keys as well.

We first attempt to cast the filter value as an `Ecto.UUID`. If this succeeds,
we know that we have a complete and valid UUID and can apply an equality filter
directly.

If the value is not a valid `Ecto.UUID`, we have a partial ID. We create a
search term and apply an `ilike` function in the query. We have to cast the
column as a string, because the binary ID type does not support `ilike`.

Note that we ignore the filter operator here and always use `ilike`. If you want
to support other filter operators, you can match on the `op` field of the
`Flop.Filter` struct.

## Ecto Schema

In the Ecto schema, we can now define a custom field that references our filter
function and pass the `field` as an option. We also need to mark the field as
filterable.

```elixir
@derive {Flop.Schema,
         filterable: [:partial_id],
         # ...
         adapter_opts: [
           custom_fields: [
             partial_id: [
               filter: {MyApp.Filters, :partial_uuid_filter, [field: :id]},
               ecto_type: :string
             ]
           ]
         ]}
```

## Complete Example

```elixir
defmodule MyApp.Pet do
  use Ecto.Schema

  import Ecto.Query

  @derive {Flop.Schema,
           filterable: [:partial_id],
           sortable: [:name],
           default_order: %{
             order_by: [:name],
             order_directions: [:asc]
           },
           adapter_opts: [
             custom_fields: [
               partial_id: [
                 filter: {MyApp.Filters, :partial_uuid_filter, [field: :id]},
                 ecto_type: :string
               ]
             ]
           ]}

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "pets" do
    field :name, :string
  end
end

defmodule MyApp.Filters do
  import Ecto.Query

  def partial_uuid_filter(q, %Flop.Filter{value: value}, opts) do
    field = Keyword.fetch!(opts, :field)

    case Ecto.Type.cast(Ecto.UUID, value) do
      {:ok, id} ->
        where(q, [r], field(r, ^field) == ^id)

      :error ->
        term = "%#{String.trim(value)}%"
        where(q, [r], ilike(type(field(r, ^field), :string), ^term))
    end
  end
end
```
