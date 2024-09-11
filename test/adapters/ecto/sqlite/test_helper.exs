Application.put_env(:flop, :async_integration_tests, false)

# Configure SQLite db
Application.put_env(:flop, Flop.Repo,
  database: "tmp/test.db",
  pool: Ecto.Adapters.SQL.Sandbox,
  show_sensitive_data_on_connection_error: true
)

defmodule Flop.Repo do
  use Ecto.Repo,
    otp_app: :flop,
    adapter: Ecto.Adapters.SQLite3
end

defmodule Flop.Integration.Case do
  use ExUnit.CaseTemplate
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Flop.Repo)
  end
end

Code.require_file("migration.exs", __DIR__)

{:ok, _} =
  Ecto.Adapters.SQLite3.ensure_all_started(Flop.Repo.config(), :temporary)

# Load up the repository, start it, and run migrations
_ = Ecto.Adapters.SQLite3.storage_down(Flop.Repo.config())
:ok = Ecto.Adapters.SQLite3.storage_up(Flop.Repo.config())

{:ok, _pid} = Flop.Repo.start_link()

:ok = Ecto.Migrator.up(Flop.Repo, 0, Flop.Repo.SQLite.Migration, log: false)

{:ok, _} = Application.ensure_all_started(:ex_machina)
ExUnit.start(exclude: [:composite_type, :prefix])
