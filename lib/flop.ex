defmodule Flop do
  @moduledoc """
  Flop is a helper library for filtering, ordering and pagination with Ecto.

  ## Usage

  Derive `Flop.Schema` in your Ecto schemas.

      defmodule Pet do
        use Ecto.Schema

        @derive {Flop.Schema,
                 filterable: [:name, :species], sortable: [:name, :age]}

        schema "pets" do
          field :name, :string
          field :age, :integer
          field :species, :string
          field :social_security_number, :string
        end
      end

  Validate a parameter map to get a `t:Flop.t/0` struct with `Flop.validate/1`.
  Add the `t:Flop.t/0` to a `t:Ecto.Queryable.t/0` with `Flop.query/2`.

      iex> params = %{"order_by" => ["name", "age"], "limit" => 5}
      iex> {:ok, flop} = Flop.validate(params, for: Pet)
      {:ok,
       %Flop{
         filters: [],
         limit: 5,
         offset: nil,
         order_by: [:name, :age],
         order_directions: nil,
         page: nil,
         page_size: nil
       }}
      iex> Pet |> Flop.query(flop)
      #Ecto.Query<from p0 in Pet, order_by: [asc: p0.name, asc: p0.age], \
  limit: ^5>
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Flop.Schema

  alias Ecto.Changeset
  alias Ecto.Query
  alias Ecto.Queryable
  alias Flop.CustomTypes.ExistingAtom
  alias Flop.CustomTypes.OrderDirection
  alias Flop.Filter

  require Ecto.Query

  @typedoc """
  Represents the supported order direction values.
  """
  @type order_direction ::
          :asc
          | :asc_nulls_first
          | :asc_nulls_last
          | :desc
          | :desc_nulls_first
          | :desc_nulls_last

  @typedoc """
  Represents the query parameters for filtering, ordering and pagination.

  ### Fields

  - `limit`, `offset`: Used for pagination. May not be used together with
    `page` and `page_size`.
  - `page`, `page_size`: Used for pagination. May not be used together with
    `limit` and `offset`.
  - `order_by`: List of fields to order by. Fields can be restricted by
    deriving `Flop.Schema` in your Ecto schema.
  - `order_directions`: List of order directions applied to the fields defined
    in `order_by`. If empty or the list is shorter than the `order_by` list,
    `:asc` will be used as a default for each missing order direction.
  - `filters`: List of filters, see `t:Flop.Filter.t/0`.
  """
  @type t :: %__MODULE__{
          filters: [Filter.t() | nil],
          limit: pos_integer | nil,
          offset: non_neg_integer | nil,
          order_by: [atom | String.t()] | nil,
          order_directions: [order_direction()] | nil,
          page: pos_integer | nil,
          page_size: pos_integer | nil
        }

  @primary_key false
  embedded_schema do
    field :limit, :integer
    field :offset, :integer
    field :order_by, {:array, ExistingAtom}
    field :order_directions, {:array, OrderDirection}
    field :page, :integer
    field :page_size, :integer

    embeds_many :filters, Filter
  end

  @doc """
  Adds clauses for filtering, ordering and pagination to a
  `t:Ecto.Queryable.t/0`.

  The parameters are represented by the `t:Flop.t/0` type. Any `nil` values
  will be ignored.

  ## Examples

      iex> flop = %Flop{limit: 10, offset: 19}
      iex> Flop.query(Pet, flop)
      #Ecto.Query<from p0 in Pet, limit: ^10, offset: ^19>

  Or enhance an already defined query:

      iex> require Ecto.Query
      iex> flop = %Flop{limit: 10}
      iex> Pet |> Ecto.Query.where(species: "dog") |> Flop.query(flop)
      #Ecto.Query<from p0 in Pet, where: p0.species == \"dog\", limit: ^10>
  """
  @spec query(Queryable.t(), Flop.t()) :: Queryable.t()
  def query(q, flop) do
    q
    |> filter(flop)
    |> order_by(flop)
    |> paginate(flop)
  end

  ## Ordering

  @doc """
  Applies the `order_by` and `order_directions` parameters of a `t:Flop.t/0`
  to an `t:Ecto.Queryable.t/0`.

  Used by `Flop.query/2`.
  """
  @spec order_by(Queryable.t(), Flop.t()) :: Queryable.t()
  def order_by(q, %Flop{order_by: nil}), do: q

  def order_by(q, %Flop{order_by: fields, order_directions: directions}) do
    Query.order_by(q, ^prepare_order(fields, directions))
  end

  @spec prepare_order([atom], [order_direction()]) :: [
          {order_direction(), atom}
        ]
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

  @doc """
  Applies the pagination parameters of a `t:Flop.t/0` to an
  `t:Ecto.Queryable.t/0`.

  The function supports both `offset`/`limit` based pagination and
  `page`/`page_size` based pagination.

  If you validated the `t:Flop.t/0` with `Flop.validate/1` before, you can be
  sure that the given `t:Flop.t/0` only has pagination parameters set for one
  pagination method. If you pass an unvalidated `t:Flop.t/0` that has
  pagination parameters set for multiple pagination methods, this function
  will arbitrarily only apply one of the pagination methods.

  Used by `Flop.query/2`.
  """
  @spec paginate(Queryable.t(), Flop.t()) :: Queryable.t()
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

  @spec limit(Queryable.t(), pos_integer | nil) :: Queryable.t()
  defp limit(q, nil), do: q
  defp limit(q, limit), do: Query.limit(q, ^limit)

  @spec offset(Queryable.t(), non_neg_integer | nil) :: Queryable.t()
  defp offset(q, nil), do: q
  defp offset(q, offset), do: Query.offset(q, ^offset)

  ## Filter

  @doc """
  Applies the `filter` parameter of a `t:Flop.t/0` to an `t:Ecto.Queryable.t/0`.

  Used by `Flop.query/2`.
  """
  @spec filter(Queryable.t(), Flop.t()) :: Queryable.t()
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

  def filter(q, %Filter{field: field, op: :=~, value: value}) do
    query_value = "%#{value}%"
    Query.where(q, ilike(^field, ^query_value))
  end

  def filter(q, %Filter{field: field, op: :>=, value: value}),
    do: Query.where(q, ^field >= ^value)

  def filter(q, %Filter{field: field, op: :<=, value: value}),
    do: Query.where(q, ^field <= ^value)

  def filter(q, %Filter{field: field, op: :>, value: value}),
    do: Query.where(q, ^field > ^value)

  def filter(q, %Filter{field: field, op: :<, value: value}),
    do: Query.where(q, ^field < ^value)

  ## Validation

  @doc """
  Validates a `t:Flop.t/0`.

  ## Examples

      iex> params = %{"limit" => 10, "offset" => 0, "texture" => "fluffy"}
      iex> Flop.validate(params)
      {:ok,
       %Flop{
         filters: [],
         limit: 10,
         offset: 0,
         order_by: nil,
         order_directions: nil,
         page: nil,
         page_size: nil
       }}

      iex> flop = %Flop{offset: -1}
      iex> {:error, changeset} = Flop.validate(flop)
      iex> changeset.valid?
      false
      iex> changeset.errors
      [
        offset: {"must be greater than or equal to %{number}",
         [validation: :number, kind: :greater_than_or_equal_to, number: 0]}
      ]

  It also makes sure that only one pagination method is used.

      iex> params = %{limit: 10, offset: 0, page: 5, page_size: 10}
      iex> {:error, changeset} = Flop.validate(params)
      iex> changeset.valid?
      false
      iex> changeset.errors
      [limit: {"cannot combine multiple pagination types", []}]

  If you derived `Flop.Schema` in your Ecto schema to define the filterable
  and sortable fields, you can pass the module name to the function to validate
  that only allowed fields are used.

      iex> params = %{"order_by" => ["social_security_number"]}
      iex> {:error, changeset} = Flop.validate(params, for: Pet)
      iex> changeset.valid?
      false
      iex> [order_by: {msg, [_, {_, enum}]}] = changeset.errors
      iex> msg
      "has an invalid entry"
      iex> enum
      [:name, :age, :species]

  Note that currently, trying to use an existing field that is not allowed as
  seen above will result in the error message `has an invalid entry`, while
  trying to use a field name that does not exist in the schema (or more
  precisely: a field name that doesn't exist as an atom) will result in
  the error message `is invalid`. This might change in the future.
  """
  @spec validate(Flop.t() | map, keyword) ::
          {:ok, Flop.t()} | {:error, Changeset.t()}
  def validate(flop, opts \\ [])

  def validate(%Flop{} = flop, opts) do
    flop
    |> Map.from_struct()
    |> changeset(opts)
    |> apply_action(:insert)
  end

  def validate(%{} = params, opts) do
    params
    |> changeset(opts)
    |> apply_action(:replace)
  end

  @spec changeset(map, keyword) :: Changeset.t()
  defp changeset(%{} = params, opts) do
    %Flop{}
    |> cast(params, [
      :limit,
      :offset,
      :order_by,
      :order_directions,
      :page,
      :page_size
    ])
    |> cast_embed(:filters, with: {Filter, :changeset, [opts]})
    |> validate_number(:limit, greater_than: 0)
    |> validate_within_max_limit(:limit, opts[:for])
    |> validate_number(:offset, greater_than_or_equal_to: 0)
    |> validate_number(:page, greater_than: 0)
    |> validate_number(:page_size, greater_than: 0)
    |> validate_exclusive([[:limit, :offset], [:page, :page_size]],
      message: "cannot combine multiple pagination types"
    )
    |> validate_sortable(opts[:for])
    |> validate_page_and_page_size(opts[:for])
    |> put_default_limit(opts[:for])
  end

  @spec validate_exclusive(Changeset.t(), [[atom]], keyword) :: Changeset.t()
  defp validate_exclusive(changeset, field_groups, opts) do
    changed_field_groups =
      Enum.filter(field_groups, fn fields ->
        Enum.any?(fields, fn field -> !is_nil(get_field(changeset, field)) end)
      end)

    if length(changed_field_groups) > 1 do
      key =
        changed_field_groups
        |> List.first()
        |> Enum.reject(&is_nil(get_field(changeset, &1)))
        |> List.first()

      add_error(
        changeset,
        key,
        opts[:message] || "invalid combination of field groups"
      )
    else
      changeset
    end
  end

  @spec validate_sortable(Changeset.t(), module | nil) :: Changeset.t()
  defp validate_sortable(changeset, nil), do: changeset

  defp validate_sortable(changeset, module) do
    sortable_fields =
      module
      |> struct()
      |> sortable()

    validate_subset(changeset, :order_by, sortable_fields)
  end

  @spec validate_page_and_page_size(Changeset.t(), module | nil) ::
          Changeset.t()
  defp validate_page_and_page_size(changeset, module) do
    page = get_field(changeset, :page)
    page_size = get_field(changeset, :page_size)

    if !is_nil(page) || !is_nil(page_size) do
      changeset
      |> validate_required([:page, :page_size])
      |> validate_within_max_limit(:page_size, module)
    else
      changeset
    end
  end

  @spec validate_within_max_limit(Changeset.t(), atom, module | nil) ::
          Changeset.t()
  defp validate_within_max_limit(changeset, _field, nil), do: changeset

  defp validate_within_max_limit(changeset, field, module) do
    max_limit = module |> struct() |> max_limit()

    if is_nil(max_limit),
      do: changeset,
      else: validate_number(changeset, field, less_than_or_equal_to: max_limit)
  end

  defp put_default_limit(changeset, nil), do: changeset

  defp put_default_limit(%Changeset{valid?: false} = changeset, _),
    do: changeset

  defp put_default_limit(changeset, module) do
    default_limit = module |> struct() |> default_limit()

    if is_nil(default_limit) do
      changeset
    else
      limit = get_field(changeset, :limit)
      page_size = get_field(changeset, :page_size)

      if is_nil(limit) && is_nil(page_size) do
        put_change(changeset, :limit, default_limit)
      else
        changeset
      end
    end
  end
end
