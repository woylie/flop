defmodule Flop.CustomTypes.Operator do
  @moduledoc false
  use Ecto.Type

  def type, do: :string

  @allowed_operators [:==, :!=, :<=, :<, :>=, :>]
  @allowed_operators_str Enum.map(@allowed_operators, &to_string/1)

  def cast(operator) when operator in @allowed_operators_str do
    {:ok, String.to_existing_atom(operator)}
  end

  def cast(operator) when operator in @allowed_operators do
    {:ok, operator}
  end

  def cast(_), do: :error

  def load(operator) when is_binary(operator) do
    {:ok, String.to_existing_atom(operator)}
  end

  def dump(operator) when is_atom(operator), do: {:ok, to_string(operator)}
  def dump(operator) when is_binary(operator), do: {:ok, operator}
  def dump(_), do: :error
end
