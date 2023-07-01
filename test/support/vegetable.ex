defmodule MyApp.Vegetable do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  @derive {Flop.Schema,
           filterable: [:name, :family, :with_bindings],
           sortable: [:name],
           default_limit: 60,
           default_order: %{
             order_by: [:name],
             order_directions: [:asc]
           },
           pagination_types: [:page],
           custom_fields: [
             with_bindings: [
               filter: {__MODULE__, :custom_filter, []},
               bindings: [:curious]
             ]
           ]}

  schema "vegetables" do
    field :name, :string
    field :family, :string
  end
end
