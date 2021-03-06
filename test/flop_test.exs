defmodule FlopTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  doctest Flop, import: true

  import Ecto.Query
  import Flop.Factory
  import Flop.Generators

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset
  alias Ecto.Query.BooleanExpr
  alias Ecto.Query.QueryExpr
  alias Flop.Filter
  alias Flop.Meta
  alias Flop.Pet
  alias Flop.Repo

  @base_query from p in Pet, where: p.age > 8, select: p.name
  @whitespace ["\u0020", "\u2000", "\u3000"]

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
                query_value != " ",
                op <- member_of([:=~, :ilike]) do
        {:ok, flop} =
          Flop.validate(%{
            filters: [
              %{field: :name, op: op, value: query_value}
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

    property "applies ilike_and filter" do
      pets = insert_list(50, :pet)
      values = Enum.map(pets, & &1.name)

      check all some_value <- member_of(values),
                str_length = String.length(some_value),
                start_at_a <- integer(0..(str_length - 2)),
                end_at_a <- integer((start_at_a + 1)..(str_length - 1)),
                start_at_b <- integer(0..(str_length - 2)),
                end_at_b <- integer((start_at_b + 1)..(str_length - 1)),
                query_value_a <-
                  some_value
                  |> String.slice(start_at_a..end_at_a)
                  |> String.trim()
                  |> constant(),
                query_value_a != "",
                query_value_b <-
                  some_value
                  |> String.slice(start_at_b..end_at_b)
                  |> String.trim()
                  |> constant(),
                query_value_b != "",
                whitespace_character <- member_of(@whitespace) do
        query_values =
          Enum.concat([
            String.split(query_value_a),
            String.split(query_value_b)
          ])

        filter_value = Enum.join(query_values, whitespace_character)

        {:ok, flop} =
          Flop.validate(%{
            filters: [
              %{field: :name, op: :ilike_or, value: filter_value}
            ]
          })

        expected_pets =
          pets
          |> Enum.filter(fn pet ->
            Enum.any?(query_values, fn value ->
              String.downcase(pet.name) =~ String.downcase(value)
            end)
          end)
          |> Enum.sort_by(& &1.id)

        query = Flop.query(Pet, flop)
        result = Repo.all(query)
        assert Enum.sort_by(result, & &1.id) == expected_pets
      end
    end

    test "applies ilike_or filter" do
      pets = insert_list(50, :pet)
      values = Enum.map(pets, & &1.name)

      check all some_value <- member_of(values),
                str_length = String.length(some_value),
                start_at_a <- integer(0..(str_length - 2)),
                end_at_a <- integer((start_at_a + 1)..(str_length - 1)),
                start_at_b <- integer(0..(str_length - 2)),
                end_at_b <- integer((start_at_b + 1)..(str_length - 1)),
                query_value_a <-
                  some_value
                  |> String.slice(start_at_a..end_at_a)
                  |> String.trim()
                  |> constant(),
                query_value_a != "",
                query_value_b <-
                  some_value
                  |> String.slice(start_at_b..end_at_b)
                  |> String.trim()
                  |> constant(),
                query_value_b != "",
                whitespace_character <- member_of(@whitespace) do
        query_values =
          Enum.concat([
            String.split(query_value_a),
            String.split(query_value_b)
          ])

        filter_value = Enum.join(query_values, whitespace_character)

        {:ok, flop} =
          Flop.validate(%{
            filters: [
              %{field: :name, op: :ilike_and, value: filter_value}
            ]
          })

        expected_pets =
          pets
          |> Enum.filter(fn pet ->
            Enum.all?(query_values, fn value ->
              String.downcase(pet.name) =~ String.downcase(value)
            end)
          end)
          |> Enum.sort_by(& &1.id)

        query = Flop.query(Pet, flop)
        result = Repo.all(query)
        assert Enum.sort_by(result, & &1.id) == expected_pets
      end
    end

    property "applies like filter" do
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
            filters: [%{field: :name, op: :like, value: query_value}]
          })

        expected_pets = Enum.filter(pets, &(&1.name =~ query_value))

        query = Flop.query(Pet, flop)
        result = Repo.all(query)
        assert Enum.all?(result, &(&1.name =~ query_value))
        assert length(result) == length(expected_pets)
      end
    end

    property "applies like_and filter" do
      pets = insert_list(50, :pet)
      values = Enum.map(pets, & &1.name)

      check all some_value <- member_of(values),
                str_length = String.length(some_value),
                start_at_a <- integer(0..(str_length - 2)),
                end_at_a <- integer((start_at_a + 1)..(str_length - 1)),
                start_at_b <- integer(0..(str_length - 2)),
                end_at_b <- integer((start_at_b + 1)..(str_length - 1)),
                query_value_a <-
                  some_value
                  |> String.slice(start_at_a..end_at_a)
                  |> String.trim()
                  |> constant(),
                query_value_a != "",
                query_value_b <-
                  some_value
                  |> String.slice(start_at_b..end_at_b)
                  |> String.trim()
                  |> constant(),
                query_value_b != "",
                whitespace_character <- member_of(@whitespace) do
        query_values =
          Enum.concat([
            String.split(query_value_a),
            String.split(query_value_b)
          ])

        filter_value = Enum.join(query_values, whitespace_character)

        {:ok, flop} =
          Flop.validate(%{
            filters: [
              %{field: :name, op: :like_and, value: filter_value}
            ]
          })

        expected_pets =
          pets
          |> Enum.filter(fn pet ->
            Enum.all?(query_values, fn value ->
              pet.name =~ value
            end)
          end)
          |> Enum.sort_by(& &1.id)

        query = Flop.query(Pet, flop)
        result = Repo.all(query)
        assert Enum.sort_by(result, & &1.id) == expected_pets
      end
    end

    property "applies like_or filter" do
      pets = insert_list(50, :pet)
      values = Enum.map(pets, & &1.name)

      check all some_value <- member_of(values),
                str_length = String.length(some_value),
                start_at_a <- integer(0..(str_length - 2)),
                end_at_a <- integer((start_at_a + 2)..(str_length - 1)),
                start_at_b <- integer(0..(str_length - 2)),
                end_at_b <- integer((start_at_b + 2)..(str_length - 1)),
                query_value_a <-
                  some_value
                  |> String.slice(start_at_a..end_at_a)
                  |> String.trim()
                  |> constant(),
                query_value_a != "",
                query_value_b <-
                  some_value
                  |> String.slice(start_at_b..end_at_b)
                  |> String.trim()
                  |> constant(),
                query_value_b != "",
                whitespace_character <- member_of(@whitespace) do
        query_values =
          Enum.concat([
            String.split(query_value_a),
            String.split(query_value_b)
          ])

        filter_value = Enum.join(query_values, whitespace_character)

        {:ok, flop} =
          Flop.validate(%{
            filters: [
              %{field: :name, op: :like_or, value: filter_value}
            ]
          })

        expected_pets =
          pets
          |> Enum.filter(fn pet ->
            Enum.any?(query_values, fn value ->
              pet.name =~ value
            end)
          end)
          |> Enum.sort_by(& &1.id)

        query = Flop.query(Pet, flop)
        result = Repo.all(query)
        assert Enum.sort_by(result, & &1.id) == expected_pets
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

        case op do
          :=~ ->
            assert [%BooleanExpr{expr: {:ilike, _, _}, op: :and}] = query.wheres

          :ilike_and ->
            assert [
                     %BooleanExpr{
                       expr: {:and, _, [true, {:ilike, _, _}]},
                       file: _,
                       line: _,
                       op: :and,
                       params: _,
                       subqueries: []
                     }
                   ] = query.wheres

          :ilike_or ->
            assert [
                     %BooleanExpr{
                       expr: {:or, _, [false, {:ilike, _, _}]},
                       file: _,
                       line: _,
                       op: :and,
                       params: _,
                       subqueries: []
                     }
                   ] = query.wheres

          :like_and ->
            assert [
                     %BooleanExpr{
                       expr: {:and, _, [true, {:like, _, _}]},
                       file: _,
                       line: _,
                       op: :and,
                       params: _,
                       subqueries: []
                     }
                   ] = query.wheres

          :like_or ->
            assert [
                     %BooleanExpr{
                       expr: {:or, _, [false, {:like, _, _}]},
                       file: _,
                       line: _,
                       op: :and,
                       params: _,
                       subqueries: []
                     }
                   ] = query.wheres

          _ ->
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

    test "can apply a query prefix" do
      insert(:pet, %{}, prefix: "other_schema")

      assert Flop.all(Pet, %Flop{}) == []
      refute Flop.all(Pet, %Flop{}, prefix: "other_schema") == []
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

    test "can apply a query prefix" do
      insert(:pet, %{}, prefix: "other_schema")

      assert Flop.count(Pet, %Flop{}) == 0
      assert Flop.count(Pet, %Flop{}, prefix: "other_schema") == 1
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
               end_cursor: nil,
               flop: flop,
               has_next_page?: true,
               has_previous_page?: true,
               next_offset: 6,
               next_page: 4,
               page_size: 2,
               previous_offset: 2,
               previous_page: 2,
               start_cursor: nil,
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
               end_cursor: nil,
               flop: flop,
               has_next_page?: true,
               has_previous_page?: true,
               next_offset: 6,
               next_page: 4,
               page_size: 2,
               previous_offset: 2,
               previous_page: 2,
               start_cursor: nil,
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
               end_cursor: nil,
               flop: flop,
               has_next_page?: false,
               has_previous_page?: false,
               next_offset: nil,
               next_page: nil,
               page_size: nil,
               previous_offset: nil,
               previous_page: nil,
               start_cursor: nil,
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

    test "can apply a query prefix" do
      insert(:pet, %{}, prefix: "other_schema")

      assert Flop.meta(Pet, %Flop{}).total_count == 0
      assert Flop.meta(Pet, %Flop{}, prefix: "other_schema").total_count == 1
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

  describe "cursor paging" do
    property "querying cursor by cursor forward includes all items in order" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}) do
        # make sure we have a clean db after each generation
        :ok = Sandbox.checkin(Repo)
        :ok = Sandbox.checkout(Repo)

        # insert pets into DB, retrieve them so we have the IDs
        pet_count = length(pets)
        assert {^pet_count, _} = Repo.insert_all(Pet, pets)
        order_by = Enum.zip(directions, cursor_fields)
        pets = Pet |> order_by(^order_by) |> Repo.all()
        assert length(pets) == pet_count

        # retrieve first cursor, ensure returned pet matches first one in list
        [first_pet | remaining_pets] = pets

        {:ok, {[returned_pet], %Meta{end_cursor: cursor}}} =
          Flop.validate_and_run(Pet, %Flop{
            first: 1,
            order_by: cursor_fields,
            order_directions: directions
          })

        assert returned_pet == first_pet

        # iterate over remaining pets, query DB cursor by cursor
        {reversed_returned_pets, last_cursor} =
          Enum.reduce(
            remaining_pets,
            {[first_pet], cursor},
            fn _current_pet, {pet_list, cursor} ->
              assert {:ok, {[returned_pet], %Meta{end_cursor: new_cursor}}} =
                       Flop.validate_and_run(Pet, %Flop{
                         first: 1,
                         after: cursor,
                         order_by: cursor_fields,
                         order_directions: directions
                       })

              {[returned_pet | pet_list], new_cursor}
            end
          )

        # ensure the accumulated list matches the manually sorted list
        returned_pets = Enum.reverse(reversed_returned_pets)
        assert returned_pets == pets

        # ensure nothing comes after the last cursor
        assert {:ok, {[], %Meta{end_cursor: nil}}} =
                 Flop.validate_and_run(Pet, %Flop{
                   first: 1,
                   after: last_cursor,
                   order_by: cursor_fields,
                   order_directions: directions
                 })
      end
    end

    property "querying all items returns same list forward and backward" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}) do
        # make sure we have a clean db after each generation
        :ok = Sandbox.checkin(Repo)
        :ok = Sandbox.checkout(Repo)

        pet_count = length(pets)
        assert {^pet_count, _} = Repo.insert_all(Pet, pets)

        {:ok, {with_first, _meta}} =
          Flop.validate_and_run(Pet, %Flop{
            first: pet_count,
            order_by: cursor_fields,
            order_directions: directions
          })

        {:ok, {with_last, _meta}} =
          Flop.validate_and_run(Pet, %Flop{
            last: pet_count,
            order_by: cursor_fields,
            order_directions: directions
          })

        assert with_first == with_last
      end
    end

    property "querying cursor by cursor backward includes all items in order" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}) do
        # make sure we have a clean db after each generation
        :ok = Sandbox.checkin(Repo)
        :ok = Sandbox.checkout(Repo)

        # insert pets into DB, retrieve them so we have the IDs
        pet_count = length(pets)
        assert {^pet_count, _} = Repo.insert_all(Pet, pets)
        order_by = Enum.zip(directions, cursor_fields)
        pets = Pet |> order_by(^order_by) |> Repo.all()
        assert length(pets) == pet_count
        pets = Enum.reverse(pets)

        # retrieve last cursor, ensure returned pet matches last one in list
        [last_pet | remaining_pets] = pets

        {:ok, {[returned_pet], %Meta{end_cursor: cursor}}} =
          Flop.validate_and_run(Pet, %Flop{
            last: 1,
            order_by: cursor_fields,
            order_directions: directions
          })

        assert returned_pet == last_pet

        # iterate over remaining pets, query DB cursor by cursor
        {reversed_returned_pets, last_cursor} =
          Enum.reduce(
            remaining_pets,
            {[last_pet], cursor},
            fn _current_pet, {pet_list, cursor} ->
              assert {:ok, {[returned_pet], %Meta{end_cursor: new_cursor}}} =
                       Flop.validate_and_run(Pet, %Flop{
                         last: 1,
                         before: cursor,
                         order_by: cursor_fields,
                         order_directions: directions
                       })

              {[returned_pet | pet_list], new_cursor}
            end
          )

        # ensure the accumulated list matches the manually sorted list
        returned_pets = Enum.reverse(reversed_returned_pets)
        assert returned_pets == pets

        # ensure nothing comes after the last cursor
        assert {:ok, {[], %Meta{end_cursor: nil}}} =
                 Flop.validate_and_run(Pet, %Flop{
                   last: 1,
                   before: last_cursor,
                   order_by: cursor_fields,
                   order_directions: directions
                 })
      end
    end

    property "has_previous_page? is false without after and last" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                first <- integer(1..(length(pets) + 1)) do
        # make sure we have a clean db after each generation
        :ok = Sandbox.checkin(Repo)
        :ok = Sandbox.checkout(Repo)

        pet_count = length(pets)
        assert {^pet_count, _} = Repo.insert_all(Pet, pets)

        assert {_, %Meta{has_previous_page?: false}} =
                 Flop.validate_and_run!(Pet, %Flop{
                   first: first,
                   order_by: cursor_fields,
                   order_directions: directions
                 })
      end
    end

    property "has_previous_page? is false with after" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                first <- integer(1..(length(pets) + 1)),
                cursor_pet <- member_of(pets) do
        # make sure we have a clean db after each generation
        :ok = Sandbox.checkin(Repo)
        :ok = Sandbox.checkout(Repo)

        pet_count = length(pets)
        assert {^pet_count, _} = Repo.insert_all(Pet, pets)

        cursor =
          cursor_fields
          |> Enum.into(%{}, fn field -> {field, Map.get(cursor_pet, field)} end)
          |> Flop.Cursor.encode()

        assert {_, %Meta{has_previous_page?: false}} =
                 Flop.validate_and_run!(Pet, %Flop{
                   first: first,
                   after: cursor,
                   order_by: cursor_fields,
                   order_directions: directions
                 })
      end
    end

    property "has_previous_page? is true with last set and items left" do
      check all pets <- uniq_list_of_pets(length: 3..50),
                pet_count = length(pets),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                last <- integer(1..(pet_count - 2)),
                cursor_index <- integer((last + 1)..(pet_count - 1)) do
        # make sure we have a clean db after each generation
        :ok = Sandbox.checkin(Repo)
        :ok = Sandbox.checkout(Repo)

        # insert pets
        assert {^pet_count, _} = Repo.insert_all(Pet, pets)
        order_by = Enum.zip(directions, cursor_fields)

        # retrieve ordered pets
        pets = Pet |> order_by(^order_by) |> Repo.all()
        assert length(pets) == pet_count

        # retrieve cursor
        pet = Enum.at(pets, cursor_index)

        cursor =
          cursor_fields
          |> Enum.into(%{}, fn field -> {field, Map.get(pet, field)} end)
          |> Flop.Cursor.encode()

        assert {_, %Meta{has_previous_page?: true}} =
                 Flop.validate_and_run!(Pet, %Flop{
                   last: last,
                   before: cursor,
                   order_by: cursor_fields,
                   order_directions: directions
                 })
      end
    end

    property "has_previous_page? is false with last set and no items left" do
      check all pets <- uniq_list_of_pets(length: 3..50),
                pet_count = length(pets),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                # include test with limits greater than item count
                last <- integer(1..(pet_count + 20)),
                cursor_index <- integer(0..min(pet_count - 1, last)) do
        # make sure we have a clean db after each generation
        :ok = Sandbox.checkin(Repo)
        :ok = Sandbox.checkout(Repo)

        # insert pets
        assert {^pet_count, _} = Repo.insert_all(Pet, pets)
        order_by = Enum.zip(directions, cursor_fields)

        # retrieve ordered pets
        pets = Pet |> order_by(^order_by) |> Repo.all()
        assert length(pets) == pet_count

        # retrieve cursor
        pet = Enum.at(pets, cursor_index)

        cursor =
          cursor_fields
          |> Enum.into(%{}, fn field -> {field, Map.get(pet, field)} end)
          |> Flop.Cursor.encode()

        assert {_, %Meta{has_previous_page?: false}} =
                 Flop.validate_and_run!(Pet, %Flop{
                   last: last,
                   before: cursor,
                   order_by: cursor_fields,
                   order_directions: directions
                 })
      end
    end

    property "has_next_page? is false without first and before" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                last <- integer(1..(length(pets) + 1)) do
        # make sure we have a clean db after each generation
        :ok = Sandbox.checkin(Repo)
        :ok = Sandbox.checkout(Repo)

        pet_count = length(pets)
        assert {^pet_count, _} = Repo.insert_all(Pet, pets)

        assert {_, %Meta{has_next_page?: false}} =
                 Flop.validate_and_run!(Pet, %Flop{
                   last: last,
                   order_by: cursor_fields,
                   order_directions: directions
                 })
      end
    end

    property "has_next_page? is false with before" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                last <- integer(1..(length(pets) + 1)),
                cursor_pet <- member_of(pets) do
        # make sure we have a clean db after each generation
        :ok = Sandbox.checkin(Repo)
        :ok = Sandbox.checkout(Repo)

        pet_count = length(pets)
        assert {^pet_count, _} = Repo.insert_all(Pet, pets)

        cursor =
          cursor_fields
          |> Enum.into(%{}, fn field -> {field, Map.get(cursor_pet, field)} end)
          |> Flop.Cursor.encode()

        assert {_, %Meta{has_next_page?: false}} =
                 Flop.validate_and_run!(Pet, %Flop{
                   last: last,
                   before: cursor,
                   order_by: cursor_fields,
                   order_directions: directions
                 })
      end
    end

    property "has_next_page? is true with first set and items left" do
      check all pets <- uniq_list_of_pets(length: 3..50),
                pet_count = length(pets),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                first <- integer(1..(pet_count - 2)),
                cursor_index <- integer((first + 1)..(pet_count - 1)) do
        # make sure we have a clean db after each generation
        :ok = Sandbox.checkin(Repo)
        :ok = Sandbox.checkout(Repo)

        # insert pets
        assert {^pet_count, _} = Repo.insert_all(Pet, pets)
        order_by = Enum.zip(directions, cursor_fields)

        # retrieve ordered pets
        pets = Pet |> order_by(^order_by) |> Repo.all() |> Enum.reverse()
        assert length(pets) == pet_count

        # retrieve cursor
        pet = Enum.at(pets, cursor_index)

        cursor =
          cursor_fields
          |> Enum.into(%{}, fn field -> {field, Map.get(pet, field)} end)
          |> Flop.Cursor.encode()

        assert {_, %Meta{has_next_page?: true}} =
                 Flop.validate_and_run!(Pet, %Flop{
                   first: first,
                   after: cursor,
                   order_by: cursor_fields,
                   order_directions: directions
                 })
      end
    end

    property "has_next_page? is false with first set and no items left" do
      check all pets <- uniq_list_of_pets(length: 3..50),
                pet_count = length(pets),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                # include test with limits greater than item count
                first <- integer(1..(pet_count + 20)),
                cursor_index <- integer(0..min(pet_count - 1, first)) do
        # make sure we have a clean db after each generation
        :ok = Sandbox.checkin(Repo)
        :ok = Sandbox.checkout(Repo)

        # insert pets
        assert {^pet_count, _} = Repo.insert_all(Pet, pets)
        order_by = Enum.zip(directions, cursor_fields)

        # retrieve ordered pets
        pets = Pet |> order_by(^order_by) |> Repo.all() |> Enum.reverse()
        assert length(pets) == pet_count

        # retrieve cursor
        pet = Enum.at(pets, cursor_index)

        cursor =
          cursor_fields
          |> Enum.into(%{}, fn field -> {field, Map.get(pet, field)} end)
          |> Flop.Cursor.encode()

        assert {_, %Meta{has_previous_page?: false}} =
                 Flop.validate_and_run!(Pet, %Flop{
                   first: first,
                   after: cursor,
                   order_by: cursor_fields,
                   order_directions: directions
                 })
      end
    end

    test "get_cursor_value function can be overridden" do
      insert_list(4, :pet)
      query = select(Pet, [p], {p, %{other: :data}})

      get_cursor_value_func = fn {pet, _}, order_by ->
        Map.take(pet, order_by)
      end

      {:ok,
       {_r1,
        %Meta{
          end_cursor: end_cursor,
          has_next_page?: true
        }}} =
        Flop.validate_and_run(
          query,
          %Flop{first: 2, order_by: [:id]},
          get_cursor_value_func: get_cursor_value_func
        )

      {:ok,
       {_r2,
        %Meta{
          end_cursor: _end_cursor,
          has_next_page?: false
        }}} =
        Flop.validate_and_run(
          query,
          %Flop{first: 2, after: end_cursor, order_by: [:id]},
          get_cursor_value_func: get_cursor_value_func
        )
    end
  end

  describe "validate/1" do
    test "returns Flop struct" do
      assert Flop.validate(%Flop{}) == {:ok, %Flop{}}
      assert Flop.validate(%{}) == {:ok, %Flop{}}
    end

    test "returns error if parameters are invalid" do
      assert {:error, %Changeset{}} = Flop.validate(%{limit: -1})
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
