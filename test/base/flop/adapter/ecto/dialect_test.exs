defmodule Flop.Adapter.Ecto.DialectTest do
  use ExUnit.Case, async: true

  alias Flop.Adapter.Ecto.Dialect

  @order_directions [
    :asc,
    :asc_nulls_first,
    :asc_nulls_last,
    :desc,
    :desc_nulls_first,
    :desc_nulls_last
  ]

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

  describe "new/1" do
    test "reads the features of a known adapter" do
      assert Dialect.new(PostgresRepo) ==
               %Dialect{
                 adapter: Ecto.Adapters.Postgres,
                 arrays?: true,
                 ilike?: true,
                 nulls_last_ascending?: true,
                 nulls_ordering?: true
               }

      assert Dialect.new(MyXQLRepo) ==
               %Dialect{
                 adapter: Ecto.Adapters.MyXQL,
                 arrays?: false,
                 ilike?: false,
                 nulls_last_ascending?: false,
                 nulls_ordering?: false
               }

      assert Dialect.new(SQLite3Repo) ==
               %Dialect{
                 adapter: Ecto.Adapters.SQLite3,
                 arrays?: true,
                 ilike?: false,
                 nulls_last_ascending?: false,
                 nulls_ordering?: true
               }
    end

    test "returns the defaults for an unknown adapter" do
      assert Dialect.new(UnknownRepo) ==
               %Dialect{adapter: SomeApp.Adapters.Unknown}
    end

    test "returns the defaults without a repo" do
      assert Dialect.new(nil) == %Dialect{}
      assert Dialect.new(NotARealRepo) == %Dialect{}
    end

    test "defaults to leaving the query unmodified" do
      assert %Dialect{} ==
               %Dialect{
                 arrays?: true,
                 ilike?: true,
                 nulls_last_ascending?: true,
                 nulls_ordering?: true
               }
    end
  end

  describe "null_placement/2" do
    test "follows the direction where it says where nulls go" do
      for repo <- [PostgresRepo, MyXQLRepo, SQLite3Repo] do
        dialect = Dialect.new(repo)

        assert Dialect.null_placement(dialect, :asc_nulls_first) == :first
        assert Dialect.null_placement(dialect, :desc_nulls_first) == :first
        assert Dialect.null_placement(dialect, :asc_nulls_last) == :last
        assert Dialect.null_placement(dialect, :desc_nulls_last) == :last
      end
    end

    test "follows the database for a plain direction" do
      postgres = Dialect.new(PostgresRepo)

      assert Dialect.null_placement(postgres, :asc) == :last
      assert Dialect.null_placement(postgres, :desc) == :first

      for repo <- [MyXQLRepo, SQLite3Repo] do
        dialect = Dialect.new(repo)

        assert Dialect.null_placement(dialect, :asc) == :first
        assert Dialect.null_placement(dialect, :desc) == :last
      end
    end
  end

  describe "the cursor predicate" do
    test "seeks past the null rows where they sort last" do
      assert cursor_clause(PostgresRepo, :asc, "abc") =~ "is_nil(p0.name)"
      assert cursor_clause(PostgresRepo, :asc, "abc") =~ "p0.name > "

      assert cursor_clause(PostgresRepo, :asc, nil) == "false"
    end

    test "seeks past the null rows where they sort first" do
      refute cursor_clause(SQLite3Repo, :asc, "abc") =~ "is_nil"
      assert cursor_clause(SQLite3Repo, :asc, "abc") =~ "p0.name > "

      assert cursor_clause(SQLite3Repo, :asc, nil) =~ "not is_nil(p0.name)"
    end

    test "reads the placement from the direction where it says" do
      for repo <- [PostgresRepo, MyXQLRepo, SQLite3Repo] do
        assert cursor_clause(repo, :asc_nulls_last, nil) == "false"
        assert cursor_clause(repo, :asc_nulls_first, nil) =~ "not is_nil"
        assert cursor_clause(repo, :desc_nulls_last, nil) == "false"
        assert cursor_clause(repo, :desc_nulls_first, nil) =~ "not is_nil"
      end
    end

    test "compares the other way round for a descending order" do
      assert cursor_clause(PostgresRepo, :desc, "abc") =~ "p0.name < "
      assert cursor_clause(SQLite3Repo, :desc, "abc") =~ "p0.name < "

      assert cursor_clause(SQLite3Repo, :desc, "abc") =~ "is_nil(p0.name)"
      refute cursor_clause(PostgresRepo, :desc, "abc") =~ "is_nil"
    end
  end

  describe "cursor pagination without a repo" do
    test "raises for a plain direction" do
      for direction <- [:asc, :desc] do
        error =
          assert_raise ArgumentError, fn ->
            cursor_query(nil, direction)
          end

        assert error.message =~ "requires the repo"
        assert error.message =~ ":asc_nulls_last"
      end
    end

    test "builds the query for a direction that states the placement" do
      for direction <- [
            :asc_nulls_first,
            :asc_nulls_last,
            :desc_nulls_first,
            :desc_nulls_last
          ] do
        assert %Ecto.Query{} = cursor_query(nil, direction)
      end
    end

    test "builds the query for a plain direction once the repo is known" do
      for repo <- [PostgresRepo, MyXQLRepo, SQLite3Repo],
          direction <- [:asc, :desc] do
        assert %Ecto.Query{} = cursor_query(repo, direction)
      end
    end

    test "does not raise without cursor pagination" do
      flop = %Flop{limit: 2, order_by: [:name], order_directions: [:asc]}
      assert %Ecto.Query{} = Flop.query(MyApp.Pet, flop, for: MyApp.Pet)
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

  describe "order_direction/2" do
    test "keeps the direction on an adapter with NULLS FIRST and NULLS LAST" do
      for direction <- @order_directions do
        assert Dialect.order_direction(Dialect.new(PostgresRepo), direction) ==
                 {:native, direction}
      end
    end

    test "maps the nulls directions on an adapter without them" do
      assert Dialect.order_direction(Dialect.new(MyXQLRepo), :asc) ==
               {:native, :asc}

      assert Dialect.order_direction(Dialect.new(MyXQLRepo), :desc) ==
               {:native, :desc}

      assert Dialect.order_direction(Dialect.new(MyXQLRepo), :asc_nulls_first) ==
               {:native, :asc}

      assert Dialect.order_direction(Dialect.new(MyXQLRepo), :desc_nulls_last) ==
               {:native, :desc}

      assert Dialect.order_direction(Dialect.new(MyXQLRepo), :asc_nulls_last) ==
               {:emulated, :asc}

      assert Dialect.order_direction(Dialect.new(MyXQLRepo), :desc_nulls_first) ==
               {:emulated, :desc}
    end

    test "keeps the direction for an unknown adapter" do
      assert Dialect.order_direction(Dialect.new(UnknownRepo), :asc_nulls_last) ==
               {:native, :asc_nulls_last}
    end

    test "keeps the direction without a repo" do
      assert Dialect.order_direction(Dialect.new(nil), :asc_nulls_last) ==
               {:native, :asc_nulls_last}

      assert Dialect.order_direction(Dialect.new(NotARealRepo), :asc_nulls_last) ==
               {:native, :asc_nulls_last}
    end
  end

  describe "the query built for the nulls order directions" do
    test "uses them on an adapter that has them" do
      for direction <- @order_directions do
        assert order_by_clause(PostgresRepo, direction) ==
                 "[#{direction}: p0.name]"
      end
    end

    test "uses the plain direction where the adapter already sorts that way" do
      assert order_by_clause(MyXQLRepo, :asc_nulls_first) == "[asc: p0.name]"
      assert order_by_clause(MyXQLRepo, :desc_nulls_last) == "[desc: p0.name]"
    end

    test "sorts on IS NULL first where it does not" do
      assert order_by_clause(MyXQLRepo, :asc_nulls_last) ==
               ~S|[asc: fragment("? IS NULL", p0.name), asc: p0.name]|

      assert order_by_clause(MyXQLRepo, :desc_nulls_first) ==
               ~S|[desc: fragment("? IS NULL", p0.name), desc: p0.name]|
    end
  end

  defp cursor_query(repo, direction) do
    flop = %Flop{
      first: 2,
      after: Flop.Cursor.encode(%{name: "abc"}),
      order_by: [:name],
      order_directions: [direction]
    }

    opts = if repo, do: [for: MyApp.Pet, repo: repo], else: [for: MyApp.Pet]
    Flop.query(MyApp.Pet, flop, opts)
  end

  defp cursor_clause(repo, direction, cursor_value) do
    flop = %Flop{
      first: 2,
      after: Flop.Cursor.encode(%{name: cursor_value}),
      order_by: [:name],
      order_directions: [direction]
    }

    MyApp.Pet
    |> Flop.query(flop, for: MyApp.Pet, repo: repo, tiebreaker: false)
    |> inspect()
    |> String.split("where: ")
    |> List.last()
    |> String.split(", order_by:")
    |> List.first()
    |> String.trim_trailing(">")
  end

  defp order_by_clause(repo, direction) do
    flop = %Flop{order_by: [:name], order_directions: [direction]}

    MyApp.Pet
    |> Flop.query(flop, for: MyApp.Pet, repo: repo, tiebreaker: false)
    |> inspect()
    |> String.split("order_by: ")
    |> List.last()
    |> String.trim_trailing(">")
  end

  describe "the query built for the array operators" do
    test "uses the array itself on an adapter that has one" do
      assert where_clause(PostgresRepo, :tags, :contains, "pear") ==
               ~S|^"pear" in p0.tags|

      assert where_clause(PostgresRepo, :tags, :not_contains, "pear") ==
               ~S|^"pear" not in p0.tags|

      assert where_clause(PostgresRepo, :tags, :empty, true) ==
               ~S|is_nil(p0.tags) or p0.tags == type(^[], {:array, :string})|
    end

    test "uses the JSON functions on an adapter that has no array type" do
      assert where_clause(MyXQLRepo, :tags, :contains, "pear") ==
               ~S|fragment("JSON_CONTAINS(?, ?)", p0.tags, ^["pear"])|

      assert where_clause(MyXQLRepo, :tags, :not_contains, "pear") ==
               ~S|not fragment("JSON_CONTAINS(?, ?)", p0.tags, ^["pear"])|

      assert where_clause(MyXQLRepo, :tags, :empty, true) ==
               ~S|is_nil(p0.tags) or fragment("JSON_LENGTH(?) = 0", p0.tags)|
    end

    test "dumps the value with the element type of the field" do
      assert Dialect.dump_array_element("pear", {:array, :string}) == "pear"

      assert Dialect.dump_array_element(~D[2026-08-13], {:array, :date}) ==
               ~D[2026-08-13]
    end

    test "passes the value through when it has no type to dump it with" do
      assert Dialect.dump_array_element("pear", nil) == "pear"
      assert Dialect.dump_array_element("pear", {:array, :integer}) == "pear"
    end
  end

  defp where_clause(repo) do
    flop = %Flop{
      filters: [%Flop.Filter{field: :name, op: :ilike, value: "abc"}]
    }

    MyApp.Pet
    |> Flop.query(flop, for: MyApp.Pet, repo: repo, tiebreaker: false)
    |> inspect()
    |> String.split("where: ")
    |> List.last()
    |> String.trim_trailing(">")
  end

  defp where_clause(repo, field, op, value) do
    flop = %Flop{filters: [%Flop.Filter{field: field, op: op, value: value}]}

    MyApp.Pet
    |> Flop.query(flop, for: MyApp.Pet, repo: repo, tiebreaker: false)
    |> inspect()
    |> String.split("where: ")
    |> List.last()
    |> String.trim_trailing(">")
  end
end
