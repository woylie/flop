defprotocol Flop.Schema do
  @moduledoc """
  This protocol allows you to set query options in your Ecto schemas.

  ## Usage

  Derive `Flop.Schema` in your Ecto schema and set the filterable and sortable
  fields.

      defmodule Flop.Pet do
        use Ecto.Schema

        @derive {Flop.Schema,
                 filterable: [:name, :species],
                 sortable: [:name, :age]}

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
         [validation: :subset, enum: [:name, :age]]}
      ]

  ### Defining default and maximum limits

  To define a default or maximum limit, you can set the `default_limit` and
  `max_limit` option when deriving `Flop.Schema`. The maximum limit will be
  validated and the default limit applied by `Flop.validate/1`.

      @derive {Flop.Schema,
                filterable: [:name, :species],
                sortable: [:name, :age],
                max_limit: 100,
                default_limit: 50}

  ### Defining a default sort order

  To define a default sort order, you can set the `default_order_by` and
  `default_order_directions` options when deriving `Flop.Schema`. The default
  values are applied by `Flop.validate/1`. If no order directions are set,
  `:asc` is assumed for all fields.

      @derive {Flop.Schema,
                filterable: [:name, :species],
                sortable: [:name, :age],
                default_order_by: [:name, :age],
                default_order_directions: [:asc, :desc]}

  ### Restricting pagination types

  By default, `page`/`page_size`, `offset`/`limit` and cursor-based pagination
  (`first`/`after` and `last`/`before`) are enabled. If you want to restrict the
  pagination type for a schema, you can do that by setting the
  `pagination_types` option.

      @derive {Flop.Schema,
                filterable: [:name, :species],
                sortable: [:name, :age],
                pagination_types: [:first, :last]}

  See also `t:Flop.option/0` and `t:Flop.pagination_type/0`. Setting the value
  to `nil` allows all pagination types.
  """

  @fallback_to_any true

  @doc """
  Returns the filterable fields of a schema.

      iex> Flop.Schema.filterable(%Flop.Pet{})
      [:name, :species]
  """
  @spec filterable(any) :: [atom]
  def filterable(data)

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
      [:name, :age]
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
      20
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

      @derive {Flop.Schema,
               filterable: [:name, :species], sortable: [:name, :age, :species]}

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

    quote do
      defimpl Flop.Schema, for: unquote(module) do
        def default_limit(_) do
          unquote(default_limit)
        end

        def default_order(_) do
          unquote(Macro.escape(default_order))
        end

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

  def default_limit(struct) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: @instructions
  end

  def default_order(struct) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: @instructions
  end

  def filterable(struct) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: @instructions
  end

  def max_limit(struct) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: @instructions
  end

  def pagination_types(struct) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: @instructions
  end

  def sortable(struct) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: @instructions
  end
end
