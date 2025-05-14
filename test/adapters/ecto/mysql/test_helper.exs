Application.put_env(:flop, :async_integration_tests, true)

# Configure PG connection
Application.put_env(:flop, Flop.Repo,
  username: "root",
  password: "",
  database: "flop_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: "localhost",
  port: 3306,
  pool: Ecto.Adapters.SQL.Sandbox
)

defmodule Flop.Repo do
  use Ecto.Repo,
    otp_app: :flop,
    adapter: Ecto.Adapters.MyXQL
end

defmodule Flop.Integration.Case do
  use ExUnit.CaseTemplate
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Flop.Repo)
  end

  setup do
    %{ecto_adapter: :mysql}
  end
end

Code.require_file("migration.exs", __DIR__)

{:ok, _} =
  Ecto.Adapters.MyXQL.ensure_all_started(Flop.Repo.config(), :temporary)

# Load up the repository, start it, and run migrations
Ecto.Adapters.MyXQL.storage_down(Flop.Repo.config())
Ecto.Adapters.MyXQL.storage_up(Flop.Repo.config())

{:ok, _pid} = Flop.Repo.start_link()

Ecto.Migrator.up(Flop.Repo, 0, Flop.Repo.Mysql.Migration, log: true)

Ecto.Adapters.SQL.Sandbox.mode(Flop.Repo, :manual)

{:ok, _} = Application.ensure_all_started(:ex_machina)
ExUnit.start()
