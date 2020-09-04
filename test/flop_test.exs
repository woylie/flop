defmodule FlopTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  doctest Flop

  import Ecto.Query, only: [from: 2]
  import Flop.Factory
  import Flop.TestUtil

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset
  alias Ecto.Query.BooleanExpr
  alias Ecto.Query.QueryExpr
  alias Flop.Filter
  alias Flop.Fruit
  alias Flop.Meta
  alias Flop.Pet
  alias Flop.Repo

  @base_query from p in Pet, where: p.age > 8, select: p.name

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "query/2" do
    test "adds order_by to query if set" do
      pets = insert_list(20, :pet)

      sorted_pets =
        Enum.sort(
          pets,
          &(&1.species < &2.species ||
              (&1.species == &2.species && &1.name >= &2.name))
        )

      flop = %Flop{
        order_by: [:species, :name],
        order_directions: [:asc, :desc]
      }

      result = Pet |> Flop.query(flop) |> Repo.all()
      assert result == sorted_pets
    end

    test "uses :asc as default direction" do
      pets = insert_list(20, :pet)

      # order by three fieds, no order directions passed

      flop = %Flop{order_by: [:species, :name, :age], order_directions: nil}
      sorted_pets = Enum.sort_by(pets, &{&1.species, &1.name, &1.age})
      result = Pet |> Flop.query(flop) |> Repo.all()
      assert result == sorted_pets

      # order by three fields, one order direction passed

      flop = %Flop{order_by: [:species, :name, :age], order_directions: [:desc]}

      sorted_pets =
        Enum.sort(
          pets,
          &(&1.species > &2.species ||
              (&1.species == &2.species &&
                 (&1.name < &2.name ||
                    (&1.name == &2.name && &1.age <= &2.age))))
        )

      result = Pet |> Flop.query(flop) |> Repo.all()
      assert result == sorted_pets

      flop = %Flop{order_by: [:species], order_directions: [:desc, :desc]}

      assert [
               %QueryExpr{
                 expr: [desc: {{_, _, [_, :species]}, _, _}]
               }
             ] = Flop.query(Pet, flop).order_bys
    end

    test "adds adds limit to query if set" do
      insert_list(11, :pet)
      flop = %Flop{limit: 10}
      query = Flop.query(Pet, flop)
      assert %QueryExpr{params: [{10, :integer}]} = query.limit
      assert length(Repo.all(query)) == 10
    end

    test "adds adds offset to query if set" do
      pets = insert_list(10, :pet)

      expected_pets =
        pets
        |> Enum.sort_by(&{&1.name, &1.species, &1.age})
        |> Enum.slice(4..10)

      flop = %Flop{offset: 4, order_by: [:name, :species, :age]}
      query = Flop.query(Pet, flop)
      assert %QueryExpr{params: [{4, :integer}]} = query.offset
      assert Repo.all(query) == expected_pets
    end

    test "adds adds limit and offset to query if page and page size are set" do
      pets = insert_list(40, :pet)
      sorted_pets = Enum.sort_by(pets, &{&1.name, &1.species, &1.age})
      order_by = [:name, :species, :age]

      flop = %Flop{page: 1, page_size: 10, order_by: order_by}
      query = Flop.query(Pet, flop)
      assert %QueryExpr{params: [{0, :integer}]} = query.offset
      assert %QueryExpr{params: [{10, :integer}]} = query.limit
      assert Repo.all(query) == Enum.slice(sorted_pets, 0..9)

      flop = %Flop{page: 2, page_size: 10, order_by: order_by}
      query = Flop.query(Pet, flop)
      assert %QueryExpr{params: [{10, :integer}]} = query.offset
      assert %QueryExpr{params: [{10, :integer}]} = query.limit
      assert Repo.all(query) == Enum.slice(sorted_pets, 10..19)

      flop = %Flop{page: 3, page_size: 4, order_by: order_by}
      query = Flop.query(Pet, flop)
      assert %QueryExpr{params: [{8, :integer}]} = query.offset
      assert %QueryExpr{params: [{4, :integer}]} = query.limit
      assert Repo.all(query) == Enum.slice(sorted_pets, 8..11)
    end

    property "applies equality filter" do
      pets = insert_list(50, :pet)

      check all field <- member_of([:age, :name]),
                values = Enum.map(pets, &Map.get(&1, field)),
                query_value <-
                  one_of([member_of(values), value_by_field(field)]),
                query_value != "" do
        {:ok, flop} =
          Flop.validate(%{
            filters: [
              %{field: field, op: :==, value: query_value}
            ]
          })

        query = Flop.query(Pet, flop)
        result = Repo.all(query)
        assert Enum.all?(result, &(Map.get(&1, field) == query_value))

        expected_pets = Enum.filter(pets, &(Map.get(&1, field) == query_value))
        assert length(result) == length(expected_pets)
      end
    end

    property "applies inequality filter" do
      pets = insert_list(50, :pet)

      check all field <- member_of([:age, :name]),
                values = Enum.map(pets, &Map.get(&1, field)),
                query_value <-
                  one_of([member_of(values), value_by_field(field)]),
                query_value != "" do
        {:ok, flop} =
          Flop.validate(%{
            filters: [
              %{field: field, op: :!=, value: query_value}
            ]
          })

        query = Flop.query(Pet, flop)
        result = Repo.all(query)
        refute Enum.any?(result, &(Map.get(&1, field) == query_value))

        expected_pets = Enum.filter(pets, &(Map.get(&1, field) != query_value))
        assert length(result) == length(expected_pets)
      end
    end

    property "applies ilike filter" do
      pets = insert_list(50, :pet)
      values = Enum.map(pets, & &1.name)

      check all some_value <- member_of(values),
                str_length = String.length(some_value),
                start_at <- integer(0..(str_length - 1)),
                end_at <- integer(start_at..(str_length - 1)),
                query_value = String.slice(some_value, start_at..end_at),
                query_value != " " do
        {:ok, flop} =
          Flop.validate(%{
            filters: [
              %{field: :name, op: :=~, value: query_value}
            ]
          })

        ci_query_value = String.downcase(query_value)

        expected_pets =
          Enum.filter(pets, &(String.downcase(&1.name) =~ ci_query_value))

        query = Flop.query(Pet, flop)
        result = Repo.all(query)
        assert Enum.all?(result, &(String.downcase(&1.name) =~ ci_query_value))

        assert length(result) == length(expected_pets)
      end
    end

    defp filter_pets(pets, field, op, value),
      do: Enum.filter(pets, pet_matches?(op, field, value))

    defp pet_matches?(:<=, k, v), do: &(Map.get(&1, k) <= v)
    defp pet_matches?(:<, k, v), do: &(Map.get(&1, k) < v)
    defp pet_matches?(:>, k, v), do: &(Map.get(&1, k) > v)
    defp pet_matches?(:>=, k, v), do: &(Map.get(&1, k) >= v)
    defp pet_matches?(:in, k, v), do: &(Map.get(&1, k) in v)

    property "applies lte, lt, gt and gte filters" do
      pets = insert_list(50, :pet_downcase)

      check all field <- member_of([:age, :name]),
                op <- one_of([:<=, :<, :>, :>=]),
                query_value <- compare_value_by_field(field) do
        {:ok, flop} =
          Flop.validate(%{
            filters: [
              %{field: field, op: op, value: query_value}
            ]
          })

        expected_pets =
          pets
          |> filter_pets(field, op, query_value)
          |> Enum.sort_by(&{&1.name, &1.species, &1.age})

        query = Flop.query(Pet, flop)

        result =
          query
          |> Repo.all()
          |> Enum.sort_by(&{&1.name, &1.species, &1.age})

        assert result == expected_pets
      end
    end

    property "applies 'in' filter" do
      pets = insert_list(50, :pet)

      check all field <- member_of([:age, :name]),
                values = Enum.map(pets, &Map.get(&1, field)),
                query_value <-
                  list_of(one_of([member_of(values), value_by_field(field)]),
                    max_length: 5
                  ) do
        {:ok, flop} =
          Flop.validate(%{
            filters: [
              %{field: field, op: :in, value: query_value}
            ]
          })

        query = Flop.query(Pet, flop)

        result =
          query |> Repo.all() |> Enum.sort_by(&{&1.name, &1.species, &1.age})

        expected_pets =
          pets
          |> filter_pets(field, :in, query_value)
          |> Enum.sort_by(&{&1.name, &1.species, &1.age})

        assert result == expected_pets
      end
    end

    property "adds where clauses for filters" do
      check all filter <- filter() do
        flop = %Flop{filters: [filter]}
        %Filter{op: op} = filter
        query = Flop.query(Pet, flop)

        if op == :=~ do
          assert [%BooleanExpr{expr: {:ilike, _, _}, op: :and}] = query.wheres
        else
          assert [%BooleanExpr{expr: {^op, _, _}, op: :and}] = query.wheres
        end

        assert is_list(Repo.all(query))
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
               %BooleanExpr{expr: {:>=, _, _}, op: :and},
               %BooleanExpr{expr: {:==, _, _}, op: :and}
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

  describe "all/3" do
    test "returns all matching entries" do
      matching_pets = insert_list(6, :pet, age: 5)
      _non_matching_pets = insert_list(4, :pet, age: 6)

      [_, _, %{name: name_1}, %{name: name_2}, _, _] =
        Enum.sort_by(matching_pets, & &1.name)

      flop = %Flop{
        limit: 2,
        offset: 2,
        order_by: [:name],
        filters: [%Filter{field: :age, op: :<=, value: 5}]
      }

      assert Enum.map(Flop.all(Pet, flop), & &1.name) == [name_1, name_2]
    end
  end

  describe "count/3" do
    test "returns count of matching entries" do
      _matching_pets = insert_list(6, :pet, age: 5)
      _non_matching_pets = insert_list(4, :pet, age: 6)

      flop = %Flop{
        limit: 2,
        offset: 2,
        order_by: [:age],
        filters: [%Filter{field: :age, op: :<=, value: 5}]
      }

      assert Flop.count(Pet, flop) == 6
    end
  end

  describe "meta/3" do
    test "returns the meta information for a query with limit/offset" do
      _matching_pets = insert_list(7, :pet, age: 5)
      _non_matching_pets = insert_list(4, :pet, age: 6)

      flop = %Flop{
        limit: 2,
        offset: 4,
        filters: [%Filter{field: :age, op: :<=, value: 5}]
      }

      assert Flop.meta(Pet, flop) == %Meta{
               current_offset: 4,
               current_page: 3,
               flop: flop,
               has_next_page?: true,
               has_previous_page?: true,
               next_offset: 6,
               next_page: 4,
               page_size: 2,
               previous_offset: 2,
               previous_page: 2,
               total_count: 7,
               total_pages: 4
             }
    end

    test "returns the meta information for a query with page/page_size" do
      _matching_pets = insert_list(7, :pet, age: 5)
      _non_matching_pets = insert_list(4, :pet, age: 6)

      flop = %Flop{
        page_size: 2,
        page: 3,
        filters: [%Filter{field: :age, op: :<=, value: 5}]
      }

      assert Flop.meta(Pet, flop) == %Meta{
               current_offset: 4,
               current_page: 3,
               flop: flop,
               has_next_page?: true,
               has_previous_page?: true,
               next_offset: 6,
               next_page: 4,
               page_size: 2,
               previous_offset: 2,
               previous_page: 2,
               total_count: 7,
               total_pages: 4
             }
    end

    test "returns the meta information for a query without limit" do
      _matching_pets = insert_list(7, :pet, age: 5)
      _non_matching_pets = insert_list(2, :pet, age: 6)

      flop = %Flop{filters: [%Filter{field: :age, op: :<=, value: 5}]}

      assert Flop.meta(Pet, flop) == %Meta{
               current_offset: 0,
               current_page: 1,
               flop: flop,
               has_next_page?: false,
               has_previous_page?: false,
               next_offset: nil,
               next_page: nil,
               page_size: nil,
               previous_offset: nil,
               previous_page: nil,
               total_count: 7,
               total_pages: 1
             }
    end

    test "rounds current page if offset is between pages" do
      insert_list(6, :pet)

      assert %Meta{
               current_offset: 1,
               current_page: 2,
               has_next_page?: true,
               has_previous_page?: true,
               next_offset: 3,
               next_page: 3,
               previous_offset: 0,
               previous_page: 1
             } = Flop.meta(Pet, %Flop{limit: 2, offset: 1})

      assert %Meta{
               current_offset: 3,
               current_page: 3,
               has_next_page?: true,
               has_previous_page?: true,
               next_offset: 5,
               next_page: 3,
               previous_offset: 1,
               previous_page: 2
             } = Flop.meta(Pet, %Flop{limit: 2, offset: 3})

      # current page shouldn't be greater than total page numbers
      assert %Meta{
               current_offset: 5,
               current_page: 3,
               has_next_page?: false,
               has_previous_page?: true,
               next_offset: nil,
               next_page: nil,
               previous_offset: 3,
               previous_page: 2
             } = Flop.meta(Pet, %Flop{limit: 2, offset: 5})
    end

    test "sets has_previous_page? and has_next_page?" do
      _matching_pets = insert_list(5, :pet)

      assert %Meta{has_next_page?: true, has_previous_page?: false} =
               Flop.meta(Pet, %Flop{limit: 2, offset: 0})

      assert %Meta{has_next_page?: true, has_previous_page?: true} =
               Flop.meta(Pet, %Flop{limit: 2, offset: 1})

      assert %Meta{has_next_page?: true, has_previous_page?: true} =
               Flop.meta(Pet, %Flop{limit: 2, offset: 2})

      assert %Meta{has_next_page?: false, has_previous_page?: true} =
               Flop.meta(Pet, %Flop{limit: 2, offset: 3})

      assert %Meta{has_next_page?: false, has_previous_page?: true} =
               Flop.meta(Pet, %Flop{limit: 2, offset: 4})

      assert %Meta{has_next_page?: true, has_previous_page?: false} =
               Flop.meta(Pet, %Flop{page_size: 3, page: 1})

      assert %Meta{has_next_page?: false, has_previous_page?: true} =
               Flop.meta(Pet, %Flop{page_size: 3, page: 2})
    end
  end

  describe "run/3" do
    test "returns data and meta data" do
      insert_list(3, :pet)
      flop = %Flop{page_size: 2, page: 2}
      assert {[%Pet{}], %Meta{}} = Flop.run(Pet, flop)
    end
  end

  describe "validate_and_run/3" do
    test "returns error if flop is invalid" do
      flop = %{page_size: -1}
      assert {:error, %Changeset{}} = Flop.validate_and_run(Pet, flop)
    end

    test "returns data and meta data" do
      insert_list(3, :pet)
      flop = %{page_size: 2, page: 2}
      assert {:ok, {[%Pet{}], %Meta{}}} = Flop.validate_and_run(Pet, flop)
    end
  end

  describe "validate_and_run!/3" do
    test "raises if flop is invalid" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        Flop.validate_and_run!(Pet, %{limit: -1})
      end
    end

    test "returns data and meta data" do
      insert_list(3, :pet)
      flop = %{page_size: 2, page: 2}
      assert {[%Pet{}], %Meta{}} = Flop.validate_and_run!(Pet, flop)
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

    test "applies default limit" do
      # struct without configured default limit

      assert {:ok, %Flop{limit: nil, page_size: nil}} =
               Flop.validate(%{}, for: Pet)

      assert {:ok, %Flop{limit: nil, page_size: nil}} =
               Flop.validate(%{offset: 10}, for: Pet)

      assert {:ok, %Flop{limit: 12}} =
               Flop.validate(%{offset: 10, limit: 12}, for: Pet)

      assert {:ok, %Flop{limit: nil, page_size: 5}} =
               Flop.validate(%{page: 10, page_size: 5}, for: Pet)

      # struct with configured default limit

      assert {:ok, %Flop{limit: 50, page_size: nil}} =
               Flop.validate(%{}, for: Fruit)

      assert {:ok, %Flop{limit: 50, page_size: nil}} =
               Flop.validate(%{offset: 10}, for: Fruit)

      assert {:ok, %Flop{limit: 12, page_size: nil}} =
               Flop.validate(%{offset: 10, limit: 12}, for: Fruit)

      assert {:ok, %Flop{limit: nil, page_size: 12}} =
               Flop.validate(%{page: 10, page_size: 12}, for: Pet)
    end

    test "applies default order" do
      # struct without configured default order

      assert {:ok, %Flop{order_by: nil, order_directions: nil}} =
               Flop.validate(%{}, for: Pet)

      # struct with configured default order

      assert {:ok, %Flop{order_by: [:name], order_directions: [:asc]}} =
               Flop.validate(%{}, for: Fruit)
    end

    test "validates offset" do
      params = %{offset: -1}
      assert {:error, %Changeset{} = changeset} = Flop.validate(params)

      assert errors_on(changeset)[:offset] == [
               "must be greater than or equal to 0"
             ]
    end

    test "sets offset to 0 if limit is set without offset" do
      params = %{limit: 5}
      assert {:ok, %Flop{offset: 0, limit: 5}} = Flop.validate(params)
    end

    test "sets offset to 0 if default limit is set" do
      assert {:ok, %Flop{limit: 50, offset: 0}} = Flop.validate(%{}, for: Fruit)
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

    test "sets page to 1 if page size is set without page" do
      params = %{page_size: 5}
      assert {:ok, %Flop{page: 1, page_size: 5}} = Flop.validate(params)
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

      params = %{filters: [%{field: :age, op: :>, value: 5}]}
      assert {:error, changeset} = Flop.validate(params, for: Pet)
      assert [%{field: ["is invalid"]}] = errors_on(changeset)[:filters]

      params = %{filters: [%{field: "age", op: ">", value: "5"}]}
      assert {:error, changeset} = Flop.validate(params, for: Pet)
      assert [%{field: ["is invalid"]}] = errors_on(changeset)[:filters]

      # field does not exist

      params = %{filters: [%{field: :halloween_costume, value: "Pirate"}]}
      assert {:error, changeset} = Flop.validate(params, for: Pet)
      assert [%{field: ["is invalid"]}] = errors_on(changeset)[:filters]

      params = %{filters: [%{field: "honorific", value: "Esquire"}]}
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
    end
  end

  describe "validate!/1" do
    test "returns a flop struct" do
      assert Flop.validate!(%Flop{}) == %Flop{}
      assert Flop.validate!(%{}) == %Flop{}
    end

    test "raises if params are invalid" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        Flop.validate!(%{limit: -1})
      end
    end
  end
end
