defmodule MyApp.Owner do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  alias MyApp.Pet

  @derive {
    Flop.Schema,
    filterable: [:name],
    sortable: [:name, :age],
    join_fields: [pet_age: {:pets, :age}],
    compound_fields: [age_and_pet_age: [:age, :pet_age]],
    alias_fields: [:pet_count],
    default_pagination_type: :page
  }

  schema "owners" do
    field :age, :integer
    field :email, :string
    field :name, :string
    field :tags, {:array, :string}, default: []
    field :pet_count, :integer, virtual: true
    field :attributes, :map
    field :extra, {:map, :string}

    has_many :pets, Pet
  end
end
