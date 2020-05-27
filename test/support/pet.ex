defmodule Flop.Pet do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:name, :species], sortable: [:name, :age], max_limit: 20
  }

  schema "pets" do
    field :name, :string
    field :age, :integer
    field :species, :string
  end
end
