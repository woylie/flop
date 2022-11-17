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

  | Operator        | Value               | WHERE clause                                            |
  | :-------------- | :------------------ | ------------------------------------------------------- |
  | `:==`           | `"Salicaceae"`      | `WHERE column = 'Salicaceae'`                           |
  | `:!=`           | `"Salicaceae"`      | `WHERE column != 'Salicaceae'`                          |
  | `:=~`           | `"cyth"`            | `WHERE column ILIKE '%cyth%'`                           |
  | `:empty`        | `true`              | `WHERE (column IS NULL) = true`                         |
  | `:empty`        | `false`             | `WHERE (column IS NULL) = false`                        |
  | `:not_empty`    | `true`              | `WHERE (column IS NOT NULL) = true`                     |
  | `:not_empty`    | `false`             | `WHERE (column IS NOT NULL) = false`                    |
  | `:<=`           | `10`                | `WHERE column <= 10`                                    |
  | `:<`            | `10`                | `WHERE column < 10`                                     |
  | `:>=`           | `10`                | `WHERE column >= 10`                                    |
  | `:>`            | `10`                | `WHERE column > 10`                                     |
  | `:in`           | `["pear", "plum"]`  | `WHERE column = ANY('pear', 'plum')`                    |
  | `:not_in`       | `["pear", "plum"]`  | `WHERE column = NOT IN('pear', 'plum')`                 |
  | `:contains`     | `"pear"`            | `WHERE 'pear' = ANY(column)`                            |
  | `:not_contains` | `"pear"`            | `WHERE 'pear' = NOT IN(column)`                         |
  | `:like`         | `"cyth"`            | `WHERE column LIKE '%cyth%'`                            |
  | `:like_and`     | `["Rubi", "Rosa"]`  | `WHERE column LIKE '%Rubi%' AND column LIKE '%Rosa%'`   |
  | `:like_and`     | `"Rubi Rosa"`       | `WHERE column LIKE '%Rubi%' AND column LIKE '%Rosa%'`   |
  | `:like_or`      | `["Rubi", "Rosa"]`  | `WHERE column LIKE '%Rubi%' OR column LIKE '%Rosa%'`    |
  | `:like_or`      | `"Rubi Rosa"`       | `WHERE column LIKE '%Rubi%' OR column LIKE '%Rosa%'`    |
  | `:ilike`        | `"cyth"`            | `WHERE column ILIKE '%cyth%'`                           |
  | `:ilike_and`    | `["Rubi", "Rosa"]`  | `WHERE column ILIKE '%Rubi%' AND column ILIKE '%Rosa%'` |
  | `:ilike_and`    | `"Rubi Rosa"`       | `WHERE column ILIKE '%Rubi%' AND column ILIKE '%Rosa%'` |
  | `:ilike_or`     | `["Rubi", "Rosa"]`  | `WHERE column ILIKE '%Rubi%' OR column ILIKE '%Rosa%'`  |
  | `:ilike_or`     | `"Rubi Rosa"`       | `WHERE column ILIKE '%Rubi%' OR column ILIKE '%Rosa%'`  |

  The filter operators `:ilike_and`, `:ilike_or`, `:like_and` and `:like_or`
  accept both strings and list of strings.

  - If the filter value is a string, it will be split at whitespace characters
    and the segments are combined with `and` or `or`.
  - If a list of strings is passed, the individual strings are not split, and
    the list items are combined with `and` or `or`.
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
          | :not_in
          | :contains
          | :not_contains
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
        :not_in,
        :contains,
        :not_contains,
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
    |> validate_op(opts[:for])
  end

  @spec validate_filterable(Changeset.t(), module | nil) :: Changeset.t()
  defp validate_filterable(changeset, nil), do: changeset

  defp validate_filterable(changeset, module) when is_atom(module) do
    filterable_fields =
      module
      |> struct()
      |> filterable()

    validate_inclusion(changeset, :field, filterable_fields)
  end

  defp validate_op(changeset, nil), do: changeset

  defp validate_op(%Changeset{valid?: true} = changeset, module)
       when is_atom(module) do
    field = Changeset.get_field(changeset, :field)
    op = Changeset.get_field(changeset, :op)
    allowed_operators = allowed_operators(module, field)

    if op in allowed_operators do
      changeset
    else
      add_error(changeset, :op, "is invalid")
    end
  end

  defp validate_op(%Changeset{valid?: false} = changeset, module)
       when is_atom(module) do
    changeset
  end

  @doc """
  Returns the allowed operators for the given schema module and field.

  If the given value is not a native Ecto type, a list with all operators is
  returned.

      iex> allowed_operators(Pet, :age)
      [:==, :!=, :empty, :not_empty, :<=, :<, :>=, :>, :in, :not_in]
  """
  @spec allowed_operators(atom, atom) :: [op]
  def allowed_operators(module, field)
      when is_atom(module) and is_atom(field) do
    :type |> module.__schema__(field) |> allowed_operators()
  end

  @doc """
  Returns the allowed operators for the given Ecto type.

  If the given value is not a native Ecto type, a list with all operators is
  returned.

      iex> allowed_operators(:integer)
      [:==, :!=, :empty, :not_empty, :<=, :<, :>=, :>, :in, :not_in]
  """
  @spec allowed_operators(atom) :: [op]
  def allowed_operators(type) when type in [:decimal, :float, :id, :integer] do
    [:==, :!=, :empty, :not_empty, :<=, :<, :>=, :>, :in, :not_in]
  end

  def allowed_operators(type) when type in [:binary_id, :string] do
    [
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
      :not_in,
      :like,
      :like_and,
      :like_or,
      :ilike,
      :ilike_and,
      :ilike_or
    ]
  end

  def allowed_operators(:boolean) do
    [:==, :!=, :=~, :empty, :not_empty]
  end

  def allowed_operators({:array, _}) do
    [
      :==,
      :!=,
      :empty,
      :not_empty,
      :<=,
      :<,
      :>=,
      :>,
      :in,
      :not_in,
      :contains,
      :not_contains
    ]
  end

  def allowed_operators({:map, _}) do
    [:==, :!=, :empty, :not_empty, :in, :not_in]
  end

  def allowed_operators(:map) do
    [:==, :!=, :empty, :not_empty, :in, :not_in]
  end

  def allowed_operators(type)
      when type in [
             :date,
             :time,
             :time_usec,
             :naive_datetime,
             :naive_datetime_usec,
             :utc_datetime,
             :utc_datetime_usec
           ] do
    [:==, :!=, :empty, :not_empty, :<=, :<, :>=, :>, :in, :not_in]
  end

  def allowed_operators({:parameterized, Ecto.Enum, _}) do
    [
      :==,
      :!=,
      :empty,
      :not_empty,
      :<=,
      :<,
      :>=,
      :>,
      :in,
      :not_in
    ]
  end

  def allowed_operators(_) do
    [
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
      :not_in,
      :contains,
      :not_contains,
      :like,
      :like_and,
      :like_or,
      :ilike,
      :ilike_and,
      :ilike_or
    ]
  end
end
