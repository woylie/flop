defmodule Flop.CustomTypes.Any do
  @moduledoc false
  use Ecto.Type

  # Since we only need this custom type to be able to work with Ecto embedded
  # schemas and Ecto.Changeset validation, the only relevant function here is
  # `cast/1`, which only returns the value as is. The other functions are only
  # here for the sake of the Ecto.Type behaviour. We don't actually dump/load
  # this type into/from a database, and you should not misuse this type for
  # that.

  def cast(value), do: {:ok, value}

  # coveralls-ignore-start
  # This type is only used for casting values. The load and dump functions will
  # never be called.
  def type, do: :string
  def load(_), do: :error
  def dump(_), do: :error
  # coveralls-ignore-end
end
