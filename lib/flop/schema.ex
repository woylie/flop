defprotocol Flop.Schema do
  @moduledoc """
  This protocol allows you to define the sortable and filterable fields in your
  Ecto schemas.

  ## Usage

  Derive `Flop.Schema` in your Ecto schema.

      defmodule Flop.Pet do
        use Ecto.Schema

        @derive {Flop.Schema,
                 filterable: [:name, :species],
                 sortable: [:name, :age],
                 max_limit: 20}

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
  @spec default_limit(any) :: pos_integer | nil
  def default_limit(data)

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
        field :social_security_number, :string
      end

  """
  defmacro __deriving__(module, _struct, options) do
    filterable_fields = Keyword.get(options, :filterable)
    sortable_fields = Keyword.get(options, :sortable)

    if is_nil(filterable_fields) || is_nil(sortable_fields),
      do: raise(ArgumentError, @instructions)

    default_limit = Keyword.get(options, :default_limit)
    max_limit = Keyword.get(options, :max_limit)

    quote do
      defimpl Flop.Schema, for: unquote(module) do
        def filterable(_) do
          unquote(filterable_fields)
        end

        def sortable(_) do
          unquote(sortable_fields)
        end

        def default_limit(_) do
          unquote(default_limit)
        end

        def max_limit(_) do
          unquote(max_limit)
        end
      end
    end
  end

  def filterable(struct) do
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

  def default_limit(struct) do
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
end
