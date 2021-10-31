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

  | Operator     | Value               | WHERE clause                        |
  | :----------- | :------------------ | ----------------------------------- |
  | `:==`        | `"Salicaceae"`      | `WHERE column = 'Salicaceae'`       |
  | `:!=`        | `"Salicaceae"`      | `WHERE column != 'Salicaceae'`      |
  | `:=~`        | `"cyth"`            | `WHERE column ILIKE '%cyth%'`       |
  | `:empty`     |                     | `WHERE column IS NULL`              |
  | `:not_empty` |                     | `WHERE column IS NOT NULL`          |
  | `:<=`        | `10`                | `WHERE column <= 10`                |
  | `:<`         | `10`                | `WHERE column < 10`                 |
  | `:>=`        | `10`                | `WHERE column >= 10`                |
  | `:>`         | `10`                | `WHERE column > 10`                 |
  | `:in`        | `["pear", "plum"]`  | `WHERE column IN ('pear', 'plum')`  |
  | `:like`      | `"cyth"`            | `WHERE column LIKE '%cyth%'`        |
  | `:like_and`  | `"Rubi Rosa"`       | `WHERE column LIKE '%Rubi%' AND column LIKE '%Rosa%'`   |
  | `:like_or`   | `"Rubi Rosa"`       | `WHERE column LIKE '%Rubi%' OR column LIKE '%Rosa%'`    |
  | `:ilike`     | `"cyth"`            | `WHERE column ILIKE '%cyth%'`       |
  | `:ilike_and` | `"Rubi Rosa"`       | `WHERE column ILIKE '%Rubi%' AND column ILIKE '%Rosa%'` |
  | `:ilike_or`  | `"Rubi Rosa"`       | `WHERE column ILIKE '%Rubi%' OR column ILIKE '%Rosa%'`  |
  """
  @type op ::
          :==
          | :!=
          | :=~
          | :empty
          | :not_empty
          | :<=
          | :<
          | :>=
          | :>
          | :in
          | :like
          | :like_and
          | :like_or
          | :ilike
          | :ilike_and
          | :ilike_or

  @primary_key false
  embedded_schema do
    field :field, ExistingAtom

    field :op, Ecto.Enum,
      default: :==,
      values: [
        :==,
        :!=,
        :=~,
        :empty,
        :not_empty,
        :<=,
        :<,
        :>=,
        :>,
        :in,
        :like,
        :like_and,
        :like_or,
        :ilike,
        :ilike_and,
        :ilike_or
      ]

    field :value, Any
  end

  @doc false
  @spec changeset(__MODULE__.t(), map, keyword) :: Changeset.t()
  def changeset(filter, %{} = params, opts \\ []) do
    filter
    |> cast(params, [:field, :op, :value])
    |> validate_required([:field, :op])
    |> validate_filterable(opts[:for])
  end

  @spec validate_filterable(Changeset.t(), module | nil) :: Changeset.t()
  defp validate_filterable(changeset, nil), do: changeset

  defp validate_filterable(changeset, module) do
    filterable_fields =
      module
      |> struct()
      |> filterable()

    validate_inclusion(changeset, :field, filterable_fields)
  end
end
