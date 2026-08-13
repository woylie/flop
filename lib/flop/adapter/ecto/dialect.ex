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

  @typedoc """
  Defines feature support for a repo's Ecto adapter.

  This is resolved once per query and passed to the query builders.
  """
  @type t :: %__MODULE__{ilike?: boolean, nulls_ordering?: boolean}

  defstruct ilike?: true, nulls_ordering?: true

  @nulls_ordering_fallback %{
    asc_nulls_first: {:native, :asc},
    asc_nulls_last: {:emulated, :asc},
    desc_nulls_first: {:emulated, :desc},
    desc_nulls_last: {:native, :desc}
  }

  @doc """
  Returns the dialect for a repo.

  Returns the defaults if the repo or its adapter are unknown.
  """
  def new(repo) do
    adapter = adapter(repo)

    %__MODULE__{
      ilike?: adapter not in @without_ilike,
      nulls_ordering?: adapter not in @without_nulls_ordering
    }
  end

  @doc """
  Returns how to build the `ORDER BY` clause for an order direction.

  - `{:native, direction}` - sort by the field with that direction.
  - `{:emulated, direction}` - sort by `field IS NULL` first, then by the
    field, both with that direction. This replaces `NULLS FIRST` and
    `NULLS LAST` on adapters that don't support them.
  """
  def order_direction(%__MODULE__{nulls_ordering?: true}, direction) do
    {:native, direction}
  end

  def order_direction(%__MODULE__{}, direction) do
    Map.get(@nulls_ordering_fallback, direction, {:native, direction})
  end

  defp adapter(repo) when is_atom(repo) and not is_nil(repo) do
    if Code.ensure_loaded?(repo) and
         function_exported?(repo, :__adapter__, 0) do
      repo.__adapter__()
    end
  end

  defp adapter(_repo), do: nil
end
