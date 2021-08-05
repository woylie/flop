defmodule Flop.Misc do
  @moduledoc false

  def add_wildcard(value), do: "%#{value}%"

  def split_search_text(s), do: s |> String.split() |> Enum.map(&add_wildcard/1)
end
