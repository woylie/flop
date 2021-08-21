defmodule Flop do
  @moduledoc """
  Flop is a helper library for filtering, ordering and pagination with Ecto.

  ## Usage

  The simplest way of using this library is just to use
  `Flop.validate_and_run/3` and `Flop.validate_and_run!/3`. Both functions
  take a queryable and a parameter map, validate the parameters, run the query
  and return the query results and the meta information.

      iex> Flop.Repo.insert_all(Flop.Pet, [
      ...>   %{name: "Harry", age: 4, species: "C. lupus"},
      ...>   %{name: "Maggie", age: 1, species: "O. cuniculus"},
      ...>   %{name: "Patty", age: 2, species: "C. aegagrus"}
      ...> ])
      iex> params = %{order_by: ["name", "age"], page: 1, page_size: 2}
      iex> {:ok, {results, meta}} =
      ...>   Flop.validate_and_run(
      ...>     Flop.Pet,
      ...>     params,
      ...>     repo: Flop.Repo
      ...>   )
      iex> Enum.map(results, & &1.name)
      ["Harry", "Maggie"]
      iex> meta.total_count
      3
      iex> meta.total_pages
      2
      iex> meta.has_next_page?
      true

  Under the hood, these functions just call `Flop.validate/2` and `Flop.run/3`,
  which in turn calls `Flop.all/3` and `Flop.meta/3`. If you need finer control
  about if and when to execute each step, you can call those functions directly.

  See `Flop.Meta` for descriptions of the meta fields.

  ## Global configuration

  You can set some global options like the default Ecto repo via the application
  environment. All global options can be overridden by passing them directly to
  the functions or configuring the options for a schema module via
  `Flop.Schema`.

      import Config

      config :flop, repo: MyApp.Repo

  See `t:Flop.option/0` for a description of all available options.

  ## Schema options

  You can set some options for a schema by deriving `Flop.Schema`. The options
  are evaluated at the validation step.

      defmodule Pet do
        use Ecto.Schema

        @derive {Flop.Schema,
                 filterable: [:name, :species],
                 sortable: [:name, :age],
                 default_limit: 20,
                 max_limit: 100}

        schema "pets" do
          field :name, :string
          field :age, :integer
          field :species, :string
          field :social_security_number, :string
        end
      end

  You need to pass the schema to `Flop.validate/2` or any function that
  includes the validation step with the `:for` option.

      iex> params = %{"order_by" => ["name", "age"], "limit" => 5}
      iex> {:ok, flop} = Flop.validate(params, for: Flop.Pet)
      iex> flop.limit
      5

      iex> params = %{"order_by" => ["name", "age"], "limit" => 10_000}
      iex> {:error, changeset} = Flop.validate(params, for: Flop.Pet)
      iex> [{:limit, {msg, _}}] = changeset.errors
      iex> msg
      "must be less than or equal to %{number}"

      iex> params = %{"order_by" => ["name", "age"], "limit" => 10_000}
      iex> {:error, changeset} =
      ...>   Flop.validate_and_run(
      ...>     Flop.Pet,
      ...>     params,
      ...>     for: Flop.Pet
      ...>   )
      iex> [{:limit, {msg, _}}] = changeset.errors
      iex> msg
      "must be less than or equal to %{number}"

  ## Ordering

  To add an ordering clause to a query, you need to set the `:order_by` and
  optionally the `:order_directions` parameter. `:order_by` should be the list
  of fields, while `:order_directions` is a list of `t:Flop.order_direction/0`.
  `:order_by` and `:order_directions` are zipped when generating the `ORDER BY`
  clause. If no order directions are given, `:asc` is used as default.

      iex> params = %{
      ...>   "order_by" => ["name", "age"],
      ...>   "order_directions" => ["asc", "desc"]
      ...> }
      iex> {:ok, flop} = Flop.validate(params)
      iex> flop.order_by
      [:name, :age]
      iex> flop.order_directions
      [:asc, :desc]

  Flop uses these two fields instead of a keyword list, so that the order
  instructions can be easily passed in a query string.

  ## Pagination

  For queries using `OFFSET` and `LIMIT`, you have the choice between
  page-based pagination parameters:

      %{page: 5, page_size: 20}

  and offset-based pagination parameters:

      %{offset: 100, limit: 20}

  For cursor-based pagination, you can either use `:first`/`:after` or
  `:last`/`:before`. You also need to pass the `:order_by` parameter or set a
  default order for the schema via `Flop.Schema`.

      iex> Flop.Repo.insert_all(Flop.Pet, [
      ...>   %{name: "Harry", age: 4, species: "C. lupus"},
      ...>   %{name: "Maggie", age: 1, species: "O. cuniculus"},
      ...>   %{name: "Patty", age: 2, species: "C. aegagrus"}
      ...> ])
      iex>
      iex> # forward (first/after)
      iex>
      iex> params = %{first: 2, order_by: [:species, :name]}
      iex> {:ok, {results, meta}} = Flop.validate_and_run(Flop.Pet, params)
      iex> Enum.map(results, & &1.name)
      ["Patty", "Harry"]
      iex> meta.has_next_page?
      true
      iex> end_cursor = meta.end_cursor
      "g3QAAAACZAAEbmFtZW0AAAAFSGFycnlkAAdzcGVjaWVzbQAAAAhDLiBsdXB1cw=="
      iex> params = %{first: 2, after: end_cursor, order_by: [:species, :name]}
      iex> {:ok, {results, meta}} = Flop.validate_and_run(Flop.Pet, params)
      iex> Enum.map(results, & &1.name)
      ["Maggie"]
      iex> meta.has_next_page?
      false
      iex>
      iex> # backward (last/before)
      iex>
      iex> params = %{last: 2, order_by: [:species, :name]}
      iex> {:ok, {results, meta}} = Flop.validate_and_run(Flop.Pet, params)
      iex> Enum.map(results, & &1.name)
      ["Harry", "Maggie"]
      iex> meta.has_previous_page?
      true
      iex> start_cursor = meta.start_cursor
      "g3QAAAACZAAEbmFtZW0AAAAFSGFycnlkAAdzcGVjaWVzbQAAAAhDLiBsdXB1cw=="
      iex> params = %{last: 2, before: start_cursor, order_by: [:species, :name]}
      iex> {:ok, {results, meta}} = Flop.validate_and_run(Flop.Pet, params)
      iex> Enum.map(results, & &1.name)
      ["Patty"]
      iex> meta.has_previous_page?
      false

  By default, it is assumed that the query result is a list of maps or structs.
  If your query returns a different data structure, you can pass the
  `:cursor_value_func` option to retrieve the cursor values. See
  `t:Flop.option/0` and `Flop.Cursor` for more information.

  You can restrict which pagination types are available. See `t:Flop.option/0`
  for details.

  ## Filters

  Filters can be passed as a list of maps. It is recommended to define the
  filterable fields for a schema using `Flop.Schema`.

      iex> Flop.Repo.insert_all(Flop.Pet, [
      ...>   %{name: "Harry", age: 4, species: "C. lupus"},
      ...>   %{name: "Maggie", age: 1, species: "O. cuniculus"},
      ...>   %{name: "Patty", age: 2, species: "C. aegagrus"}
      ...> ])
      iex>
      iex> params = %{filters: [%{field: :name, op: :=~, value: "Mag"}]}
      iex> {:ok, {results, meta}} = Flop.validate_and_run(Flop.Pet, params)
      iex> meta.total_count
      1
      iex> [pet] = results
      iex> pet.name
      "Maggie"

  See `t:Flop.Filter.op/0` for a list of all available filter operators.

  ## GraphQL and Relay

  The parameters used for cursor-based pagination follow the Relay
  specification, so you can just pass the arguments you get from the client on
  to Flop.

  `Flop.Relay` can convert the query results returned by
  `Flop.validate_and_run/3` into `Edges` and `PageInfo` formats required for
  Relay connections.

  For example, if you have a context module like this:

      defmodule MyApp.Flora
        import Ecto.query, warn: false

        alias MyApp.Flora.Plant

        def list_plants_by_continent(%Continent{} = continent, %{} = args) do
          Plant
          |> where(continent_id: ^continent.id)
          |> Flop.validate_and_run(args, for: Plant)
        end
      end

  Then your Absinthe resolver for the `plants` connection may look something
  like this:

      def list_plants(args, %{source: %Continent{} = continent}) do
        with {:ok, result} <-
               Flora.list_plants_by_continent(continent, args) do
          {:ok, Flop.Relay.connection_from_result(result)}
        end
      end
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Changeset
  alias Ecto.Query
  alias Ecto.Queryable
  alias Flop.Builder
  alias Flop.Cursor
  alias Flop.CustomTypes.ExistingAtom
  alias Flop.CustomTypes.OrderDirection
  alias Flop.Filter
  alias Flop.Meta

  require Ecto.Query
  require Logger

  @typedoc """
  Options that can be passed to most of the functions or that can be set via
  the application environment.

  - `:for` - The schema module to be used for validation. `Flop.Schema` must be
    derived for the given module. This option is optional and can not be set
    globally. If it is not set, schema specific validation will be omitted. Used
    by the validation functions and passed on by any function calling a
    validation function.
  - `:default_limit` - Sets a global default limit for queries that is used if
    no default limit is set for a schema and no limit is set in the parameters.
    Can only be set in the application configuration.
  - `:filtering` (boolean) - Can be set to `false` to silently ignore filter
    parameters.
  - `:cursor_value_func` - 2-arity function used to get the (unencoded)
    cursor value from a record. Only used with cursor-based pagination. The
    first argument is the record, the second argument is the list of fields used
    in the `ORDER BY` clause. Needs to return a map with the order fields as
    keys and the the record values of these fields as values. Defaults to
    `Flop.Cursor.get_cursor_from_node/2`.
  - `:max_limit` - Sets a global maximum limit for queries that is used if no
    maximum limit is set for a schema. Can only be set in the application
    configuration.
  - `:pagination_types` - Defines which pagination types are allowed. Passing
    parameters for other pagination types will result in a validation error. By
    default, all pagination types are allowed. See also
    `t:Flop.pagination_type/0`. Note that an offset value of `0` and a limit
    are still accepted even if offset-based pagination is disabled.
  - `:ordering` (boolean) - Can be set to `false` to silently ignore order
    parameters. Default orders are still applied.
  - `:prefix` - Configures the query to be executed with the given query prefix.
    See the Ecto documentation on ["Query prefix"](https://hexdocs.pm/ecto/Ecto.Query.html#module-query-prefix).
  - `:repo` - The Ecto Repo module to use for the database query. Used by all
    functions that execute a database query.

  All options can be passed directly to the functions. Some of the options can
  be set on a schema level via `Flop.Schema`.

  All options except `:for` can be set globally via the application environment.

      import Config

      config :flop,
        default_limit: 25,
        filtering: false,
        cursor_value_func: &MyApp.Repo.get_cursor_value/2,
        max_limit: 100,
        ordering: false,
        pagination_types: [:first, :last, :page],
        repo: MyApp.Repo,
        prefix: "some-prefix"

  The look up order is:

  1. option passed to function
  2. option set for schema using `Flop.Schema` (only `:max_limit`,
     `:default_limit` and `:pagination_types`)
  3. option set in global config (except `:for`)
  4. default value (only `:cursor_value_func`)
  """
  @type option ::
          {:for, module}
          | {:default_limit, pos_integer}
          | {:filtering, boolean}
          | {:cursor_value_func, (any, [atom] -> map)}
          | {:max_limit, pos_integer}
          | {:ordering, boolean}
          | {:pagination_types, [pagination_type()]}
          | {:prefix, binary}
          | {:repo, module}

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
  Represents the pagination type.

  - `:offset` - pagination using the `offset` and `limit` parameters
  - `:page` - pagination using the `page` and `page_size` parameters
  - `:first` - cursor-based pagination using the `first` and `after` parameters
  - `:last` - cursor-based pagination using the `last` and `before` parameters
  """
  @type pagination_type :: :offset | :page | :first | :last

  @typedoc """
  Represents the query parameters for filtering, ordering and pagination.

  ### Fields

  - `after`: Used for cursor-based pagination. Must be used with `first` or a
    default limit.
  - `before`: Used for cursor-based pagination. Must be used with `last` or a
    default limit.
  - `limit`, `offset`: Used for offset-based pagination.
  - `first` Used for cursor-based pagination. Can be used alone to begin
    pagination or with `after`
  - `last` Used for cursor-based pagination.
  - `page`, `page_size`: Used for offset-based pagination as an alternative to
    `offset` and `limit`.
  - `order_by`: List of fields to order by. Fields can be restricted by
    deriving `Flop.Schema` in your Ecto schema.
  - `order_directions`: List of order directions applied to the fields defined
    in `order_by`. If empty or the list is shorter than the `order_by` list,
    `:asc` will be used as a default for each missing order direction.
  - `filters`: List of filters, see `t:Flop.Filter.t/0`.
  """
  @type t :: %__MODULE__{
          after: String.t() | nil,
          before: String.t() | nil,
          filters: [Filter.t()] | nil,
          first: pos_integer | nil,
          last: pos_integer | nil,
          limit: pos_integer | nil,
          offset: non_neg_integer | nil,
          order_by: [atom | String.t()] | nil,
          order_directions: [order_direction()] | nil,
          page: pos_integer | nil,
          page_size: pos_integer | nil
        }

  @primary_key false
  embedded_schema do
    field :after, :string
    field :before, :string
    field :first, :integer
    field :last, :integer
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

  Note that when using cursor-based pagination, the applied limit will be
  `first + 1` or `last + 1`. The extra record is removed by `Flop.run/3`.
  """
  @spec query(Queryable.t(), Flop.t(), keyword) :: Queryable.t()
  def query(q, flop, opts \\ []) do
    q
    |> filter(flop, opts)
    |> order_by(flop, opts)
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

  Note that when using cursor-based pagination, the applied limit will be
  `first + 1` or `last + 1`. The extra record is removed by `Flop.run/3`, but
  not by this function.
  """
  @doc since: "0.6.0"
  @spec all(Queryable.t(), Flop.t(), [option()]) :: [any]
  def all(q, flop, opts \\ []) do
    apply_on_repo(:all, "all", [query(q, flop, opts)], opts)
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
  @spec run(Queryable.t(), Flop.t(), [option()]) :: {[any], Meta.t()}
  def run(q, flop, opts \\ [])

  def run(
        q,
        %Flop{
          before: nil,
          first: first,
          last: nil
        } = flop,
        opts
      )
      when is_integer(first) do
    results = all(q, flop, opts)
    {Enum.take(results, first), meta(results, flop, opts)}
  end

  def run(
        q,
        %Flop{
          after: nil,
          first: nil,
          last: last
        } = flop,
        opts
      )
      when is_integer(last) do
    results = all(q, flop, opts)

    page_data =
      results
      |> Enum.take(last)
      |> Enum.reverse()

    {page_data, meta(results, flop, opts)}
  end

  def run(q, flop, opts) do
    {all(q, flop, opts), meta(q, flop, opts)}
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
  - `cursor_value_func`: An arity-2 function to be used to retrieve an
    unencoded cursor value from a query result item and the `order_by` fields.
    Defaults to `Flop.Cursor.get_cursor_from_node/2`.
  """
  @doc since: "0.6.0"
  @spec validate_and_run(Queryable.t(), map | Flop.t(), [option()]) ::
          {:ok, {[any], Meta.t()}} | {:error, Changeset.t()}
  def validate_and_run(q, flop, opts \\ []) do
    validate_opts = Keyword.take(opts, [:for, :pagination_types])

    with {:ok, flop} <- validate(flop, validate_opts) do
      {:ok, run(q, flop, opts)}
    end
  end

  @doc """
  Same as `Flop.validate_and_run/3`, but raises on error.
  """
  @doc since: "0.6.0"
  @spec validate_and_run!(Queryable.t(), map | Flop.t(), [option()]) ::
          {[any], Meta.t()}
  def validate_and_run!(q, flop, opts \\ []) do
    validate_opts = Keyword.take(opts, [:for, :pagination_types])
    flop = validate!(flop, validate_opts)
    run(q, flop, opts)
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
  @spec count(Queryable.t(), Flop.t(), [option()]) :: non_neg_integer
  def count(q, flop, opts \\ []) do
    apply_on_repo(:aggregate, "count", [filter(q, flop, opts), :count], opts)
  end

  @doc """
  Returns meta information for the given query and flop that can be used for
  building the pagination links.

      iex> Flop.meta(Flop.Pet, %Flop{limit: 10}, repo: Flop.Repo)
      %Flop.Meta{
        current_offset: 0,
        current_page: 1,
        end_cursor: nil,
        flop: %Flop{limit: 10},
        has_next_page?: false,
        has_previous_page?: false,
        next_offset: nil,
        next_page: nil,
        page_size: 10,
        previous_offset: nil,
        previous_page: nil,
        start_cursor: nil,
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

  Unless cursor-based pagination is used, this function will run a query to
  figure get the total count of matching records.
  """
  @doc since: "0.6.0"
  @spec meta(Queryable.t() | [any], Flop.t(), [option()]) :: Meta.t()
  def meta(query_or_results, flop, opts \\ [])

  def meta(
        results,
        %Flop{
          first: first,
          order_by: order_by,
          before: nil,
          last: nil
        } = flop,
        opts
      )
      when is_list(results) and is_integer(first) do
    {start_cursor, end_cursor} =
      results
      |> Enum.take(first)
      |> Cursor.get_cursors(order_by, opts)

    %Meta{
      flop: flop,
      start_cursor: start_cursor,
      end_cursor: end_cursor,
      has_next_page?: length(results) > first,
      has_previous_page?: false,
      page_size: first
    }
  end

  def meta(
        results,
        %Flop{
          after: nil,
          first: nil,
          order_by: order_by,
          last: last
        } = flop,
        opts
      )
      when is_list(results) and is_integer(last) do
    {start_cursor, end_cursor} =
      results
      |> Enum.take(last)
      |> Enum.reverse()
      |> Cursor.get_cursors(order_by, opts)

    %Meta{
      flop: flop,
      start_cursor: start_cursor,
      end_cursor: end_cursor,
      has_next_page?: false,
      has_previous_page?: length(results) > last,
      page_size: last
    }
  end

  def meta(q, flop, opts) do
    repo = option_or_default(opts, :repo) || raise no_repo_error("meta")
    opts = Keyword.put(opts, :repo, repo)

    total_count = count(q, flop, opts)
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
      flop: flop,
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

  defp get_next(current_offset, _, page_size, total_count, _)
       when current_offset + page_size >= total_count do
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
  @spec order_by(Queryable.t(), Flop.t(), keyword) :: Queryable.t()
  def order_by(q, flop, opts \\ [])

  def order_by(q, %Flop{order_by: nil}, _opts), do: q

  # For backwards cursor pagination
  def order_by(
        q,
        %Flop{
          last: last,
          order_by: fields,
          order_directions: directions,
          first: nil,
          after: nil,
          offset: nil
        },
        opts
      )
      when is_integer(last) do
    reversed_order =
      fields
      |> prepare_order(directions)
      |> reverse_ordering()

    case opts[:for] do
      nil ->
        Query.order_by(q, ^reversed_order)

      module ->
        struct = struct(module)

        Enum.reduce(reversed_order, q, fn expr, acc_q ->
          Flop.Schema.apply_order_by(struct, acc_q, expr)
        end)
    end
  end

  def order_by(
        q,
        %Flop{order_by: fields, order_directions: directions},
        opts
      ) do
    case opts[:for] do
      nil ->
        Query.order_by(q, ^prepare_order(fields, directions))

      module ->
        struct = struct(module)

        fields
        |> prepare_order(directions)
        |> Enum.reduce(q, fn expr, acc_q ->
          Flop.Schema.apply_order_by(struct, acc_q, expr)
        end)
    end
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

  def paginate(q, %Flop{
        first: first,
        after: nil,
        before: nil,
        last: nil,
        limit: nil
      })
      when is_integer(first),
      do: limit(q, first + 1)

  def paginate(
        q,
        %Flop{
          first: first,
          after: after_,
          order_by: order_by,
          order_directions: order_directions,
          before: nil,
          last: nil,
          limit: nil
        }
      )
      when is_integer(first) do
    orderings = prepare_order(order_by, order_directions)

    q
    |> apply_cursor(after_, orderings)
    |> limit(first + 1)
  end

  def paginate(
        q,
        %Flop{
          last: last,
          before: before,
          order_by: order_by,
          order_directions: order_directions,
          first: nil,
          after: nil,
          limit: nil
        }
      )
      when is_integer(last) do
    prepared_order_reversed =
      order_by
      |> prepare_order(order_directions)
      |> reverse_ordering()

    q
    |> apply_cursor(before, prepared_order_reversed)
    |> limit(last + 1)
  end

  def paginate(q, _), do: q

  ## Offset/limit pagination

  @spec limit(Queryable.t(), pos_integer | nil) :: Queryable.t()
  defp limit(q, nil), do: q
  defp limit(q, limit), do: Query.limit(q, ^limit)

  @spec offset(Queryable.t(), non_neg_integer | nil) :: Queryable.t()
  defp offset(q, nil), do: q
  defp offset(q, offset), do: Query.offset(q, ^offset)

  ## Cursor pagination helpers

  @spec apply_cursor(Queryable.t(), map() | nil, [order_direction()]) ::
          Queryable.t()
  defp apply_cursor(q, nil, _), do: q

  defp apply_cursor(q, cursor, ordering) do
    cursor = Cursor.decode!(cursor)
    where_dynamic = cursor_dynamic(ordering, cursor)
    Query.where(q, ^where_dynamic)
  end

  defp cursor_dynamic([], _), do: nil

  defp cursor_dynamic([{direction, field}], cursor) do
    case direction do
      dir when dir in [:asc, :asc_nulls_first, :asc_nulls_last] ->
        Query.dynamic([r], field(r, ^field) > ^cursor[field])

      dir when dir in [:desc, :desc_nulls_first, :desc_nulls_last] ->
        Query.dynamic([r], field(r, ^field) < ^cursor[field])
    end
  end

  defp cursor_dynamic([{direction, field} | [{_, _} | _] = tail], cursor) do
    field_cursor = cursor[field]

    case direction do
      dir when dir in [:asc, :asc_nulls_first, :asc_nulls_last] ->
        Query.dynamic(
          [r],
          field(r, ^field) >= ^field_cursor and
            (field(r, ^field) > ^field_cursor or ^cursor_dynamic(tail, cursor))
        )

      dir when dir in [:desc, :desc_nulls_first, :desc_nulls_last] ->
        Query.dynamic(
          [r],
          field(r, ^field) <= ^field_cursor and
            (field(r, ^field) < ^field_cursor or ^cursor_dynamic(tail, cursor))
        )
    end
  end

  @spec reverse_ordering([order_direction()]) :: [order_direction()]
  defp reverse_ordering(order_directions) do
    Enum.map(order_directions, fn
      {:desc, field} -> {:asc, field}
      {:desc_nulls_last, field} -> {:asc_nulls_first, field}
      {:desc_nulls_first, field} -> {:asc_nulls_last, field}
      {:asc, field} -> {:desc, field}
      {:asc_nulls_last, field} -> {:desc_nulls_first, field}
      {:asc_nulls_first, field} -> {:desc_nulls_last, field}
    end)
  end

  ## Filter

  @doc """
  Applies the `filter` parameter of a `t:Flop.t/0` to an `t:Ecto.Queryable.t/0`.

  Used by `Flop.query/2`.
  """
  @spec filter(Queryable.t(), Flop.t(), keyword) :: Queryable.t()
  def filter(q, flop, opt \\ [])

  def filter(q, %Flop{filters: nil}, _), do: q
  def filter(q, %Flop{filters: []}, _), do: q

  def filter(q, %Flop{filters: filters}, opts) when is_list(filters) do
    schema_struct =
      case opts[:for] do
        nil -> nil
        module -> struct(module)
      end

    conditions =
      Enum.reduce(filters, true, &Builder.filter(schema_struct, &1, &2))

    Query.where(q, ^conditions)
  end

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
  that only allowed fields are used. The function will also apply any default
  values set for the schema.

      iex> params = %{"order_by" => ["species"]}
      iex> {:error, changeset} = Flop.validate(params, for: Flop.Pet)
      iex> changeset.valid?
      false
      iex> [order_by: {msg, [_, {_, enum}]}] = changeset.errors
      iex> msg
      "has an invalid entry"
      iex> enum
      [:name, :age, :owner_name, :owner_age]

  Note that currently, trying to use an existing field that is not allowed as
  seen above will result in the error message `has an invalid entry`, while
  trying to use a field name that does not exist in the schema (or more
  precisely: a field name that doesn't exist as an atom) will result in
  the error message `is invalid`. This might change in the future.
  """
  @spec validate(Flop.t() | map, [option()]) ::
          {:ok, Flop.t()} | {:error, Changeset.t()}
  def validate(flop, opts \\ [])

  def validate(%Flop{} = flop, opts) do
    flop
    |> Map.from_struct()
    |> validate(opts)
  end

  def validate(%{} = params, opts) do
    result =
      params
      |> Flop.Validation.changeset(opts)
      |> apply_action(:replace)

    case result do
      {:ok, _} = r ->
        r

      {:error, %Changeset{} = changeset} = r ->
        Logger.debug("Invalid Flop: #{inspect(changeset)}")
        r
    end
  end

  @doc """
  Same as `Flop.validate/2`, but raises an `Ecto.InvalidChangesetError` if the
  parameters are invalid.
  """
  @doc since: "0.5.0"
  @spec validate!(Flop.t() | map, [option()]) :: Flop.t()
  def validate!(flop, opts \\ []) do
    case validate(flop, opts) do
      {:ok, flop} ->
        flop

      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :replace, changeset: changeset
    end
  end

  @doc """
  Sets the page value of a `Flop` struct while also removing/converting
  pagination parameters for other pagination types.

      iex> set_page(%Flop{page: 2, page_size: 10}, 6)
      %Flop{page: 6, page_size: 10}

      iex> set_page(%Flop{limit: 10, offset: 20}, 8)
      %Flop{limit: nil, offset: nil, page: 8, page_size: 10}

  The page number will not be allowed to go below 1.

      iex> set_page(%Flop{}, -5)
      %Flop{page: 1}
  """
  @doc since: "0.12.0"
  @spec set_page(Flop.t(), pos_integer) :: Flop.t()
  def set_page(%Flop{} = flop, page) do
    %{
      flop
      | after: nil,
        before: nil,
        first: nil,
        last: nil,
        limit: nil,
        offset: nil,
        page_size: flop.page_size || flop.limit || flop.first || flop.last,
        page: max(page, 1)
    }
  end

  @doc """
  Updates the `order_by` and `order_directions` values of a `Flop` struct.

  - If the field is not in the current `order_by` value, it will be prepended to
    the list. The order direction for the field will be set to `:asc`.
  - If the field is already at the front of the `order_by` list, the order
    direction will be reversed.
  - If the field is already in the list, but not at the front, it will be moved
    to the front and the order direction will be set to `:asc`.

  ## Example

      iex> flop = push_order(%Flop{}, :name)
      iex> flop.order_by
      [:name]
      iex> flop.order_directions
      [:asc]
      iex> flop = push_order(flop, :age)
      iex> flop.order_by
      [:age, :name]
      iex> flop.order_directions
      [:asc, :asc]
      iex> flop = push_order(flop, :age)
      iex> flop.order_by
      [:age, :name]
      iex> flop.order_directions
      [:desc, :asc]
      iex> flop = push_order(flop, :species)
      iex> flop.order_by
      [:species, :age, :name]
      iex> flop.order_directions
      [:asc, :desc, :asc]
      iex> flop = push_order(flop, :age)
      iex> flop.order_by
      [:age, :species, :name]
      iex> flop.order_directions
      [:asc, :asc, :asc]

  If a string is passed as the second argument, it will be converted to an atom
  using `String.to_existing_atom/1`. If the atom does not exist, the `Flop`
  struct will be returned unchanged.

      iex> flop = push_order(%Flop{}, "name")
      iex> flop.order_by
      [:name]
      iex> flop = push_order(%Flop{}, "this_atom_does_not_exist")
      iex> flop.order_by
      nil
  """
  @spec push_order(Flop.t(), atom | String.t()) :: Flop.t()
  @doc since: "0.10.0"
  def push_order(
        %Flop{order_by: order_by, order_directions: order_directions} = flop,
        field
      )
      when is_atom(field) do
    previous_index = get_index(order_by, field)
    previous_direction = get_order_direction(order_directions, previous_index)
    new_direction = new_order_direction(previous_index, previous_direction)

    {order_by, order_directions} =
      get_new_order(
        order_by,
        order_directions,
        field,
        new_direction,
        previous_index
      )

    %{flop | order_by: order_by, order_directions: order_directions}
  end

  def push_order(flop, field) when is_binary(field) do
    push_order(flop, String.to_existing_atom(field))
  rescue
    _e in ArgumentError -> flop
  end

  defp get_index(nil, _field), do: nil
  defp get_index(order_by, field), do: Enum.find_index(order_by, &(&1 == field))

  defp get_order_direction(_, nil), do: nil
  defp get_order_direction(nil, _), do: :asc
  defp get_order_direction(directions, index), do: Enum.at(directions, index)

  defp new_order_direction(0, :asc), do: :desc
  defp new_order_direction(0, :asc_nulls_first), do: :desc_nulls_last
  defp new_order_direction(0, :asc_nulls_last), do: :desc_nulls_first
  defp new_order_direction(0, :desc), do: :asc
  defp new_order_direction(0, :desc_nulls_first), do: :asc_nulls_last
  defp new_order_direction(0, :desc_nulls_last), do: :asc_nulls_first
  defp new_order_direction(_, _), do: :asc

  defp get_new_order(
         order_by,
         order_directions,
         field,
         new_direction,
         previous_index
       ) do
    {order_by, order_directions} =
      if previous_index do
        {List.delete_at(order_by, previous_index),
         List.delete_at(order_directions, previous_index)}
      else
        {order_by, order_directions}
      end

    {[field | order_by || []], [new_direction | order_directions || []]}
  end

  defp apply_on_repo(repo_fn, flop_fn, args, opts) do
    repo = option_or_default(opts, :repo) || raise no_repo_error(flop_fn)

    opts =
      if prefix = option_or_default(opts, :prefix) do
        [prefix: prefix]
      else
        []
      end

    apply(repo, repo_fn, args ++ [opts])
  end

  defp option_or_default(opts, key) do
    opts[key] || Application.get_env(:flop, key)
  end

  @doc """
  Returns the option with the given key.

  The look-up order is:

  1. the keyword list passed as the second argument
  2. the schema module that derives `Flop.Schema`, if the passed list includes
     the `:for` option
  3. the application environment
  """
  @doc since: "0.11.0"
  @spec get_option(atom, [option()]) :: any
  def get_option(key, opts) do
    case opts[key] do
      nil ->
        case schema_option(opts[:for], key) do
          nil -> global_option(key)
          v -> v
        end

      v ->
        v
    end
  end

  defp schema_option(module, key)
       when is_atom(module) and module != nil and
              key in [
                :default_limit,
                :default_order,
                :filterable_fields,
                :max_limit,
                :pagination_types,
                :sortable
              ] do
    apply(Flop.Schema, key, [struct(module)])
  end

  defp schema_option(_, _), do: nil

  defp global_option(key) when is_atom(key) do
    Application.get_env(:flop, key)
  end

  # coveralls-ignore-start
  defp no_repo_error(function_name),
    do: """
    No repo specified. You can specify the repo either by passing it
    explicitly:

        Flop.#{function_name}(MyApp.Item, %Flop{}, repo: MyApp.Repo)

    Or you can configure a default repo in your config:

    config :flop, repo: MyApp.Repo
    """

  # coveralls-ignore-end
end
