import Config

config :flop,
  ecto_repos: [Flop.Repo],
  repo: Flop.Repo

config :stream_data,
  max_runs: if(System.get_env("CI"), do: 100, else: 50),
  max_run_time: if(System.get_env("CI"), do: 3000, else: 200)

config :logger, level: :warning
