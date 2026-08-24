defmodule Flop.Misc do
  @moduledoc false

  @doc """
  Resolves the Ecto type of a field configuration to a type that can be passed
  to `Ecto.Type.cast/2`.

      iex> expand_type({:from_schema, MyApp.Pet, :age})
      :integer

      iex> expand_type(:string)
      :string
  """
  def expand_type({:from_schema, module, field}),
    do: module.__schema__(:type, field)

  def expand_type({:ecto_enum, values}),
    do: Ecto.ParameterizedType.init(Ecto.Enum, values: values)

  def expand_type(type), do: type

  @doc """
  Returns `true` if the value can be stored in a text column.

  Returns `false` for invalid UTF-8 and for NUL bytes, which are rejected by
  databases at query time.

  Lists and maps are checked element by element. For any other type, `true` is
  returned.

      iex> storable_text?("borscht")
      true

      iex> storable_text?(<<98, 0, 116>>)
      false

      iex> storable_text?(<<0xFF>>)
      false

      iex> storable_text?(["ok", <<0xED, 0xA0, 0x80>>])
      false

      iex> storable_text?(%{"unit" => "m"})
      true

      iex> storable_text?(%{"unit" => <<0xFF>>})
      false
  """
  def storable_text?(value) when is_binary(value) do
    String.valid?(value) and not String.contains?(value, <<0>>)
  end

  def storable_text?(value) when is_list(value) do
    Enum.all?(value, &storable_text?/1)
  end

  def storable_text?(%_{}), do: true

  def storable_text?(%{} = value) do
    Enum.all?(value, fn {key, val} ->
      storable_text?(key) and storable_text?(val)
    end)
  end

  def storable_text?(_), do: true

  @doc """
  Returns `true` if the value can be stored in a column of the given type.

      iex> storable_value?(:string, <<0xFF>>)
      false

      iex> storable_value?(:binary, <<0xFF>>)
      true

      iex> storable_value?({:array, :binary}, [<<0xFF>>])
      true
  """
  def storable_value?(:binary, _value), do: true
  def storable_value?({:array, :binary}, _value), do: true
  def storable_value?(_type, value), do: storable_text?(value)

  @doc """
  Adds wildcard at the beginning and end of a string for partial matches.

  Escapes `%` and `_` within the given string.

      iex> add_wildcard("borscht")
      "%borscht%"

      iex> add_wildcard("bor%t")
      "%bor\\\\%t%"

      iex> add_wildcard("bor_cht")
      "%bor\\\\_cht%"
  """
  def add_wildcard(value, escape_char \\ "\\")

  def add_wildcard(value, escape_char) when is_binary(value) do
    "%" <>
      String.replace(value, ["\\", "%", "_"], &"#{escape_char}#{&1}") <>
      "%"
  end

  def add_wildcard(value, _), do: raise_pattern_value_error(value)

  @doc """
  Splits a search text into tokens.

      iex> split_search_text("borscht batchoy gumbo")
      ["%borscht%", "%batchoy%", "%gumbo%"]
  """
  def split_search_text(s), do: s |> String.split() |> Enum.map(&add_wildcard/1)

  @doc """
  Adds wildcard at the end of a string for prefix matches.

  Escapes `%` and `_` within the given string.

      iex> add_wildcard_suffix("borscht")
      "borscht%"

      iex> add_wildcard_suffix("bor%t")
      "bor\\\\%t%"

      iex> add_wildcard_suffix("bor_cht")
      "bor\\\\_cht%"
  """
  def add_wildcard_suffix(value, escape_char \\ "\\")

  def add_wildcard_suffix(value, escape_char) when is_binary(value) do
    String.replace(value, ["\\", "%", "_"], &"#{escape_char}#{&1}") <> "%"
  end

  def add_wildcard_suffix(value, _), do: raise_pattern_value_error(value)

  @doc """
  Adds wildcard at the beginning of a string for suffix matches.

  Escapes `%` and `_` within the given string.

      iex> add_wildcard_prefix("borscht")
      "%borscht"

      iex> add_wildcard_prefix("bor%t")
      "%bor\\\\%t"

      iex> add_wildcard_prefix("bor_cht")
      "%bor\\\\_cht"
  """
  def add_wildcard_prefix(value, escape_char \\ "\\")

  def add_wildcard_prefix(value, escape_char) when is_binary(value) do
    "%" <> String.replace(value, ["\\", "%", "_"], &"#{escape_char}#{&1}")
  end

  def add_wildcard_prefix(value, _), do: raise_pattern_value_error(value)

  @doc """
  Inspects and indents a term for an exception message.

      iex> indent([:a, :b])
      "    [:a, :b]"
  """
  def indent(term) do
    term
    |> inspect(pretty: true, width: 76)
    |> String.split("\n")
    |> Enum.map_join("\n", &("    " <> &1))
  end

  defp raise_pattern_value_error(value) do
    raise ArgumentError, """
    invalid filter value for pattern operator

    Operators such as :like, :ilike, :starts_with and :ends_with build a LIKE
    pattern from the filter value, which requires a string.

    Got:

        #{inspect(value)}
    """
  end
end
