defmodule Flop.Misc do
  @moduledoc false

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
  def add_wildcard(value, escape_char \\ "\\") when is_binary(value) do
    "%" <>
      String.replace(value, ["\\", "%", "_"], &"#{escape_char}#{&1}") <>
      "%"
  end

  @doc """
  Splits a search text into tokens.

      iex> split_search_text("borscht batchoy gumbo")
      ["%borscht%", "%batchoy%", "%gumbo%"]
  """
  def split_search_text(s), do: s |> String.split() |> Enum.map(&add_wildcard/1)
end
