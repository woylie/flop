defmodule Flop.Adapter.Ecto.Dialect do
  @moduledoc false

  # ILIKE is a PostgreSQL extension. Flop falls back to LIKE for Ecto adapters
  # that don't support it. SQLite performs LIKE queries case-insensitively for
  # ASCII only. MySQL does so depending on the column collation.
  #
  # The list names the adapters without ILIKE rather than the ones with it, so
  # that an adapter Flop hasn't been measured against keeps building ILIKE.
  # Falling back for such an adapter would silently make a case-insensitive
  # filter case-sensitive.
  @without_ilike [Ecto.Adapters.MyXQL, Ecto.Adapters.SQLite3]

  # MySQL has neither NULLS FIRST nor NULLS LAST. It sorts NULLs first
  # ascending and last descending, so two of the four directions are plain ASC
  # and DESC, and the other two need `field IS NULL` as an extra sort key.
  @without_nulls_ordering [Ecto.Adapters.MyXQL]

  @nulls_ordering_fallback %{
    asc_nulls_first: {:native, :asc},
    asc_nulls_last: {:emulated, :asc},
    desc_nulls_first: {:emulated, :desc},
    desc_nulls_last: {:native, :desc}
  }

  @doc """
  Returns whether the repo's Ecto adapter supports `ILIKE`.

  Returns `true` if the adapter or repo are unknown.
  """
  def supports_ilike?(repo) do
    adapter(repo) not in @without_ilike
  end

  @doc """
  Returns how to build the `ORDER BY` clause for an order direction.

  - `{:native, direction}` - sort by the field with that direction.
  - `{:emulated, direction}` - sort by `field IS NULL` first, then by the
    field, both with that direction. This replaces `NULLS FIRST` and
    `NULLS LAST` on adapters that don't support them.
  """
  def order_direction(repo, direction) do
    if adapter(repo) in @without_nulls_ordering do
      Map.get(@nulls_ordering_fallback, direction, {:native, direction})
    else
      {:native, direction}
    end
  end

  defp adapter(repo) when is_atom(repo) and not is_nil(repo) do
    if Code.ensure_loaded?(repo) and
         function_exported?(repo, :__adapter__, 0) do
      repo.__adapter__()
    end
  end

  defp adapter(_repo), do: nil
end
