defmodule Flop do
  @moduledoc """
  Documentation for Flop.
  """

  require Ecto.Query

  alias Ecto.Query

  defstruct [
    :filters,
    :limit,
    :offset,
    :order_by,
    :order_directions,
    :page,
    :page_size
  ]

  defmodule Filter do
    @moduledoc """
    Defines a filter.
    """
    defstruct [:field, :op, :value]
  end

  def query(q, flop) do
    q
    |> filter(flop)
    |> order_by(flop)
    |> paginate(flop)
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

  ## Pagination

  def paginate(q, %Flop{limit: limit, offset: offset})
      when (is_integer(limit) and limit >= 1) or
             (is_integer(offset) and offset >= 0) do
    q
    |> limit(limit)
    |> offset(offset)
  end

  def paginate(q, %Flop{page: page, page_size: page_size})
      when is_integer(page) and is_integer(page_size) and
             page >= 1 and page_size >= 1 do
    q
    |> limit(page_size)
    |> offset((page - 1) * page_size)
  end

  def paginate(q, _), do: q

  ## Offset/limit pagination

  defp limit(q, nil), do: q
  defp limit(q, limit), do: Query.limit(q, ^limit)

  defp offset(q, nil), do: q
  defp offset(q, offset), do: Query.offset(q, ^offset)

  ## Filter

  def filter(q, %Flop{filters: nil}), do: q
  def filter(q, %Flop{filters: []}), do: q

  def filter(q, %Flop{filters: filters}) when is_list(filters) do
    Enum.reduce(filters, q, &filter(&2, &1))
  end

  def filter(_, %Filter{field: field, op: _, value: value})
      when is_nil(field) or is_nil(value) do
    raise ArgumentError
  end

  def filter(q, %Filter{field: field, op: "==", value: value}),
    do: Query.where(q, ^field == ^value)

  def filter(q, %Filter{field: field, op: "!=", value: value}),
    do: Query.where(q, ^field != ^value)

  def filter(q, %Filter{field: field, op: ">=", value: value}),
    do: Query.where(q, ^field >= ^value)

  def filter(q, %Filter{field: field, op: "<=", value: value}),
    do: Query.where(q, ^field <= ^value)

  def filter(q, %Filter{field: field, op: ">", value: value}),
    do: Query.where(q, ^field > ^value)

  def filter(q, %Filter{field: field, op: "<", value: value}),
    do: Query.where(q, ^field < ^value)
end
