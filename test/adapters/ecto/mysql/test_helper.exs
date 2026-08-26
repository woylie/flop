# Configure PG connection
Application.put_env(:flop, Flop.Repo,
  username: "root",
  password: "",
  database: "flop_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: "localhost",
  port: 3306,
  # Without this, cursor pagination on a string column fails with an "Illegal
  # mix of collations" error: the cursor value is cast, the cast takes the
  # connection's collation, and MyXQL leaves that at utf8mb4_general_ci while
  # MySQL 8 columns default to utf8mb4_0900_ai_ci.
  charset: "utf8mb4",
  collation: "utf8mb4_0900_ai_ci",
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

# A MySQL schema is a database, so `other_schema` is a sibling of the test
# database rather than something inside it, and storage_down leaves it behind.
Flop.Repo.query!("DROP SCHEMA IF EXISTS other_schema;")

Ecto.Migrator.up(Flop.Repo, 0, Flop.Repo.Mysql.Migration, log: true)

Ecto.Adapters.SQL.Sandbox.mode(Flop.Repo, :manual)

{:ok, _} = Application.ensure_all_started(:ex_machina)
ExUnit.start(exclude: [:binary_id_array, :composite_type])
