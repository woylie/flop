defmodule Flop do
  @moduledoc """
  Documentation for Flop.
  """

  require Ecto.Query

  alias Ecto.Query

  defstruct [
    :limit,
    :offset,
    :order_by,
    :order_directions
  ]

  def query(q, flop) do
    q
    |> order_by(flop)
    |> limit(flop)
    |> offset(flop)
  end

  ## Ordering

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

  ## Offset/limit pagination

  def limit(q, %Flop{limit: nil}), do: q
  def limit(q, %Flop{limit: limit}), do: Query.limit(q, ^limit)

  def offset(q, %Flop{offset: nil}), do: q
  def offset(q, %Flop{offset: offset}), do: Query.offset(q, ^offset)
end
