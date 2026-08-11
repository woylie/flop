defmodule FlopTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias __MODULE__.TestProvider
  alias Flop.Meta
  alias MyApp.Fruit
  alias MyApp.Pet
  alias MyApp.Vegetable

  defmodule TestProvider do
    use Flop, repo: Flop.Repo, default_limit: 35
  end

  defmodule TestProviderWithoutLimit do
    use Flop, repo: Flop.Repo, default_limit: false
  end

  defmodule StubRepo do
    def all(_query, opts) do
      send(self(), {__MODULE__, :all, opts})
      []
    end
  end

  defmodule OtherStubRepo do
    def all(_query, opts) do
      send(self(), {__MODULE__, :all, opts})
      []
    end
  end

  defmodule BackendWithQueryOpts do
    use Flop, repo: FlopTest.StubRepo, query_opts: [prefix: "backend"]
  end

  defmodule BackendWithNestedAdapterOpts do
    use Flop,
      adapter_opts: [
        repo: FlopTest.StubRepo,
        query_opts: [prefix: "backend", timeout: 1000]
      ]
  end

  describe "validate/1" do
    test "returns Flop struct" do
      assert Flop.validate(%Flop{}) == {:ok, %Flop{limit: 50}}
      assert Flop.validate(%{}) == {:ok, %Flop{limit: 50}}
    end

    test "returns error if parameters are invalid" do
      assert {:error, %Meta{} = meta} =
               Flop.validate(
                 %{
                   limit: -1,
                   filters: [%{field: :name}, %{field: :age, op: "approx"}]
                 },
                 for: Pet
               )

      assert meta.flop == %Flop{}
      assert meta.schema == Pet

      assert meta.params == %{
               "limit" => -1,
               "filters" => [
                 %{"field" => :name},
                 %{"field" => :age, "op" => "approx"}
               ]
             }

      assert [{"must be greater than %{number}", _}] =
               Keyword.get(meta.errors, :limit)

      assert [[], [op: [{"is invalid", _}]]] =
               Keyword.get(meta.errors, :filters)
    end

    test "returns error for struct values" do
      assert {:error, %Meta{} = meta} =
               Flop.validate(
                 %{filters: [%{field: :age, op: :>=, value: ~D[2015-01-01]}]},
                 for: Pet
               )

      assert meta.params == %{
               "filters" => [
                 %{"field" => :age, "op" => :>=, "value" => ~D[2015-01-01]}
               ]
             }
    end

    test "returns error if operator is not allowed for field" do
      assert {:error, %Meta{} = meta} =
               Flop.validate(
                 %{filters: [%{field: :age, op: "=~", value: 20}]},
                 for: Pet
               )

      assert meta.flop == %Flop{}
      assert meta.schema == Pet

      assert meta.params == %{
               "filters" => [%{"field" => :age, "op" => "=~", "value" => 20}]
             }

      assert [
               [
                 op: [
                   {"is invalid",
                    [
                      allowed_operators: [
                        :==,
                        :!=,
                        :empty,
                        :not_empty,
                        :<=,
                        :<,
                        :>=,
                        :>,
                        :in,
                        :not_in
                      ]
                    ]}
                 ]
               ]
             ] = Keyword.get(meta.errors, :filters)
    end

    test "returns error for non-string value with a pattern operator" do
      for op <- [:=~, :like, :not_like, :ilike, :not_ilike],
          value <- [["8"], %{"a" => "8"}, 8] do
        assert {:error, %Meta{} = meta} =
                 Flop.validate(%{
                   filters: [%{field: :name, op: op, value: value}]
                 })

        assert [[value: [{"is invalid", _}]]] =
                 Keyword.get(meta.errors, :filters)
      end
    end

    test "accepts string value with a pattern operator on an untyped field" do
      assert {:ok, %Flop{filters: [filter]}} =
               Flop.validate(%{
                 filters: [%{field: :name, op: :like, value: "8"}]
               })

      assert filter.value == "8"
    end

    test "returns filter params as list if passed as a map" do
      assert {:error, %Meta{} = meta} =
               Flop.validate(
                 %{
                   limit: -1,
                   filters: %{
                     "0" => %{field: :name},
                     "1" => %{field: :age, op: "approx"}
                   }
                 },
                 for: Pet
               )

      assert meta.params == %{
               "limit" => -1,
               "filters" => [
                 %{"field" => :name},
                 %{"field" => :age, "op" => "approx"}
               ]
             }
    end

    test "requires limit for pagination" do
      assert {:error, %Meta{} = meta} =
               TestProviderWithoutLimit.validate(%{})

      assert [{"can't be blank", _}] = meta.errors[:limit]
    end

    test "does not require limit if pagination is disabled" do
      assert {:ok, _} =
               TestProviderWithoutLimit.validate(%{}, pagination: false)
    end
  end

  describe "validate!/1" do
    test "returns a flop struct" do
      assert Flop.validate!(%Flop{}) == %Flop{limit: 50}
      assert Flop.validate!(%{}) == %Flop{limit: 50}
    end

    test "raises if params are invalid" do
      error =
        assert_raise Flop.InvalidParamsError, fn ->
          Flop.validate!(%{
            limit: -1,
            filters: [%{field: :name}, %{field: :age, op: "approx"}]
          })
        end

      assert error.params ==
               %{
                 "limit" => -1,
                 "filters" => [
                   %{"field" => :name},
                   %{"field" => :age, "op" => "approx"}
                 ]
               }

      assert [{"must be greater than %{number}", _}] =
               Keyword.get(error.errors, :limit)

      assert [[], [op: [{"is invalid", _}]]] =
               Keyword.get(error.errors, :filters)
    end
  end

  describe "adapter options with a backend module" do
    test "merges query_opts passed at the call site over the backend's" do
      BackendWithQueryOpts.all(Pet, %Flop{}, query_opts: [timeout: 30_000])
      assert_received {StubRepo, :all, opts}
      assert Enum.sort(opts) == [prefix: "backend", timeout: 30_000]
    end

    test "a repo passed at the call site overrides the backend's" do
      BackendWithQueryOpts.all(Pet, %Flop{}, repo: OtherStubRepo)
      assert_received {OtherStubRepo, :all, opts}
      assert Enum.sort(opts) == [prefix: "backend"]
    end

    test "merges nested adapter_opts over the backend's" do
      BackendWithQueryOpts.all(Pet, %Flop{},
        adapter_opts: [repo: OtherStubRepo, query_opts: [timeout: 30_000]]
      )

      assert_received {OtherStubRepo, :all, opts}
      assert Enum.sort(opts) == [prefix: "backend", timeout: 30_000]
    end

    test "applies call site options without a backend" do
      Flop.all(Pet, %Flop{}, repo: StubRepo, query_opts: [timeout: 30_000])
      assert_received {StubRepo, :all, opts}
      assert Enum.sort(opts) == [timeout: 30_000]
    end

    test "merges over a backend declared with nested adapter_opts" do
      BackendWithNestedAdapterOpts.all(Pet, %Flop{},
        query_opts: [timeout: 30_000]
      )

      assert_received {StubRepo, :all, opts}
      assert Enum.sort(opts) == [prefix: "backend", timeout: 30_000]
    end
  end

  describe "adapter_opts/1" do
    test "call site options win over the backend" do
      opts = [backend: BackendWithQueryOpts, repo: OtherStubRepo]
      assert Flop.adapter_opts(opts)[:repo] == OtherStubRepo
    end

    test "a root key wins over the same key nested in adapter_opts" do
      opts = [repo: OtherStubRepo, adapter_opts: [repo: StubRepo]]
      assert Flop.adapter_opts(opts)[:repo] == OtherStubRepo
    end

    test "query_opts merge key by key across all levels" do
      opts = [
        backend: BackendWithNestedAdapterOpts,
        adapter_opts: [query_opts: [timeout: 2000]],
        query_opts: [prefix: "call site"]
      ]

      assert Enum.sort(Flop.adapter_opts(opts)[:query_opts]) ==
               [prefix: "call site", timeout: 2000]
    end

    test "falls back to the application environment" do
      assert Flop.adapter_opts([])[:repo] == Flop.Repo
    end
  end

  describe "meta/3" do
    test "returns meta struct without limit" do
      assert %Meta{} = meta = Flop.meta([], %Flop{offset: 10}, count: 100)
      assert meta.current_offset == 10
      assert meta.current_page == 1
      assert meta.page_size == nil
      assert meta.previous_offset == nil
      assert meta.total_pages == 1
    end

    test "returns meta struct without page size" do
      assert %Meta{} = meta = Flop.meta([], %Flop{page: 3}, count: 100)
      assert meta.current_offset == 0
      assert meta.current_page == 3
    end
  end

  describe "aliases/2" do
    test "returns alias fields" do
      assert Flop.aliases(%Flop{order_by: [:name, :pet_count]}, MyApp.Owner) ==
               [:pet_count]
    end

    test "returns empty list if order_by is nil" do
      assert Flop.aliases(%Flop{order_by: nil}, MyApp.Owner) == []
    end
  end

  describe "named_bindings/3" do
    test "returns used binding names with order_by and filters" do
      flop = %Flop{
        filters: [
          # join fields
          %Flop.Filter{field: :owner_age, op: :==, value: 5},
          %Flop.Filter{field: :owner_name, op: :==, value: "George"},
          # compound field
          %Flop.Filter{field: :full_name, op: :==, value: "George the Dog"}
        ],
        # join field and normal field
        order_by: [:owner_name, :age]
      }

      assert Flop.named_bindings(flop, Pet) == [:owner]
    end

    test "allows disabling order fields" do
      flop = %Flop{order_by: [:owner_name, :age]}
      assert Flop.named_bindings(flop, Pet, order: false) == []
      assert Flop.named_bindings(flop, Pet, order: true) == [:owner]
    end

    test "returns used binding names with order_by" do
      flop = %Flop{
        # join field and normal field
        order_by: [:owner_name, :age]
      }

      assert Flop.named_bindings(flop, Pet) == [:owner]
    end

    test "returns used binding names with filters" do
      flop = %Flop{
        filters: [
          # join fields
          %Flop.Filter{field: :owner_age, op: :==, value: 5},
          %Flop.Filter{field: :owner_name, op: :==, value: "George"},
          # compound field
          %Flop.Filter{field: :full_name, op: :==, value: "George the Dog"}
        ]
      }

      assert Flop.named_bindings(flop, Pet) == [:owner]
    end

    test "returns used binding names with custom filter using bindings opt" do
      flop = %Flop{
        filters: [
          %Flop.Filter{field: :with_bindings, op: :==, value: 5}
        ]
      }

      assert Flop.named_bindings(flop, Vegetable) == [:curious]
    end

    test "returns empty list if no join fields are used" do
      flop = %Flop{
        filters: [
          # compound field
          %Flop.Filter{field: :full_name, op: :==, value: "George the Dog"}
        ],
        # normal field
        order_by: [:age]
      }

      assert Flop.named_bindings(flop, Pet) == []
    end

    test "returns empty list if there are no filters and order fields" do
      assert Flop.named_bindings(%Flop{}, Pet) == []
    end
  end

  describe "with_named_bindings/4" do
    test "adds necessary bindings to query" do
      query = Pet
      opts = [for: Pet]

      flop = %Flop{
        filters: [
          # join fields
          %Flop.Filter{field: :owner_age, op: :==, value: 5},
          %Flop.Filter{field: :owner_name, op: :==, value: "George"},
          # compound field
          %Flop.Filter{field: :full_name, op: :==, value: "George the Dog"}
        ],
        # join field and normal field
        order_by: [:owner_name, :age]
      }

      fun = fn q, :owner ->
        join(q, :left, [p], o in assoc(p, :owner), as: :owner)
      end

      new_query = Flop.with_named_bindings(query, flop, fun, opts)
      assert Ecto.Query.has_named_binding?(new_query, :owner)
    end

    test "allows disabling order fields" do
      query = Pet
      flop = %Flop{order_by: [:owner_name, :age]}

      fun = fn q, :owner ->
        join(q, :left, [p], o in assoc(p, :owner), as: :owner)
      end

      opts = [for: Pet, order: false]
      new_query = Flop.with_named_bindings(query, flop, fun, opts)
      assert new_query == query

      opts = [for: Pet, order: true]
      new_query = Flop.with_named_bindings(query, flop, fun, opts)
      assert Ecto.Query.has_named_binding?(new_query, :owner)
    end

    test "returns query unchanged if no bindings are required" do
      query = Pet
      opts = [for: Pet]

      assert Flop.with_named_bindings(
               query,
               %Flop{},
               fn _, _ -> nil end,
               opts
             ) == query
    end
  end

  describe "push_order/3" do
    test "raises error if invalid directions option is passed" do
      for flop <- [%Flop{}, %Flop{order_by: [:name], order_directions: [:asc]}],
          directions <- [{:up, :down}, "up,down"] do
        assert_raise Flop.InvalidDirectionsError, fn ->
          Flop.push_order(flop, :name, directions: directions)
        end
      end
    end
  end

  describe "get_option/3" do
    test "returns value from option list" do
      # sanity check
      default_limit = Flop.Schema.default_limit(%Fruit{})
      assert default_limit && default_limit != 40

      assert Flop.get_option(
               :default_limit,
               [default_limit: 40, backend: TestProvider, for: Fruit],
               1
             ) == 40
    end

    test "falls back to schema option" do
      # sanity check
      assert default_limit = Flop.Schema.default_limit(%Fruit{})

      assert Flop.get_option(
               :default_limit,
               [backend: TestProvider, for: Fruit],
               1
             ) == default_limit
    end

    test "falls back to backend config if schema option is not set" do
      # sanity check
      assert Flop.Schema.default_limit(%Pet{}) == nil

      assert Flop.get_option(
               :default_limit,
               [backend: TestProvider, for: Pet],
               1
             ) == 35
    end

    test "falls back to backend config if :for option is not set" do
      assert Flop.get_option(:default_limit, [backend: TestProvider], 1) == 35
    end

    test "falls back to default value" do
      assert Flop.get_option(:default_limit, []) == 50
    end

    test "falls back to default value passed to function" do
      assert Flop.get_option(:some_option, [], 2) == 2
    end

    test "falls back to nil" do
      assert Flop.get_option(:some_option, []) == nil
    end

    test "resolves the filterable fields of a schema" do
      assert Flop.get_option(:filterable, for: Pet) ==
               Flop.Schema.filterable(%Pet{})
    end
  end

  describe "option levels" do
    defmodule BackendWithReplaceInvalidParams do
      use Flop, repo: Flop.Repo, replace_invalid_params: true
    end

    test "replace_invalid_params can be set on a backend module" do
      assert Flop.get_option(
               :replace_invalid_params,
               backend: BackendWithReplaceInvalidParams
             ) == true

      assert {:ok, %Flop{limit: 50}} =
               Flop.validate(%{limit: 20_000},
                 backend: BackendWithReplaceInvalidParams,
                 for: Pet
               )
    end

    test "replace_invalid_params at the call site wins over the backend" do
      assert {:error, %Meta{}} =
               Flop.validate(%{limit: 20_000},
                 backend: BackendWithReplaceInvalidParams,
                 for: Pet,
                 replace_invalid_params: false
               )
    end

    defmodule BackendWithCursorValueFunc do
      use Flop,
        repo: Flop.Repo,
        cursor_value_func: &Flop.Cursor.get_cursor_from_edge/2
    end

    test "cursor_value_func can be set on a backend module" do
      assert {cursor, _} =
               Flop.Cursor.get_cursors(
                 [{%Pet{name: "a"}, %{name: "edge"}}],
                 [:name],
                 backend: BackendWithCursorValueFunc
               )

      assert Flop.Cursor.decode!(cursor) == %{name: "edge"}
    end

    test "raises for a cursor_value_func that is not a function" do
      assert_raise Flop.InvalidConfigError, fn ->
        defmodule BackendWithBadCursorValueFunc do
          use Flop, repo: Flop.Repo, cursor_value_func: :not_a_function
        end
      end
    end

    defmodule BackendWithMaxCursorSize do
      use Flop, repo: Flop.Repo, max_cursor_size: 10
    end

    test "max_cursor_size can be set on a backend module" do
      cursor = Flop.Cursor.encode(%{name: "George"})

      assert {:error, %Meta{errors: [after: _]}} =
               Flop.validate(
                 %{first: 2, after: cursor, order_by: [:name]},
                 backend: BackendWithMaxCursorSize,
                 for: Pet
               )
    end

    defmodule BackendWithoutMaxLimit do
      use Flop, repo: Flop.Repo, max_limit: false
    end

    defmodule SchemaWithoutMaxLimit do
      use Ecto.Schema

      @derive {Flop.Schema, filterable: [], sortable: [:name], max_limit: false}

      schema "pets" do
        field :name, :string
      end
    end

    test "max_limit can be disabled on a backend module" do
      assert Flop.get_option(:max_limit, backend: BackendWithoutMaxLimit) ==
               false

      assert {:ok, %Flop{limit: 20_000}} =
               Flop.validate(%{limit: 20_000}, backend: BackendWithoutMaxLimit)
    end

    test "max_limit can be disabled on a schema" do
      assert Flop.get_option(:max_limit, for: SchemaWithoutMaxLimit) == false

      assert {:ok, %Flop{limit: 20_000}} =
               Flop.validate(%{limit: 20_000}, for: SchemaWithoutMaxLimit)
    end

    test "raises for an option a backend module does not accept" do
      assert_raise Flop.InvalidConfigError, fn ->
        defmodule BackendWithUnknownOption do
          use Flop, repo: Flop.Repo, filterable: [:name]
        end
      end
    end
  end
end
