defmodule MyApp.Vegetable do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  @derive {Flop.Schema,
           filterable: [:name, :family],
           sortable: [:name],
           default_limit: 60,
           default_order: %{
             order_by: [:name],
             order_directions: [:asc]
           },
           pagination_types: [:page]}

  schema "vegetables" do
    field :name, :string
    field :family, :string
  end
end
