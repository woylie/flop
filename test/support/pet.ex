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
    compound_fields: [
      full_name: [:family_name, :given_name],
      pet_and_owner_name: [:name, :owner_name]
    ],
    join_fields: [owner_age: {:owner, :age}, owner_name: {:owner, :name}]
  }

  schema "pets" do
    field :age, :integer
    field :family_name, :string
    field :given_name, :string
    field :name, :string
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

  def random_value_for_compound_field(
        %__MODULE__{family_name: family_name, given_name: given_name},
        :full_name
      ),
      do: Enum.random([family_name, given_name])

  def random_value_for_compound_field(
        %__MODULE__{name: name, owner: %Owner{name: owner_name}},
        :pet_and_owner_name
      ),
      do: Enum.random([name, owner_name])
end
