defmodule Flop.Adapter.Ecto.DialectTest do
  use ExUnit.Case, async: true

  alias Flop.Adapter.Ecto.Dialect

  defmodule PostgresRepo do
    def __adapter__, do: Ecto.Adapters.Postgres
  end

  defmodule MyXQLRepo do
    def __adapter__, do: Ecto.Adapters.MyXQL
  end

  defmodule SQLite3Repo do
    def __adapter__, do: Ecto.Adapters.SQLite3
  end

  defmodule UnknownRepo do
    def __adapter__, do: SomeApp.Adapters.Unknown
  end

  describe "supports_ilike?/1" do
    test "returns true for an adapter that has ILIKE" do
      assert Dialect.supports_ilike?(PostgresRepo)
    end

    test "returns false for adapters that do not have ILIKE" do
      refute Dialect.supports_ilike?(MyXQLRepo)
      refute Dialect.supports_ilike?(SQLite3Repo)
    end

    test "returns true for an unknown adapter" do
      assert Dialect.supports_ilike?(UnknownRepo)
    end

    test "returns true without a repo" do
      assert Dialect.supports_ilike?(nil)
      assert Dialect.supports_ilike?(NotARealRepo)
    end
  end

  describe "the query built for the case-insensitive operators" do
    test "uses ILIKE on an adapter that has it" do
      assert where_clause(PostgresRepo) ==
               ~S|ilike(p0.name, ^"%abc%")|
    end

    test "uses LIKE with an ESCAPE clause on an adapter that does not" do
      assert where_clause(SQLite3Repo) ==
               ~S|fragment("? LIKE ? ESCAPE ?", p0.name, ^"%abc%", ^"\\")|

      assert where_clause(MyXQLRepo) == where_clause(SQLite3Repo)
    end

    test "uses ILIKE when no repo is configured" do
      assert where_clause(nil) == where_clause(PostgresRepo)
    end
  end

  defp where_clause(repo) do
    flop = %Flop{
      filters: [%Flop.Filter{field: :name, op: :ilike, value: "abc"}]
    }

    MyApp.Pet
    |> Flop.query(flop, for: MyApp.Pet, repo: repo)
    |> inspect()
    |> String.split("where: ")
    |> List.last()
    |> String.trim_trailing(">")
  end
end
