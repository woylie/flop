defmodule Flop.MixProject do
  use Mix.Project

  @source_url "https://github.com/woylie/flop"
  @version "0.27.2"
  @adapters ~w(postgres sqlite mysql)
  @supported_adapters ~w(postgres sqlite mysql)

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
      test_ignore_filters: [&String.ends_with?(&1, "migration.exs")],
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

  def cli do
    [
      preferred_envs: [
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
        "test.adapters": :test,
        "test.base": :test,
        coveralls: :test,
        dialyzer: :test
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
      {:credo, "== 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "1.4.7", only: [:dev, :test], runtime: false},
      {:ecto, "~> 3.11"},
      {:ecto_sql, "== 3.14.0", only: :test},
      {:ex_doc, "0.40.3", only: :dev, runtime: false},
      {:ex_machina, "2.8.2", only: :test},
      {:makeup_diff, "0.1.1", only: :dev, runtime: false},
      {:excoveralls, "0.18.5", only: :test},
      {:myxql, "0.9.0", only: :test},
      {:nimble_options, "~> 1.0"},
      {:postgrex, "0.22.4", only: :test},
      {:ecto_sqlite3, "== 0.24.1", only: :test},
      {:stream_data, "1.4.0", only: [:dev, :test]}
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
      extras:
        Path.wildcard("guides/**/*.{md,cheatmd}") ++
          ["README.md", "CHANGELOG.md"],
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
      test: ["test", &test_adapters(@supported_adapters, &1)],
      # calls the task rather than the task name, which would resolve to the
      # alias above and run the adapters too
      "test.base": &Mix.Tasks.Test.run/1,
      "test.mysql": &test_adapters(["mysql"], &1),
      "test.postgres": &test_adapters(["postgres"], &1),
      "test.sqlite": &test_adapters(["sqlite"], &1),
      "test.adapters": &test_adapters(@adapters, &1),
      "coveralls.html.all": [
        "test.adapters --cover",
        "coveralls.html --import-cover cover"
      ],
      "coveralls.json.all": [
        fn _ -> test_adapters(@supported_adapters, ["--cover"]) end,
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

  defp test_adapters(adapters, args) do
    if is_nil(System.get_env("ECTO_ADAPTER")) do
      adapters
      |> Enum.map(&{&1, test_adapter(&1, args)})
      |> print_adapter_summary()
    end
  end

  defp test_adapter(adapter, args) do
    IO.puts("==> Running tests for ECTO_ADAPTER=#{adapter} mix test")

    {_, res} =
      System.cmd(
        "mix",
        ["test", ansi_option(), "--export-coverage=#{adapter}" | args],
        into: IO.binstream(:stdio, :line),
        env: [{"ECTO_ADAPTER", adapter}]
      )

    if res > 0, do: System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    res
  end

  defp print_adapter_summary([_]), do: :ok

  defp print_adapter_summary(results) do
    IO.puts("\n==> Adapter summary")

    for {adapter, res} <- results do
      IO.puts("    #{String.pad_trailing(adapter, 9)} #{status(res)}")
    end
  end

  defp status(0), do: "passed"
  defp status(res), do: "FAILED (exit #{res})"

  defp ansi_option do
    if IO.ANSI.enabled?(), do: "--color", else: "--no-color"
  end
end
