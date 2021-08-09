defmodule Flop.Misc do
  @moduledoc false

  def add_wildcard(value), do: "%#{value}%"

  def split_search_text(s), do: s |> String.split() |> Enum.map(&add_wildcard/1)

  def quote_dynamic(nil, _), do: nil

  def quote_dynamic(dynamic_builder, binding)
      when is_binary(dynamic_builder) do
    dynamic_builder
    |> String.replace("<<<binding>>>", binding)
    |> Code.string_to_quoted!()
  end
end
