defmodule Flop.MixProject do
  use Mix.Project

  def project do
    [
      app: :flop,
      version: "0.6.1",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ],
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters: true,
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      name: "Flop",
      source_url: "https://github.com/woylie/flop",
      homepage_url: "https://github.com/woylie/flop",
      description: description(),
      package: package(),
      docs: [
        main: "readme",
        extras: ["README.md"]
      ],
      aliases: aliases(),
      consolidate_protocols: Mix.env() != :test
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.4.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0.0", only: [:dev], runtime: false},
      {:ecto, "~> 3.2"},
      {:ecto_sql, "~> 3.4", only: :test},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:ex_machina, "~> 2.4", only: :test},
      {:excoveralls, "~> 0.10", only: :test},
      {:postgrex, ">= 0.0.0", only: :test},
      {:stream_data, "~> 0.5", only: [:dev, :test]}
    ]
  end

  defp description do
    "Flop is a library for filtering, ordering and pagination with Ecto."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/woylie/flop"},
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*)
    ]
  end

  defp aliases do
    [test: ["ecto.create --quiet", "ecto.migrate", "test"]]
  end
end
