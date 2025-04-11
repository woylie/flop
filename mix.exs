defmodule Flop.MixProject do
  use Mix.Project

  @source_url "https://github.com/woylie/flop"
  @version "0.26.1"
  @adapters ~w(postgres sqlite)

  def project do
    [
      app: :flop,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      test_paths: test_paths(System.get_env("ECTO_ADAPTER")),
      preferred_cli_env: [
        "coveralls.detail": :test,
        "coveralls.github": :test,
        "coveralls.html": :test,
        "coveralls.html.all": :test,
        "coveralls.json": :test,
        "coveralls.json.all": :test,
        "coveralls.post": :test,
        "ecto.create": :test,
        "ecto.drop": :test,
        "ecto.migrate": :test,
        "ecto.reset": :test,
        "test.all": :test,
        "test.adapters": :test,
        coveralls: :test,
        dialyzer: :test
      ],
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters: true,
        plt_file: {:no_warn, ".plts/dialyzer.plt"}
      ],
      name: "Flop",
      source_url: @source_url,
      homepage_url: @source_url,
      description: description(),
      package: package(),
      docs: docs(),
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
      {:credo, "~> 1.7.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.0", only: [:dev, :test], runtime: false},
      {:ecto, "~> 3.11"},
      {:ecto_sql, "~> 3.11", only: :test},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:ex_machina, "~> 2.4", only: :test},
      {:makeup_diff, "~> 0.1.0", only: :dev, runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:nimble_options, "~> 1.0"},
      {:postgrex, ">= 0.0.0", only: :test},
      {:ecto_sqlite3, "~> 0.19.0", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp description do
    "Filtering, ordering and pagination with Ecto."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @source_url <> "/blob/main/CHANGELOG.md",
        "Sponsor" => "https://github.com/sponsors/woylie"
      },
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*)
    ]
  end

  defp docs do
    [
      main: "readme",
      extra_section: "GUIDES",
      extras: [
        "guides/cheatsheets/schema.cheatmd",
        "guides/recipes/partial_uuid_filter.md",
        "README.md",
        "CHANGELOG.md"
      ],
      source_ref: @version,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      groups_for_extras: [
        Recipes: ~r/recipes\/.?/,
        Cheatsheets: ~r/cheatsheets\/.?/
      ],
      groups_for_docs: [
        "Query Functions": &(&1[:group] == :queries),
        "Parameter Manipulation": &(&1[:group] == :parameters),
        Miscellaneous: &(&1[:group] == :miscellaneous)
      ]
    ]
  end

  defp aliases do
    [
      "test.all": ["test", "test.adapters"],
      "test.postgres": &test_adapters(["postgres"], &1),
      "test.sqlite": &test_adapters(["sqlite"], &1),
      "test.adapters": &test_adapters/1,
      "coveralls.html.all": [
        "test.adapters --cover",
        "coveralls.html --import-cover cover"
      ],
      "coveralls.json.all": [
        # only run postgres and base tests for coverage until sqlite tests are
        # fixed
        fn _ -> test_adapters(["postgres"], ["--cover"]) end,
        "coveralls.json --import-cover cover"
      ]
    ]
  end

  defp test_paths(adapter) when adapter in @adapters,
    do: ["test/adapters/ecto/#{adapter}"]

  defp test_paths(nil), do: ["test/base"]

  defp test_paths(adapter) do
    raise """
    unknown Ecto adapter

    Expected ECTO_ADAPTER to be one of: #{inspect(@adapters)}

    Got: #{inspect(adapter)}
    """
  end

  defp test_adapters(adapters \\ @adapters, args) do
    for adapter <- adapters do
      IO.puts("==> Running tests for ECTO_ADAPTER=#{adapter} mix test")

      {_, res} =
        System.cmd(
          "mix",
          ["test", ansi_option(), "--export-coverage=#{adapter}" | args],
          into: IO.binstream(:stdio, :line),
          env: [{"ECTO_ADAPTER", adapter}]
        )

      if res > 0 do
        System.at_exit(fn _ -> exit({:shutdown, 1}) end)
      end
    end
  end

  defp ansi_option do
    if IO.ANSI.enabled?(), do: "--color", else: "--no-color"
  end
end
