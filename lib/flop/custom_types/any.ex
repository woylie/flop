defmodule Flop.CustomTypes.Any do
  @moduledoc false
  use Ecto.Type

  # Since we only need this custom type to be able to work with Ecto embedded
  # schemas and Ecto.Changeset validation, the only relevant function here is
  # `cast/1`, which only returns the value as is. The other functions are only
  # here for the sake of the Ecto.Type behaviour. We don't actually dump/load
  # this type into/from a database, and you should not misuse this type for
  # that.

  def type, do: :string

  def cast(value), do: {:ok, value}

  def load(value), do: {:ok, value}

  def dump(value) when is_number(value), do: {:ok, to_string(value)}
  def dump(value) when is_binary(value), do: {:ok, value}
  def dump(value) when is_boolean(value), do: {:ok, to_string(value)}
  def dump(nil), do: {:ok, ""}
  def dump(_), do: :error
end
