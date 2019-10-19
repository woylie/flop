defmodule Flop.Filter do
  @moduledoc """
  Defines a filter.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Flop.Schema

  alias Ecto.Changeset
  alias Flop.CustomTypes.Any
  alias Flop.CustomTypes.ExistingAtom
  alias Flop.CustomTypes.Operator

  @typedoc """
  Represents filter query parameters.

  ### Fields

  - `field`: The field the filter is applied to. The allowed fields can be
    restricted by deriving `Flop.Schema` in your Ecto schema.
  - `op`: The filter operator.
  - `value`: The comparison value of the filter.
  """
  @type t :: %__MODULE__{
          field: atom | String.t(),
          op: op,
          value: any
        }

  @typedoc """
  Represents valid filter operators.
  """
  @type op :: :== | :!= | :<= | :< | :>= | :>

  @primary_key false
  embedded_schema do
    field :field, ExistingAtom
    field :op, Operator, default: :==
    field :value, Any
  end

  @doc false
  @spec changeset(__MODULE__.t(), map, keyword) :: Changeset.t()
  def changeset(filter, %{} = params, opts \\ []) do
    filter
    |> cast(params, [:field, :op, :value])
    |> validate_required([:field, :op, :value])
    |> validate_filterable(opts[:for])
  end

  @spec validate_filterable(Changeset.t(), module | nil) :: Changeset.t()
  defp validate_filterable(changeset, nil), do: changeset

  defp validate_filterable(changeset, module) do
    filterable_fields =
      module
      |> struct()
      |> sortable()

    validate_inclusion(changeset, :field, filterable_fields)
  end
end
