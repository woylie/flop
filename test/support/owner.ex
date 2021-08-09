defmodule Flop.Owner do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  alias Flop.Pet

  @derive {
    Flop.Schema,
    filterable: [:name, :species],
    sortable: [:name, :age],
    compound_fields: [full_name: [:family_name, :given_name]],
    join_fields: [pet_age: {:pets, :age}]
  }

  schema "owners" do
    field :age, :integer
    field :email, :string
    field :family_name, :string
    field :given_name, :string
    field :name, :string

    has_many :pets, Pet
  end
end
