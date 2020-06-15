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
      iex> {:ok, flop} = Flop.validate(params, for: Flop.Pet)
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
      iex> Flop.Pet |> Flop.query(flop)
      #Ecto.Query<from p0 in Flop.Pet, order_by: [asc: p0.name, asc: p0.age], \
  limit: ^5>

  Use `Flop.validate_and_run/3`, `Flop.validate_and_run!/3`, `Flop.run/3`,
  `Flop.all/3` or `Flop.meta/3` to query the database. Also consult the
  [readme](https://hexdocs.pm/flop/readme.html) for more details.
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
  alias Flop.Meta

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
      iex> Flop.query(Flop.Pet, flop)
      #Ecto.Query<from p0 in Flop.Pet, limit: ^10, offset: ^19>

  Or enhance an already defined query:

      iex> require Ecto.Query
      iex> flop = %Flop{limit: 10}
      iex> Flop.Pet |> Ecto.Query.where(species: "dog") |> Flop.query(flop)
      #Ecto.Query<from p0 in Flop.Pet, where: p0.species == \"dog\", limit: ^10>
  """
  @spec query(Queryable.t(), Flop.t()) :: Queryable.t()
  def query(q, flop) do
    q
    |> filter(flop)
    |> order_by(flop)
    |> paginate(flop)
  end

  @doc """
  Applies the given Flop to the given queryable and returns all matchings
  entries.

      iex> Flop.all(Flop.Pet, %Flop{}, repo: Flop.Repo)
      []

  You can also configure a default repo in your config files:

      config :flop, repo: MyApp.Repo

  This allows you to omit the third argument:

      iex> Flop.all(Flop.Pet, %Flop{})
      []
  """
  @doc since: "0.6.0"
  @spec all(Queryable.t(), Flop.t(), keyword) :: [any]
  def all(q, flop, opts \\ []) do
    repo = opts[:repo] || default_repo() || raise no_repo_error("all")
    apply(repo, :all, [query(q, flop)])
  end

  @doc """
  Applies the given Flop to the given queryable, retrieves the data and the
  meta data.

  This function does not validate the given flop parameters. You can validate
  the parameters with `Flop.validate/2` or `Flop.validate!/2`, or you can use
  `Flop.validate_and_run/3` or `Flop.validate_and_run!/3` instead of this
  function.

      iex> {data, meta} = Flop.run(Flop.Pet, %Flop{})
      iex> data == []
      true
      iex> match?(%Flop.Meta{}, meta)
      true
  """
  @doc since: "0.6.0"
  @spec run(Queryable.t(), Flop.t(), keyword) :: {[any], Meta.t()}
  def run(q, flop, opts \\ []) do
    repo = opts[:repo] || default_repo() || raise no_repo_error("run")
    {all(q, flop, repo: repo), meta(q, flop, repo: repo)}
  end

  @doc """
  Validates the given flop parameters and retrieves the data and meta data on
  success.

      iex> {:ok, {[], %Flop.Meta{}}} =
      ...>   Flop.validate_and_run(Flop.Pet, %Flop{}, for: Flop.Pet)
      iex> {:error, %Ecto.Changeset{} = changeset} =
      ...>   Flop.validate_and_run(Flop.Pet, %Flop{limit: -1})
      iex> changeset.errors
      [
        limit: {"must be greater than %{number}",
          [validation: :number, kind: :greater_than, number: 0]}
      ]

  ## Options

  - `for`: Passed to `Flop.validate/2`.
  - `repo`: The `Ecto.Repo` module. Required if no default repo is configured.
  """
  @doc since: "0.6.0"
  @spec validate_and_run(Queryable.t(), map | Flop.t(), keyword) ::
          {:ok, {[any], Meta.t()}} | {:error, Changeset.t()}
  def validate_and_run(q, flop, opts \\ []) do
    repo = opts[:repo] || default_repo() || raise no_repo_error("run")
    validate_opts = Keyword.take(opts, [:for])

    with {:ok, flop} <- validate(flop, validate_opts) do
      {:ok, {all(q, flop, repo: repo), meta(q, flop, repo: repo)}}
    end
  end

  @doc """
  Same as `Flop.validate_and_run/3`, but raises on error.
  """
  @doc since: "0.6.0"
  @spec validate_and_run!(Queryable.t(), map | Flop.t(), keyword) ::
          {[any], Meta.t()}
  def validate_and_run!(q, flop, opts \\ []) do
    repo = opts[:repo] || default_repo() || raise no_repo_error("run")
    validate_opts = Keyword.take(opts, [:for])
    flop = validate!(flop, validate_opts)
    {all(q, flop, repo: repo), meta(q, flop, repo: repo)}
  end

  @doc """
  Returns the total count of entries matching the filter conditions of the
  Flop.

  The pagination and ordering option are disregarded.

      iex> Flop.count(Flop.Pet, %Flop{}, repo: Flop.Repo)
      0

  You can also configure a default repo in your config files:

      config :flop, repo: MyApp.Repo

  This allows you to omit the third argument:

      iex> Flop.count(Flop.Pet, %Flop{})
      0
  """
  @doc since: "0.6.0"
  @spec count(Queryable.t(), Flop.t(), keyword) :: non_neg_integer
  def count(q, flop, opts \\ []) do
    repo = opts[:repo] || default_repo() || raise no_repo_error("count")
    apply(repo, :aggregate, [filter(q, flop), :count])
  end

  @doc """
  Returns meta information for the given query and flop that can be used for
  building the pagination links.

      iex> Flop.meta(Flop.Pet, %Flop{limit: 10}, repo: Flop.Repo)
      %Flop.Meta{
        current_offset: 0,
        current_page: 1,
        has_next_page?: false,
        has_previous_page?: false,
        next_offset: nil,
        next_page: nil,
        page_size: 10,
        previous_offset: nil,
        previous_page: nil,
        total_count: 0,
        total_pages: 0
      }

  The function returns both the current offset and the current page, regardless
  of the pagination type. If the offset lies in between pages, the current page
  number is rounded up. This means that it is possible that the values for
  `current_page` and `next_page` can be identical. This can only occur if you
  use offset/limit based pagination with arbitrary offsets, but in that case,
  you will use the `previous_offset`, `current_offset` and `next_offset` values
  to render the pagination links anyway, so this shouldn't be a problem.
  """
  @doc since: "0.6.0"
  @spec meta(Queryable.t(), Flop.t(), keyword) :: Meta.t()
  def meta(q, flop, opts \\ []) do
    repo = opts[:repo] || default_repo() || raise no_repo_error("meta")

    total_count = count(q, flop, repo: repo)
    page_size = flop.page_size || flop.limit
    total_pages = get_total_pages(total_count, page_size)
    current_offset = get_current_offset(flop)
    current_page = get_current_page(flop, total_pages)

    {has_previous_page?, previous_offset, previous_page} =
      get_previous(current_offset, current_page, page_size)

    {has_next_page?, next_offset, next_page} =
      get_next(
        current_offset,
        current_page,
        page_size,
        total_count,
        total_pages
      )

    %Meta{
      current_offset: current_offset,
      current_page: current_page,
      has_next_page?: has_next_page?,
      has_previous_page?: has_previous_page?,
      next_offset: next_offset,
      next_page: next_page,
      page_size: page_size,
      previous_offset: previous_offset,
      previous_page: previous_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  defp get_previous(offset, current_page, limit) do
    has_previous? = offset > 0
    previous_offset = if has_previous?, do: max(0, offset - limit), else: nil
    previous_page = if current_page > 1, do: current_page - 1, else: nil

    {has_previous?, previous_offset, previous_page}
  end

  defp get_next(_, _, nil = _page_size, _, _) do
    {false, nil, nil}
  end

  defp get_next(current_offset, _, _, total_count, _)
       when current_offset >= total_count - 1 do
    {false, nil, nil}
  end

  defp get_next(current_offset, current_page, page_size, _, total_pages) do
    {true, current_offset + page_size, min(total_pages, current_page + 1)}
  end

  defp get_total_pages(0, _), do: 0
  defp get_total_pages(_, nil), do: 1
  defp get_total_pages(total_count, limit), do: ceil(total_count / limit)

  defp get_current_offset(%Flop{offset: nil, page: nil}), do: 0

  defp get_current_offset(%Flop{offset: nil, page: page, page_size: page_size}),
    do: (page - 1) * page_size

  defp get_current_offset(%Flop{offset: offset}), do: offset

  defp get_current_page(%Flop{offset: nil, page: nil}, _), do: 1
  defp get_current_page(%Flop{offset: nil, page: page}, _), do: page

  defp get_current_page(%Flop{limit: limit, offset: offset, page: nil}, total),
    do: min(ceil(offset / limit) + 1, total)

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
    do: Query.where(q, ^[{field, value}])

  def filter(q, %Filter{field: field, op: :!=, value: value}),
    do: Query.where(q, [r], field(r, ^field) != ^value)

  def filter(q, %Filter{field: field, op: :=~, value: value}) do
    query_value = "%#{value}%"
    Query.where(q, [r], ilike(field(r, ^field), ^query_value))
  end

  def filter(q, %Filter{field: field, op: :>=, value: value}),
    do: Query.where(q, [r], field(r, ^field) >= ^value)

  def filter(q, %Filter{field: field, op: :<=, value: value}),
    do: Query.where(q, [r], field(r, ^field) <= ^value)

  def filter(q, %Filter{field: field, op: :>, value: value}),
    do: Query.where(q, [r], field(r, ^field) > ^value)

  def filter(q, %Filter{field: field, op: :<, value: value}),
    do: Query.where(q, [r], field(r, ^field) < ^value)

  def filter(q, %Filter{field: field, op: :in, value: value}),
    do: Query.where(q, [r], field(r, ^field) in ^value)

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

      iex> params = %{"order_by" => ["species"]}
      iex> {:error, changeset} = Flop.validate(params, for: Flop.Pet)
      iex> changeset.valid?
      false
      iex> [order_by: {msg, [_, {_, enum}]}] = changeset.errors
      iex> msg
      "has an invalid entry"
      iex> enum
      [:name, :age]

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

  @doc """
  Same as `Flop.validate/2`, but raises an `Ecto.InvalidChangesetError` if the
  parameters are invalid.
  """
  @doc since: "0.5.0"
  @spec validate!(Flop.t() | map, keyword) :: Flop.t()
  def validate!(flop, opts \\ []) do
    case validate(flop, opts) do
      {:ok, flop} ->
        flop

      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :replace, changeset: changeset
    end
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

  defp default_repo, do: Application.get_env(:flop, :repo)

  defp no_repo_error(function_name),
    do: """
    No repo specified. You can specify the repo either by passing it
    explicitly:

        Flop.#{function_name}(Flop.Pet, %Flop{}, repo: MyApp.Repo)

    Or you can configure a default repo in your config:

        config :flop, repo: MyApp.Repo
    """
end
