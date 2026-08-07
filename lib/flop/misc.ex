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
