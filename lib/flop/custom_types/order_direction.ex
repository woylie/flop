defmodule Flop.CustomTypes.OrderDirection do
  @moduledoc false
  use Ecto.Type

  def type, do: :string

  @allowed_directions [
    :asc,
    :asc_nulls_first,
    :asc_nulls_last,
    :desc,
    :desc_nulls_first,
    :desc_nulls_last
  ]

  @allowed_directions_str Enum.map(@allowed_directions, &to_string/1)

  def cast(direction) when direction in @allowed_directions_str do
    {:ok, String.to_existing_atom(direction)}
  end

  def cast(direction) when direction in @allowed_directions do
    {:ok, direction}
  end

  def cast(_), do: :error

  def load(direction) when is_binary(direction) do
    {:ok, String.to_existing_atom(direction)}
  end

  def dump(direction) when is_atom(direction), do: {:ok, to_string(direction)}
  def dump(direction) when is_binary(direction), do: {:ok, direction}
  def dump(_), do: :error
end
