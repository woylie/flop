defprotocol Flop.Schema do
  @moduledoc """
  This protocol allows you to define the sortable and filterable fields in your
  Ecto schemas.

  ## Usage

  Derive `Flop.Schema` in your Ecto schema.

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

  After that, you can pass the module as the `:for` option to `Flop.validate/2`.

      iex> Flop.validate(%Flop{order_by: [:name]}, for: Pet)
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
      ...>   %Flop{order_by: [:social_security_number]}, for: Pet
      ...> )
      iex> changeset.valid?
      false
      iex> changeset.errors
      [
        order_by: {"has an invalid entry",
         [validation: :subset, enum: [:name, :age, :species]]}
      ]
  """

  @fallback_to_any true

  @doc """
  Returns the filterable fields of a schema.

      iex> Flop.Schema.filterable(%Pet{})
      [:name, :species]
  """
  @spec filterable(any) :: [atom]
  def filterable(data)

  @doc """
  Returns the sortable fields of a schema.

      iex> Flop.Schema.sortable(%Pet{})
      [:name, :age, :species]
  """
  @spec sortable(any) :: [atom]
  def sortable(data)
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

    quote do
      defimpl Flop.Schema, for: unquote(module) do
        def filterable(_) do
          unquote(filterable_fields)
        end

        def sortable(_) do
          unquote(sortable_fields)
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
end
