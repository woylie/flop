defmodule Flop.Adapters.Ecto.FlopTest do
  use Flop.Integration.Case,
    async: Application.compile_env(:flop, :async_integration_tests, true)

  use ExUnitProperties

  doctest Flop, import: true

  import ExUnit.CaptureLog
  import Ecto.Query
  import Flop.Factory
  import Flop.Generators
  import Flop.TestUtil

  alias __MODULE__.TestProvider
  alias Ecto.Query.QueryExpr
  alias Flop.Filter
  alias Flop.Meta
  alias Flop.Repo
  alias MyApp.Fruit
  alias MyApp.Owner
  alias MyApp.Pet

  @pet_count_range 1..200

  defmodule TestProvider do
    use Flop, repo: Flop.Repo, default_limit: 35
  end

  defmodule TestProviderNested do
    use Flop,
      adapter_opts: [repo: Flop.Repo],
      default_limit: 35
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

    test "orders by join fields" do
      pets = insert_list(20, :pet_with_owner)

      expected =
        Enum.sort_by(
          pets,
          &{&1.owner.name, &1.owner.age, &1.name, &1.age}
        )

      result =
        Pet
        |> join(:left, [p], o in assoc(p, :owner), as: :owner)
        |> preload(:owner)
        |> Flop.all(
          %Flop{order_by: [:owner_name, :owner_age, :name, :age]},
          for: Pet
        )

      assert result == expected
    end

    test "orders by custom fields" do
      pets = insert_list(5, :pet)
      expected = Enum.sort_by(pets, &Kernel.*(&1.age, 7), :asc)
      result = Flop.all(Pet, %Flop{order_by: [:dog_age]}, for: Pet)

      assert result == expected
    end

    test "orders by compound fields" do
      pets = insert_list(20, :pet)

      expected =
        Enum.sort_by(
          pets,
          &{&1.family_name, &1.given_name, &1.id}
        )

      result = Flop.all(Pet, %Flop{order_by: [:full_name, :id]}, for: Pet)
      assert result == expected
    end

    test "orders by compound fields with join fields" do
      pets = insert_list(20, :pet, owner: fn -> build(:owner) end)

      expected =
        pets |> Enum.map(&{&1.name, &1.owner.name, &1.id}) |> Enum.sort()

      q =
        Pet
        |> join(:left, [p], o in assoc(p, :owner), as: :owner)
        |> select([p, owner: o], {p.name, o.name, p.id})

      assert Flop.all(
               q,
               %Flop{order_by: [:pet_and_owner_name, :id]},
               for: Pet
             ) == expected

      assert Flop.all(
               q,
               %Flop{
                 order_by: [:pet_and_owner_name, :id],
                 order_directions: [:desc, :desc]
               },
               for: Pet
             ) == Enum.reverse(expected)
    end

    test "orders by alias fields" do
      owner_1 = insert(:owner, pets: build_list(2, :pet))
      owner_2 = insert(:owner, pets: build_list(1, :pet))
      owner_3 = insert(:owner, pets: build_list(4, :pet))
      owner_4 = insert(:owner, pets: build_list(3, :pet))

      expected = [
        {owner_2.id, 1},
        {owner_1.id, 2},
        {owner_4.id, 3},
        {owner_3.id, 4}
      ]

      q =
        Owner
        |> join(:left, [o], p in assoc(o, :pets), as: :pets)
        |> group_by([o], o.id)
        |> select(
          [o, pets: p],
          {o.id, p.id |> count() |> selected_as(:pet_count)}
        )

      assert Flop.all(q, %Flop{order_by: [:pet_count]}, for: Owner) == expected

      assert Flop.all(
               q,
               %Flop{order_by: [:pet_count], order_directions: [:desc]},
               for: Owner
             ) == Enum.reverse(expected)
    end

    test "warns if query passed to Flop already included ordering" do
      query = from p in Pet, order_by: :species

      assert capture_log(fn ->
               Flop.all(query, %Flop{order_by: [:species, :name]})
             end) =~
               "This may interfere with Flop's ordering and pagination features"

      Flop.all(Pet, %Flop{order_by: [:species, :name]})
    end

    test "does not warn if no order parameters are set" do
      query = from p in Pet, order_by: :species

      assert capture_log(fn ->
               Flop.all(query, %Flop{})
             end) == ""
    end

    test "does not warn if query has no order by" do
      query = Pet

      assert capture_log(fn ->
               Flop.all(query, %Flop{order_by: [:species, :name]})
             end) == ""
    end

    test "warns if query has order bys and default order is set" do
      query = from f in Fruit, order_by: :id
      opts = [for: Fruit]
      flop = Flop.validate!(%{}, opts)

      assert capture_log(fn ->
               Flop.all(query, flop, opts)
             end) =~
               "This may interfere with Flop's ordering and pagination features"
    end

    test "does not warn if query has order bys and default order is disabled" do
      query = from f in Fruit, order_by: :id
      opts = [for: Fruit, default_order: false]
      flop = Flop.validate!(%{}, opts)

      assert capture_log(fn ->
               Flop.all(query, flop, opts)
             end) == ""
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
        expected = filter_items(pets, field, :==, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :==, value: query_value}]
               }) == expected

        checkin_checkout()
      end
    end

    test "does not allow equality filter on compound fields" do
      assert_raise Flop.InvalidParamsError, fn ->
        query_pets_with_owners(%{
          filters: [%{field: :full_name, op: :==, value: "o"}]
        })
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
        expected = filter_items(pets, field, :!=, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :!=, value: query_value}]
               }) == expected

        checkin_checkout()
      end
    end

    test "does not allow inequality filter on compound fields" do
      assert_raise Flop.InvalidParamsError, fn ->
        query_pets_with_owners(%{
          filters: [%{field: :full_name, op: :!=, value: "o"}]
        })
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
        [opposite_op] = [:empty, :not_empty] -- [op]
        expected = filter_items(pets, field, op)
        opposite_expected = filter_items(pets, field, opposite_op)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: op, value: true}]
               }) == expected

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: op, value: false}]
               }) == opposite_expected

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: opposite_op, value: true}]
               }) == opposite_expected

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: opposite_op, value: false}]
               }) == expected

        checkin_checkout()
      end
    end

    # test "applies empty filter" do
    #   require Flop.Adapter.Ecto.Operators

    #   field = :species

    #   d1 = dynamic([r], is_nil(field(r, ^field)) == ^true); d2 = dynamic([r], Flop.Adapter.Ecto.Operators.empty(:other) == ^true)

    #   assert where(Pet, ^d1) == where(Pet, ^d2)
    # end

    test "applies empty and not_empty filter with string values" do
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
        [opposite_op] = [:empty, :not_empty] -- [op]
        expected = filter_items(pets, field, op)
        opposite_expected = filter_items(pets, field, opposite_op)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: op, value: "true"}]
               }) == expected

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: op, value: "false"}]
               }) == opposite_expected

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: opposite_op, value: "true"}]
               }) == opposite_expected

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: opposite_op, value: "false"}]
               }) == expected

        checkin_checkout()
      end
    end

    test "applies empty and not_empty filter to array fields" do
      check all pet_count <- integer(@pet_count_range),
                pets =
                  insert_list_and_sort(pet_count, :pet_with_owner,
                    tags: fn -> Enum.random([nil, [], ["catdog"]]) end,
                    owner: fn ->
                      build(:owner,
                        tags: fn -> Enum.random([nil, [], ["catlover"]]) end
                      )
                    end
                  ),
                field <- member_of([:tags, :owner_tags]),
                op <- member_of([:empty, :not_empty]) do
        [opposite_op] = [:empty, :not_empty] -- [op]
        expected = filter_items(pets, field, op, true)
        opposite_expected = filter_items(pets, field, opposite_op, true)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: op, value: true}]
               }) == expected

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: op, value: false}]
               }) == opposite_expected

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: opposite_op, value: true}]
               }) == opposite_expected

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: opposite_op, value: false}]
               }) == expected

        checkin_checkout()
      end
    end

    test "applies empty and not_empty filter to map fields" do
      check all fruit_count <- integer(@pet_count_range),
                fruits =
                  insert_list_and_sort(fruit_count, :fruit,
                    attributes: fn -> Enum.random([nil, %{}, %{"a" => "b"}]) end,
                    extra: fn -> Enum.random([nil, %{}, %{"a" => "b"}]) end,
                    owner:
                      build(:owner,
                        attributes: fn ->
                          Enum.random([nil, %{}, %{"a" => "b"}])
                        end,
                        extra: fn -> Enum.random([nil, %{}, %{"a" => "b"}]) end
                      )
                  ),
                field <-
                  member_of([
                    :attributes,
                    :extra,
                    :owner_attributes,
                    :owner_extra
                  ]),
                op <- member_of([:empty, :not_empty]) do
        [opposite_op] = [:empty, :not_empty] -- [op]
        expected = filter_items(fruits, field, op, true)
        opposite_expected = filter_items(fruits, field, opposite_op, true)

        assert query_fruits_with_owners(%{
                 filters: [%{field: field, op: op, value: true}]
               }) == expected

        assert query_fruits_with_owners(%{
                 filters: [%{field: field, op: op, value: false}]
               }) == opposite_expected

        assert query_fruits_with_owners(%{
                 filters: [%{field: field, op: opposite_op, value: true}]
               }) == opposite_expected

        assert query_fruits_with_owners(%{
                 filters: [%{field: field, op: opposite_op, value: false}]
               }) == expected

        checkin_checkout()
      end
    end

    property "applies like filter", %{ecto_adapter: ecto_adapter} do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                query_value <- substring(value) do
        expected = filter_items(pets, field, :like, query_value, ecto_adapter)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :like, value: query_value}]
               }) == expected

        checkin_checkout()
      end
    end

    test "escapes % in like queries" do
      %{id: _id1} = insert(:pet, name: "abc")
      %{id: id2} = insert(:pet, name: "a%c")

      for op <- [:like, :like_and, :like_or] do
        flop = %Flop{filters: [%Filter{field: :name, op: op, value: "a%c"}]}
        assert [%Pet{id: ^id2}] = Flop.all(Pet, flop)
      end
    end

    @tag :ilike
    test "escapes % in ilike queries" do
      %{id: _id1} = insert(:pet, name: "abc")
      %{id: id2} = insert(:pet, name: "a%c")

      for op <- [:ilike, :ilike_and, :ilike_or] do
        flop = %Flop{filters: [%Filter{field: :name, op: op, value: "a%c"}]}
        assert [%Pet{id: ^id2}] = Flop.all(Pet, flop)
      end
    end

    test "escapes % in starts_with queries" do
      %{id: _id1} = insert(:pet, name: "abc")
      %{id: id2} = insert(:pet, name: "a%c")

      flop = %Flop{
        filters: [%Filter{field: :name, op: :starts_with, value: "a%"}]
      }

      assert [%Pet{id: ^id2}] = Flop.all(Pet, flop)
    end

    test "escapes % in ends_with queries" do
      %{id: _id1} = insert(:pet, name: "abc")
      %{id: id2} = insert(:pet, name: "a%c")

      flop = %Flop{
        filters: [%Filter{field: :name, op: :ends_with, value: "%c"}]
      }

      assert [%Pet{id: ^id2}] = Flop.all(Pet, flop)
    end

    test "escapes _ in starts_with queries" do
      %{id: _id1} = insert(:pet, name: "abc")
      %{id: id2} = insert(:pet, name: "a_c")

      flop = %Flop{
        filters: [%Filter{field: :name, op: :starts_with, value: "a_"}]
      }

      assert [%Pet{id: ^id2}] = Flop.all(Pet, flop)
    end

    test "escapes _ in ends_with queries" do
      %{id: _id1} = insert(:pet, name: "abc")
      %{id: id2} = insert(:pet, name: "a_c")

      flop = %Flop{
        filters: [%Filter{field: :name, op: :ends_with, value: "_c"}]
      }

      assert [%Pet{id: ^id2}] = Flop.all(Pet, flop)
    end

    test "escapes _ in like queries" do
      %{id: _id1} = insert(:pet, name: "abc")
      %{id: id2} = insert(:pet, name: "a_c")

      for op <- [:like, :like_and, :like_or] do
        flop = %Flop{filters: [%Filter{field: :name, op: op, value: "a_c"}]}
        assert [%Pet{id: ^id2}] = Flop.all(Pet, flop)
      end
    end

    @tag :ilike
    test "escapes _ in ilike queries" do
      %{id: _id1} = insert(:pet, name: "abc")
      %{id: id2} = insert(:pet, name: "a_c")

      for op <- [:ilike, :ilike_and, :ilike_or] do
        flop = %Flop{filters: [%Filter{field: :name, op: op, value: "a_c"}]}
        assert [%Pet{id: ^id2}] = Flop.all(Pet, flop)
      end
    end

    test "escapes \\ in like queries" do
      %{id: _id1} = insert(:pet, name: "abc")
      %{id: id2} = insert(:pet, name: "a\\c")

      for op <- [:like, :like_and, :like_or] do
        flop = %Flop{filters: [%Filter{field: :name, op: op, value: "a\\c"}]}
        assert [%Pet{id: ^id2}] = Flop.all(Pet, flop)
      end
    end

    @tag :ilike
    test "escapes \\ in ilike queries" do
      %{id: _id1} = insert(:pet, name: "abc")
      %{id: id2} = insert(:pet, name: "a\\c")

      for op <- [:ilike, :ilike_and, :ilike_or] do
        flop = %Flop{filters: [%Filter{field: :name, op: op, value: "a\\c"}]}
        assert [%Pet{id: ^id2}] = Flop.all(Pet, flop)
      end
    end

    property "applies not like filter", %{ecto_adapter: ecto_adapter} do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                query_value <- substring(value) do
        expected =
          filter_items(pets, field, :not_like, query_value, ecto_adapter)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :not_like, value: query_value}]
               }) == expected

        checkin_checkout()
      end
    end

    @tag :ilike
    property "applies ilike filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                op <- member_of([:=~, :ilike]),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                query_value <- substring(value) do
        expected = filter_items(pets, field, :ilike, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: op, value: query_value}]
               }) == expected

        checkin_checkout()
      end
    end

    @tag :ilike
    property "applies not ilike filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                query_value <- substring(value) do
        expected = filter_items(pets, field, :not_ilike, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :not_ilike, value: query_value}]
               }) == expected

        checkin_checkout()
      end
    end

    property "applies like_and filter", %{ecto_adapter: ecto_adapter} do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                search_text_or_list <- search_text_or_list(value) do
        expected =
          filter_items(
            pets,
            field,
            :like_and,
            search_text_or_list,
            ecto_adapter
          )

        assert query_pets_with_owners(%{
                 filters: [
                   %{field: field, op: :like_and, value: search_text_or_list}
                 ]
               }) == expected

        checkin_checkout()
      end
    end

    property "applies like_or filter", %{ecto_adapter: ecto_adapter} do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                search_text_or_list <- search_text_or_list(value) do
        expected =
          filter_items(pets, field, :like_or, search_text_or_list, ecto_adapter)

        assert query_pets_with_owners(%{
                 filters: [
                   %{field: field, op: :like_or, value: search_text_or_list}
                 ]
               }) == expected

        checkin_checkout()
      end
    end

    @tag :ilike
    property "applies ilike_and filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                search_text_or_list <- search_text_or_list(value) do
        expected = filter_items(pets, field, :ilike_and, search_text_or_list)

        assert query_pets_with_owners(%{
                 filters: [
                   %{field: field, op: :ilike_and, value: search_text_or_list}
                 ]
               }) == expected

        checkin_checkout()
      end
    end

    @tag :ilike
    property "applies ilike_or filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                search_text_or_list <- search_text_or_list(value) do
        expected = filter_items(pets, field, :ilike_or, search_text_or_list)

        assert query_pets_with_owners(%{
                 filters: [
                   %{field: field, op: :ilike_or, value: search_text_or_list}
                 ]
               }) == expected

        checkin_checkout()
      end
    end

    property "applies starts_with filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                query_value <- prefix(value) do
        expected = filter_items(pets, field, :starts_with, query_value)

        assert query_pets_with_owners(%{
                 filters: [
                   %{field: field, op: :starts_with, value: query_value}
                 ]
               }) == expected

        checkin_checkout()
      end
    end

    property "applies ends_with filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- filterable_pet_field(:string),
                pet <- member_of(pets),
                value = Pet.get_field(pet, field),
                query_value <- suffix(value) do
        expected = filter_items(pets, field, :ends_with, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :ends_with, value: query_value}]
               }) == expected

        checkin_checkout()
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
        expected = filter_items(pets, field, op, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: op, value: query_value}]
               }) == expected

        checkin_checkout()
      end
    end

    property "applies :in operator" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- member_of([:age, :name, :owner_age]),
                values = Enum.map(pets, &Map.get(&1, field)),
                query_value <-
                  list_of(one_of([member_of(values), value_by_field(field)]),
                    max_length: 5
                  ) do
        expected = filter_items(pets, field, :in, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :in, value: query_value}]
               }) == expected

        checkin_checkout()
      end
    end

    property "applies :not_in operator" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- member_of([:age, :name, :owner_age]),
                values = Enum.map(pets, &Map.get(&1, field)),
                query_value <-
                  list_of(one_of([member_of(values), value_by_field(field)]),
                    max_length: 5
                  ) do
        expected = filter_items(pets, field, :not_in, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :not_in, value: query_value}]
               }) == expected

        checkin_checkout()
      end
    end

    property "applies :contains operator" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- member_of([:tags, :owner_tags]),
                values = Enum.flat_map(pets, &Pet.get_field(&1, field)),
                query_value <- member_of(values) do
        expected = filter_items(pets, field, :contains, query_value)

        assert query_pets_with_owners(%{
                 filters: [%{field: field, op: :contains, value: query_value}]
               }) == expected

        checkin_checkout()
      end
    end

    property "applies :not_contains operator" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                field <- member_of([:tags, :owner_tags]),
                values = Enum.flat_map(pets, &Pet.get_field(&1, field)),
                query_value <- member_of(values) do
        expected = filter_items(pets, field, :not_contains, query_value)

        assert query_pets_with_owners(%{
                 filters: [
                   %{field: field, op: :not_contains, value: query_value}
                 ]
               }) == expected

        checkin_checkout()
      end
    end

    property "custom field filter" do
      check all pet_count <- integer(@pet_count_range),
                pets = insert_list_and_sort(pet_count, :pet_with_owner),
                values = Enum.map(pets, &String.reverse(&1.name)),
                query_value <- member_of(values) do
        expected = filter_items(pets, :name, :==, query_value)

        assert query_pets_with_owners(%{
                 filters: [
                   %{field: :reverse_name, op: :==, value: query_value}
                 ]
               }) == expected

        checkin_checkout()
      end
    end

    test "filtering with custom fields" do
      pets = insert_list_and_sort(1, :pet_with_owner)

      assert [] =
               query_pets_with_owners(%{
                 filters: [
                   %{field: :custom, op: :==, value: "some_value"}
                 ]
               })

      receive do
        {:filter, filter} ->
          assert filter ==
                   {%Flop.Filter{field: :custom, op: :==, value: "some_value"},
                    [some: :options]}
      end

      assert ^pets =
               query_pets_with_owners(
                 %{
                   filters: [
                     %{field: :custom, op: :==, value: "some_other_value"}
                   ]
                 },
                 extra_opts: [other: :options]
               )

      receive do
        {:filter, filter} ->
          assert filter ==
                   {%Flop.Filter{
                      field: :custom,
                      op: :==,
                      value: "some_other_value"
                    }, [other: :options, some: :options]}
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

    @tag :prefix
    test "can apply a query prefix" do
      insert(:pet, %{}, prefix: "other_schema")

      assert Flop.all(Pet, %Flop{}) == []
      refute Flop.all(Pet, %Flop{}, query_opts: [prefix: "other_schema"]) == []
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

    @tag :prefix
    test "can apply a query prefix" do
      insert(:pet, %{}, prefix: "other_schema")

      assert Flop.count(Pet, %Flop{}) == 0
      assert Flop.count(Pet, %Flop{}, query_opts: [prefix: "other_schema"]) == 1
    end

    test "allows overriding query" do
      _matching_pets = insert_list(6, :pet, age: 5, name: "A")
      _more_matching_pets = insert_list(5, :pet, age: 5, name: "B")
      _non_matching_pets = insert_list(4, :pet, age: 6)

      flop = %Flop{
        limit: 2,
        offset: 2,
        order_by: [:age],
        filters: [%Filter{field: :age, op: :<=, value: 5}]
      }

      # default query
      assert Flop.count(Pet, flop) == 11

      # custom count query
      assert Flop.count(Pet, flop, count_query: where(Pet, name: "A")) == 6
      assert Flop.count(Pet, flop, count_query: where(Pet, name: "B")) == 5
    end

    test "allows overriding the count itself" do
      _matching_pets = insert_list(6, :pet, age: 5, name: "A")
      _more_matching_pets = insert_list(5, :pet, age: 5, name: "B")
      _non_matching_pets = insert_list(4, :pet, age: 6)

      flop = %Flop{
        limit: 2,
        offset: 2,
        order_by: [:age],
        filters: [%Filter{field: :age, op: :<=, value: 5}]
      }

      # default query
      assert Flop.count(Pet, flop) == 11

      # custom count
      assert Flop.count(Pet, flop, count: 6) == 6
    end

    test "counts entries for queries with group_by clauses" do
      _owner_1 = insert(:owner, age: 13, pets: build_list(3, :pet))
      _owner_2 = insert(:owner, age: 20, pets: build_list(2, :pet))
      _owner_3 = insert(:owner, age: 22, pets: build_list(1, :pet))
      _non_matching_owner = insert(:owner, age: 52, pets: build_list(4, :pet))

      q =
        Owner
        |> join(:left, [o], p in assoc(o, :pets), as: :pets)
        |> group_by([o], o.id)
        |> select(
          [o, pets: p],
          %{o | pet_count: count(p.id)}
        )

      flop = %Flop{
        filters: [%Filter{field: :age, op: :<=, value: 30}]
      }

      assert Flop.count(q, flop) == 3
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

    @tag :prefix
    test "can apply a query prefix" do
      insert(:pet, %{}, prefix: "other_schema")

      assert Flop.meta(Pet, %Flop{}).total_count == 0

      assert Flop.meta(
               Pet,
               %Flop{},
               query_opts: [prefix: "other_schema"]
             ).total_count == 1
    end

    test "sets the schema if :for option is passed" do
      assert Flop.meta(Pet, %Flop{}).schema == nil
      assert Flop.meta(Pet, %Flop{}, for: Pet).schema == Pet
    end

    test "sets options" do
      opts = Flop.meta(Pet, %Flop{}, for: Pet).opts
      assert opts[:for] == Pet
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
      flop = %Flop{
        page_size: -1,
        filters: [%Filter{field: :name, op: :something_like}]
      }

      assert {:error, %Meta{} = meta} = Flop.validate_and_run(Pet, flop)

      assert meta.params == %{
               "page_size" => -1,
               "filters" => [%{"field" => :name, "op" => :something_like}]
             }

      assert [filters: [_], page_size: [_]] = meta.errors
    end

    test "returns data and meta data" do
      insert_list(3, :pet)
      flop = %{page_size: 2, page: 2}
      assert {:ok, {[%Pet{}], %Meta{}}} = Flop.validate_and_run(Pet, flop)
    end
  end

  describe "validate_and_run!/3" do
    test "raises if flop is invalid" do
      assert_raise Flop.InvalidParamsError, fn ->
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

      flop = %Flop{limit: 100, offset: 4, order_by: [:name, :species, :age]}
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
      assert %{params: [{10, :integer}]} = query.limit
      assert Repo.all(query) == Enum.slice(sorted_pets, 0..9)

      flop = %Flop{page: 2, page_size: 10, order_by: order_by}
      query = Flop.query(Pet, flop)
      assert %QueryExpr{params: [{10, :integer}]} = query.offset
      assert %{params: [{10, :integer}]} = query.limit
      assert Repo.all(query) == Enum.slice(sorted_pets, 10..19)

      flop = %Flop{page: 3, page_size: 4, order_by: order_by}
      query = Flop.query(Pet, flop)
      assert %QueryExpr{params: [{8, :integer}]} = query.offset
      assert %{params: [{4, :integer}]} = query.limit
      assert Repo.all(query) == Enum.slice(sorted_pets, 8..11)
    end
  end

  describe "cursor pagination" do
    property "querying cursor by cursor forward includes all items in order" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}) do
        checkin_checkout()

        # insert pets into DB, retrieve them so we have the IDs
        Enum.each(pets, &Repo.insert!(&1))

        pets =
          Flop.all(
            pets_with_owners_query(),
            %Flop{order_by: cursor_fields, order_directions: directions},
            for: Pet
          )

        # retrieve first cursor, ensure returned pet matches first one in list
        [first_pet | remaining_pets] = pets

        {:ok, {[returned_pet], %Meta{end_cursor: cursor}}} =
          Flop.validate_and_run(
            pets_with_owners_query(),
            %Flop{
              first: 1,
              order_by: cursor_fields,
              order_directions: directions
            },
            for: Pet
          )

        assert returned_pet == first_pet

        # iterate over remaining pets, query DB cursor by cursor
        {reversed_returned_pets, last_cursor} =
          Enum.reduce(
            remaining_pets,
            {[first_pet], cursor},
            fn _current_pet, {pet_list, cursor} ->
              assert {:ok,
                      {[returned_pet],
                       %Meta{
                         end_cursor: new_cursor,
                         flop: %Flop{decoded_cursor: nil}
                       }}} =
                       Flop.validate_and_run(
                         pets_with_owners_query(),
                         %Flop{
                           first: 1,
                           after: cursor,
                           order_by: cursor_fields,
                           order_directions: directions
                         },
                         for: Pet
                       )

              {[returned_pet | pet_list], new_cursor}
            end
          )

        # ensure the accumulated list matches the manually sorted list
        returned_pets = Enum.reverse(reversed_returned_pets)

        assert returned_pets == pets

        # ensure nothing comes after the last cursor
        assert {:ok, {[], %Meta{end_cursor: nil}}} =
                 Flop.validate_and_run(
                   pets_with_owners_query(),
                   %Flop{
                     first: 1,
                     after: last_cursor,
                     order_by: cursor_fields,
                     order_directions: directions
                   },
                   for: Pet
                 )
      end
    end

    property "querying all items returns same list forward and backward" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}) do
        checkin_checkout()
        Enum.each(pets, &Repo.insert!(&1))
        pet_count = length(pets)

        {:ok, {with_first, _meta}} =
          Flop.validate_and_run(
            pets_with_owners_query(),
            %Flop{
              first: pet_count,
              order_by: cursor_fields,
              order_directions: directions
            },
            for: Pet
          )

        {:ok, {with_last, _meta}} =
          Flop.validate_and_run(
            pets_with_owners_query(),
            %Flop{
              last: pet_count,
              order_by: cursor_fields,
              order_directions: directions
            },
            for: Pet
          )

        assert with_first == with_last
      end
    end

    property "querying cursor by cursor backward includes all items in order" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}) do
        checkin_checkout()

        # insert pets into DB, retrieve them so we have the IDs
        Enum.each(pets, &Repo.insert!(&1))

        pets =
          Flop.all(
            pets_with_owners_query(),
            %Flop{order_by: cursor_fields, order_directions: directions},
            for: Pet
          )

        pets = Enum.reverse(pets)

        # retrieve last cursor, ensure returned pet matches last one in list
        [last_pet | remaining_pets] = pets

        {:ok, {[returned_pet], %Meta{end_cursor: cursor}}} =
          Flop.validate_and_run(
            pets_with_owners_query(),
            %Flop{
              last: 1,
              order_by: cursor_fields,
              order_directions: directions
            },
            for: Pet
          )

        assert returned_pet == last_pet

        # iterate over remaining pets, query DB cursor by cursor
        {reversed_returned_pets, last_cursor} =
          Enum.reduce(
            remaining_pets,
            {[last_pet], cursor},
            fn _current_pet, {pet_list, cursor} ->
              assert {:ok, {[returned_pet], %Meta{end_cursor: new_cursor}}} =
                       Flop.validate_and_run(
                         pets_with_owners_query(),
                         %Flop{
                           last: 1,
                           before: cursor,
                           order_by: cursor_fields,
                           order_directions: directions
                         },
                         for: Pet
                       )

              {[returned_pet | pet_list], new_cursor}
            end
          )

        # ensure the accumulated list matches the manually sorted list
        returned_pets = Enum.reverse(reversed_returned_pets)
        assert returned_pets == pets

        # ensure nothing comes after the last cursor
        assert {:ok, {[], %Meta{end_cursor: nil}}} =
                 Flop.validate_and_run(
                   pets_with_owners_query(),
                   %Flop{
                     last: 1,
                     before: last_cursor,
                     order_by: cursor_fields,
                     order_directions: directions
                   },
                   for: Pet
                 )
      end
    end

    property "has_previous_page? is false without after and last" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                first <- integer(1..(length(pets) + 1)) do
        checkin_checkout()
        Enum.each(pets, &Repo.insert!(&1))

        assert {_, %Meta{has_previous_page?: false}} =
                 Flop.validate_and_run!(
                   pets_with_owners_query(),
                   %Flop{
                     first: first,
                     order_by: cursor_fields,
                     order_directions: directions
                   },
                   for: Pet
                 )
      end
    end

    property "has_previous_page? is true with after" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                first <- integer(1..(length(pets) + 1)),
                cursor_pet <- member_of(pets) do
        checkin_checkout()
        Enum.each(pets, &Repo.insert!(&1))

        cursor =
          cursor_fields
          |> Enum.into(%{}, fn field ->
            {field, Pet.get_field(cursor_pet, field)}
          end)
          |> Flop.Cursor.encode()

        assert {_, %Meta{has_previous_page?: true}} =
                 Flop.validate_and_run!(
                   pets_with_owners_query(),
                   %Flop{
                     first: first,
                     after: cursor,
                     order_by: cursor_fields,
                     order_directions: directions
                   },
                   for: Pet
                 )
      end
    end

    property "has_previous_page? is true with last set and items left" do
      check all pets <- uniq_list_of_pets(length: 3..50),
                pet_count = length(pets),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                last <- integer(1..(pet_count - 2)),
                cursor_index <- integer((last + 1)..(pet_count - 1)) do
        checkin_checkout()
        Enum.each(pets, &Repo.insert!(&1))

        # retrieve ordered pets
        pets =
          Flop.all(
            pets_with_owners_query(),
            %Flop{order_by: cursor_fields, order_directions: directions},
            for: Pet
          )

        # retrieve cursor
        pet = Enum.at(pets, cursor_index)

        cursor =
          cursor_fields
          |> Enum.into(%{}, fn field -> {field, Pet.get_field(pet, field)} end)
          |> Flop.Cursor.encode()

        assert {_, %Meta{has_previous_page?: true}} =
                 Flop.validate_and_run!(
                   pets_with_owners_query(),
                   %Flop{
                     last: last,
                     before: cursor,
                     order_by: cursor_fields,
                     order_directions: directions
                   },
                   for: Pet
                 )
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
        checkin_checkout()

        # insert pets
        Enum.each(pets, &Repo.insert!(&1))

        # retrieve ordered pets
        pets =
          Flop.all(
            pets_with_owners_query(),
            %Flop{order_by: cursor_fields, order_directions: directions},
            for: Pet
          )

        # retrieve cursor
        pet = Enum.at(pets, cursor_index)

        cursor =
          cursor_fields
          |> Enum.into(%{}, fn field -> {field, Pet.get_field(pet, field)} end)
          |> Flop.Cursor.encode()

        assert {_, %Meta{has_previous_page?: false}} =
                 Flop.validate_and_run!(
                   pets_with_owners_query(),
                   %Flop{
                     last: last,
                     before: cursor,
                     order_by: cursor_fields,
                     order_directions: directions
                   },
                   for: Pet
                 )
      end
    end

    property "has_next_page? is false without first and before" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                last <- integer(1..(length(pets) + 1)) do
        checkin_checkout()
        Enum.each(pets, &Repo.insert!(&1))

        assert {_, %Meta{has_next_page?: false}} =
                 Flop.validate_and_run!(
                   pets_with_owners_query(),
                   %Flop{
                     last: last,
                     order_by: cursor_fields,
                     order_directions: directions
                   },
                   for: Pet
                 )
      end
    end

    property "has_next_page? is true with before" do
      check all pets <- uniq_list_of_pets(length: 1..25),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                last <- integer(1..(length(pets) + 1)),
                cursor_pet <- member_of(pets) do
        checkin_checkout()
        Enum.each(pets, &Repo.insert!(&1))

        cursor =
          cursor_fields
          |> Enum.into(%{}, fn field ->
            {field, Pet.get_field(cursor_pet, field)}
          end)
          |> Flop.Cursor.encode()

        assert {_, %Meta{has_next_page?: true}} =
                 Flop.validate_and_run!(
                   pets_with_owners_query(),
                   %Flop{
                     last: last,
                     before: cursor,
                     order_by: cursor_fields,
                     order_directions: directions
                   },
                   for: Pet
                 )
      end
    end

    property "has_next_page? is true with first set and items left" do
      check all pets <- uniq_list_of_pets(length: 3..50),
                pet_count = length(pets),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                first <- integer(1..(pet_count - 2)),
                cursor_index <- integer((first + 1)..(pet_count - 1)) do
        checkin_checkout()
        Enum.each(pets, &Repo.insert!(&1))

        # retrieve ordered pets
        pets =
          pets_with_owners_query()
          |> Flop.all(
            %Flop{order_by: cursor_fields, order_directions: directions},
            for: Pet
          )
          |> Enum.reverse()

        # retrieve cursor
        pet = Enum.at(pets, cursor_index)

        cursor =
          cursor_fields
          |> Enum.into(%{}, fn field -> {field, Pet.get_field(pet, field)} end)
          |> Flop.Cursor.encode()

        assert {_, %Meta{has_next_page?: true}} =
                 Flop.validate_and_run!(
                   pets_with_owners_query(),
                   %Flop{
                     first: first,
                     after: cursor,
                     order_by: cursor_fields,
                     order_directions: directions
                   },
                   for: Pet
                 )
      end
    end

    property "has_next_page? is false with first set and no items left" do
      check all pet_count <- integer(3..50),
                pets <- uniq_list_of_pets(length: pet_count..pet_count),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}),
                # include test with limits greater than item count
                first <- integer(1..(pet_count + 20)),
                cursor_index <-
                  integer(max(0, pet_count - first)..(pet_count - 1)) do
        checkin_checkout()

        Enum.each(pets, &Repo.insert!(&1))

        # retrieve ordered pets
        pets =
          Flop.all(
            pets_with_owners_query(),
            %Flop{order_by: cursor_fields, order_directions: directions},
            for: Pet
          )

        # retrieve cursor
        pet = Enum.at(pets, cursor_index)

        cursor =
          cursor_fields
          |> Enum.into(%{}, fn field -> {field, Pet.get_field(pet, field)} end)
          |> Flop.Cursor.encode()

        assert {_, %Meta{has_next_page?: false}} =
                 Flop.validate_and_run!(
                   pets_with_owners_query(),
                   %Flop{
                     first: first,
                     after: cursor,
                     order_by: cursor_fields,
                     order_directions: directions
                   },
                   for: Pet
                 )
      end
    end

    test "cursor value function can be overridden" do
      insert_list(4, :pet)
      query = select(Pet, [p], {p, %{other: :data}})

      cursor_value_func = fn {pet, _}, order_by ->
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
          cursor_value_func: cursor_value_func
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
          cursor_value_func: cursor_value_func
        )
    end

    test "nil values for cursors are ignored when using for option" do
      check all pets <- uniq_list_of_pets(length: 2..2),
                cursor_fields <- cursor_fields(%Pet{}),
                directions <- order_directions(%Pet{}) do
        checkin_checkout()

        # set name fields to nil and insert
        pets
        |> Enum.map(&Map.update!(&1, :name, fn _ -> nil end))
        |> Enum.each(&Repo.insert!(&1))

        assert {:ok, {[_], %Meta{end_cursor: end_cursor}}} =
                 Flop.validate_and_run(
                   pets_with_owners_query(),
                   %Flop{
                     first: 1,
                     order_by: cursor_fields,
                     order_directions: directions
                   },
                   for: Pet
                 )

        assert {:ok, _} =
                 Flop.validate_and_run(
                   pets_with_owners_query(),
                   %Flop{
                     first: 1,
                     after: end_cursor,
                     order_by: cursor_fields,
                     order_directions: directions
                   },
                   for: Pet
                 )
      end
    end

    test "raises if alias field is used" do
      q =
        Owner
        |> join(:left, [o], p in assoc(o, :pets), as: :pets)
        |> group_by([o], o.id)
        |> select(
          [o, pets: p],
          %{o | pet_count: p.id |> count() |> selected_as(:pet_count)}
        )

      insert(:owner)

      assert {_, %Meta{end_cursor: end_cursor}} =
               Flop.run(
                 q,
                 %Flop{first: 1, order_by: [:pet_count, :id]},
                 for: Owner
               )

      error =
        assert_raise RuntimeError,
                     fn ->
                       Flop.run(
                         q,
                         %Flop{
                           first: 1,
                           after: end_cursor,
                           order_by: [:pet_count, :id]
                         },
                         for: Owner
                       )
                     end

      assert error.message =~
               "alias fields are not supported in cursor pagination"
    end

    test "nil values for cursors are ignored when not using for option" do
      check all pets <- uniq_list_of_pets(length: 2..2),
                directions <- order_directions(%Pet{}) do
        checkin_checkout()
        cursor_fields = [:name, :age]

        # set name fields to nil and insert
        pets
        |> Enum.map(&Map.update!(&1, :name, fn _ -> nil end))
        |> Enum.each(&Repo.insert!(&1))

        assert {:ok, {[_], %Meta{end_cursor: end_cursor}}} =
                 Flop.validate_and_run(
                   pets_with_owners_query(),
                   %Flop{
                     first: 1,
                     order_by: cursor_fields,
                     order_directions: directions
                   }
                 )

        assert {:ok, _} =
                 Flop.validate_and_run(
                   pets_with_owners_query(),
                   %Flop{
                     first: 1,
                     after: end_cursor,
                     order_by: cursor_fields,
                     order_directions: directions
                   }
                 )
      end
    end

    @tag :composite_type
    test "paging on composite type" do
      1..10
      |> Enum.map(
        &MyApp.WalkingDistances.changeset(%MyApp.WalkingDistances{}, %{
          trip: %{value: &1, unit: "m"}
        })
      )
      |> Enum.each(&Repo.insert!(&1))

      assert {:ok, {[_element], %Meta{end_cursor: end_cursor}}} =
               Flop.validate_and_run(
                 MyApp.WalkingDistances,
                 %Flop{first: 1, order_by: [:trip]},
                 for: MyApp.WalkingDistances
               )

      assert {:ok, {[_element], %Meta{}}} =
               Flop.validate_and_run(
                 MyApp.WalkingDistances,
                 %Flop{first: 1, after: end_cursor, order_by: [:trip]},
                 for: MyApp.WalkingDistances
               )
    end
  end

  describe "__using__/1" do
    test "defines wrapper functions that pass default options" do
      insert_list(3, :pet)

      assert {:ok, {_, %Meta{page_size: 35}}} =
               TestProvider.validate_and_run(Pet, %{})
    end

    test "allows to override defaults" do
      insert_list(3, :pet)

      assert {:ok, {_, %Meta{page_size: 30}}} =
               TestProvider.validate_and_run(Pet, %{page_size: 30})
    end

    test "passes backend module" do
      assert {:ok, {_, %Meta{backend: TestProvider, opts: opts}}} =
               TestProvider.validate_and_run(Pet, %{})

      assert Keyword.get(opts, :backend) == TestProvider
    end
  end

  describe "__using__/1 with nested adapter options" do
    test "defines wrapper functions that pass default options" do
      insert_list(3, :pet)

      assert {:ok, {_, %Meta{page_size: 35}}} =
               TestProviderNested.validate_and_run(Pet, %{})
    end

    test "allows to override defaults" do
      insert_list(3, :pet)

      assert {:ok, {_, %Meta{page_size: 30}}} =
               TestProviderNested.validate_and_run(Pet, %{page_size: 30})
    end

    test "passes backend module" do
      assert {:ok, {_, %Meta{backend: TestProviderNested, opts: opts}}} =
               TestProviderNested.validate_and_run(Pet, %{})

      assert Keyword.get(opts, :backend) == TestProviderNested
    end
  end
end
