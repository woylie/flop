defmodule Flop.Owner do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:name, :species],
    sortable: [:name, :age],
    join_fields: [pet_age: {:pets, :age}]
  }

  schema "owners" do
    field :name, :string
    field :email, :string
    field :age, :integer
  end
end
