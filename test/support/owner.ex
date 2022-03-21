defmodule Flop.Owner do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  alias Flop.Pet

  @derive {
    Flop.Schema,
    filterable: [:name],
    sortable: [:name, :age],
    join_fields: [pet_age: {:pets, :age}],
    compound_fields: [age_and_pet_age: [:age, :pet_age]]
  }

  schema "owners" do
    field :age, :integer
    field :email, :string
    field :name, :string
    field :tags, {:array, :string}, default: []

    has_many :pets, Pet
  end
end
