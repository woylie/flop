defmodule Flop.CustomTypes.Like do
  @moduledoc false
  use Ecto.Type

  # Custom ecto type for casting values for (i)like_and/or operators. Attempts
  # to cast the value as either a string or a list of strings.

  def cast(value) do
    case Ecto.Type.cast(:string, value) do
      {:ok, cast_value} ->
        {:ok, cast_value}

      _ ->
        case Ecto.Type.cast({:array, :string}, value) do
          {:ok, cast_value} -> {:ok, cast_value}
          _ -> :error
        end
    end
  end

  # coveralls-ignore-start
  # This type is only used for casting values. The load and dump functions will
  # never be called.
  def type, do: :string
  def load(_), do: :error
  def dump(_), do: :error
  # coveralls-ignore-end
end
