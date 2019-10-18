defmodule Flop do
  @moduledoc """
  Documentation for Flop.
  """

  require Ecto.Query

  alias Ecto.Query

  defstruct [:order_by, :order_directions]

  def query(q, flop) do
    order_by(q, flop)
  end

  def order_by(q, %Flop{order_by: nil}), do: q

  def order_by(q, %Flop{order_by: fields, order_directions: directions}) do
    Query.order_by(q, ^prepare_order(fields, directions))
  end

  defp prepare_order(fields, directions) do
    directions = directions || []
    field_count = length(fields)
    direction_count = length(directions)

    directions =
      if direction_count < field_count,
        do: directions ++ List.duplicate(:asc, field_count - direction_count),
        else: directions

    Enum.zip(directions, fields)
  end
end
