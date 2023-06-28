defmodule Flop.CustomTypes.ExistingAtom do
  @moduledoc false
  use Ecto.Type

  def cast(a) when is_binary(a) do
    {:ok, String.to_existing_atom(a)}
  rescue
    ArgumentError -> :error
  end

  def cast(a) when is_atom(a) do
    {:ok, a}
  end

  def cast(_), do: :error

  # coveralls-ignore-start
  # This type is only used for casting values. The load and dump functions will
  # never be called.
  def type, do: :string
  def load(_), do: :error
  def dump(_), do: :error
  # coveralls-ignore-end
end
