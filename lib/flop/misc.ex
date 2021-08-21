defmodule Flop.Misc do
  @moduledoc false

  @doc """
  Adds wildcard at the beginning and end of a string for partial matches.

      iex> add_wildcard("borscht")
      "%borscht%"
  """
  def add_wildcard(value), do: "%#{value}%"

  @doc """
  Splits a search text into tokens.

      iex> split_search_text("borscht batchoy gumbo")
      ["%borscht%", "%batchoy%", "%gumbo%"]
  """
  def split_search_text(s), do: s |> String.split() |> Enum.map(&add_wildcard/1)

  @doc """
  Takes a string representation of a Ecto dynamic query and a string
  representation of a binding list and returns a quoted dynamic.

      iex> quote_dynamic(nil, "[borscht: b]")
      nil

      iex> d = "dynamic(<<<binding>>>, field(b, ^field) == ^value)"
      iex> quote_dynamic(d, "[borscht: b]")
      {
        :dynamic,
        [line: 1],
        [
          [borscht: {:b, [line: 1], nil}],
          {
            :==,
            [line: 1],
            [
              {:field, [line: 1],
               [{:b, [line: 1], nil}, {:^, [line: 1], [{:field, [line: 1], nil}]}]},
              {:^, [line: 1], [{:value, [line: 1], nil}]}
            ]
          }
        ]
      }
  """
  def quote_dynamic(nil, _), do: nil

  def quote_dynamic(dynamic_builder, binding)
      when is_binary(dynamic_builder) do
    dynamic_builder
    |> String.replace("<<<binding>>>", binding)
    |> Code.string_to_quoted!()
  end
end
