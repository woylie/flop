Application.put_env(:flop, :async_integration_tests, true)

# Configure PG connection
Application.put_env(:flop, Flop.Repo,
  username: "postgres",
  password: "postgres",
  database: "flop_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox
)

defmodule Flop.Repo do
  use Ecto.Repo,
    otp_app: :flop,
    adapter: Ecto.Adapters.Postgres
end

defmodule Flop.Integration.Case do
  use ExUnit.CaseTemplate
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Flop.Repo)
  end

  setup do
    %{ecto_adapter: :postgres}
  end
end

Code.require_file("migration.exs", __DIR__)

{:ok, _} =
  Ecto.Adapters.Postgres.ensure_all_started(Flop.Repo.config(), :temporary)

# Load up the repository, start it, and run migrations
Ecto.Adapters.Postgres.storage_down(Flop.Repo.config())
Ecto.Adapters.Postgres.storage_up(Flop.Repo.config())

{:ok, _pid} = Flop.Repo.start_link()

Ecto.Migrator.up(Flop.Repo, 0, Flop.Repo.Postgres.Migration, log: true)

Ecto.Adapters.SQL.Sandbox.mode(Flop.Repo, :manual)

{:ok, _} = Application.ensure_all_started(:ex_machina)
ExUnit.start()
