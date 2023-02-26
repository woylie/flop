defmodule Flop.Fruit do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  @derive {Flop.Schema,
           filterable: [:name, :family, :attributes, :extra],
           sortable: [:name],
           default_limit: 60,
           default_order: %{
             order_by: [:name],
             order_directions: [:asc]
           },
           pagination_types: [:first, :last, :offset]}

  schema "fruits" do
    field :name, :string
    field :family, :string
    field :attributes, :map
    field :extra, {:map, :string}
  end
end
