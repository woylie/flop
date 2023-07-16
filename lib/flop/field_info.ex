defmodule Flop.FieldInfo do
  @moduledoc false

  @type t :: %__MODULE__{
          ecto_type: Flop.Schema.ecto_type() | nil,
          operators: [Flop.Filter.op()] | nil,
          extra: map
        }

  defstruct [:ecto_type, :extra, :operators]
end
