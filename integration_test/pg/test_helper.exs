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

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Flop.Repo)
  end
end

{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(Flop.Repo.config(), :temporary)

# Load up the repository, start it, and run migrations
_   = Ecto.Adapters.Postgres.storage_down(Flop.Repo.config())
:ok = Ecto.Adapters.Postgres.storage_up(Flop.Repo.config())

{:ok, _pid} = Flop.Repo.start_link()

[_ | _] = Ecto.Migrator.run(Flop.Repo, :up, log: true, all: true)
Ecto.Adapters.SQL.Sandbox.mode(Flop.Repo, :manual)

{:ok, _} = Application.ensure_all_started(:ex_machina)
ExUnit.start()