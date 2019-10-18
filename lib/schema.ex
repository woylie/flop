defprotocol Flop.Schema do
  @moduledoc false

  @fallback_to_any true

  def filterable(data)
  def sortable(data)
end

defimpl Flop.Schema, for: Any do
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
      description: """
      Flop.Schema protocol must always be explicitly implemented.
      """
  end

  def sortable(struct) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: """
      Flop.Schema protocol must always be explicitly implemented.
      """
  end
end
