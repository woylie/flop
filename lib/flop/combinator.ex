defmodule Flop.Combinator do
  @moduledoc """
  Defines a combinator for boolean logic on filters.
  """

  use Ecto.Schema

  import PolymorphicEmbed
  import Ecto.Changeset

  alias Ecto.Changeset

  @typedoc """
  Represents a combinator for applying boolean logic to filters.

  ### Fields

  - `type`: The boolean operator to apply to the filters (`:and` or `:or`).
  - `filters`: A list of filters or nested combinators to combine.
  """
  @type t :: %__MODULE__{
          type: combinator_type,
          filters: [Flop.Filter.t() | t()]
        }

  @typedoc """
  Represents valid combinator types.

  | Type  | Description                      |
  | :---- | :------------------------------- |
  | `:and`| Combines filters with AND logic  |
  | `:or` | Combines filters with OR logic   |
  """
  @type combinator_type :: :and | :or

  @combinator_types [:and, :or]

  @primary_key false
  embedded_schema do
    field :type, Ecto.Enum,
      default: :and,
      values: @combinator_types

    polymorphic_embeds_many(:filters,
      types: [
        filter: [module: Flop.Filter, identify_by_fields: [:field, :op, :value]],
        combinator: [module: __MODULE__, identify_by_fields: [:type, :filters]]
      ],
      on_replace: :delete
    )
  end

  @doc false
  @spec changeset(__MODULE__.t(), map, keyword) :: Changeset.t()
  def changeset(combinator, %{} = params, opts \\ []) do
    combinator
    |> cast(params, [:type])
    |> validate_required([:type])
    |> cast_polymorphic_embed(:filters, with: filter_changeset_opts(opts))
    |> validate_filters_not_empty()
  end

  defp validate_filters_not_empty(changeset) do
    filters = get_field(changeset, :filters)
    is_list = is_list(filters)
    length = if is_list, do: length(filters), else: 0

    cond do
      is_list and length == 0 ->
        add_error(
          changeset,
          :filters,
          "must have at least two filters or one combinator"
        )

      is_list and length == 1 ->
        case List.first(filters) do
          %__MODULE__{} ->
            changeset

          _ ->
            add_error(
              changeset,
              :filters,
              "must have at least two filters or one combinator"
            )
        end

      true ->
        changeset
    end
  end

  defp filter_changeset_opts(opts) do
    [
      filter: &Flop.Filter.changeset/3,
      combinator: &changeset/3
    ]
    |> Enum.map(fn {type, changeset_fn} ->
      {type, fn struct, params -> changeset_fn.(struct, params, opts) end}
    end)
  end
end
