defmodule Flop.CustomTypes.ExistingAtom do
  @moduledoc false
  use Ecto.Type

  def type, do: :string

  def cast(a) when is_binary(a) do
    {:ok, String.to_existing_atom(a)}
  rescue
    ArgumentError -> :error
  end

  def cast(a) when is_atom(a) do
    {:ok, a}
  end

  def cast(_), do: :error

  def load(a) when is_binary(a) do
    {:ok, String.to_existing_atom(a)}
  rescue
    ArgumentError -> :error
  end

  def dump(a) when is_atom(a), do: {:ok, to_string(a)}
  def dump(a) when is_binary(a), do: {:ok, a}
  def dump(_), do: :error
end
