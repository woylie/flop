defmodule FlopTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  doctest Flop, import: true

  import Ecto.Query
  import Flop.Factory
  import Flop.Generators
  import Flop.TestUtil

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset
  alias Ecto.Query.QueryExpr
  alias Flop.Filter
  alias Flop.Meta
  alias Flop.Pet
  alias Flop.Repo

  @pet_count_range 1..200

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "ordering" do
    test "adds order_by to query if set" do
      pets = insert_list(20, :pet)

      expected =
        Enum.sort(
          pets,
          &(&1.species < &2.species ||
              (&1.species == &2.species && &1.name >= &2.name))
        )

      assert Flop.all(Pet, %Flop{
               order_by: [:species, :name],
               order_directions: [:asc, :desc]
             }) == expected
    end

    test "uses :asc as default direction if no directions are passed" do
      pets = insert_list(20, :pet)
      expected = Enum.sort_by(pets, &{&1.species, &1.name, &1.age})

      assert Flop.all(Pet, %Flop{
               order_by: [:species, :name, :age],
               order_directions: nil
             }) == expected
    end

    test "uses :asc as default direction if not enough directions are passed" do
      pets = insert_list(20, :pet)

      expected =
        Enum.sort(
          pets,
          &(&1.species > &2.species ||
              (&1.species == &2.species &&
                 (&1.name < &2.name ||
                    (&1.name == &2.name && &1.age <= &2.age))))
        )

      assert Flop.all(Pet, %Flop{
               order_by: [:species, :name, :age],
               order_directions: [:desc]
             }) == expected
    end
  end

  describe "filtering" do
    property "applies equality filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                # all except compound fields
                field <-
                  member_of([:age, :name, :owner_age, :owner_name, :species]),
                pet <- member_of(pets),
                query_value <- pet |> Pet.get_field(field) |> constant(),
                query_value != "" do
        expected = filter_pets(pets, field, :==, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :==, value: query_value}]
               }) == expected
      end
    end

    property "applies equality filter to compound fields" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                # only compound fields
                field <- member_of([:full_name, :pet_and_owner_name]),
                pet <- member_of(pets),
                query_value <-
                  pet
                  |> Pet.concatenated_value_for_compound_field(field)
                  |> constant(),
                query_value != "" do
        expected = filter_pets(pets, field, :==, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :==, value: query_value}]
               }) == expected
      end
    end

    property "applies inequality filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                # all except compound fields
                field <-
                  member_of([:age, :name, :owner_age, :owner_name, :species]),
                pet <- member_of(pets),
                query_value = Pet.get_field(pet, field),
                query_value != "" do
        expected = filter_pets(pets, field, :!=, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :!=, value: query_value}]
               }) == expected
      end
    end

    property "applies inequality filter to compound fields" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                # only compound fields
                field <- member_of([:full_name, :pet_and_owner_name]),
                pet <- member_of(pets),
                query_value =
                  Pet.concatenated_value_for_compound_field(pet, field),
                query_value != "" do
        expected = filter_pets(pets, field, :!=, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :!=, value: query_value}]
               }) == expected
      end
    end

    test "applies empty and not_empty filter" do
      check all pet_count <- integer(@pet_count_range),
                pets =
                  insert_list_and_sort(pet_count, :pet,
                    species: fn -> Enum.random([nil, "fox"]) end,
                    owner: fn ->
                      build(:owner, name: fn -> Enum.random([nil, "Carl"]) end)
                    end
                  ),
                field <- member_of([:species, :owner_name]),
                op <- member_of([:empty, :not_empty]) do
        expected = filter_pets(pets, field, op)

        assert query_pets_with_owners(%{filters: [%{field: field, op: op}]}) ==
                 expected
      end
    end

    property "applies like filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                query_value <- substring(value) do
        expected = filter_pets(pets, field, :like, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :like, value: query_value}]
               }) == expected
      end
    end

    property "applies ilike filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                op <- member_of([:=~, :ilike]),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                query_value <- substring(value) do
        expected = filter_pets(pets, field, :ilike, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: op, value: query_value}]
               }) == expected
      end
    end

    property "applies like_and filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                search_text <- search_text(value) do
        expected = filter_pets(pets, field, :like_and, search_text)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :like_and, value: search_text}]
               }) == expected
      end
    end

    property "applies like_or filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                search_text <- search_text(value) do
        expected = filter_pets(pets, field, :like_or, search_text)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :like_or, value: search_text}]
               }) == expected
      end
    end

    property "applies ilike_and filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                search_text <- search_text(value) do
        expected = filter_pets(pets, field, :ilike_and, search_text)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :ilike_and, value: search_text}]
               }) == expected
      end
    end

    property "applies ilike_or filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                search_text <- search_text(value) do
        expected = filter_pets(pets, field, :ilike_or, search_text)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :ilike_or, value: search_text}]
               }) == expected
      end
    end

    property "applies lte, lt, gt and gte filters" do
      check all pet_count <- integer(@pet_count_range),
                pets =
                  pet_count
                  |> insert_list(:pet_downcase, owner: fn -> build(:owner) end)
                  |> Enum.sort_by(& &1.id),
                field <- member_of([:age, :name, :owner_age]),
                op <- one_of([:<=, :<, :>, :>=]),
                query_value <- compare_value_by_field(field) do
        expected = filter_pets(pets, field, op, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: op, value: query_value}]
               }) == expected
      end
    end

    property "applies 'in' filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- member_of([:age, :name, :owner_age]),
                values = Enum.map(pets, &Map.get(&1, field)),
                query_value <-
                  list_of(one_of([member_of(values), value_by_field(field)]),
                    max_length: 5
                  ) do
        expected = filter_pets(pets, field, :in, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :in, value: query_value}]
               }) == expected
      end
    end

    test "silently ignores nil values for field and value" do
      flop = %Flop{filters: [%Filter{op: :>=, value: 4}]}
      assert Flop.query(Pet, flop) == Pet

      flop = %Flop{filters: [%Filter{field: :name, op: :>=}]}
      assert Flop.query(Pet, flop) == Pet
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

  describe "offset-based pagination" do
    test "applies limit to query" do
      insert_list(6, :pet)
      assert Pet |> Flop.query(%Flop{limit: 4}) |> Repo.all() |> length() == 4
    end

    test "applies offset to query if set" do
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

    test "applies limit and offset to query if page and page size are set" do
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
  end

  describe "cursor pagination" do
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
