defmodule Flop.Pet do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  @derive {Flop.Schema,
           filterable: [:name, :species], sortable: [:name, :age, :species]}

  schema "pets" do
    field :name, :string
    field :age, :integer
    field :species, :string
    field :social_security_number, :string
  end
end
