defmodule Flop.CustomTypes.Any do
  @moduledoc false
  use Ecto.Type

  def type, do: :string

  def cast(value) when is_binary(value) or is_number(value) do
    {:ok, value}
  end

  def cast(_), do: :error

  def load(value), do: {:ok, value}

  def dump(value) when is_number(value), do: {:ok, to_string(value)}
  def dump(value) when is_binary(value), do: {:ok, value}
  def dump(_), do: :error
end
