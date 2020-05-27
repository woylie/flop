defmodule Flop.Fruit do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  @derive {Flop.Schema,
           filterable: [:name, :family], sortable: [:name], default_limit: 50}

  schema "fruits" do
    field :name, :string
    field :family, :string
  end
end
