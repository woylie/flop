use Mix.Config

config :flop,
  ecto_repos: [Flop.Repo]

config :flop, Flop.Repo,
  username: "postgres",
  password: "postgres",
  database: "flop_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

config :logger, level: :warn
