defmodule Flop do
  @moduledoc """
  Flop is a helper library for filtering, ordering and pagination with Ecto.

  ## Usage

  The simplest way of using this library is just to use
  `Flop.validate_and_run/3` and `Flop.validate_and_run!/3`. Both functions
  take a queryable and a parameter map, validate the parameters, run the query
  and return the query results and the meta information.

      iex> Flop.Repo.insert_all(MyApp.Pet, [
      ...>   %{name: "Harry", age: 4, species: "C. lupus"},
      ...>   %{name: "Maggie", age: 1, species: "O. cuniculus"},
      ...>   %{name: "Patty", age: 2, species: "C. aegagrus"}
      ...> ])
      iex> params = %{order_by: ["name", "age"], page: 1, page_size: 2}
      iex> {:ok, {results, meta}} =
      ...>   Flop.validate_and_run(
      ...>     MyApp.Pet,
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

  ## Config modules

  Instead of setting global options in the application environment, you can also
  create a Flop config module. This is especially useful in an umbrella
  application, or if you have multiple Repos.

  ```elixir
  defmodule MyApp.Flop do
    use Flop, repo: MyApp.Repo, default_limit: 25
  end
  ```

  > #### `use Flop` {: .info}
  >
  > When you `use Flop`, the Flop module will define wrapper functions around
  > all of the `Flop` functions that take a query, the Flop parameters, and
  > options as arguments. The options passed to `use Flop` will be used as
  > default options in all the wrapper functions, but you can still override
  > them.

  The wrapped functions are:

  - `Flop.all/3`
  - `Flop.count/3`
  - `Flop.filter/3`
  - `Flop.meta/3`
  - `Flop.order_by/3`
  - `Flop.paginate/3`
  - `Flop.query/3`
  - `Flop.run/3`
  - `Flop.validate_and_run/3`
  - `Flop.validate_and_run!/3`

  So instead of using `Flop.validate_and_run/3`, you would call
  `MyApp.Flop.validate_and_run/3`.

  If you have both a config module and a global application config, Flop will
  fall back to the application config if an option is not set.

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
      iex> {:ok, flop} = Flop.validate(params, for: MyApp.Pet)
      iex> flop.limit
      5

      iex> params = %{"order_by" => ["name", "age"], "limit" => 10_000}
      iex> {:error, meta} = Flop.validate(params, for: MyApp.Pet)
      iex> [limit: [{msg, _}]] = meta.errors
      iex> msg
      "must be less than or equal to %{number}"

      iex> params = %{"order_by" => ["name", "age"], "limit" => 10_000}
      iex> {:error, %Flop.Meta{} = meta} =
      ...>   Flop.validate_and_run(
      ...>     MyApp.Pet,
      ...>     params,
      ...>     for: MyApp.Pet
      ...>   )
      iex> [limit: [{msg, _}]] = meta.errors
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

      iex> Flop.Repo.insert_all(MyApp.Pet, [
      ...>   %{name: "Harry", age: 4, species: "C. lupus"},
      ...>   %{name: "Maggie", age: 1, species: "O. cuniculus"},
      ...>   %{name: "Patty", age: 2, species: "C. aegagrus"}
      ...> ])
      iex>
      iex> # forward (first/after)
      iex>
      iex> params = %{first: 2, order_by: [:species, :name]}
      iex> {:ok, {results, meta}} = Flop.validate_and_run(MyApp.Pet, params)
      iex> Enum.map(results, & &1.name)
      ["Patty", "Harry"]
      iex> meta.has_next_page?
      true
      iex> end_cursor = meta.end_cursor
      "g3QAAAACdwRuYW1lbQAAAAVIYXJyeXcHc3BlY2llc20AAAAIQy4gbHVwdXM="
      iex> params = %{first: 2, after: end_cursor, order_by: [:species, :name]}
      iex> {:ok, {results, meta}} = Flop.validate_and_run(MyApp.Pet, params)
      iex> Enum.map(results, & &1.name)
      ["Maggie"]
      iex> meta.has_next_page?
      false
      iex>
      iex> # backward (last/before)
      iex>
      iex> params = %{last: 2, order_by: [:species, :name]}
      iex> {:ok, {results, meta}} = Flop.validate_and_run(MyApp.Pet, params)
      iex> Enum.map(results, & &1.name)
      ["Harry", "Maggie"]
      iex> meta.has_previous_page?
      true
      iex> start_cursor = meta.start_cursor
      "g3QAAAACdwRuYW1lbQAAAAVIYXJyeXcHc3BlY2llc20AAAAIQy4gbHVwdXM="
      iex> params = %{last: 2, before: start_cursor, order_by: [:species, :name]}
      iex> {:ok, {results, meta}} = Flop.validate_and_run(MyApp.Pet, params)
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

      iex> Flop.Repo.insert_all(MyApp.Pet, [
      ...>   %{name: "Harry", age: 4, species: "C. lupus"},
      ...>   %{name: "Maggie", age: 1, species: "O. cuniculus"},
      ...>   %{name: "Patty", age: 2, species: "C. aegagrus"}
      ...> ])
      iex>
      iex> params = %{filters: [%{field: :name, op: :=~, value: "Mag"}]}
      iex> {:ok, {results, meta}} = Flop.validate_and_run(MyApp.Pet, params)
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

  alias Ecto.Changeset
  alias Ecto.Queryable
  alias Flop.Adapter
  alias Flop.Cursor
  alias Flop.CustomTypes.ExistingAtom
  alias Flop.Filter
  alias Flop.Meta
  alias Flop.NimbleSchemas

  require Ecto.Query
  require Logger

  @default_opts [default_limit: 50, max_limit: 1000]

  defmacro __using__(opts) do
    opts =
      NimbleSchemas.validate!(
        opts,
        :backend_option,
        Flop,
        __CALLER__.module
      )

    {legacy_adapter_opts, opts} = Keyword.split(opts, [:query_opts, :repo])
    adapter = Keyword.fetch!(opts, :adapter)

    adapter_opts =
      Keyword.merge(legacy_adapter_opts, Keyword.fetch!(opts, :adapter_opts))

    adapter_opts =
      adapter.init_backend_opts(opts, adapter_opts, __CALLER__.module)

    opts = Keyword.put(opts, :adapter_opts, adapter_opts)

    quote do
      @doc false
      def __flop_options__, do: unquote(opts)

      unquote(backend_functions(__CALLER__.module))
      unquote(validate_functions(__CALLER__.module))
    end
  end

  defp backend_functions(backend_module) do
    for func <- [
          :all,
          :count,
          :filter,
          :meta,
          :order_by,
          :paginate,
          :query,
          :run,
          :validate_and_run,
          :validate_and_run!
        ] do
      quote do
        def unquote(func)(q, map_or_flop, opts \\ []) do
          apply(Flop, unquote(func), [
            q,
            map_or_flop,
            Keyword.put(opts, :backend, unquote(backend_module))
          ])
        end
      end
    end
  end

  defp validate_functions(backend_module) do
    for func <- [:validate, :validate!] do
      quote do
        def unquote(func)(map_or_flop, opts \\ []) do
          apply(Flop, unquote(func), [
            map_or_flop,
            Keyword.put(opts, :backend, unquote(backend_module))
          ])
        end
      end
    end
  end

  @typedoc """
  These options can be passed to most functions or configured via the
  application environment.

  ## Options

  ### General

  - `:for` - The Ecto schema module for validation and query building.
    `Flop.Schema` must be derived for this module.
  - `:cursor_value_func` - A function used to extract the cursor value from a
    record. It takes the record and the list of fields used in the `ORDER BY`
    clause as arguments, and returns a map with the order fields as keys and the
    corresponding record values as values. Default is
    `Flop.Cursor.get_cursor_from_node/2`.
  - `:replace_invalid_params` - If set to `true`, invalid parameters are
    replaced with default values or removed instead of causing errors. Default
    is `false`.

  ### Defaults

  - `:default_limit` - The default limit for queries. Used when no specific
    limit is set in the parameters or schema.  Set to `false` to not set any
    default limit. Default is `50`.
  - `:default_order` - The default ordering for a query when no order is
    specified in the parameters, or if ordering is disabled. Can be set in the
    schema or in the options passed to the query functions.
  - `:default_pagination_type` - The default pagination type when it cannot be
    inferred from the parameters.
  - `:max_limit` - The maximum limit for queries. Used when no maximum limit is
    set in the parameters or schema. Set to `false` to not set any maximum
    limit. Default is `1000`.

  ### Modifying counts

  - `:count_query` - A separate base query for counting. Can only be passed as
    an option to one of the query functions. See `Flop.validate_and_run/3` and
    `Flop.count/3`.
  - `:count` - A precomputed count. Useful when the count is already known.

  ### Disabling features

  - `:filtering` (boolean) - Enables or disables filtering. When set to `false`,
    filter parameters are ignored.
  - `:ordering` (boolean) - Enables or disables ordering. When set to `false`,
    order parameters are ignored, but the default order is still applied.
  - `:pagination` (boolean) - Enables or disables pagination. When set to
    `false`, pagination parameters are ignored.
  - `:pagination_types` - The allowed pagination types. Parameters for
    disallowed pagination types will not be cast. By default, all types are
    allowed. See also `t:Flop.pagination_type/0`.

  ### Additional options

  - `:extra_opts` (keyword list) - Extra options for custom fields.
  - `:adapter_opts` - Adapter-specific options. For backward compatibility,
    options for the Ecto adapter can be set directly at the root level.

  ## Look-up order

  Options are looked up in the following order:

  1. Function arguments
  2. Schema-level options
  3. Module-level options in the config (backend) module
  4. Global options in the application environment
  5. Library defaults
  """
  @type option ::
          {:cursor_value_func, (any, [atom] -> map)}
          | {:default_limit, pos_integer | false}
          | {:default_order, default_order()}
          | {:default_pagination_type, pagination_type() | false}
          | {:filtering, boolean}
          | {:for, module}
          | {:max_limit, pos_integer | false}
          | {:count_query, Ecto.Queryable.t()}
          | {:count, integer}
          | {:ordering, boolean}
          | {:pagination, boolean}
          | {:pagination_types, [pagination_type()]}
          | {:replace_invalid_params, boolean}
          | {:extra_opts, Keyword.t()}
          | {:adapter_opts, adapter_option()}
          | adapter_option()
          | private_option()

  @typep private_option ::
           {:adapter, module} | {:backend, module}

  @typedoc """
  Options specific to the Ecto adapter.

  - `:repo` - The Ecto Repo module used for database queries.
  - `:query_opts` - Options passed to the `Ecto.Repo` query functions. Refer to
    the Ecto documentation for `c:Ecto.Repo.all/2`, `c:Ecto.Repo.aggregate/3`,
    and the ["Shared Options"](https://hexdocs.pm/ecto/Ecto.Repo.html#module-shared-options)
    section of `Ecto.Repo`.
  """
  @type adapter_option :: {:repo, module} | {:query_opts, Keyword.t()}

  @typedoc """
  A map with the order fields and the order directions.

  Each atom in `:order_by` corresponds to a field by which the data is ordered.
  The list of order fields and order directions is zipped when the parameters
  are applied. If no order directions are given or the list of order directions
  is shorter than the list of order fields, `:asc` is used as a default order
  direction.
  """
  @type default_order ::
          %{
            required(:order_by) => [atom],
            optional(:order_directions) => [order_direction()]
          }

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
  - `decoded_cursor`: Used internally to hold on to the decoded cursor between
    validation and query execution. Value is discarded when meta is built.
  - `limit`, `offset`: Used for offset-based pagination.
  - `first`: Used for cursor-based pagination. Can be used alone to begin
    pagination from the start or in conjunction with `after`.
  - `last`: Used for cursor-based pagination.
  - `page`, `page_size`: Used for offset-based pagination as an alternative to
    `offset` and `limit`.
  - `order_by`: List of fields to order by. Fields can be restricted by
    deriving `Flop.Schema` in your Ecto schema.
  - `order_directions`: List of order directions applied to the fields defined
    in `order_by`. If empty or the list is shorter than the `order_by` list,
    `:asc` will be used as a default for each missing order direction.
  - `filters`: List of filters, see `t:Flop.Filter.t/0`. Each `Filter.t()`
    represents a filter operation on a specific field.

  Note: Pagination fields are mutually exclusive.
  """
  @type t :: %__MODULE__{
          after: String.t() | nil,
          before: String.t() | nil,
          decoded_cursor: map | nil,
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

    field :order_directions, {:array, Ecto.Enum},
      values: [
        :asc,
        :asc_nulls_first,
        :asc_nulls_last,
        :desc,
        :desc_nulls_first,
        :desc_nulls_last
      ]

    field :page, :integer
    field :page_size, :integer
    field :decoded_cursor, :map

    embeds_many :filters, Filter
  end

  @doc """
  Adds clauses for filtering, ordering and pagination to a
  `t:Ecto.Queryable.t/0`.

  The parameters are represented by the `t:Flop.t/0` type. Any `nil` values
  will be ignored.

  This function does _not_ validate or apply default parameters to the given
  Flop struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function.

  ## Examples

      iex> flop = %Flop{limit: 10, offset: 19}
      iex> Flop.query(MyApp.Pet, flop)
      #Ecto.Query<from p0 in MyApp.Pet, limit: ^10, offset: ^19>

  Or enhance an already defined query:

      iex> require Ecto.Query
      iex> flop = %Flop{limit: 10}
      iex> q = Ecto.Query.where(MyApp.Pet, species: "dog")
      iex> Flop.query(q, flop, for: MyApp.Pet)
      #Ecto.Query<from p0 in MyApp.Pet, where: p0.species == \"dog\", limit: ^10>

  Note that when using cursor-based pagination, the applied limit will be
  `first + 1` or `last + 1`. The extra record is removed by `Flop.run/3`.

  Also note that you will need to pass the `for` option in order for Flop to be
  able to find your join, compound, alias and custom field configuration.
  """
  @doc group: :queries
  @spec query(Queryable.t(), Flop.t(), [option()]) :: Queryable.t()
  def query(q, %Flop{} = flop, opts \\ []) do
    q
    |> filter(flop, opts)
    |> order_by(flop, opts)
    |> paginate(flop, opts)
  end

  @doc """
  Applies the given Flop to the given queryable and returns all matchings
  entries.

      iex> Flop.all(MyApp.Pet, %Flop{}, repo: Flop.Repo)
      []

  You can also configure a default repo in your config files:

      config :flop, repo: MyApp.Repo

  This allows you to omit the third argument:

      iex> Flop.all(MyApp.Pet, %Flop{}, for: MyApp.Pet)
      []

  Note that when using cursor-based pagination, the applied limit will be
  `first + 1` or `last + 1`. The extra record is removed by `Flop.run/3`, but
  not by this function.

  Also note that you will need to pass the `for` option in order for Flop to be
  able to find your join, compound, alias and custom field configuration.

  This function does _not_ validate or apply default parameters to the given
  Flop struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function.
  """
  @doc since: "0.6.0"
  @doc group: :queries
  @spec all(Queryable.t(), Flop.t(), [option()]) :: [any]
  def all(q, %Flop{} = flop, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, Adapter.Ecto)

    q
    |> query(flop, opts)
    |> adapter.list(opts)
  end

  @doc """
  Applies the given Flop to the given queryable, retrieves the data and the
  meta data.

  This function does _not_ validate or apply default parameters to the given
  flop parameters. You can validate the parameters with `Flop.validate/2` or
  `Flop.validate!/2`, or you can use `Flop.validate_and_run/3` or
  `Flop.validate_and_run!/3` instead of this function.

  Note that you will need to pass the `for` option to both to `validate/2`,
  `validate!/2` and `run/3`. Otherwise, Flop would not know how to find your
  field configuration (join fields, alias fields, custom fields, compound
  fields).

      iex> opts = [for: MyApp.Pet]
      iex> flop = Flop.validate!(%{}, opts)
      iex> {data, meta} = Flop.run(MyApp.Pet, flop, opts)
      iex> data == []
      true
      iex> match?(%Flop.Meta{}, meta)
      true

  See the documentation for `Flop.validate_and_run/3` for supported options.
  """
  @doc since: "0.6.0"
  @doc group: :queries
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

  def run(q, %Flop{} = flop, opts) do
    {all(q, flop, opts), meta(q, flop, opts)}
  end

  @doc """
  Validates the given flop parameters and retrieves the data and meta data on
  success.

      iex> {:ok, {[], %Flop.Meta{}}} =
      ...>   Flop.validate_and_run(MyApp.Pet, %Flop{}, for: MyApp.Pet)
      iex> {:error, %Flop.Meta{} = meta} =
      ...>   Flop.validate_and_run(MyApp.Pet, %Flop{limit: -1})
      iex> meta.errors
      [
        limit: [
          {"must be greater than %{number}",
           [validation: :number, kind: :greater_than, number: 0]}
        ]
      ]

  ## Options

  - `for`: Passed to `Flop.validate/2`. Also used to look up the join, alias,
    compound and custom field configuration.
  - `repo`: The `Ecto.Repo` module. Required if no default repo is configured.
  - `cursor_value_func`: An arity-2 function to be used to retrieve an
    unencoded cursor value from a query result item and the `order_by` fields.
    Defaults to `Flop.Cursor.get_cursor_from_node/2`.
  - `count_query`: Lets you override the base query for counting, e.g. if you
    don't want to include unnecessary joins. The filter parameters are applied
    to the given query. See also `Flop.count/3`.
  """
  @doc since: "0.6.0"
  @doc group: :queries
  @spec validate_and_run(Queryable.t(), map | Flop.t(), [option()]) ::
          {:ok, {[any], Meta.t()}} | {:error, Meta.t()}
  def validate_and_run(q, map_or_flop, opts \\ []) do
    with {:ok, flop} <- validate(map_or_flop, opts) do
      {:ok, run(q, flop, opts)}
    end
  end

  @doc """
  Same as `Flop.validate_and_run/3`, but raises on error.
  """
  @doc since: "0.6.0"
  @doc group: :queries
  @spec validate_and_run!(Queryable.t(), map | Flop.t(), [option()]) ::
          {[any], Meta.t()}
  def validate_and_run!(q, map_or_flop, opts \\ []) do
    flop = validate!(map_or_flop, opts)
    run(q, flop, opts)
  end

  @doc """
  Returns the total count of entries matching the filter conditions of the
  Flop.

  The pagination and ordering option are disregarded.

      iex> Flop.count(MyApp.Pet, %Flop{}, repo: Flop.Repo)
      0

  You can also configure a default repo in your config files:

      config :flop, repo: MyApp.Repo

  This allows you to omit the third argument:

      iex> Flop.count(MyApp.Pet, %Flop{})
      0

  You can override the default query by passing the `:count_query` option. This
  doesn't make a lot of sense when you use `count/3` directly, but allows you to
  optimize the count query when you use one of the `run/3`,
  `validate_and_run/3` and `validate_and_run!/3` functions.

      query = join(Pet, :left, [p], o in assoc(p, :owner))
      count_query = Pet
      count(query, %Flop{}, count_query: count_query, for: Pet)

  The filter parameters of the given Flop are applied to the custom count query.

  If for some reason you already have the count, you can pass it as the `:count`
  option.

      count(query, %Flop{}, count: 42, for: Pet)

  If you pass both the `:count` and the `:count_query` options, the `:count`
  option will take precedence.

  This function does _not_ validate or apply default parameters to the given
  Flop struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function.

  Note that you will need to pass the `for` option in order for Flop to be
  able to find your join, compound, alias and custom field configuration.
  """
  @doc since: "0.6.0"
  @doc group: :queries
  @spec count(Queryable.t(), Flop.t(), [option()]) :: non_neg_integer
  def count(q, %Flop{} = flop, opts \\ []) do
    if count = opts[:count] do
      count
    else
      q =
        if count_query = opts[:count_query] do
          filter(count_query, flop, opts)
        else
          filter(q, flop, opts)
        end

      adapter = Keyword.get(opts, :adapter, Adapter.Ecto)
      adapter.count(q, opts)
    end
  end

  @doc """
  Returns meta information for the given query and flop that can be used for
  building the pagination links.

      iex> Flop.meta(MyApp.Pet, %Flop{limit: 10}, repo: Flop.Repo)
      %Flop.Meta{
        current_offset: 0,
        current_page: 1,
        end_cursor: nil,
        flop: %Flop{limit: 10},
        has_next_page?: false,
        has_previous_page?: false,
        next_offset: nil,
        next_page: nil,
        opts: [repo: Flop.Repo],
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

  This function does _not_ validate or apply default parameters to the given
  Flop struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function.
  """
  @doc since: "0.6.0"
  @doc group: :queries
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
      backend: opts[:backend],
      flop: %{flop | decoded_cursor: nil},
      start_cursor: start_cursor,
      end_cursor: end_cursor,
      has_next_page?: length(results) > first,
      has_previous_page?: !is_nil(flop.after),
      opts: opts,
      page_size: first,
      schema: opts[:for]
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
      backend: opts[:backend],
      flop: %{flop | decoded_cursor: nil},
      start_cursor: start_cursor,
      end_cursor: end_cursor,
      has_next_page?: !is_nil(flop.before),
      has_previous_page?: length(results) > last,
      opts: opts,
      page_size: last,
      schema: opts[:for]
    }
  end

  def meta(q, %Flop{} = flop, opts) do
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
      backend: opts[:backend],
      current_offset: current_offset,
      current_page: current_page,
      flop: %{flop | decoded_cursor: nil},
      has_next_page?: has_next_page?,
      has_previous_page?: has_previous_page?,
      next_offset: next_offset,
      next_page: next_page,
      opts: opts,
      page_size: page_size,
      previous_offset: previous_offset,
      previous_page: previous_page,
      schema: opts[:for],
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

  This function does _not_ validate or apply default parameters to the given
  Flop struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function.

  Note that you will need to pass the `for` option in order for Flop to be
  able to find your join, compound, alias and custom field configuration.
  """
  @doc group: :queries
  @spec order_by(Queryable.t(), Flop.t(), [option()]) :: Queryable.t()
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
    adapter = Keyword.get(opts, :adapter, Adapter.Ecto)

    prepared_directions =
      fields
      |> prepare_order_fields_and_directions(directions)
      |> reverse_ordering()

    adapter.apply_order_by(q, prepared_directions, opts)
  end

  def order_by(
        q,
        %Flop{order_by: fields, order_directions: directions},
        opts
      ) do
    adapter = Keyword.get(opts, :adapter, Adapter.Ecto)

    prepared_directions =
      prepare_order_fields_and_directions(
        fields,
        directions
      )

    adapter.apply_order_by(q, prepared_directions, opts)
  end

  @spec prepare_order_fields_and_directions([atom], [order_direction()]) :: [
          {order_direction(), atom}
        ]
  defp prepare_order_fields_and_directions(fields, directions) do
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

  This function does _not_ validate or apply default parameters to the given
  Flop struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function.

  Note that you will need to pass the `for` option in order for Flop to be
  able to find your join, compound, alias and custom field configuration.
  """
  @doc group: :queries
  @spec paginate(Queryable.t(), Flop.t(), [option()]) :: Queryable.t()
  def paginate(q, flop, opts \\ [])

  def paginate(q, %Flop{limit: limit, offset: offset}, opts)
      when (is_integer(limit) and limit >= 1) or
             (is_integer(offset) and offset >= 0) do
    adapter = Keyword.get(opts, :adapter, Adapter.Ecto)
    adapter.apply_limit_offset(q, limit, offset, opts)
  end

  def paginate(q, %Flop{page: page, page_size: page_size}, opts)
      when is_integer(page) and is_integer(page_size) and
             page >= 1 and page_size >= 1 do
    adapter = Keyword.get(opts, :adapter, Adapter.Ecto)
    adapter.apply_page_page_size(q, page, page_size, opts)
  end

  def paginate(
        q,
        %Flop{
          first: first,
          after: nil,
          before: nil,
          last: nil,
          limit: nil
        },
        opts
      )
      when is_integer(first) do
    adapter = Keyword.get(opts, :adapter, Adapter.Ecto)
    adapter.apply_limit_offset(q, first + 1, nil, opts)
  end

  def paginate(
        q,
        %Flop{
          first: first,
          after: after_,
          decoded_cursor: decoded_cursor,
          order_by: order_by,
          order_directions: order_directions,
          before: nil,
          last: nil,
          limit: nil
        },
        opts
      )
      when is_integer(first) do
    adapter = Keyword.get(opts, :adapter, Adapter.Ecto)
    struct = if module = opts[:for], do: struct(module)
    orderings = prepare_order_fields_and_directions(order_by, order_directions)
    decoded_cursor = decoded_cursor || Cursor.decode!(after_)
    cursor_fields = prepare_cursor_fields(struct, decoded_cursor, orderings)

    q
    |> adapter.apply_cursor(cursor_fields, opts)
    |> adapter.apply_limit_offset(first + 1, nil, opts)
  end

  def paginate(
        q,
        %Flop{
          last: last,
          before: nil,
          first: nil,
          after: nil,
          limit: nil
        },
        opts
      )
      when is_integer(last) do
    adapter = Keyword.get(opts, :adapter, Adapter.Ecto)
    adapter.apply_limit_offset(q, last + 1, nil, opts)
  end

  def paginate(
        q,
        %Flop{
          last: last,
          before: before,
          decoded_cursor: decoded_cursor,
          order_by: order_by,
          order_directions: order_directions,
          first: nil,
          after: nil,
          limit: nil
        },
        opts
      )
      when is_integer(last) do
    adapter = Keyword.get(opts, :adapter, Adapter.Ecto)
    struct = if module = opts[:for], do: struct(module)

    orderings =
      order_by
      |> prepare_order_fields_and_directions(order_directions)
      |> reverse_ordering()

    decoded_cursor = decoded_cursor || Cursor.decode!(before)
    cursor_fields = prepare_cursor_fields(struct, decoded_cursor, orderings)

    q
    |> adapter.apply_cursor(cursor_fields, opts)
    # add 1 to limit, so that we know whether there are more items to show
    |> adapter.apply_limit_offset(last + 1, nil, opts)
  end

  def paginate(q, _, _), do: q

  @spec prepare_cursor_fields(struct | nil, map, [{atom, atom}]) :: [
          {order_direction(), atom, any, Flop.FieldInfo.t()}
        ]
  defp prepare_cursor_fields(struct, decoded_cursor, ordering) do
    Enum.map(ordering, fn {direction, field} ->
      field_info = struct && Flop.Schema.field_info(struct, field)
      cursor_value = Map.get(decoded_cursor, field)
      {direction, field, cursor_value, field_info}
    end)
  end

  @spec reverse_ordering([order_direction()]) :: [order_direction()]
  defp reverse_ordering(order_directions) do
    Enum.map(order_directions, fn {direction, field} ->
      {reverse_direction(direction), field}
    end)
  end

  defp reverse_direction(:asc), do: :desc
  defp reverse_direction(:asc_nulls_first), do: :desc_nulls_last
  defp reverse_direction(:asc_nulls_last), do: :desc_nulls_first
  defp reverse_direction(:desc), do: :asc
  defp reverse_direction(:desc_nulls_first), do: :asc_nulls_last
  defp reverse_direction(:desc_nulls_last), do: :asc_nulls_first

  defguardp is_direction(value)
            when value in [
                   :asc,
                   :asc_nulls_first,
                   :asc_nulls_last,
                   :desc,
                   :desc_nulls_first,
                   :desc_nulls_last
                 ]

  defguardp is_asc_direction(value)
            when value in [
                   :asc,
                   :asc_nulls_first,
                   :asc_nulls_last
                 ]

  defguardp is_desc_direction(value)
            when value in [
                   :desc,
                   :desc_nulls_first,
                   :desc_nulls_last
                 ]

  ## Filter

  @doc """
  Applies the `filter` parameter of a `t:Flop.t/0` to an `t:Ecto.Queryable.t/0`.

  Used by `Flop.query/2`.

  This function does _not_ validate or apply default parameters to the given
  Flop struct. Be sure to validate any user-generated parameters with
  `validate/2` or `validate!/2` before passing them to this function.

  Note that you will need to pass the `for` option in order for Flop to be
  able to find your join, compound, alias and custom field configuration.
  """
  @doc group: :queries
  @spec filter(Queryable.t(), Flop.t(), [option()]) :: Queryable.t()
  def filter(q, flop, opt \\ [])

  def filter(q, %Flop{filters: nil}, _), do: q
  def filter(q, %Flop{filters: []}, _), do: q

  def filter(q, %Flop{filters: filters}, opts) when is_list(filters) do
    schema_struct =
      case opts[:for] do
        nil -> nil
        module -> struct(module)
      end

    Enum.reduce(filters, q, &apply_filter(&2, &1, schema_struct, opts))
  end

  defp apply_filter(query, %Filter{field: nil}, _, _), do: query
  defp apply_filter(query, %Filter{value: nil}, _, _), do: query

  defp apply_filter(query, %Filter{} = filter, schema_struct, opts) do
    adapter = Keyword.get(opts, :adapter, Adapter.Ecto)
    adapter.apply_filter(query, filter, schema_struct, opts)
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
      iex> {:error, %Flop.Meta{} = meta} = Flop.validate(flop)
      iex> meta.errors
      [
        offset: [
          {"must be greater than or equal to %{number}",
           [validation: :number, kind: :greater_than_or_equal_to, number: 0]}
        ]
      ]

  It also makes sure that only one pagination method is used.

      iex> params = %{limit: 10, offset: 0, page: 5, page_size: 10}
      iex> {:error, %Flop.Meta{} = meta} = Flop.validate(params)
      iex> meta.errors
      [limit: [{"cannot combine multiple pagination types", []}]]

  If you derived `Flop.Schema` in your Ecto schema to define the filterable
  and sortable fields, you can pass the module name to the function to validate
  that only allowed fields are used. The function will also apply any default
  values set for the schema.

      iex> params = %{"order_by" => ["species"]}
      iex> {:error, %Flop.Meta{} = meta} = Flop.validate(params, for: MyApp.Pet)
      iex> [order_by: [{msg, [_, {_, enum}]}]] = meta.errors
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
  @doc group: :queries
  @spec validate(Flop.t() | map, [option()]) ::
          {:ok, Flop.t()} | {:error, Meta.t()}
  def validate(flop_or_map, opts \\ [])

  def validate(%Flop{} = flop, opts) do
    flop
    |> flop_struct_to_map()
    |> validate(opts)
  end

  def validate(%{} = params, opts) do
    result =
      params
      |> Flop.Validation.changeset(opts)
      |> Changeset.apply_action(:replace)

    case result do
      {:ok, _} = r ->
        r

      {:error, %Changeset{} = changeset} ->
        Logger.debug("Invalid Flop: #{inspect(changeset)}")
        {:error, Meta.with_errors(params, convert_errors(changeset), opts)}
    end
  end

  defp convert_errors(changeset) do
    changeset
    |> Changeset.traverse_errors(& &1)
    |> map_to_keyword()
  end

  defp map_to_keyword(%{} = map) do
    Enum.into(map, [], fn {key, value} -> {key, map_to_keyword(value)} end)
  end

  defp map_to_keyword(list) when is_list(list) do
    Enum.map(list, &map_to_keyword/1)
  end

  defp map_to_keyword(value), do: value

  defp flop_struct_to_map(%Flop{} = flop) do
    flop
    |> Map.from_struct()
    |> Map.update!(:filters, &filters_to_maps/1)
    |> Enum.reject(fn {_, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end

  defp filters_to_maps(nil), do: nil

  defp filters_to_maps(filters) when is_list(filters),
    do: Enum.map(filters, &filter_to_map/1)

  defp filter_to_map(%Filter{} = filter) do
    filter
    |> Map.from_struct()
    |> Enum.reject(fn {_, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end

  defp filter_to_map(%{} = filter), do: filter

  @doc """
  Same as `Flop.validate/2`, but raises an `Ecto.InvalidChangesetError` if the
  parameters are invalid.
  """
  @doc group: :queries
  @doc since: "0.5.0"
  @spec validate!(Flop.t() | map, [option()]) :: Flop.t()
  def validate!(flop_or_map, opts \\ []) do
    case validate(flop_or_map, opts) do
      {:ok, flop} ->
        flop

      {:error, %Meta{errors: errors, params: params}} ->
        raise Flop.InvalidParamsError, errors: errors, params: params
    end
  end

  @doc """
  Sets the page value of a `Flop` struct while also removing/converting
  pagination parameters for other pagination types.

      iex> set_page(%Flop{page: 2, page_size: 10}, 6)
      %Flop{page: 6, page_size: 10}

      iex> set_page(%Flop{limit: 10, offset: 20}, 8)
      %Flop{limit: nil, offset: nil, page: 8, page_size: 10}

      iex> set_page(%Flop{page: 2, page_size: 10}, "6")
      %Flop{page: 6, page_size: 10}

  The page number will not be allowed to go below 1.

      iex> set_page(%Flop{}, -5)
      %Flop{page: 1}
  """
  @doc since: "0.12.0"
  @doc group: :parameters
  @spec set_page(Flop.t(), pos_integer | binary) :: Flop.t()
  def set_page(%Flop{} = flop, page) when is_integer(page) do
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

  def set_page(%Flop{} = flop, page) when is_binary(page) do
    set_page(flop, String.to_integer(page))
  end

  @doc """
  Sets the page of a Flop struct to the previous page, but not less than 1.

  ## Examples

      iex> to_previous_page(%Flop{page: 5})
      %Flop{page: 4}

      iex> to_previous_page(%Flop{page: 1})
      %Flop{page: 1}

      iex> to_previous_page(%Flop{page: -2})
      %Flop{page: 1}
  """
  @doc since: "0.15.0"
  @doc group: :parameters
  @spec to_previous_page(Flop.t()) :: Flop.t()
  def to_previous_page(%Flop{page: 1} = flop), do: flop

  def to_previous_page(%Flop{page: page} = flop)
      when is_integer(page) and page < 1,
      do: %{flop | page: 1}

  def to_previous_page(%Flop{page: page} = flop) when is_integer(page),
    do: %{flop | page: page - 1}

  @doc """
  Sets the page of a Flop struct to the next page.

  If the total number of pages is given as the second argument, the page number
  will not be increased if the last page has already been reached. You can get
  the total number of pages from the `Flop.Meta` struct.

  ## Examples

      iex> to_next_page(%Flop{page: 5})
      %Flop{page: 6}

      iex> to_next_page(%Flop{page: 5}, 6)
      %Flop{page: 6}

      iex> to_next_page(%Flop{page: 6}, 6)
      %Flop{page: 6}

      iex> to_next_page(%Flop{page: 7}, 6)
      %Flop{page: 6}

      iex> to_next_page(%Flop{page: -5})
      %Flop{page: 1}
  """
  @doc since: "0.15.0"
  @doc group: :parameters
  @spec to_next_page(Flop.t(), non_neg_integer | nil) :: Flop.t()
  def to_next_page(flop, total_pages \\ nil)

  def to_next_page(%Flop{page: page} = flop, _)
      when is_integer(page) and page < 0,
      do: %{flop | page: 1}

  def to_next_page(%Flop{page: page} = flop, nil), do: %{flop | page: page + 1}

  def to_next_page(%Flop{page: page} = flop, total_pages)
      when is_integer(total_pages) and page < total_pages,
      do: %{flop | page: page + 1}

  def to_next_page(%Flop{} = flop, total_pages)
      when is_integer(total_pages),
      do: %{flop | page: total_pages}

  @doc """
  Sets the offset value of a `Flop` struct while also removing/converting
  pagination parameters for other pagination types.

      iex> set_offset(%Flop{limit: 10, offset: 10}, 20)
      %Flop{offset: 20, limit: 10}

      iex> set_offset(%Flop{page: 5, page_size: 10}, 20)
      %Flop{limit: 10, offset: 20, page: nil, page_size: nil}

      iex> set_offset(%Flop{limit: 10, offset: 10}, "20")
      %Flop{offset: 20, limit: 10}

  The offset will not be allowed to go below 0.

      iex> set_offset(%Flop{}, -5)
      %Flop{offset: 0}
  """
  @doc since: "0.15.0"
  @doc group: :parameters
  @spec set_offset(Flop.t(), non_neg_integer | binary) :: Flop.t()
  def set_offset(%Flop{} = flop, offset) when is_integer(offset) do
    %{
      flop
      | after: nil,
        before: nil,
        first: nil,
        last: nil,
        limit: flop.limit || flop.page_size || flop.first || flop.last,
        offset: max(offset, 0),
        page_size: nil,
        page: nil
    }
  end

  def set_offset(%Flop{} = flop, offset) when is_binary(offset) do
    set_offset(flop, String.to_integer(offset))
  end

  @doc """
  Sets the offset of a Flop struct to the page depending on the limit.

  ## Examples

      iex> to_previous_offset(%Flop{offset: 20, limit: 10})
      %Flop{offset: 10, limit: 10}

      iex> to_previous_offset(%Flop{offset: 5, limit: 10})
      %Flop{offset: 0, limit: 10}

      iex> to_previous_offset(%Flop{offset: 0, limit: 10})
      %Flop{offset: 0, limit: 10}

      iex> to_previous_offset(%Flop{offset: -2, limit: 10})
      %Flop{offset: 0, limit: 10}
  """
  @doc since: "0.15.0"
  @doc group: :parameters
  @spec to_previous_offset(Flop.t()) :: Flop.t()
  def to_previous_offset(%Flop{offset: 0} = flop), do: flop

  def to_previous_offset(%Flop{offset: offset, limit: limit} = flop)
      when is_integer(limit) and is_integer(offset),
      do: %{flop | offset: max(0, offset - limit)}

  @doc """
  Sets the offset of a Flop struct to the next page depending on the limit.

  If the total count is given as the second argument, the offset will not be
  increased if the last page has already been reached. You can get the total
  count from the `Flop.Meta` struct. If the Flop has an offset beyond the total
  count, the offset will be set to the last page.

  ## Examples

      iex> to_next_offset(%Flop{offset: 10, limit: 5})
      %Flop{offset: 15, limit: 5}

      iex> to_next_offset(%Flop{offset: 15, limit: 5}, 21)
      %Flop{offset: 20, limit: 5}

      iex> to_next_offset(%Flop{offset: 15, limit: 5}, 20)
      %Flop{offset: 15, limit: 5}

      iex> to_next_offset(%Flop{offset: 28, limit: 5}, 22)
      %Flop{offset: 20, limit: 5}

      iex> to_next_offset(%Flop{offset: -5, limit: 20})
      %Flop{offset: 0, limit: 20}
  """
  @doc since: "0.15.0"
  @doc group: :parameters
  @spec to_next_offset(Flop.t(), non_neg_integer | nil) :: Flop.t()
  def to_next_offset(flop, total_count \\ nil)

  def to_next_offset(%Flop{limit: limit, offset: offset} = flop, _)
      when is_integer(limit) and is_integer(offset) and offset < 0,
      do: %{flop | offset: 0}

  def to_next_offset(%Flop{limit: limit, offset: offset} = flop, nil)
      when is_integer(limit) and is_integer(offset),
      do: %{flop | offset: offset + limit}

  def to_next_offset(%Flop{limit: limit, offset: offset} = flop, total_count)
      when is_integer(limit) and
             is_integer(offset) and
             is_integer(total_count) and offset >= total_count do
    %{flop | offset: (ceil(total_count / limit) - 1) * limit}
  end

  def to_next_offset(%Flop{limit: limit, offset: offset} = flop, total_count)
      when is_integer(limit) and
             is_integer(offset) and
             is_integer(total_count) do
    case offset + limit do
      new_offset when new_offset >= total_count -> flop
      new_offset -> %{flop | offset: new_offset}
    end
  end

  @doc """
  Takes a `Flop.Meta` struct and returns a `Flop` struct with updated cursor
  pagination params for going to either the previous or the next page.

  See `to_previous_cursor/1` and `to_next_cursor/1` for details.

  ## Examples

      iex> set_cursor(
      ...>   %Flop.Meta{
      ...>     flop: %Flop{first: 5, after: "a"},
      ...>     has_previous_page?: true, start_cursor: "b"
      ...>   },
      ...>   :previous
      ...> )
      %Flop{last: 5, before: "b"}

      iex> set_cursor(
      ...>   %Flop.Meta{
      ...>     flop: %Flop{first: 5, after: "a"},
      ...>     has_next_page?: true, end_cursor: "b"
      ...>   },
      ...>   :next
      ...> )
      %Flop{first: 5, after: "b"}
  """
  @doc since: "0.15.0"
  @doc group: :parameters
  @spec set_cursor(Meta.t(), :previous | :next) :: Flop.t()
  def set_cursor(%Meta{} = meta, :previous), do: to_previous_cursor(meta)
  def set_cursor(%Meta{} = meta, :next), do: to_next_cursor(meta)

  @doc """
  Takes a `Flop.Meta` struct and returns a `Flop` struct with updated cursor
  pagination params for going to the previous page.

  ## Examples

      iex> to_previous_cursor(
      ...>   %Flop.Meta{
      ...>     flop: %Flop{first: 5, after: "a"},
      ...>     has_previous_page?: true, start_cursor: "b"
      ...>   }
      ...> )
      %Flop{last: 5, before: "b"}

      iex> to_previous_cursor(
      ...>   %Flop.Meta{
      ...>     flop: %Flop{last: 5, before: "b"},
      ...>     has_previous_page?: true, start_cursor: "a"
      ...>   }
      ...> )
      %Flop{last: 5, before: "a"}

  If there is no previous page, the `Flop` struct is returned unchanged.

      iex> to_previous_cursor(
      ...>   %Flop.Meta{
      ...>     flop: %Flop{first: 5, after: "b"},
      ...>     has_previous_page?: false, start_cursor: "a"
      ...>   }
      ...> )
      %Flop{first: 5, after: "b"}

  It can happen that `has_previous_page?` is `true`, but no start cursor is set,
  for example if the user is on the next-to-last page and switches to the next
  page right after the only item on the last page is deleted. Since the result
  set would be empty and there is no start cursor in this case, this function
  sets the new `before` parameter to `nil`. By doing this, the user is sent to
  the actual last page without skipping any items.

      iex> to_previous_cursor(
      ...>   %Flop.Meta{
      ...>     flop: %Flop{first: 5, after: "a"},
      ...>     has_previous_page?: true, start_cursor: nil
      ...>   }
      ...> )
      %Flop{last: 5, before: nil}

      iex> to_previous_cursor(
      ...>   %Flop.Meta{
      ...>     flop: %Flop{last: 5, before: "b"},
      ...>     has_previous_page?: true, start_cursor: nil
      ...>   }
      ...> )
      %Flop{last: 5, before: nil}
  """
  @doc since: "0.15.0"
  @doc group: :parameters
  @spec to_previous_cursor(Meta.t()) :: Flop.t()
  def to_previous_cursor(%Meta{
        flop: %Flop{} = flop,
        has_previous_page?: false
      }),
      do: flop

  def to_previous_cursor(%Meta{
        flop: %Flop{} = flop,
        has_previous_page?: true,
        start_cursor: start_cursor
      }) do
    %{
      flop
      | before: start_cursor,
        last: flop.last || flop.first || flop.page_size || flop.limit,
        after: nil,
        first: nil,
        page: nil,
        page_size: nil,
        limit: nil,
        offset: nil
    }
  end

  @doc """
  Takes a `Flop.Meta` struct and returns a `Flop` struct with updated cursor
  pagination params for going to the next page.

  ## Examples

      iex> to_next_cursor(
      ...>   %Flop.Meta{
      ...>     flop: %Flop{first: 5, after: "a"},
      ...>     has_next_page?: true, end_cursor: "b"
      ...>   }
      ...> )
      %Flop{first: 5, after: "b"}

      iex> to_next_cursor(
      ...>   %Flop.Meta{
      ...>     flop: %Flop{last: 5, before: "b"},
      ...>     has_next_page?: true, end_cursor: "a"
      ...>   }
      ...> )
      %Flop{first: 5, after: "a"}

  If there is no next page, the `Flop` struct is returned unchanged.

      iex> to_next_cursor(
      ...>   %Flop.Meta{
      ...>     flop: %Flop{first: 5, after: "a"},
      ...>     has_next_page?: false, start_cursor: "b"
      ...>   }
      ...> )
      %Flop{first: 5, after: "a"}

  It can happen that `has_next_page?` is `true`, but no end cursor is set,
  for example if the user is on the second page and switches to the previous
  page right after the only item on the first page is deleted. Since the result
  set is empty and there is no end cursor in this case, this function sets the
  new `after` parameter to `nil`. By doing this, the user is sent to the first
  page without skipping any items.

      iex> to_next_cursor(
      ...>   %Flop.Meta{
      ...>     flop: %Flop{first: 5, after: "a"},
      ...>     has_next_page?: true, end_cursor: nil
      ...>   }
      ...> )
      %Flop{first: 5, after: nil}

      iex> to_next_cursor(
      ...>   %Flop.Meta{
      ...>     flop: %Flop{last: 5, before: "b"},
      ...>     has_next_page?: true, end_cursor: nil
      ...>   }
      ...> )
      %Flop{first: 5, after: nil}
  """
  @doc since: "0.15.0"
  @doc group: :parameters
  @spec to_next_cursor(Meta.t()) :: Flop.t()
  def to_next_cursor(%Meta{flop: %Flop{} = flop, has_next_page?: false}),
    do: flop

  def to_next_cursor(%Meta{
        flop: %Flop{} = flop,
        has_next_page?: true,
        end_cursor: end_cursor
      }) do
    %{
      flop
      | after: end_cursor,
        first: flop.first || flop.last || flop.page_size || flop.limit,
        before: nil,
        last: nil,
        page: nil,
        page_size: nil,
        limit: nil,
        offset: nil
    }
  end

  @doc """
  Removes the `after` and `before` cursors from a Flop struct.

  ## Example

      iex> reset_cursors(%Flop{after: "A"})
      %Flop{}

      iex> reset_cursors(%Flop{before: "A"})
      %Flop{}
  """
  @doc since: "0.15.0"
  @doc group: :parameters
  @spec reset_cursors(Flop.t()) :: Flop.t()
  def reset_cursors(%Flop{} = flop), do: %{flop | after: nil, before: nil}

  @doc """
  Removes all filters from a Flop struct.

  ## Example

      iex> reset_filters(%Flop{filters: [
      ...>   %Flop.Filter{field: :name, value: "Jim"}
      ...> ]})
      %Flop{filters: []}
  """
  @doc since: "0.15.0"
  @doc group: :parameters
  @spec reset_filters(Flop.t()) :: Flop.t()
  def reset_filters(%Flop{} = flop), do: %{flop | filters: []}

  @doc """
  Returns the current order direction for the given field.

  ## Examples

      iex> flop = %Flop{order_by: [:name, :age], order_directions: [:desc]}
      iex> current_order(flop, :name)
      :desc
      iex> current_order(flop, :age)
      :asc
      iex> current_order(flop, :species)
      nil
  """
  @doc since: "0.15.0"
  @doc group: :parameters
  @spec current_order(Flop.t(), atom) :: order_direction() | nil
  def current_order(
        %Flop{order_by: order_by, order_directions: order_directions},
        field
      )
      when is_atom(field) do
    get_order_direction(order_directions, get_index(order_by, field))
  end

  @doc """
  Removes the order parameters from a Flop struct.

  ## Example

      iex> reset_order(%Flop{order_by: [:name], order_directions: [:asc]})
      %Flop{order_by: nil, order_directions: nil}
  """
  @doc since: "0.15.0"
  @doc group: :parameters
  @spec reset_order(Flop.t()) :: Flop.t()
  def reset_order(%Flop{} = flop),
    do: %{flop | order_by: nil, order_directions: nil}

  @doc """
  Updates the `order_by` and `order_directions` values of a `Flop` struct.

  - If the field is not in the current `order_by` value, it will be prepended to
    the list. By default, the order direction for the field will be set to
    `:asc`.
  - If the field is already at the front of the `order_by` list, the order
    direction will be reversed.
  - If the field is already in the list, but not at the front, it will be moved
    to the front and the order direction will be set to `:asc` (or the custom
    asc direction supplied in the `:directions` option).
  - If the `:directions` option——a 2-element tuple——is passed, the first and
    second elements will be used as custom sort declarations for ascending and
    descending, respectively.

  ## Examples

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

  By default, the function toggles between `:asc` and `:desc`. You can override
  this with the `:directions` option.

      iex> directions = {:asc_nulls_last, :desc_nulls_last}
      iex> flop = push_order(%Flop{}, :ttfb, directions: directions)
      iex> flop.order_by
      [:ttfb]
      iex> flop.order_directions
      [:asc_nulls_last]
      iex> flop = push_order(flop, :ttfb, directions: directions)
      iex> flop.order_by
      [:ttfb]
      iex> flop.order_directions
      [:desc_nulls_last]

  This also allows you to sort in descending order initially.

      iex> directions = {:desc, :asc}
      iex> flop = push_order(%Flop{}, :ttfb, directions: directions)
      iex> flop.order_by
      [:ttfb]
      iex> flop.order_directions
      [:desc]
      iex> flop = push_order(flop, :ttfb, directions: directions)
      iex> flop.order_by
      [:ttfb]
      iex> flop.order_directions
      [:asc]

  If a string is passed as the second argument, it will be converted to an atom
  using `String.to_existing_atom/1`. If the atom does not exist, the `Flop`
  struct will be returned unchanged.

      iex> flop = push_order(%Flop{}, "name")
      iex> flop.order_by
      [:name]
      iex> flop = push_order(%Flop{}, "this_atom_does_not_exist")
      iex> flop.order_by
      nil

  Since the pagination cursor depends on the sort order, the `:before` and
  `:after` parameters are reset.

      iex> push_order(%Flop{order_by: [:id], after: "ABC"}, :name)
      %Flop{order_by: [:name, :id], order_directions: [:asc], after: nil}
      iex> push_order(%Flop{order_by: [:id], before: "DEF"}, :name)
      %Flop{order_by: [:name, :id], order_directions: [:asc], before: nil}
  """
  @spec push_order(Flop.t(), atom | String.t(), keyword) :: Flop.t()
  @doc since: "0.10.0"
  @doc group: :parameters
  def push_order(flop, field, opts \\ [])

  def push_order(
        %Flop{order_by: order_by, order_directions: order_directions} = flop,
        field,
        opts
      )
      when is_atom(field) do
    previous_index = get_index(order_by, field)
    previous_direction = get_order_direction(order_directions, previous_index)

    directions = Keyword.get(opts, :directions, nil)

    new_direction =
      new_order_direction(previous_index, previous_direction, directions)

    {order_by, order_directions} =
      get_new_order(
        order_by,
        order_directions,
        field,
        new_direction,
        previous_index
      )

    %{
      flop
      | after: nil,
        before: nil,
        order_by: order_by,
        order_directions: order_directions
    }
  end

  def push_order(flop, field, opts) when is_binary(field) do
    push_order(flop, String.to_existing_atom(field), opts)
  rescue
    _e in ArgumentError -> flop
  end

  defp get_index(nil, _field), do: nil
  defp get_index(order_by, field), do: Enum.find_index(order_by, &(&1 == field))

  defp get_order_direction(_, nil), do: nil
  defp get_order_direction(nil, _), do: :asc

  defp get_order_direction(directions, index),
    do: Enum.at(directions, index, :asc)

  defp new_order_direction(0, current_direction, nil),
    do: reverse_direction(current_direction)

  defp new_order_direction(0, current_direction, {_asc, desc})
       when is_asc_direction(current_direction) and is_desc_direction(desc),
       do: desc

  defp new_order_direction(0, current_direction, {desc, _asc})
       when is_asc_direction(current_direction) and is_desc_direction(desc),
       do: desc

  defp new_order_direction(0, current_direction, {asc, _desc})
       when is_desc_direction(current_direction) and is_asc_direction(asc),
       do: asc

  defp new_order_direction(0, current_direction, {_desc, asc})
       when is_desc_direction(current_direction) and is_asc_direction(asc),
       do: asc

  defp new_order_direction(0, _current_direction, directions) do
    raise Flop.InvalidDirectionsError, directions: directions
  end

  defp new_order_direction(_, _, nil), do: :asc
  defp new_order_direction(_, _, {asc, _desc}) when is_direction(asc), do: asc

  defp new_order_direction(_, _, directions) do
    raise Flop.InvalidDirectionsError, directions: directions
  end

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

  @doc """
  Returns the option with the given key.

  The look-up order is:

  1. the keyword list passed as the second argument
  2. the schema module that derives `Flop.Schema`, if the passed list includes
     the `:for` option
  3. the backend module with `use Flop`
  4. the application environment
  5. the default passed as the last argument
  """
  @doc since: "0.11.0"
  @doc group: :miscellaneous
  @spec get_option(atom, [option()], any) :: any
  def get_option(key, opts, default \\ nil) do
    with nil <- opts[key],
         nil <- schema_option(opts[:for], key),
         nil <- backend_option(opts[:backend], key),
         nil <- global_option(key) do
      Keyword.get(@default_opts, key, default)
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
                :default_pagination_type,
                :sortable
              ] do
    apply(Flop.Schema, key, [struct(module)])
  end

  defp schema_option(_, _), do: nil

  defp backend_option(module, key)
       when is_atom(module) and module != nil do
    module.__flop_options__()[key]
  end

  defp backend_option(_, _), do: nil

  defp global_option(key) when is_atom(key) do
    Application.get_env(:flop, key)
  end

  @doc """
  Converts key/value filter parameters at the root of a map, converts them into
  a list of filter parameter maps and nests them under the `:filters` key.

  This is useful in cases where you get some or all filter parameters as
  key/value pairs instead of a full map with operators, for example when you
  expose certain filters with fixed operators on an API, or if you want to
  reflect some or all filters in the URL as path parameters or simple query
  parameters (e.g. `/posts/{tag}` or `/posts?s=searchterm`).

  The given map should have either string keys or atom keys. Passing a map with
  mixed keys will lead to unexpected results and will cause an Ecto error when
  the return value is passed to one of the validation functions.

  The second argument is a list of fields as atoms.

  The `opts` argument is passed to `map_to_filter_params/2`.

  The function returns a map that eventually needs to be passed to one of the
  Flop validation functions (any `Flop.validate*` function) before it can be
  used to make a query.

  ## Examples

  Map with atom keys

      iex> nest_filters(%{name: "Peter", page_size: 10}, [:name])
      %{filters: [%{field: :name, op: :==, value: "Peter"}], page_size: 10}

  Map with string keys

      iex> nest_filters(%{"name" => "Peter"}, [:name])
      %{"filters" => [%{"field" => "name", "op" => :==, "value" =>  "Peter"}]}

  Specifying operators

      iex> nest_filters(%{name: "Peter"}, [:name], operators: %{name: :!=})
      %{filters: [%{field: :name, op: :!=, value: "Peter"}]}

  Renaming fields

      iex> nest_filters(%{nombre: "Peter", page_size: 10}, [:nombre],
      ...>   rename: %{nombre: :name}
      ...> )
      %{filters: [%{field: :name, op: :==, value: "Peter"}], page_size: 10}

      iex> nest_filters(%{"nombre" => "Peter"}, [:nombre],
      ...>   rename: %{nombre: :name}
      ...> )
      %{"filters" => [%{"field" => "name", "op" => :==, "value" =>  "Peter"}]}

      iex> nest_filters(%{"nombre" => "Peter"}, [:nombre],
      ...>   rename: %{nombre: :name},
      ...>   operators: %{name: :like}
      ...> )
      %{"filters" => [%{"field" => "name", "op" => :like, "value" =>  "Peter"}]}

  If the map already has a `filters` key, the extracted filters are added to
  the existing filters.

      iex> nest_filters(%{name: "Peter", filters: [%{field: "age", op: ">", value: 25}]}, [:name])
      %{filters: [%{field: "age", op: ">", value: 25}, %{field: :name, op: :==, value: "Peter"}]}

      iex> nest_filters(%{"name" => "Peter", "filters" => [%{"field" => "age", "op" => ">", "value" => 25}]}, [:name])
      %{"filters" => [%{"field" => "age", "op" => ">", "value" => 25}, %{"field" => "name", "op" => :==, "value" => "Peter"}]}

  If the existing filters are formatted as a map with integer indexes as keys as
  produced by a form, the map is converted to a list first.

      iex> nest_filters(%{name: "Peter", filters: %{"0" => %{field: "age", op: ">", value: 25}}}, [:name])
      %{filters: [%{field: "age", op: ">", value: 25}, %{field: :name, op: :==, value: "Peter"}]}

      iex> nest_filters(%{"name" => "Peter", "filters" => %{"0" => %{"field" => "age", "op" => ">", "value" => 25}}}, [:name])
      %{"filters" => [%{"field" => "age", "op" => ">", "value" => 25}, %{"field" => "name", "op" => :==, "value" => "Peter"}]}
  """
  @doc since: "0.15.0"
  @doc group: :parameters
  @spec nest_filters(map, [atom | String.t()], keyword) :: map
  def nest_filters(%{} = args, fields, opts \\ []) when is_list(fields) do
    fields = fields ++ Enum.map(fields, &Atom.to_string/1)

    filters =
      args
      |> Map.take(fields)
      |> map_to_filter_params(opts)

    key = if has_atom_keys?(args), do: :filters, else: "filters"

    args
    |> Map.update(key, [], &map_to_list/1)
    |> Map.update!(key, &(&1 ++ filters))
    |> Map.drop(fields)
  end

  defp has_atom_keys?(%{} = map) do
    map
    |> Map.keys()
    |> List.first()
    |> is_atom()
  end

  defp map_to_list(%{} = map), do: Map.values(map)
  defp map_to_list(nil), do: []
  defp map_to_list(list) when is_list(list), do: list

  @doc """
  Takes a Flop, converts it to a map and unnests the filters for the given
  fields.

  This is the reverse operation of `nest_filters/3`, with the caveat that the
  result of `nest_filters/3` needs to be validated to convert it to a `Flop`
  struct before it can be passed back to `unnest_filters/3`.

  The function returns a map with `nil` values removed.

  ## Examples

      iex> unnest_filters(
      ...>   %Flop{
      ...>     filters: [%Flop.Filter{field: :name, op: :==, value: "Peter"}],
      ...>     page_size: 10
      ...>   },
      ...>   [:name]
      ...> )
      %{name: "Peter", page_size: 10}

      iex> unnest_filters(
      ...>   %Flop{
      ...>     filters: [%Flop.Filter{field: :name, op: :==, value: nil}],
      ...>     page_size: 10
      ...>   },
      ...>   [:name]
      ...> )
      %{page_size: 10}

  To rename fields, you can pass a map, where the keys are the field names in
  the unnested map and the values are the field names in the `Flop.Filter`
  struct. You can pass the exact same rename map to `nest_filters/3` and
  `unnest_filters/3` to revert the nesting/unnesting.

      iex> unnest_filters(
      ...>   %Flop{
      ...>     filters: [%Flop.Filter{field: :name, op: :==, value: "Peter"}],
      ...>     page_size: 10
      ...>   },
      ...>   [:name],
      ...>   rename: %{nombre: :name}
      ...> )
      %{nombre: "Peter", page_size: 10}
  """
  @doc since: "0.20.0"
  @doc group: :parameters
  @spec unnest_filters(Flop.t(), [atom], keyword) :: map
  def unnest_filters(%Flop{filters: filters} = flop, fields, opts \\ [])
      when is_list(fields) do
    renamings = Enum.into(opts[:rename] || %{}, %{}, fn {k, v} -> {v, k} end)

    {to_unnest, remaining} = Enum.split_with(filters, &(&1.field in fields))

    unnested_map =
      Enum.into(to_unnest, %{}, &{rename_field(&1.field, renamings), &1.value})

    remaining_maps =
      remaining
      |> Enum.map(&Map.from_struct/1)
      |> Enum.reject(&is_nil(&1.value))

    flop
    |> Map.from_struct()
    |> Map.merge(unnested_map)
    |> Map.put(:filters, remaining_maps)
    |> Enum.reject(fn
      {_, nil} -> true
      {_, []} -> true
      _ -> false
    end)
    |> Enum.into(%{})
  end

  @doc """
  Converts a map of filter conditions into a list of Flop filter params.

  The default operator is `:==`. `nil` values are excluded from the result.

      iex> params = map_to_filter_params(
      ...>   %{name: "George", age: 8, species: nil}
      ...> )
      iex> Enum.sort(params)
      [
        %{field: :age, op: :==, value: 8},
        %{field: :name, op: :==, value: "George"}
      ]

      iex> params = map_to_filter_params(
      ...>   %{"name" => "George", "age" => 8, "cat" => true}
      ...>  )
      iex> Enum.sort(params)
      [
        %{"field" => "age", "op" => :==, "value" => 8},
        %{"field" => "cat", "op" => :==, "value" => true},
        %{"field" => "name", "op" => :==, "value" => "George"}
      ]

  You can optionally pass a mapping from field names to operators as a map
  with atom keys.

      iex> params = map_to_filter_params(
      ...>   %{name: "George", age: 8, species: nil},
      ...>   operators: %{name: :ilike_and}
      ...> )
      iex> Enum.sort(params)
      [
        %{field: :age, op: :==, value: 8},
        %{field: :name, op: :ilike_and, value: "George"}
      ]

      iex> map_to_filter_params(
      ...>   %{"name" => "George", "age" => 8, "cat" => true},
      ...>   operators: %{name: :ilike_and, age: :<=}
      ...> )
      [
        %{"field" => "age", "op" => :<=, "value" => 8},
        %{"field" => "cat", "op" => :==, "value" => true},
        %{"field" => "name", "op" => :ilike_and, "value" => "George"}
      ]

  You can also pass a map to rename fields.

      iex> params = map_to_filter_params(
      ...>   %{s: "George", age: 8, species: nil},
      ...>   rename: %{s: :name}
      ...> )
      iex> Enum.sort(params)
      [
        %{field: :age, op: :==, value: 8},
        %{field: :name, op: :==, value: "George"}
      ]

      iex> map_to_filter_params(
      ...>   %{"s" => "George", "cat" => true},
      ...>   rename: %{s: :name, cat: :dog}
      ...> )
      [
        %{"field" => "dog", "op" => :==, "value" => true},
        %{"field" => "name", "op" => :==, "value" => "George"}
      ]

  If both a rename option and an operator are set for a field, the operator
  option needs to use the new field name.

      iex> map_to_filter_params(
      ...>   %{n: "George"},
      ...>   rename: %{n: :name},
      ...>   operators: %{name: :ilike_or}
      ...> )
      [%{field: :name, op: :ilike_or, value: "George"}]

  See also `Flop.Filter.new/2`.
  """
  @doc since: "0.14.0"
  @doc group: :parameters
  @spec map_to_filter_params(map, keyword) :: [map]
  def map_to_filter_params(%{} = map, opts \\ []) do
    operators = opts[:operators]
    renamings = opts[:rename]

    map
    |> Stream.reject(fn
      {_, nil} -> true
      _ -> false
    end)
    |> Enum.map(fn
      {field, value} when is_atom(field) ->
        field = rename_field(field, renamings)

        %{
          field: field,
          op: op_from_mapping(field, operators),
          value: value
        }

      {field, value} when is_binary(field) ->
        field = field |> rename_field(renamings) |> to_string()

        %{
          "field" => field,
          "op" => op_from_mapping(field, operators),
          "value" => value
        }
    end)
  end

  defp op_from_mapping(_field, nil), do: :==

  defp op_from_mapping(field, %{} = operators) when is_atom(field) do
    Map.get(operators, field, :==)
  end

  defp op_from_mapping(field, %{} = operators) when is_binary(field) do
    atom_key = String.to_existing_atom(field)
    Map.get(operators, atom_key, :==)
  rescue
    ArgumentError -> :==
  end

  defp rename_field(field, nil), do: field

  defp rename_field(field, %{} = renamings) when is_atom(field) do
    Map.get(renamings, field, field)
  end

  defp rename_field(field, %{} = renamings) when is_binary(field) do
    atom_key = String.to_existing_atom(field)
    Map.get(renamings, atom_key, field)
  rescue
    ArgumentError -> field
  end

  @doc """
  Returns the names of the bindings that are required for the filters and order
  clauses of the given Flop.

  The second argument is the schema module that derives `Flop.Schema`.

  For example, your schema module might define a join field called `:owner_age`.

      @derive {
        Flop.Schema,
        filterable: [:name, :owner_age],
        sortable: [:name, :owner_age],
        adapter_opts: [
          join_fields: [owner_age: {:owner, :age}]
        ]
      }

  If you pass a Flop with a filter on the `:owner_age` field, the returned list
  will include the `:owner` binding.

      iex> named_bindings(
      ...>   %Flop{
      ...>     filters: [%Flop.Filter{field: :owner_age, op: :==, value: 5}]
      ...>   },
      ...>   MyApp.Pet
      ...> )
      [:owner]

  If on the other hand only normal fields or compound fields are used in the
  filter and order options, or if the filter values are nil, an empty list will
  be returned.

      iex> named_bindings(
      ...>   %Flop{
      ...>     filters: [
      ...>       %Flop.Filter{field: :name, op: :==, value: "George"},
      ...>       %Flop.Filter{field: :owner_age, op: :==, value: nil}
      ...>     ]
      ...>   },
      ...>   MyApp.Pet
      ...> )
      []

  If a join field is part of a compound field, it will be returned.

      iex> named_bindings(
      ...>   %Flop{
      ...>     filters: [
      ...>       %Flop.Filter{field: :pet_and_owner_name, op: :==, value: "Mae"}
      ...>     ]
      ...>   },
      ...>   MyApp.Pet
      ...> )
      [:owner]

  For custom fields, you can set the `:bindings` option when you derive the
  `Flop.Schema` protocol.

  You can use this to dynamically build the join clauses needed for the query.
  See also `Flop.with_named_bindings/4`.

  For more information about join fields, refer to the module documentation of
  `Flop.Schema`.

  ## Options

  - `:order` - If `false`, only bindings needed for filtering are included.
    Defaults to `true`.
  """
  @doc since: "0.16.0"
  @doc group: :queries
  @spec named_bindings(Flop.t(), module, keyword) :: [atom]
  def named_bindings(
        %Flop{filters: filters, order_by: order_by},
        module,
        opts \\ []
      )
      when is_atom(module) do
    order = Keyword.get(opts, :order, true)
    order_by = if order, do: order_by || [], else: []
    filters = filters || []

    if order_by == [] && filters == [] do
      []
    else
      schema_struct = struct(module)

      filter_fields =
        filters |> Enum.reject(&is_nil(&1.value)) |> Enum.map(& &1.field)

      fields = Enum.uniq(order_by ++ filter_fields)

      fields
      |> Enum.map(&get_binding(schema_struct, &1))
      |> List.flatten()
      |> Enum.uniq()
    end
  end

  defp get_binding(schema_struct, field) when is_atom(field) do
    field_info = Flop.Schema.field_info(schema_struct, field)
    get_binding(schema_struct, field_info)
  end

  defp get_binding(_, %{extra: %{type: :join, binding: binding}}), do: binding
  defp get_binding(_, %{extra: %{type: :custom, bindings: bndgns}}), do: bndgns

  defp get_binding(struct, %{extra: %{type: :compound, fields: fields}}) do
    Enum.map(fields, &get_binding(struct, &1))
  end

  defp get_binding(_, _), do: []

  @doc """
  Applies a callback function to a query for all named bindings that are
  necessary for the given `Flop` parameters.

  The callback function must accept a queryable and the name of the binding and
  return a query that includes the given binding. This is the same as
  `Ecto.Query.with_named_binding/3`, except that the callback function _must_
  take the second argument.

  ## Options

  - `:for` (required) - The schema module that derives `Flop.Schema`.
  - `:order` - If `false`, only bindings needed for filtering are included.
    Defaults to `true`.

  ## Example

      def list_pets(params) do
        opts = [for: Pet]

        with {:ok, flop} <- Flop.validate(params, opts) do
          Pet
          |> Flop.with_named_bindings(flop, &join_pet_assocs/2, opts)
          |> Flop.run(flop, opts)
        end
      end

      defp join_pet_assocs(query, :owner) do
        join(query, [p], o in assoc(p, :owner), as: :owner)
      end

      defp join_pet_assocs(query, :toys) do
        join(query, [p], t in assoc(p, :toys), as: :toys)
      end

  Since the callback function has the same arguments and return value as the one
  passed to `Ecto.Query.with_named_binding/3`, you can reuse the function to add
  any other bindings you may need for the query besides the ones for Flop
  filters.

  This also means you can use `Ecto.Query.with_named_binding/3` to recursively
  add bindings in case you need intermediate joins to get to a nested
  association.

      def list_owners(params) do
        opts = [for: Owner]

        with {:ok, flop} <- Flop.validate(params, opts) do
          Pet
          |> Flop.with_named_bindings(flop, &join_owner_assocs/2, opts)
          |> Flop.run(flop, opts)
        end
      end

      defp join_owner_assocs(query, :pets) do
        join(query, [o], p in assoc(o, :pets), as: :pets)
      end

      defp join_owner_assocs(query, :toys) do
        query
        |> Ecto.Query.with_named_binding(:pets, &join_owner_assocs/2)
        |> join(query, [pets: p], t in assoc(p, :toys), as: :toys)
      end
  """
  @doc since: "0.19.0"
  @doc group: :queries
  @spec with_named_bindings(
          Ecto.Queryable.t(),
          Flop.t(),
          (Ecto.Queryable.t(), atom -> Ecto.Queryable.t()),
          keyword
        ) :: Ecto.Queryable.t()
  def with_named_bindings(query, %Flop{} = flop, fun, opts) do
    module = Keyword.fetch!(opts, :for)
    bindings = named_bindings(flop, module, opts)

    Enum.reduce(bindings, query, fn binding, acc_query ->
      Ecto.Query.with_named_binding(acc_query, binding, fun)
    end)
  end

  @doc """
  Returns the names of the alias fields that are required for the order clause
  of the given Flop.

  The second argument is the schema module that derives `Flop.Schema`.

  For example, your schema module might define an alias field called
  `:pet_count`.

      @derive {
        Flop.Schema,
        filterable: [],
        sortable: [:name, :pet_count],
        adapter_opts: [
          alias_fields: [:pet_count]
        ]
      }

  If you pass a Flop that orders by the `:pet_count` field, the returned list
  will include the `:pet_count` alias.

      iex> aliases(%Flop{order_by: [:name, :pet_count]}, MyApp.Owner)
      [:pet_count]

  If on the other hand only normal fields are used in the `order_by` parameter,
  an empty list will be returned.

      iex> aliases(%Flop{order_by: [:name]}, MyApp.Owner)
      []

  You can use this to dynamically build the select clause needed for the query.

  For more information about alias fields, refer to the module documentation of
  `Flop.Schema`.
  """
  @doc since: "0.18.0"
  @doc group: :queries
  @spec aliases(Flop.t(), module) :: [atom]
  def aliases(%Flop{order_by: order_by}, module) when is_atom(module) do
    if order_by == [] do
      []
    else
      schema_struct = struct(module)

      order_by
      |> filter_alias_fields(schema_struct)
      |> Enum.uniq()
    end
  end

  defp filter_alias_fields(order_fields, schema_struct) do
    Enum.reduce(order_fields, [], fn order_field, alias_fields ->
      case Flop.Schema.field_info(schema_struct, order_field) do
        %{extra: %{type: :alias}} -> [order_field | alias_fields]
        _ -> alias_fields
      end
    end)
  end
end
