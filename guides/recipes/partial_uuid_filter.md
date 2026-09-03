# Partial UUID filter

Flop attempts to cast filter values as the type of the underlying Ecto schema
field. If the value cannot be cast, an error is returned for that filter value,
or if the `replace_invalid_params` option is set, the invalid filter will be
removed from the query.

In the case of binary IDs (UUIDs), this means that the user has to pass
the full ID to apply a filter on the ID column. In some cases, you may prefer
to allow users to search for partial UUIDs. The pattern operators such as
`:like` are not available for binary ID fields, since none of the supported
databases matches a text pattern against such a column, but you can achieve the
same with a custom filter.

## Filter module

First, we add a generic custom filter function for partial UUID matches to a
separate module.

```elixir
defmodule MyApp.Filters do
  import Ecto.Query

  def partial_uuid_filter(q, %Flop.Filter{value: value}, opts) do
    field = Keyword.fetch!(opts, :field)

    case Ecto.Type.cast(Ecto.UUID, value) do
      {:ok, id} -> where(q, [r], field(r, ^field) == ^id)
      :error -> partial_match(q, field, uuid_fragment(value))
    end
  end

  defp partial_match(q, _field, ""), do: where(q, [r], false)

  defp partial_match(q, field, search) do
    where(q, [r], like(type(field(r, ^field), :string), ^"%#{search}%"))
  end

  defp uuid_fragment(value) do
    value |> String.downcase() |> String.replace(~r/[^0-9a-f-]/, "")
  end
end
```

The function takes an Ecto query and a `Flop.Filter` struct as arguments. It
also accepts a `field` option, which must be set to the Ecto schema field on
which this filter is applied. This way, we can reuse the custom filter for
filtering on foreign keys as well.

We first attempt to cast the filter value as an `Ecto.UUID`. If this succeeds,
we know that we have a complete and valid UUID and can apply an equality filter
directly.

If the value cannot be cast, we treat it as a partial ID. We cast the column as
a string, because the binary ID type does not support `like`, and we build the
search term from the characters a UUID can contain: hexadecimal digits and
dashes. Removing everything else is simpler than escaping `%`, `_` and `\`, and
it does not depend on the database having a default escape character, which
SQLite does not. A user searching for `%` gets no results instead of every row.

Since the search term can end up empty, we match on that case and return no
rows. Without it, a term of `zzz` would become `%%` and match everything.

We use `like` rather than `ilike`, which SQLite and MySQL do not support. A
UUID is rendered in lowercase, so downcasing the search term gives the same
result.

Note that we ignore the filter operator here. If you want to support several
filter operators, you can match on the `op` field of the `Flop.Filter` struct.

## MySQL

The MyXQL adapter stores a binary ID as the raw 16 bytes, so casting the column
as a string returns those bytes rather than the UUID as it is rendered. The
column has to be hexed instead, and the dashes have to be removed from the
search term, since `HEX` returns 32 characters without them.

```elixir
defp partial_match(q, field, search) do
  where(q, [r], like(fragment("LOWER(HEX(?))", field(r, ^field)), ^"%#{search}%"))
end

defp uuid_fragment(value) do
  value |> String.downcase() |> String.replace(~r/[^0-9a-f]/, "")
end
```

## Ecto schema

In the Ecto schema, we can now define a custom field that references our filter
function and pass the `field` as an option. We also need to mark the field as
filterable.

```elixir
use Flop.Schema

@flop_options [
  filterable: [:partial_id],
  # ...
  adapter_opts: [
    custom_fields: [
      partial_id: [
        filter: {MyApp.Filters, :partial_uuid_filter, [field: :id]},
        ecto_type: :string
      ]
    ]
  ]
]
```

## Complete example

```elixir
defmodule MyApp.Pet do
  use Ecto.Schema
  use Flop.Schema

  @flop_options [
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
    ]
  ]

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
      {:ok, id} -> where(q, [r], field(r, ^field) == ^id)
      :error -> partial_match(q, field, uuid_fragment(value))
    end
  end

  defp partial_match(q, _field, ""), do: where(q, [r], false)

  defp partial_match(q, field, search) do
    where(q, [r], like(type(field(r, ^field), :string), ^"%#{search}%"))
  end

  defp uuid_fragment(value) do
    value |> String.downcase() |> String.replace(~r/[^0-9a-f-]/, "")
  end
end
```
