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

      assert {:error, %Meta{}} =
               Flop.validate(
                 %{
                   limit: 10,
                   filters: [%{field: :age, op: :>=, value: ~D[2015-01-01]}]
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
  end
end
