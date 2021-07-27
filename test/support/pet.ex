defmodule Flop.Pet do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  alias Flop.Owner

  @derive {
    Flop.Schema,
    filterable: [:name, :owner_age, :owner_name, :species],
    sortable: [:name, :age],
    max_limit: 20,
    join_fields: [owner_name: {:owner, :name}]
  }

  schema "pets" do
    field :name, :string
    field :age, :integer
    field :species, :string

    belongs_to :owner, Owner
  end

  def get_field(%__MODULE__{owner: %Owner{age: age}}, :owner_age), do: age
  def get_field(%__MODULE__{owner: nil}, :owner_age), do: nil
  def get_field(%__MODULE__{owner: %Owner{name: name}}, :owner_name), do: name
  def get_field(%__MODULE__{owner: nil}, :owner_name), do: nil

  def get_field(%__MODULE__{} = pet, field)
      when field in [:name, :age, :species],
      do: Map.get(pet, field)
end
