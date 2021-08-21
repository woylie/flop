defprotocol Flop.Schema do
  @moduledoc """
  This protocol allows you to set query options in your Ecto schemas.

  ## Usage

  Derive `Flop.Schema` in your Ecto schema and set the filterable and sortable
  fields.

      defmodule Flop.Pet do
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


  After that, you can pass the module as the `:for` option to `Flop.validate/2`.

      iex> Flop.validate(%Flop{order_by: [:name]}, for: Flop.Pet)
      {:ok,
       %Flop{
         filters: [],
         limit: nil,
         offset: nil,
         order_by: [:name],
         order_directions: nil,
         page: nil,
         page_size: nil
       }}

      iex> {:error, changeset} = Flop.validate(
      ...>   %Flop{order_by: [:species]}, for: Flop.Pet
      ...> )
      iex> changeset.valid?
      false
      iex> changeset.errors
      [
        order_by: {"has an invalid entry",
         [validation: :subset, enum: [:name, :age, :owner_name, :owner_age]]}
      ]

  ## Default and maximum limits

  To define a default or maximum limit, you can set the `default_limit` and
  `max_limit` option when deriving `Flop.Schema`. The maximum limit will be
  validated and the default limit applied by `Flop.validate/1`.

      @derive {
        Flop.Schema,
        filterable: [:name, :species],
        sortable: [:name, :age],
        max_limit: 100,
        default_limit: 50
      }

  ## Default sort order

  To define a default sort order, you can set the `default_order_by` and
  `default_order_directions` options when deriving `Flop.Schema`. The default
  values are applied by `Flop.validate/1`. If no order directions are set,
  `:asc` is assumed for all fields.

      @derive {
        Flop.Schema,
        filterable: [:name, :species],
        sortable: [:name, :age],
        default_order_by: [:name, :age],
        default_order_directions: [:asc, :desc]
      }

  ## Restricting pagination types

  By default, `page`/`page_size`, `offset`/`limit` and cursor-based pagination
  (`first`/`after` and `last`/`before`) are enabled. If you want to restrict the
  pagination type for a schema, you can do that by setting the
  `pagination_types` option.

      @derive {
        Flop.Schema,
        filterable: [:name, :species],
        sortable: [:name, :age],
        pagination_types: [:first, :last]
      }

  See also `t:Flop.option/0` and `t:Flop.pagination_type/0`. Setting the value
  to `nil` allows all pagination types.

  ## Compound fields

  Sometimes you might need to apply a search term to multiple fields at once,
  e.g. you might want to search in both the family name and given name field.
  You can do that with Flop by defining a compound field.

      @derive {
        Flop.Schema,
        filterable: [:full_name],
        sortable: [],
        compound_fields: [full_name: [:family_name, :given_name]]
      }

  This allows you to use the field name `:full_name` as any other field in the
  filters.

      params = %{
        filters: [%{
          field: :full_name,
          op: :==,
          value: "margo"
        }]
      }

  This would translate to:

      WHERE family_name='margo' OR given_name ='martindale'

  Partial matches and splitting of the search term can be achieved with one of
  the ilike operators.

      params = %{
        filters: [%{
          field: :full_name,
          op: :ilike_and,
          value: "margo martindale"
        }]
      }

  This would translate to:

      WHERE (family_name ilike '%margo%' OR given_name ='%margo%')
      AND (family_name ilike '%martindale%' OR given_name ='%martindale%')

  ### Filter operator rules

  - `:=~`, `:like`, `:like_and`, `:like_or`, `:ilike`, `:ilike_and`,
    `:ilike_or` - The filter value is split at whitespace characters as usual.
    The filter matches for a value if it matches for any of the fields.
  - `:empty` - Matches if all fields of the compound field are `nil`.
  - `:not_empty` - Matches if any field of the compound field is not `nil`.
  - `:==`, `:!=`, `:<=`, `:<`, `:>=`, `:>`, `:in` - The filter value is
    normalized by splitting the string at whitespaces and joining it with a
    space. The values of all fields of the compound field are split by
    whitespace character and joined with a space, and the resulting values are
    joined with a space again. **This will be added in a future version. These
    filter operators are ignored for compound fields at the moment.**

  ## Join fields

  If you need filter or order across tables, you can define join fields.

  **Note: Support for ordering by join fields will be added in a future
  version.**

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
        join_fields: [pet_species: {:pets, :species}]
      }

  In this case, `:pet_species` would be the alias of the field that you can
  refer to in the filter and order parameters. In `{:pets, :species}`, `:pets`
  refers to the field name for the association as set with `:has_one`,
  `:has_many` or `:belongs_to`. The binding name used for the join in the query
  must match the field name. `:species` refers to a field on the association.

  After setting up the join fields, you can write a query like this:

      params = %{
        filters: [%{field: :pet_species, op: :==, value: "E. africanus"}]
      }

      Owner
      |> join(:left, [o], p in assoc(o, :pets), as: :pets)
      |> Flop.validate_and_run!(params, for: Owner)

  Note that Flop doesn't create the join clauses for you. The named bindings
  already have to be present in the query you pass to the Flop functions.
  """

  @fallback_to_any true

  @doc """
  Returns the field type in a schema.

  - `{:normal, atom}` - An ordinary field on the schema. The second tuple
    element is the field name.
  - `{:compound, [atom]}` - A combination of fields defined with the
    `compound_fields` option. The list of atoms refers to the list of fields
    that are included.
  - `{:join, {atom, atom}}` - A field from a named binding as defined with the
    `join_fields` option. The first atom refers to the binding name, the second
    atom refers to the field.
  """
  @doc since: "0.11.0"
  @spec field_type(any, atom) ::
          {:normal, atom} | {:compound, [atom]} | {:join, {atom, atom}}
  def field_type(data, field)

  @doc """
  Returns the filterable fields of a schema.

      iex> Flop.Schema.filterable(%Flop.Pet{})
      [
        :age,
        :full_name,
        :name,
        :owner_age,
        :owner_name,
        :pet_and_owner_name,
        :species
      ]
  """
  @spec filterable(any) :: [atom]
  def filterable(data)

  @doc false
  @doc since: "0.13.0"
  @spec dynamic_order_by(any, Ecto.Query.t(), keyword) :: Ecto.Query.t()
  def dynamic_order_by(data, q, expr)

  @doc """
  Gets the field value from a struct.

  Resolves join fields and compound fields according to the config.

      # join_fields: [owner_name: {:owner, :name}]
      iex> pet = %Flop.Pet{name: "George", owner: %Flop.Owner{name: "Carl"}}
      iex> Flop.Schema.get_field(pet, :name)
      "George"
      iex> Flop.Schema.get_field(pet, :owner_name)
      "Carl"

      # compound_fields: [full_name: [:family_name, :given_name]]
      iex> pet = %Flop.Pet{given_name: "George", family_name: "Gooney"}
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

      iex> Flop.Schema.pagination_types(%Flop.Fruit{})
      [:first, :last, :offset]
  """
  @doc since: "0.9.0"
  @spec pagination_types(any) :: [Flop.pagination_type()] | nil
  def pagination_types(data)

  @doc """
  Returns the sortable fields of a schema.

      iex> Flop.Schema.sortable(%Flop.Pet{})
      [:name, :age, :owner_name, :owner_age]
  """
  @spec sortable(any) :: [atom]
  def sortable(data)

  @doc """
  Returns the default limit of a schema.

      iex> Flop.Schema.default_limit(%Flop.Fruit{})
      50
  """
  @doc since: "0.3.0"
  @spec default_limit(any) :: pos_integer | nil
  def default_limit(data)

  @doc """
  Returns the default order of a schema.

      iex> Flop.Schema.default_order(%Flop.Fruit{})
      %{order_by: [:name], order_directions: [:asc]}
  """
  @doc since: "0.7.0"
  @spec default_order(any) :: %{
          order_by: [atom] | nil,
          order_directions: [Flop.order_direction()] | nil
        }
  def default_order(data)

  @doc """
  Returns the maximum limit of a schema.

      iex> Flop.Schema.max_limit(%Flop.Pet{})
      1000
  """
  @doc since: "0.2.0"
  @spec max_limit(any) :: pos_integer | nil
  def max_limit(data)
end

defimpl Flop.Schema, for: Any do
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
  defmacro __deriving__(module, _struct, options) do
    filterable_fields = Keyword.get(options, :filterable)
    sortable_fields = Keyword.get(options, :sortable)

    if is_nil(filterable_fields) || is_nil(sortable_fields),
      do: raise(ArgumentError, @instructions)

    default_limit = Keyword.get(options, :default_limit)
    max_limit = Keyword.get(options, :max_limit)
    pagination_types = Keyword.get(options, :pagination_types)

    default_order = %{
      order_by: Keyword.get(options, :default_order_by),
      order_directions: Keyword.get(options, :default_order_directions)
    }

    compound_fields = Keyword.get(options, :compound_fields, [])
    join_fields = Keyword.get(options, :join_fields, [])

    field_type_func = build_field_type_func(compound_fields, join_fields)
    dynamic_func = build_dynamic_func(join_fields)
    get_field_func = build_get_field_func(compound_fields, join_fields)

    quote do
      defimpl Flop.Schema, for: unquote(module) do
        import Ecto.Query

        def default_limit(_) do
          unquote(default_limit)
        end

        def default_order(_) do
          unquote(Macro.escape(default_order))
        end

        unquote(field_type_func)
        unquote(dynamic_func)
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

        def sortable(_) do
          unquote(sortable_fields)
        end
      end
    end
  end

  def build_field_type_func(compound_fields, join_fields) do
    compound_field_funcs =
      for {name, fields} <- compound_fields do
        quote do
          def field_type(_, unquote(name)) do
            {:compound, unquote(fields)}
          end
        end
      end

    join_field_funcs =
      for {name, {_binding_name, _field} = path} <- join_fields do
        quote do
          def field_type(_, unquote(name)) do
            {:join, unquote(path)}
          end
        end
      end

    default_funcs =
      quote do
        def field_type(_, name) do
          {:normal, name}
        end
      end

    [compound_field_funcs, join_field_funcs, default_funcs]
  end

  def build_dynamic_func(join_fields) do
    join_field_funcs =
      for {join_field, {binding, field}} <- join_fields do
        bindings = Code.string_to_quoted!("[#{binding}: r]")

        quote do
          def dynamic_order_by(_struct, q, {direction, unquote(join_field)}) do
            order_by(
              q,
              unquote(bindings),
              [{^direction, field(r, unquote(field))}]
            )
          end
        end
      end

    normal_field_func =
      quote do
        def dynamic_order_by(_struct, q, direction) do
          order_by(q, ^direction)
        end
      end

    [join_field_funcs, normal_field_func]
  end

  def build_get_field_func(compound_fields, join_fields) do
    compound_field_funcs =
      for {name, fields} <- compound_fields do
        quote do
          def get_field(struct, unquote(name)) do
            unquote(fields)
            |> Enum.map(&get_field(struct, &1))
            |> Enum.join(" ")
          end
        end
      end

    join_field_funcs =
      for {name, {assoc_field, field}} <- join_fields do
        quote do
          def get_field(struct, unquote(name)) do
            struct
            |> Map.get(unquote(assoc_field), %{})
            |> Map.get(unquote(field))
          end
        end
      end

    fallback_func =
      quote do
        def get_field(struct, field), do: Map.get(struct, field)
      end

    [compound_field_funcs, join_field_funcs, fallback_func]
  end

  function_names = [
    :default_limit,
    :default_order,
    :filterable,
    :max_limit,
    :pagination_types,
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

  function_names = [
    :field_type,
    :get_field
  ]

  for function_name <- function_names do
    def unquote(function_name)(struct, _) do
      raise Protocol.UndefinedError,
        protocol: @protocol,
        value: struct,
        description: @instructions
    end
  end

  def dynamic_order_by(struct, _, _) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: @instructions
  end
end
