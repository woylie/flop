defmodule Flop.Adapter.Ecto.Dialect do
  @moduledoc false

  # ILIKE is a PostgreSQL extension. Flop falls back to LIKE for Ecto adapters
  # that don't support it. SQLite performs LIKE queries case-insensitively for
  # ASCII only. MySQL does so depending on the column collation. Falling back
  # for an unmeasured adapter would silently make a case-insensitive filter
  # case-sensitive.
  @without_ilike [Ecto.Adapters.MyXQL, Ecto.Adapters.SQLite3]

  # MySQL has neither NULLS FIRST nor NULLS LAST. It sorts NULLs first
  # ascending and last descending, so two of the four directions are plain ASC
  # and DESC, and the other two need `field IS NULL` as an extra sort key.
  @without_nulls_ordering [Ecto.Adapters.MyXQL]

  # Ecto's MyXQL adapter can store arrays in JSON columns, but it cannot build
  # array operations. Flop uses JSON_CONTAINS and JSON_LENGTH instead.
  @without_arrays [Ecto.Adapters.MyXQL]

  # Postgres puts nulls last when sorting by ASC/DESC without classifier.
  # MySQL and SQLite puts nulls first.
  @nulls_first_ascending [Ecto.Adapters.MyXQL, Ecto.Adapters.SQLite3]

  @typedoc """
  Feature support of a repo's Ecto adapter, resolved once per query and passed
  to the query builders.
  """
  @type t :: %__MODULE__{
          adapter: module | nil,
          arrays?: boolean,
          ilike?: boolean,
          nulls_last_ascending?: boolean,
          nulls_ordering?: boolean
        }

  defstruct adapter: nil,
            arrays?: true,
            ilike?: true,
            nulls_last_ascending?: true,
            nulls_ordering?: true

  @nulls_ordering_fallback %{
    asc_nulls_first: {:native, :asc},
    asc_nulls_last: {:emulated, :asc},
    desc_nulls_first: {:emulated, :desc},
    desc_nulls_last: {:native, :desc}
  }

  @doc """
  Returns the dialect for a repo, or the defaults if the repo or its adapter
  are unknown.
  """
  @spec new(module | nil) :: t
  def new(repo) do
    adapter = adapter(repo)

    %__MODULE__{
      adapter: adapter,
      arrays?: adapter not in @without_arrays,
      ilike?: adapter not in @without_ilike,
      nulls_last_ascending?: adapter not in @nulls_first_ascending,
      nulls_ordering?: adapter not in @without_nulls_ordering
    }
  end

  @doc """
  Dumps a filter value with the element type of an array field.

  Takes the type of the field, not of the element. Returns the value unchanged
  if it cannot be dumped, or if there is no type, which is the case for a query
  built without a schema.
  """
  @spec dump_array_element(term, term) :: term
  def dump_array_element(value, {:array, element_type}) do
    case Ecto.Type.dump(element_type, value) do
      {:ok, dumped} -> dumped
      :error -> value
    end
  end

  def dump_array_element(value, _ecto_type), do: value

  @doc """
  Returns how to build the `ORDER BY` clause for an order direction.

  - `{:native, direction}` - sort by the field with that direction.
  - `{:emulated, direction}` - sort by `field IS NULL` first, then by the
    field, both with that direction. This replaces `NULLS FIRST` and
    `NULLS LAST` on adapters that don't support them.
  """
  @spec order_direction(t, atom) :: {:native | :emulated, atom}
  def order_direction(%__MODULE__{nulls_ordering?: true}, direction) do
    {:native, direction}
  end

  def order_direction(%__MODULE__{}, direction) do
    Map.get(@nulls_ordering_fallback, direction, {:native, direction})
  end

  @doc """
  Returns the placement of NULLs for an order direction.
  """
  @spec null_placement(t, atom) :: :first | :last
  def null_placement(%__MODULE__{}, direction)
      when direction in [:asc_nulls_first, :desc_nulls_first],
      do: :first

  def null_placement(%__MODULE__{}, direction)
      when direction in [:asc_nulls_last, :desc_nulls_last],
      do: :last

  def null_placement(%__MODULE__{nulls_last_ascending?: true}, :asc), do: :last

  def null_placement(%__MODULE__{nulls_last_ascending?: true}, :desc),
    do: :first

  def null_placement(%__MODULE__{}, :asc), do: :first
  def null_placement(%__MODULE__{}, :desc), do: :last

  defp adapter(repo) when is_atom(repo) and not is_nil(repo) do
    if Code.ensure_loaded?(repo) and
         function_exported?(repo, :__adapter__, 0) do
      repo.__adapter__()
    end
  end

  defp adapter(_repo), do: nil
end
