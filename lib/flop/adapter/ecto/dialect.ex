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

  @doc """
  Returns whether the repo's Ecto adapter supports `ILIKE`.

  Returns `true` if the adapter or repo are unknown.
  """
  def supports_ilike?(nil), do: true

  def supports_ilike?(repo) when is_atom(repo) do
    not (Code.ensure_loaded?(repo) and
           function_exported?(repo, :__adapter__, 0) and
           repo.__adapter__() in @without_ilike)
  end

  def supports_ilike?(_repo), do: true
end
