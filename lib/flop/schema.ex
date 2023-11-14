defprotocol Flop.Schema do
  @moduledoc """
  Flop.Schema is a protocol that allows you to customize and set query options
  in your Ecto schemas.

  This module allows you to define which fields are filterable and sortable, set
  default and maximum limits, specify default sort orders, restrict pagination
  types, and more.

  ## Usage

  To utilize this protocol, derive `Flop.Schema` in your Ecto schema and define
  the filterable and sortable fields.

      defmodule MyApp.Pet do
        use Ecto.Schema

        @derive {
          Flop.Schema,
          filterable: [:name, :species],
          sortable: [:name, :age]
        }

        schema "pets" do
          field :name, :string
          field :age, :integer
          field :species, :string
        end
      end

  See `t:option/0` for an overview of all available options.

  > #### `@derive Flop.Schema` {: .info}
  >
  > When you derive `Flop.Schema`, all the functions required for the
  > `Flop.Schema` protocol will be defined based on the options you set.

  After that, you can pass the module as the `:for` option to `Flop.validate/2`.

      iex> Flop.validate(%Flop{order_by: [:name]}, for: MyApp.Pet)
      {:ok,
       %Flop{
         filters: [],
         limit: 50,
         offset: nil,
         order_by: [:name],
         order_directions: nil,
         page: nil,
         page_size: nil
       }}

      iex> {:error, %Flop.Meta{} = meta} = Flop.validate(
      ...>   %Flop{order_by: [:species]}, for: MyApp.Pet
      ...> )
      iex> meta.params
      %{"order_by" => [:species], "filters" => []}
      iex> meta.errors
      [
        order_by: [
          {"has an invalid entry",
           [validation: :subset, enum: [:name, :age, :owner_name, :owner_age]]}
        ]
      ]

  ## Default and maximum limits

  Define a default or maximum limit by setting the `default_limit` and
  `max_limit` options while deriving Flop.Schema. `Flop.validate/1` will apply
  the default limit and validate the maximum limit.

      @derive {
        Flop.Schema,
        filterable: [:name, :species],
        sortable: [:name, :age],
        max_limit: 100,
        default_limit: 50
      }

  ## Default sort order

  Specify a default sort order by setting the `default_order_by` and
  `default_order_directions` options when deriving Flop.Schema. The default
  values will be applied by `Flop.validate/1`. If no order directions are set,
  `:asc` is the default for all fields.

      @derive {
        Flop.Schema,
        filterable: [:name, :species],
        sortable: [:name, :age],
        default_order: %{
          order_by: [:name, :age],
          order_directions: [:asc, :desc]
        }
      }

  ## Restricting pagination types

  By default, `page`/`page_size`, `offset`/`limit` and cursor-based pagination
  (`first`/`after` and `last`/`before`) are enabled. If you wish to restrict the
  pagination type for a schema, you can set the `pagination_types` option.

      @derive {
        Flop.Schema,
        filterable: [:name, :species],
        sortable: [:name, :age],
        pagination_types: [:first, :last]
      }

  See also `t:Flop.option/0` and `t:Flop.pagination_type/0`. Setting the value
  to `nil` allows all pagination types.

  ## Alias fields

  To sort by calculated values, you can use `Ecto.Query.API.selected_as/2` in
  your query, define an alias field in your schema, and add the alias field to
  the list of sortable fields.

  Schema:

      @derive {
        Flop.Schema,
        filterable: [],
        sortable: [:pet_count],
        adapter_opts: [
          alias_fields: [:pet_count]
        ]
      }

  Query:

      Owner
      |> join(:left, [o], p in assoc(o, :pets), as: :pets)
      |> group_by([o], o.id)
      |> select(
        [o, pets: p],
        {o.id, p.id |> count() |> selected_as(:pet_count)}
      )
      |> Flop.validate_and_run(params, for: Owner)

  Note that it is not possible to use field aliases in `WHERE` clauses, which
  means you cannot add alias fields to the list of filterable fields, and you
  cannot sort by an alias field if you are using cursor-based pagination.

  ## Compound fields

  Sometimes you might need to apply a search term to multiple fields at once,
  e.g. you might want to search in both the family name and given name field.
  You can do that with Flop by defining a compound field.

      @derive {
        Flop.Schema,
        filterable: [:full_name],
        sortable: [:full_name],
        adapter_opts: [
          compound_fields: [full_name: [:family_name, :given_name]]
        ]
      }

  This allows you to use the field name `:full_name` as any other field in the
  filter and order parameters.

  ### Filtering

      params = %{
        filters: [%{
          field: :full_name,
          op: :like,
          value: "margo"
        }]
      }

  This would translate to:

      WHERE family_name like '%margo%' OR given_name like '%margo%'

  Partial matches of the search term can be achieved with one of
  the like operators.

      params = %{
        filters: [%{
          field: :full_name,
          op: :ilike_and,
          value: ["margo", "martindale"]
        }]
      }
  or
      params = %{
        filters: [%{
          field: :full_name,
          op: :ilike_and,
          value: "margo martindale"
        }]
      }
  This would translate to:

      WHERE (family_name ilike '%margo%' OR given_name ilike '%margo%')
      AND (family_name ilike '%martindale%' OR given_name ilike '%martindale%')

  ### Filter operator rules

  - `:=~` `:like` `:not_like` `:like_and` `:like_or` `:ilike` `:not_ilike` `:ilike_and` `:ilike_or`  
    If a string value is passed it will be split at whitespace
    characters and each segment will be checked separately. If a list of strings is
    passed the individual strings are not split. The filter matches for a value
    if it matches for any of the fields.
  - `:empty`  
    Matches if all fields of the compound field are `nil`.
  - `:not_empty`  
    Matches if any field of the compound field is not `nil`.
  - `:==` `:!=` `:<=` `:<` `:>=` `:>` `:in` `:not_in` `:contains` `:not_contains`  
    ** These filter operators are ignored for compound fields at the moment.
    This will be added in a future version.**  
    The filter value is normalized by splitting the string at whitespaces and
    joining it with a space. The values of all fields of the compound field are
    split by whitespace character and joined with a space, and the resulting
    values are joined with a space again.

  ### Sorting

      params = %{
        order_by: [:full_name],
        order_directions: [:desc]
      }

  This would translate to:

      ORDER BY family_name DESC, given_name DESC

  Note that compound fields cannot be used as pagination cursors.

  ## Join fields

  If you need to filter or order across tables, you can define join fields.

  As an example, let's define these schemas:

      schema "owners" do
        field :name, :string
        field :email, :string

        has_many :pets, Pet
      end

      schema "pets" do
        field :name, :string
        field :species, :string

        belongs_to :owner, Owner
      end

  And now we want to find all owners that have pets of the species
  `"E. africanus"`. To do this, first we need to define a join field on the
  `Owner` schema.

      @derive {
        Flop.Schema,
        filterable: [:pet_species],
        sortable: [:pet_species],
        adapter_opts: [
          join_fields: [
            pet_species: [
              binding: :pets,
              field: :species,
              ecto_type: :string
            ]
          ]
        ]
      }

  In this case, `:pet_species` would be the alias of the field that you can
  refer to in the filter and order parameters. The options are:

  - `:binding` - The named binding you set with the `:as` option in the join
    statement of your query.
  - `:field` - The field on that binding on which the filter should be applied.
  - `:ecto_type` - The Ecto type of the field. This allows Flop to validate
    filter values, and also to treat empty arrays and empty maps as empty values
    depending on the type. See also `Ecto type option` section below.

  In order to retrieve the pagination cursor value for a join field, Flop needs
  to know how to get the field value from the struct that is returned from the
  database. `Flop.Schema.get_field/2` is used for that. By default, Flop assumes
  that the binding name matches the name of the field for the association in
  your Ecto schema (the one you set with `has_one`, `has_many` or `belongs_to`).

  In the example above, Flop would try to access the field in the struct under
  the path `[:pets, :species]`.

  If you have joins across multiple tables, or if you can't give the binding
  the same name as the association field, you can specify the path explicitly.

      @derive {
        Flop.Schema,
        filterable: [:pet_species],
        sortable: [:pet_species],
        adapter_opts: [
          join_fields: [
            pet_species: [
              binding: :pets,
              field: :species,
              path: [:pets, :species]
            ]
          ]
        ]
      }

  After setting up the join fields, you can write a query like this:

      params = %{
        filters: [%{field: :pet_species, op: :==, value: "E. africanus"}]
      }

      Owner
      |> join(:left, [o], p in assoc(o, :pets), as: :pets)
      |> preload([pets: p], [pets: p])
      |> Flop.validate_and_run!(params, for: Owner)

  If your query returns data in a different format, you don't need to set the
  `:path` option. Instead, you can pass a custom cursor value function in the
  options. See `Flop.Cursor.get_cursors/2` and `t:Flop.option/0`.

  Note that Flop doesn't create the join clauses for you. The named bindings
  already have to be present in the query you pass to the Flop functions. You
  can use `Flop.with_named_bindings/4` or `Flop.named_bindings/3` to get the
  build the join clauses needed for a query dynamically and avoid adding
  unnecessary joins.

  ## Filtering by calculated values with subqueries

  You can join on a subquery with a named binding and add a join field as
  described above.

  Schema:

      @derive {
        Flop.Schema,
        filterable: [:pet_count],
        sortable: [:pet_count],
        adapter_opts: [
          join_fields: [
            pet_count: [
              binding: :pet_count,
              field: :count,
              ecto_type: :integer
            ]
          ]
        ]
      }

  Query:

      params = %{filters: [%{field: :pet_count, op: :>, value: 2}]}

      pet_count_query =
        Pet
        |> where([p], parent_as(:owner).id == p.owner_id)
        |> select([p], %{count: count(p)})

      q =
        (o in Owner)
        |> from(as: :owner)
        |> join(:inner_lateral, [owner: o], p in subquery(pet_count_query),
          as: :pet_count
        )
        |> Flop.validate_and_run(params, for: Owner)

  ## Custom fields

  Custom fields allow for precise control over filter queries, making it
  possible to implement filter logic that the built-in filtering options cannot
  satisfy.

  For example, you might need to handle dates and times in a particular way that
  takes into account different time zones, or perform database-specific queries
  using fragments.

  Custom field filters are referenced by a tuple
  `{mod :: module, function :: atom, opts :: keyword}`. The referenced function
  receives three arguments: the Ecto query, the Flop filter, and an options
  keyword list.

  If runtime options are necessary (like the timezone of the request or the user
  ID of the current user), use the `extra_opts` option when calling Flop
  functions.

  Note that as of now, custom fields only support filtering, not sorting.

  Schema:

      @derive {
        Flop.Schema,
        filterable: [:inserted_at_date],
        adapter_opts: [
          custom_fields: [
            inserted_at_date: [
              filter: {CustomFilters, :date_filter, [source: :inserted_at]},
              ecto_type: :date,
              operators: [:<=, :>=]
            ]
          ]
        ]
      }

  If you pass the `:ecto_type` option like above, the filter value will be
  automatically cast.

  Filter module:

      defmodule CustomFilters do
        import Ecto.Query

        def date_filter(query, %Flop.Filter{value: value, op: op}, opts) do
          source = Keyword.fetch!(opts, :source)
          timezone = Keyword.fetch!(opts, :timezone)

          expr = dynamic(
            [r],
            fragment("((? AT TIME ZONE 'utc') AT TIME ZONE ?)::date",
            field(r, ^source), ^timezone)
          )

          conditions =
            case op do
              :>= -> dynamic([r], ^expr >= ^value)
              :<= -> dynamic([r], ^expr <= ^value)
            end

          where(query, ^conditions)
        end
      end

  Query:

      Flop.validate_and_run(
        MyApp.Pet,
        params,
        for: MyApp.Pet,
        extra_opts: [timezone: timezone]
      )

  If your custom filter requires certain named bindings, you can use the
  `:bindings` option to specify them. Then, using `Flop.with_named_bindings/4`,
  these bindings can be conditionally added to your query based on filter
  conditions.

  ## Ecto type option

  Flop automatically retrieves the field type from the schema module for regular
  schema fields, enabling it to correctly cast filter values. Compound fields
  are always treated as string fields.

  For join and custom fields, Flop cannot automatically determine the Ecto type.
  Therefore, you need to specify the `ecto_type` option. This helps Flop cast
  filter values for join and custom fields properly. If this option is not set,
  Flop will accept any filter value, potentially leading to an
  `Ecto.Query.CastError` if an invalid filter value is used. Additionally,
  without this option, Flop cannot identify empty lists and maps as empty values
  for array and map fields.

      @derive {
        Flop.Schema,
        filterable: [:full_text, :pet_species],
        sortable: [:id],
        adapter_opts: [
          join_fields: [
            pet_species: [
              binding: :pets,
              field: :species,
              ecto_type: :string
            ]
          ],
          custom_fields: [
            full_text: [
              filter: {__MODULE__, :full_text_filter, []},
              ecto_type: :string
            ]
          ]
        ]
      }

  You can specify any Ecto type with the `ecto_type` option. Here are some
  examples:

  - A simple string: `ecto_type: :string`
  - An integer: `ecto_type: :integer`
  - An array of strings: `ecto_type: {:array, :string}`
  - A custom Ecto type: `ecto_type: MyCustomType`

  For parameterized types, use the following syntax:

  - `ecto_type: {:parameterized, Ecto.Enum, Ecto.Enum.init(values: [:one, :two])}`

  If you're working with `Ecto.Enum` types, you can use a more convenient
  syntax:

  - `ecto_type: {:ecto_enum, [:one, :two]}`

  Furthermore, you can reference a type from another schema:

  - `ecto_type: {:from_schema, MyApp.Pet, :mood}`

  Note that `Flop.Phoenix` encodes all filters in query string using
  `Plug.Conn.Query`. It is expected that filter values can be converted to
  strings with `to_string/1`. If you are using an Ecto custom type that casts
  as a struct, you will need to implement the `String.Chars` protocol for that
  struct.
  """

  @fallback_to_any true

  @typedoc """
  Options that can be passed when deriving the Flop.Schema protocol.

  These are either general schema options or adapter-specific options nested
  under the `:adapter_opts` key. For backward compatibility, the options of the
  Ecto adapter can be set directly at the root level as well.

  - `:filterable` (required) - A list of fields that can be used in filters.
    Supports fields from the Ecto schema, join fields, compound fields and
    custom fields. Alias fields are not supported.
  - `:sortable` (required) - A list of fields that can be used for sorting.
    Supports fields from the Ecto schema, join fields, and alias fields. Custom
    fields and compound fields are not supported.
  - `:default_limit` - The default limit applied if no `limit`, `page_size`,
    `first` or `last` parameter is set.
  - `:max_limit` - The maximum limit that can be set via parameters.
  - `:default_order` - The default order applied when no order parameters are
    set.
  - `:pagination_types` - A list of allowed pagination types for this schema.
  - `:default_pagination_type` - The default pagination type used if no
    pagination parameters are set.
  - `:adapter_opts` - Additional adapter-specific options.
  """
  @type option ::
          {:filterable, [atom]}
          | {:sortable, [atom]}
          | {:default_limit, integer}
          | {:max_limit, integer}
          | {:default_order, Flop.default_order()}
          | {:pagination_types, [Flop.pagination_type()]}
          | {:default_pagination_type, Flop.pagination_type()}
          | {:adapter_opts, [adapter_option]}
          | adapter_option()

  @typedoc """
  Options specific to the adapter.

  - `:join_fields` - A list of fields on named bindings.
  - `:compound_fields` - Groups of fields that can be combined and filtered, for
    example a family name plus a given name field.
  - `:custom_fields` - Custom fields with user-defined filter functions.
  - `:alias_field` - Fields that reference aliases defined with
    `Ecto.Query.API.selected_as/2`.
  """
  @type adapter_option ::
          {:join_fields, [{atom, [join_field_option()]}]}
          | {:compound_fields, [{atom, [atom]}]}
          | {:custom_fields, [{atom, [custom_field_option()]}]}
          | {:alias_fields, [atom]}

  @typedoc """
  Defines the options for a join field.

  - `:binding` (required) - Any named binding
  - `:field` (required)
  - `:ecto_type` - The Ecto type of the field. The filter operator and value
    validation is based on this option.
  - `:path` - This option is used by `Flop.Schema.get_field/2` to retrieve the
    field value from a row. That function is also used by the default cursor
    functions in `Flop.Cursor` to determine the cursors. If the option is
    omitted, it defaults to `[binding, field]`.
  """
  @type join_field_option ::
          {:binding, atom}
          | {:field, atom}
          | {:ecto_type, ecto_type()}
          | {:path, [atom]}

  @typedoc """
  Defines the options for a custom field.

  - `:filter` (required) - A module/function/options tuple referencing a
    custom filter function. The function must take the Ecto query, the
    `Flop.Filter` struct, and the options from the tuple as arguments.
  - `:ecto_type` - The Ecto type of the field. The filter operator and value
    validation is based on this option.
  - `:bindings` - If the custom filter function requires certain named bindings
    to be present in the Ecto query, you can specify them here. These bindings
    will be conditionally added by `Flop.with_named_bindings/4` if the filter
    is used.
  - `:operators` - Defines which filter operators are allowed for this field.
    If omitted, all operators will be accepted.

  If both the `:ecto_type` and the `:operators` option are set, the `:operators`
  option takes precedence and only the filter value validation is based on the
  `:ecto_type`.
  """
  @type custom_field_option ::
          {:filter, {module, atom, keyword}}
          | {:ecto_type, ecto_type()}
          | {:bindings, [atom]}
          | {:operators, [Flop.Filter.op()]}

  @typedoc """
  Either an Ecto type, or reference to the type of an existing schema field, or
  an adhoc Ecto.Enum.

  ## Examples

  You can pass any Ecto type:

  - `:string`
  - `:integer`
  - `Ecto.UUID`
  - `{:parameterized, Ecto.Enum, Ecto.Enum.init(values: [:one, :two])}`

  Or reference a schema field:

  `{:from_schema, MyApp.Pet, :mood}`

  Or build an adhoc Ecto.Enum:

  - `{:ecto_enum, [:one, :two]}` (This has the same effect as the `:parameterized`
    example above.)
  - `{:ecto_enum, [one: 1, two: 2]}`

  Note that if you make an `Ecto.Enum` type this way, the filter value will be
  cast as an atom. This means the field you filter on also needs to be an
  `Ecto.Enum`, or a custom type that is able to cast atoms. You cannot use this
  on a string field.
  """
  @type ecto_type ::
          Ecto.Type.t()
          | {:from_schema, module, atom}
          | {:ecto_enum, [atom] | keyword}

  @doc """
  Returns the field type in a schema.

  - `{:normal, atom}` - An ordinary field on the schema. The second tuple
    element is the field name.
  - `{:compound, [atom]}` - A combination of fields defined with the
    `compound_fields` option. The list of atoms refers to the list of fields
    that are included.
  - `{:join, map}` - A field from a named binding as defined with the
    `join_fields` option. The map has keys for the `:binding`, `:field` and
    `:path`.
  - `{:custom, keyword}` - A filter field that uses a custom filter function.

  ## Examples

      iex> field_type(%MyApp.Pet{}, :age)
      {:normal, :age}
      iex> field_type(%MyApp.Pet{}, :full_name)
      {:compound, [:family_name, :given_name]}
      iex> field_type(%MyApp.Pet{}, :owner_name)
      {
        :join,
        %{
          binding: :owner,
          field: :name,
          path: [:owner, :name],
          ecto_type: :string
        }
      }
      iex> field_type(%MyApp.Pet{}, :reverse_name)
      {
        :custom,
        %{
          filter: {MyApp.Pet, :reverse_name_filter, []},
          ecto_type: :string,
          operators: nil,
          bindings: []
        }
      }
  """
  @doc since: "0.11.0"
  @spec field_type(any, atom) ::
          {:normal, atom}
          | {:compound, [atom]}
          | {:join, map}
          | {:alias, atom}
          | {:custom, map}
  @deprecated "use field_info/2 instead"
  def field_type(data, field)

  @doc """
  Returns the field information for the given field name.

  ## Examples

      iex> field_info(%MyApp.Pet{}, :age)
      %Flop.FieldInfo{ecto_type: :integer, extra: %{type: :normal, field: :age}}
      iex> field_info(%MyApp.Pet{}, :full_name)
      %Flop.FieldInfo{
        ecto_type: :string,
        operators: [
          :=~,
          :like,
          :not_like,
          :like_and,
          :like_or,
          :ilike,
          :not_ilike,
          :ilike_and,
          :ilike_or,
          :empty,
          :not_empty
        ],
        extra: %{type: :compound, fields: [:family_name, :given_name]}
      }
      iex> field_info(%MyApp.Pet{}, :owner_name)
      %Flop.FieldInfo{
        ecto_type: :string,
        extra: %{
          type: :join,
          path: [:owner, :name],
          binding: :owner,
          field: :name
        }
      }
      iex> field_info(%MyApp.Pet{}, :reverse_name)
      %Flop.FieldInfo{
        ecto_type: :string,
        extra: %{
          type: :custom,
          filter: {MyApp.Pet, :reverse_name_filter, []},
          bindings: []
        }
      }
  """
  @spec field_info(any, atom) :: Flop.FieldInfo.t()
  def field_info(data, field)

  @doc """
  Returns the filterable fields of a schema.

      iex> Flop.Schema.filterable(%MyApp.Pet{})
      [
        :age,
        :full_name,
        :mood,
        :name,
        :owner_age,
        :owner_name,
        :owner_tags,
        :pet_and_owner_name,
        :species,
        :tags,
        :custom,
        :reverse_name
      ]
  """
  @spec filterable(any) :: [atom]
  def filterable(data)

  @doc """
  Gets the field value from a struct.

  Resolves join fields and compound fields according to the config.

      # join_fields: [owner_name: [binding: :owner, field: :name]]
      iex> pet = %MyApp.Pet{name: "George", owner: %MyApp.Owner{name: "Carl"}}
      iex> Flop.Schema.get_field(pet, :name)
      "George"
      iex> Flop.Schema.get_field(pet, :owner_name)
      "Carl"

      # compound_fields: [full_name: [:family_name, :given_name]]
      iex> pet = %MyApp.Pet{given_name: "George", family_name: "Gooney"}
      iex> Flop.Schema.get_field(pet, :full_name)
      "Gooney George"

  For join fields, this function relies on the binding name in the schema config
  matching the field name for the association in the struct.
  """
  @doc since: "0.13.0"
  @spec get_field(any, atom) :: any
  def get_field(data, field)

  @doc """
  Returns the allowed pagination types of a schema.

      iex> Flop.Schema.pagination_types(%MyApp.Fruit{})
      [:first, :last, :offset]
  """
  @doc since: "0.9.0"
  @spec pagination_types(any) :: [Flop.pagination_type()] | nil
  def pagination_types(data)

  @doc """
  Returns the allowed pagination types of a schema.

      iex> Flop.Schema.pagination_types(%MyApp.Fruit{})
      [:first, :last, :offset]
  """
  @doc since: "0.21.0"
  @spec default_pagination_type(any) :: Flop.pagination_type() | nil
  def default_pagination_type(data)

  @doc """
  Returns the sortable fields of a schema.

      iex> Flop.Schema.sortable(%MyApp.Pet{})
      [:name, :age, :owner_name, :owner_age]
  """
  @spec sortable(any) :: [atom]
  def sortable(data)

  @doc """
  Returns the default limit of a schema.

      iex> Flop.Schema.default_limit(%MyApp.Fruit{})
      60
  """
  @doc since: "0.3.0"
  @spec default_limit(any) :: pos_integer | nil
  def default_limit(data)

  @doc """
  Returns the default order of a schema.

      iex> Flop.Schema.default_order(%MyApp.Fruit{})
      %{order_by: [:name], order_directions: [:asc]}
  """
  @doc since: "0.7.0"
  # This is a map instead of a keyword list because the default order can also
  # be passed directly to the `validate_*` functions, where we need it as a map.
  # Using two different formats would be confusing.
  @spec default_order(any) ::
          %{
            order_by: [atom] | nil,
            order_directions: [Flop.order_direction()] | nil
          }
          | nil
  def default_order(data)

  @doc """
  Returns the maximum limit of a schema.

      iex> Flop.Schema.max_limit(%MyApp.Pet{})
      1000
  """
  @doc since: "0.2.0"
  @spec max_limit(any) :: pos_integer | nil
  def max_limit(data)
end

defimpl Flop.Schema, for: Any do
  alias Flop.NimbleSchemas
  require Logger

  @instructions """
  Flop.Schema protocol must always be explicitly implemented.

  To do this, you have to derive Flop.Schema in your Ecto schema module. You
  have to set both the filterable and the sortable option.

      @derive {
        Flop.Schema,
        filterable: [:name, :species],
        sortable: [:name, :age, :species]
      }

      schema "pets" do
        field :name, :string
        field :age, :integer
        field :species, :string
      end

  """
  # credo:disable-for-next-line
  defmacro __deriving__(module, struct, options) do
    options =
      NimbleSchemas.validate!(
        options,
        :schema_option,
        Flop.Schema,
        __CALLER__.module
      )

    legacy_adapter_opts =
      Keyword.take(options, [
        :alias_fields,
        :compound_fields,
        :custom_fields,
        :join_fields
      ])

    adapter = Keyword.fetch!(options, :adapter)

    adapter_opts =
      Keyword.merge(legacy_adapter_opts, Keyword.fetch!(options, :adapter_opts))

    adapter_opts =
      adapter.init_schema_opts(options, adapter_opts, __CALLER__.module, struct)

    options = Keyword.put(options, :adapter_opts, adapter_opts)

    validate_options!(options, adapter_opts, struct)

    alias_fields = Map.fetch!(adapter_opts, :alias_fields)
    compound_fields = Map.fetch!(adapter_opts, :compound_fields)
    custom_fields = Map.fetch!(adapter_opts, :custom_fields)
    join_fields = Map.fetch!(adapter_opts, :join_fields)

    filterable_fields = Keyword.get(options, :filterable)
    sortable_fields = Keyword.get(options, :sortable)
    default_limit = Keyword.get(options, :default_limit)
    max_limit = Keyword.get(options, :max_limit)
    pagination_types = Keyword.get(options, :pagination_types)
    default_pagination_type = Keyword.get(options, :default_pagination_type)
    default_order = Keyword.get(options, :default_order)

    field_type_func =
      build_field_type_func(
        compound_fields,
        join_fields,
        alias_fields,
        custom_fields
      )

    field_info_func = build_field_info_func(adapter, adapter_opts, struct)
    get_field_func = build_get_field_func(struct, adapter, adapter_opts)

    quote do
      defimpl Flop.Schema, for: unquote(module) do
        import Ecto.Query

        require Logger

        def default_limit(_) do
          unquote(default_limit)
        end

        def default_order(_) do
          unquote(Macro.escape(default_order))
        end

        unquote(field_info_func)
        unquote(field_type_func)
        unquote(get_field_func)

        def filterable(_) do
          unquote(filterable_fields)
        end

        def max_limit(_) do
          unquote(max_limit)
        end

        def pagination_types(_) do
          unquote(pagination_types)
        end

        def default_pagination_type(_) do
          unquote(default_pagination_type)
        end

        def sortable(_) do
          unquote(sortable_fields)
        end
      end
    end
  end

  defp validate_options!(opts, adapter_opts, struct) do
    adapter = Keyword.fetch!(opts, :adapter)
    fields = struct |> adapter.fields(adapter_opts) |> Keyword.keys()

    validate_default_pagination_type!(
      opts[:default_pagination_type],
      opts[:pagination_types]
    )

    validate_no_unknown_field!(opts[:filterable], fields, "filterable")
    validate_no_unknown_field!(opts[:sortable], fields, "sortable")
    validate_default_order!(opts[:default_order], opts[:sortable])
  end

  defp validate_default_pagination_type!(nil, _), do: :ok

  defp validate_default_pagination_type!(default_type, types) do
    unless is_nil(types) || default_type in types do
      raise Flop.InvalidDefaultPaginationTypeError,
        default_pagination_type: default_type,
        pagination_types: types
    end
  end

  defp validate_no_unknown_field!(fields, known_fields, option) do
    all_fields = MapSet.new(fields)
    known_fields = MapSet.new(known_fields)
    unknown_fields = MapSet.difference(all_fields, known_fields)

    unless Enum.empty?(unknown_fields) do
      raise Flop.UnknownFieldError,
        known_fields: MapSet.to_list(known_fields),
        unknown_fields: MapSet.to_list(unknown_fields),
        option: option
    end
  end

  defp validate_default_order!(nil, _), do: :ok

  defp validate_default_order!(%{} = map, sortable_fields) do
    order_by = Map.get(map, :order_by, [])
    sortable_fields = MapSet.new(sortable_fields)

    unsortable_fields =
      order_by
      |> MapSet.new()
      |> MapSet.difference(sortable_fields)

    unless Enum.empty?(unsortable_fields) do
      raise Flop.InvalidDefaultOrderError,
        sortable_fields: MapSet.to_list(sortable_fields),
        unsortable_fields: MapSet.to_list(unsortable_fields)
    end
  end

  def build_field_info_func(adapter, adapter_opts, struct) do
    for {name, field_info} <- adapter.fields(struct, adapter_opts) do
      case field_info do
        %{ecto_type: {:from_schema, module, field}} ->
          quote do
            def field_info(_, unquote(name)) do
              %{
                unquote(Macro.escape(field_info))
                | ecto_type: unquote(module).__schema__(:type, unquote(field))
              }
            end
          end

        %{ecto_type: {:ecto_enum, values}} ->
          type = {:parameterized, Ecto.Enum, Ecto.Enum.init(values: values)}
          field_info = %{field_info | ecto_type: type}

          quote do
            def field_info(_, unquote(name)) do
              unquote(Macro.escape(field_info))
            end
          end

        _ ->
          quote do
            def field_info(_, unquote(name)) do
              unquote(Macro.escape(field_info))
            end
          end
      end
    end
  end

  def build_field_type_func(
        compound_fields,
        join_fields,
        alias_fields,
        custom_fields
      ) do
    compound_field_funcs = field_type_funcs(:compound, compound_fields)
    join_field_funcs = field_type_funcs(:join, join_fields)
    alias_field_funcs = field_type_funcs(:alias, alias_fields)
    custom_field_funcs = field_type_funcs(:custom, custom_fields)

    default_funcs =
      quote do
        def field_type(_, name) do
          {:normal, name}
        end
      end

    quote do
      unquote(compound_field_funcs)
      unquote(join_field_funcs)
      unquote(alias_field_funcs)
      unquote(custom_field_funcs)
      unquote(default_funcs)
    end
  end

  defp field_type_funcs(type, fields)
       when type in [:compound, :join, :custom] do
    for {name, value} <- fields do
      quote do
        def field_type(_, unquote(name)) do
          {unquote(type), unquote(Macro.escape(value))}
        end
      end
    end
  end

  defp field_type_funcs(:alias, fields) do
    for name <- fields do
      quote do
        def field_type(_, unquote(name)) do
          {:alias, unquote(name)}
        end
      end
    end
  end

  def build_get_field_func(struct, adapter, adapter_opts) do
    for {field, field_info} <- adapter.fields(struct, adapter_opts) do
      quote do
        def get_field(struct, unquote(field)) do
          unquote(adapter).get_field(
            struct,
            unquote(field),
            unquote(Macro.escape(field_info))
          )
        end
      end
    end
  end

  function_names = [
    :default_limit,
    :default_order,
    :filterable,
    :max_limit,
    :pagination_types,
    :default_pagination_type,
    :sortable
  ]

  for function_name <- function_names do
    def unquote(function_name)(struct) do
      raise Protocol.UndefinedError,
        protocol: @protocol,
        value: struct,
        description: @instructions
    end
  end

  def field_info(struct, _) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: @instructions
  end

  def field_type(struct, _) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: @instructions
  end

  def custom(_, _), do: []

  # add default implementation for maps, so that cursor value functions can use
  # it without checking protocol implementation
  def get_field(%{} = map, field), do: Map.get(map, field)

  def get_field(thing, _) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: thing,
      description: @instructions
  end
end
