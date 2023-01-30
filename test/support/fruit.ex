defmodule Flop.Fruit do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  alias Flop.Owner

  @derive {Flop.Schema,
           filterable: [
             :name,
             :family,
             :attributes,
             :extra,
             :owner_attributes,
             :owner_extra
           ],
           sortable: [:name],
           join_fields: [
             owner_attributes: [
               binding: :owner,
               field: :attributes,
               path: [:owner, :attributes],
               ecto_type: {:map, :string}
             ],
             owner_extra: [
               binding: :owner,
               field: :extra,
               path: [:owner, :extra],
               ecto_type: :map
             ]
           ],
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

    belongs_to :owner, Owner
  end
end
