defmodule Flop.MixProject do
  use Mix.Project

  def project do
    [
      app: :flop,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
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
      ]
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
      {:credo, "~> 1.1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0.0-rc.7", only: [:dev], runtime: false},
      {:ecto, "~> 3.2"},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:stream_data, "~> 0.4.3", only: [:dev, :test]}
    ]
  end

  defp description do
    "Flop is a library for filtering, ordering and pagination with Ecto."
  end

  defp package do
    [
      name: "Flop",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/woylie/flop"},
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*)
    ]
  end
end
