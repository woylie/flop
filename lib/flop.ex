defmodule Flop do
  @moduledoc """
  Documentation for Flop.
  """
  use Ecto.Schema

  require Ecto.Query

  import Ecto.Changeset

  alias __MODULE__.Filter
  alias Ecto.Query
  alias Flop.CustomTypes.OrderDirection

  @type t :: %__MODULE__{
          filters: [Filter.t() | nil],
          limit: pos_integer | nil,
          offset: non_neg_integer | nil,
          order_by: atom | String.t() | nil,
          order_directions: [:asc | :desc] | nil,
          page: pos_integer | nil,
          page_size: pos_integer | nil
        }

  embedded_schema do
    field :limit, :integer
    field :offset, :integer
    field :order_by, {:array, :string}
    field :order_directions, {:array, OrderDirection}
    field :page, :integer
    field :page_size, :integer

    embeds_many :filters, Filter
  end

  defmodule Filter do
    @moduledoc """
    Defines a filter.
    """

    use Ecto.Schema

    alias Flop.CustomTypes.Operator

    @type t :: %__MODULE__{
            field: atom | String.t(),
            op: op,
            value: any
          }

    @type op :: :== | :!= | :<= | :< | :>= | :>

    embedded_schema do
      field :field, :string
      field :op, Operator
      field :value, :string
    end

    def changeset(filter, %{} = params \\ %{}) do
      filter
      |> cast(params, [:field, :op, :value])
    end
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

  def filter(q, %Filter{field: field, op: :==, value: value}),
    do: Query.where(q, ^field == ^value)

  def filter(q, %Filter{field: field, op: :!=, value: value}),
    do: Query.where(q, ^field != ^value)

  def filter(q, %Filter{field: field, op: :>=, value: value}),
    do: Query.where(q, ^field >= ^value)

  def filter(q, %Filter{field: field, op: :<=, value: value}),
    do: Query.where(q, ^field <= ^value)

  def filter(q, %Filter{field: field, op: :>, value: value}),
    do: Query.where(q, ^field > ^value)

  def filter(q, %Filter{field: field, op: :<, value: value}),
    do: Query.where(q, ^field < ^value)

  ## Validation

  def validate(%Flop{} = flop) do
    flop
    |> Map.from_struct()
    |> changeset()
    |> apply_action(:insert)
  end

  def validate(%{} = params) do
    params
    |> changeset()
    |> apply_action(:replace)
  end

  def changeset(%{} = params \\ %{}) do
    %Flop{}
    |> cast(params, [
      :limit,
      :offset,
      :order_by,
      :order_directions,
      :page,
      :page_size
    ])
    |> cast_embed(:filters)
    |> validate_number(:limit, greater_than: 0)
    |> validate_number(:offset, greater_than_or_equal_to: 0)
    |> validate_number(:page, greater_than: 0)
    |> validate_number(:page_size, greater_than: 0)
  end
end
