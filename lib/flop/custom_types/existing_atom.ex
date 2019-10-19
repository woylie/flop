defmodule Flop.CustomTypes.ExistingAtom do
  @moduledoc false
  use Ecto.Type

  def type, do: :string

  def cast(operator) when is_binary(operator) do
    {:ok, String.to_existing_atom(operator)}
  rescue
    ArgumentError -> :error
  end

  def cast(operator) when is_atom(operator) do
    {:ok, operator}
  end

  def cast(_), do: :error

  def load(operator) when is_binary(operator) do
    {:ok, String.to_existing_atom(operator)}
  rescue
    ArgumentError -> :error
  end

  def dump(operator) when is_atom(operator), do: {:ok, to_string(operator)}
  def dump(operator) when is_binary(operator), do: {:ok, operator}
  def dump(_), do: :error
end
