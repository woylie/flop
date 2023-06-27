defmodule MyApp.WalkingDistances do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema
  import Ecto.Query

  alias Ecto.Changeset
  alias Flop.DistanceType

  @derive {
    Flop.Schema,
    filterable: [
      :trip
    ],
    sortable: [:trip],
    default_order: %{
      order_by: [:trip],
      order_directions: [:desc]
    }
  }

  schema "walking_distances" do
    field :trip, DistanceType
  end

  def changeset(%__MODULE__{} = module, attr),
    do: Changeset.cast(module, attr, [:trip])
end
