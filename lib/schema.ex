defprotocol Flop.Schema do
  @moduledoc false

  @fallback_to_any true

  @spec filterable(any) :: [atom]
  def filterable(data)

  @spec sortable(any) :: [atom]
  def sortable(data)
end

defimpl Flop.Schema, for: Any do
  @instructions """
  Flop.Schema protocol must always be explicitly implemented.

  To do this, you have to derive Flop.Schema in your Ecto schema module.

      @derive {Flop.Schema,
               filterable: [:name, :species], sortable: [:name, :age, :species]}

      schema "pets do
        field :name, :string
        field :age, :integer
        field :species, :string
        field :social_security_number, :string
      end

  """
  defmacro __deriving__(module, _struct, options) do
    filterable_fields = Keyword.get(options, :filterable, [])
    sortable_fields = Keyword.get(options, :sortable, [])

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
