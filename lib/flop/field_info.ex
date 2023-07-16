defmodule Flop.FieldInfo do
  @moduledoc """
  Defines a struct that holds the information about a schema field.

  This struct is mainly for use by adapters.
  """

  @typedoc """
  Contains the information about a schema field.

  - `ecto_type` - The Ecto type of the field. This value is used to determine
    which operators can be used on the field and to determine how to cast
    filter values.
  - `operators` - The allowed filter operators on this field. If `nil`, the
    allowed operators are determined based on the `ecto_type`. If set, the
    given operator list is used instead.
  - `extra` - A map with additional configuration for the field. The contents
    depend on the specific adapter.
  """
  @type t :: %__MODULE__{
          ecto_type: Flop.Schema.ecto_type() | nil,
          operators: [Flop.Filter.op()] | nil,
          extra: map
        }

  defstruct [:ecto_type, :extra, :operators]
end
