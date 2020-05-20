defmodule FlopTest do
  use ExUnit.Case
  use ExUnitProperties

  doctest Flop

  import Ecto.Query, only: [from: 2]
  import Flop.TestUtil

  alias Ecto.Changeset
  alias Ecto.Query.BooleanExpr
  alias Ecto.Query.QueryExpr
  alias Flop
  alias Flop.Filter

  @base_query from p in Pet, where: p.age > 8, select: p.name

  describe "query/2" do
    test "adds order_by to query if set" do
      flop = %Flop{order_by: [:species, :name], order_directions: [:asc, :desc]}

      assert [
               %QueryExpr{
                 expr: [
                   asc: {{_, _, [_, :species]}, _, _},
                   desc: {{_, _, [_, :name]}, _, _}
                 ]
               }
             ] = Flop.query(Pet, flop).order_bys

      assert [
               %QueryExpr{
                 expr: [
                   asc: {{_, _, [_, :species]}, _, _},
                   desc: {{_, _, [_, :name]}, _, _}
                 ]
               }
             ] = Flop.query(@base_query, flop).order_bys
    end

    test "uses :asc as default direction" do
      flop = %Flop{order_by: [:species, :name], order_directions: nil}

      assert [
               %QueryExpr{
                 expr: [
                   asc: {{_, _, [_, :species]}, _, _},
                   asc: {{_, _, [_, :name]}, _, _}
                 ]
               }
             ] = Flop.query(Pet, flop).order_bys

      flop = %Flop{order_by: [:species, :name], order_directions: [:desc]}

      assert [
               %QueryExpr{
                 expr: [
                   desc: {{_, _, [_, :species]}, _, _},
                   asc: {{_, _, [_, :name]}, _, _}
                 ]
               }
             ] = Flop.query(Pet, flop).order_bys

      flop = %Flop{order_by: [:species], order_directions: [:desc]}

      assert [
               %QueryExpr{
                 expr: [desc: {{_, _, [_, :species]}, _, _}]
               }
             ] = Flop.query(Pet, flop).order_bys

      flop = %Flop{order_by: [:species], order_directions: [:desc, :desc]}

      assert [
               %QueryExpr{
                 expr: [desc: {{_, _, [_, :species]}, _, _}]
               }
             ] = Flop.query(Pet, flop).order_bys
    end

    test "adds adds limit to query if set" do
      flop = %Flop{limit: 10}
      query = Flop.query(Pet, flop)

      assert %QueryExpr{params: [{10, :integer}]} = query.limit
    end

    test "adds adds offset to query if set" do
      flop = %Flop{offset: 14}
      query = Flop.query(Pet, flop)

      assert %QueryExpr{params: [{14, :integer}]} = query.offset
    end

    test "adds adds limit and offset to query if page and page size are set" do
      flop = %Flop{page: 1, page_size: 10}
      assert %QueryExpr{params: [{0, :integer}]} = Flop.query(Pet, flop).offset
      assert %QueryExpr{params: [{10, :integer}]} = Flop.query(Pet, flop).limit

      flop = %Flop{page: 2, page_size: 10}
      assert %QueryExpr{params: [{10, :integer}]} = Flop.query(Pet, flop).offset
      assert %QueryExpr{params: [{10, :integer}]} = Flop.query(Pet, flop).limit

      flop = %Flop{page: 3, page_size: 4}
      assert %QueryExpr{params: [{8, :integer}]} = Flop.query(Pet, flop).offset
      assert %QueryExpr{params: [{4, :integer}]} = Flop.query(Pet, flop).limit
    end

    property "adds where clauses for filters" do
      check all filter <- filter() do
        flop = %Flop{filters: [filter]}
        %Filter{field: field, op: op, value: value} = filter

        assert [
                 %BooleanExpr{
                   expr: {^op, _, _},
                   op: :and,
                   params: [{^field, _}, {^value, _}]
                 }
               ] = Flop.query(Pet, flop).wheres
      end
    end

    test "adds where clauses for filters" do
      flop = %Flop{
        filters: [
          %Filter{field: :age, op: :>=, value: 4},
          %Filter{field: :name, op: :==, value: "Bo"}
        ]
      }

      assert [
               %BooleanExpr{
                 expr: {:>=, _, _},
                 op: :and,
                 params: [{:age, _}, {4, _}]
               },
               %BooleanExpr{
                 expr: {:==, _, _},
                 op: :and,
                 params: [{:name, _}, {"Bo", _}]
               }
             ] = Flop.query(Pet, flop).wheres
    end

    test "raises error if field or value are nil" do
      flop = %Flop{filters: [%Filter{op: :>=, value: 4}]}
      assert_raise ArgumentError, fn -> Flop.query(Pet, flop) end

      flop = %Flop{filters: [%Filter{field: :name, op: :>=}]}
      assert_raise ArgumentError, fn -> Flop.query(Pet, flop) end
    end

    test "leaves query unchanged if everything is nil" do
      flop = %Flop{
        filters: nil,
        limit: nil,
        offset: nil,
        order_by: nil,
        order_directions: nil,
        page: nil,
        page_size: nil
      }

      assert Flop.query(Pet, flop) == Pet
      assert Flop.query(@base_query, flop) == @base_query
    end
  end

  describe "validate/1" do
    test "returns Flop struct" do
      assert Flop.validate(%Flop{}) == {:ok, %Flop{}}
      assert Flop.validate(%{}) == {:ok, %Flop{}}
    end

    test "validates limit" do
      params = %{limit: -1}
      assert {:error, %Changeset{} = changeset} = Flop.validate(params)
      assert errors_on(changeset)[:limit] == ["must be greater than 0"]

      flop = %Flop{limit: 0}
      assert {:error, %Changeset{} = changeset} = Flop.validate(flop)
      assert errors_on(changeset)[:limit] == ["must be greater than 0"]

      flop = %Flop{limit: 21}
      assert {:error, %Changeset{} = changeset} = Flop.validate(flop, for: Pet)

      assert errors_on(changeset)[:limit] == [
               "must be less than or equal to 20"
             ]
    end

    test "validates offset" do
      params = %{offset: -1}
      assert {:error, %Changeset{} = changeset} = Flop.validate(params)

      assert errors_on(changeset)[:offset] == [
               "must be greater than or equal to 0"
             ]
    end

    test "only allows to order by fields marked as sortable" do
      # field exists, but is not sortable

      params = %{order_by: [:social_security_number]}
      assert {:error, changeset} = Flop.validate(params, for: Pet)
      assert errors_on(changeset)[:order_by] == ["has an invalid entry"]

      params = %{order_by: ["social_security_number"]}
      assert {:error, changeset} = Flop.validate(params, for: Pet)
      assert errors_on(changeset)[:order_by] == ["has an invalid entry"]

      # field does not exist

      params = %{order_by: [:halloween_costume]}
      assert {:error, changeset} = Flop.validate(params, for: Pet)
      assert errors_on(changeset)[:order_by] == ["has an invalid entry"]

      params = %{order_by: ["honorific"]}
      assert {:error, changeset} = Flop.validate(params, for: Pet)
      assert errors_on(changeset)[:order_by] == ["is invalid"]

      # field exists and is sortable

      params = %{order_by: [:name]}
      assert {:ok, %Flop{order_by: [:name]}} = Flop.validate(params, for: Pet)

      params = %{order_by: ["name"]}
      assert {:ok, %Flop{order_by: [:name]}} = Flop.validate(params, for: Pet)
    end

    test "validates order directions" do
      params = %{order_directions: [:up, :down]}
      assert {:error, %Changeset{} = changeset} = Flop.validate(params)
      assert errors_on(changeset)[:order_directions] == ["is invalid"]

      params = %{order_directions: ["up", "down"]}
      assert {:error, %Changeset{} = changeset} = Flop.validate(params)
      assert errors_on(changeset)[:order_directions] == ["is invalid"]

      params = %{order_directions: [:desc, :asc]}

      assert Flop.validate(params) ==
               {:ok, %Flop{order_directions: [:desc, :asc]}}

      params = %{order_directions: ["desc", "asc"]}

      assert Flop.validate(params) ==
               {:ok, %Flop{order_directions: [:desc, :asc]}}
    end

    test "validates page number" do
      params = %{page: -1}
      assert {:error, %Changeset{} = changeset} = Flop.validate(params)
      assert errors_on(changeset)[:page] == ["must be greater than 0"]

      flop = %Flop{page: 0}
      assert {:error, %Changeset{} = changeset} = Flop.validate(flop)
      assert errors_on(changeset)[:page] == ["must be greater than 0"]
    end

    test "validates page size" do
      params = %{page_size: -1}
      assert {:error, %Changeset{} = changeset} = Flop.validate(params)
      assert errors_on(changeset)[:page_size] == ["must be greater than 0"]

      flop = %Flop{page_size: 0}
      assert {:error, %Changeset{} = changeset} = Flop.validate(flop)
      assert errors_on(changeset)[:page_size] == ["must be greater than 0"]

      flop = %Flop{page_size: 21}
      assert {:error, %Changeset{} = changeset} = Flop.validate(flop, for: Pet)

      assert errors_on(changeset)[:page_size] == [
               "must be less than or equal to 20"
             ]
    end

    property "only allows one pagination method" do
      check all val_1 <- positive_integer(),
                val_2 <- one_of([positive_integer(), constant(nil)]),
                [offset, limit] = Enum.shuffle([val_1, val_2]),
                val_3 <- positive_integer(),
                val_4 <- one_of([positive_integer(), constant(nil)]),
                [page, page_size] = Enum.shuffle([val_3, val_4]) do
        params = %{
          offset: offset,
          limit: limit,
          page: page,
          page_size: page_size
        }

        assert {:error, %Changeset{} = changeset} = Flop.validate(params)

        messages = changeset |> errors_on() |> Map.values()

        assert ["cannot combine multiple pagination types"] in messages
      end
    end

    test "only allows to filter by fields marked as filterable" do
      # field exists, but is not filterable

      params = %{filters: [%{field: :social_security_number}]}
      assert {:error, changeset} = Flop.validate(params, for: Pet)
      assert [%{field: ["is invalid"]}] = errors_on(changeset)[:filters]

      params = %{filters: [%{field: "social_security_number"}]}
      assert {:error, changeset} = Flop.validate(params, for: Pet)
      assert [%{field: ["is invalid"]}] = errors_on(changeset)[:filters]

      # field does not exist

      params = %{filters: [%{field: :halloween_costume}]}
      assert {:error, changeset} = Flop.validate(params, for: Pet)
      assert [%{field: ["is invalid"]}] = errors_on(changeset)[:filters]

      params = %{filters: [%{field: "honorific"}]}
      assert {:error, changeset} = Flop.validate(params, for: Pet)
      assert [%{field: ["is invalid"]}] = errors_on(changeset)[:filters]

      # field exists and is filterable

      params = %{filters: [%{field: :species, value: "dog"}]}

      assert {:ok, %Flop{filters: [%{field: :species}]}} =
               Flop.validate(params, for: Pet)

      params = %{filters: [%{field: "species", value: "dog"}]}

      assert {:ok, %Flop{filters: [%{field: :species}]}} =
               Flop.validate(params, for: Pet)
    end

    test "validates filter operator" do
      params = %{filters: [%{field: "a", op: :=, value: "b"}]}
      assert {:error, %Changeset{} = changeset} = Flop.validate(params)
      assert errors_on(changeset)[:filters] == [%{op: ["is invalid"]}]

      params = %{filters: [%{field: "a", op: "=", value: "b"}]}
      assert {:error, %Changeset{} = changeset} = Flop.validate(params)
      assert errors_on(changeset)[:filters]

      params = %{filters: [%{field: "a", op: :==, value: "b"}]}
      assert {:ok, %Flop{filters: [%{op: :==}]}} = Flop.validate(params)

      params = %{filters: [%{field: "a", op: "==", value: "b"}]}
      assert {:ok, %Flop{filters: [%{op: :==}]}} = Flop.validate(params)
    end

    test "requires both page size and page" do
      params = %{page: 5}
      assert {:error, %Changeset{} = changeset} = Flop.validate(params)
      assert errors_on(changeset)[:page_size] == ["can't be blank"]

      params = %{page_size: 10}
      assert {:error, %Changeset{} = changeset} = Flop.validate(params)
      assert errors_on(changeset)[:page] == ["can't be blank"]
    end
  end
end
