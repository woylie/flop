defprotocol Flop.Schema do
  @moduledoc false

  @type opts :: Jason.Encode.opts()

  @fallback_to_any true

  def sortable(struct)
end

defimpl Flop.Schema, for: Any do
  defmacro __deriving__(module, _struct, options) do
    sortable_fields = Keyword.get(options, :sortable, [])

    quote do
      defimpl Flop.Schema, for: unquote(module) do
        def sortable(_) do
          unquote(sortable_fields)
        end
      end
    end
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
