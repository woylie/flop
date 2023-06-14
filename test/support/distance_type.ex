defmodule Flop.DistanceType do
  @moduledoc "A simple distance ecto type"

  use Ecto.Type

  alias Flop.Distance

  @impl Ecto.Type
  def type, do: :distance

  @impl Ecto.Type
  def cast(nil), do: {:ok, nil}
  def cast(%Distance{} = distance), do: {:ok, distance}

  def cast(%{unit: unit, value: distance}),
    do: {:ok, %Distance{unit: unit, value: distance}}

  def cast(_), do: :error

  @impl Ecto.Type
  def dump(nil), do: {:ok, nil}

  def dump(%Distance{} = distance),
    do: {:ok, {distance.unit, distance.value}}

  def dump(_), do: :error

  @impl Ecto.Type
  def load(nil), do: {:ok, nil}

  def load({unit, distance}),
    do: {:ok, %Distance{unit: unit, value: distance}}
end
