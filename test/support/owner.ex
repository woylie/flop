defmodule Flop.Owner do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  import Ecto.Query

  alias Flop.Pet

  @derive {
    Flop.Schema,
    filterable: [:name, :species],
    sortable: [:name, :age, :pet_count],
    join_fields: [pet_age: {:pets, :age}],
    dynamic_fields: [
      pet_count: "[pets: p], count(p.id)"
    ]
  }

  schema "owners" do
    field :age, :integer
    field :email, :string
    field :name, :string

    has_many :pets, Pet
  end
end
