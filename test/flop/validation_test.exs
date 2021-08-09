defmodule Flop.ValidationTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Ecto.Changeset
  import Flop.Generators
  import Flop.TestUtil

  alias Flop.Cursor
  alias Flop.Fruit
  alias Flop.Pet
  alias Flop.Validation
  alias Flop.Vegetable

  defp validate(params, opts \\ []) do
    params
    |> Validation.changeset(opts)
    |> apply_action(:insert)
  end

  property "only allows one pagination method" do
    pagination_types = [:offset, :page, :first, :last]

    check all type_1 <- member_of(pagination_types),
              type_2 <- member_of(pagination_types -- [type_1]),
              params_1 <- pagination_parameters(type_1),
              params_2 <- pagination_parameters(type_2) do
      params = Map.merge(params_1, params_2)
      assert {:error, changeset} = validate(params)
      messages = changeset |> errors_on() |> Map.values()
      assert ["cannot combine multiple pagination types"] in messages
    end
  end

  test "only allows configured pagination types if used with Flop.Schema" do
    assert {:error, changeset} = validate(%{page: 1}, for: Fruit)

    assert errors_on(changeset)[:page] == [
             "page-based pagination is not allowed"
           ]

    assert {:ok, _} = validate(%{first: 1, order_by: [:name]}, for: Fruit)
    assert {:ok, _} = validate(%{last: 1, order_by: [:name]}, for: Fruit)
    assert {:ok, _} = validate(%{offset: 1}, for: Fruit)

    assert {:error, changeset} =
             validate(%{first: 1, order_by: [:name]}, for: Vegetable)

    assert errors_on(changeset)[:first] == [
             "cursor-based pagination with first/after is not allowed"
           ]

    assert {:error, changeset} =
             validate(%{last: 1, order_by: [:name]}, for: Vegetable)

    assert errors_on(changeset)[:last] == [
             "cursor-based pagination with last/before is not allowed"
           ]

    assert {:error, changeset} = validate(%{offset: 1}, for: Vegetable)

    assert errors_on(changeset)[:offset] == [
             "offset-based pagination is not allowed"
           ]
  end

  test "an offset of 0 is still allowed if offset pagination is disabled" do
    # passing only a limit
    assert {:ok, %Flop{offset: 0, limit: 20}} =
             validate(%{limit: 20}, for: Vegetable)

    # passing an offset of 0 and a limit
    assert {:ok, %Flop{offset: 0, limit: 20}} =
             validate(%{offset: 0, limit: 20}, for: Vegetable)

    # using the default limit, passing an offset
    assert {:ok, %Flop{offset: 0, limit: 50}} =
             validate(%{offset: 0}, for: Vegetable)

    # using the default limit, not passing an offset
    assert {:ok, %Flop{offset: nil, limit: 50}} = validate(%{}, for: Vegetable)
  end

  describe "offset/limit parameters" do
    test "limit must be a positive integer" do
      params = %{limit: 0}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:limit] == ["must be greater than 0"]
    end

    test "offset must be a non-negative integer" do
      params = %{offset: -1}
      assert {:error, changeset} = validate(params)

      assert errors_on(changeset)[:offset] == [
               "must be greater than or equal to 0"
             ]
    end

    test "validates max limit if set with Flop.Schema" do
      params = %{limit: 21}
      assert {:error, changeset} = validate(params, for: Pet)

      assert errors_on(changeset)[:limit] == [
               "must be less than or equal to 20"
             ]
    end

    test "applies default limit" do
      # struct without configured default limit
      assert {:ok, %Flop{limit: nil}} = validate(%{}, for: Pet)
      assert {:ok, %Flop{limit: nil}} = validate(%{offset: 10}, for: Pet)
      assert {:ok, %Flop{limit: 1}} = validate(%{limit: 1, offset: 2}, for: Pet)

      # struct with configured default limit
      assert {:ok, %Flop{limit: 50}} = validate(%{offset: 10}, for: Fruit)
      assert {:ok, %Flop{limit: 1}} = validate(%{limit: 1}, for: Fruit)
    end

    test "sets default limit if no pagination parameters are set" do
      assert {:ok, %Flop{limit: 50}} = validate(%{}, for: Fruit)
    end

    test "does not set default limit for other pagination types" do
      assert {:ok, %Flop{page_size: nil, first: nil, last: nil}} =
               validate(%{}, for: Fruit)

      assert {:ok, %Flop{page_size: nil, first: nil, last: nil}} =
               validate(%{offset: 0}, for: Fruit)
    end

    test "sets offset to 0 if limit is set without offset" do
      params = %{limit: 5}
      assert {:ok, %Flop{offset: 0, limit: 5}} = validate(params)
    end
  end

  describe "page/page_size parameters" do
    test "page must be a positive integer" do
      params = %{page: 0}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:page] == ["must be greater than 0"]
    end

    test "page size must be a positive integer" do
      params = %{page_size: 0}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:page_size] == ["must be greater than 0"]
    end

    test "requires page size" do
      params = %{page: 1}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:page_size] == ["can't be blank"]
    end

    test "uses default limit if page size is not set" do
      assert {:ok, %Flop{page: 2, page_size: 50}} =
               validate(%{page: 2}, for: Vegetable)
    end

    test "validates max limit if set with Flop.Schema" do
      params = %{page: 1, page_size: 21}
      assert {:error, changeset} = validate(params, for: Pet)

      assert errors_on(changeset)[:page_size] == [
               "must be less than or equal to 20"
             ]
    end

    test "does not set default limit for other pagination types" do
      assert {:ok, %Flop{limit: nil, first: nil, last: nil}} =
               validate(%{page: 1}, for: Vegetable)
    end

    test "sets page to 1 if page size is set without page" do
      params = %{page_size: 5}
      assert {:ok, %Flop{page: 1, page_size: 5}} = validate(params)
    end
  end

  describe "first/after parameters" do
    test "first must be a positive integer" do
      params = %{first: 0}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:first] == ["must be greater than 0"]
    end

    test "requires first" do
      params = %{after: "a"}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:first] == ["can't be blank"]
    end

    test "uses default limit if first is not set" do
      cursor = Cursor.encode(%{name: "a"})

      assert {:ok, %Flop{first: 50, after: ^cursor}} =
               validate(%{after: cursor, order_by: [:name]}, for: Fruit)
    end

    test "does not set default limit for other pagination types" do
      assert {:ok, %Flop{limit: nil, page_size: nil, last: nil}} =
               validate(%{first: 1, order_by: [:name]}, for: Fruit)
    end

    test "validates max limit if set with Flop.Schema" do
      params = %{first: 21}
      assert {:error, changeset} = validate(params, for: Pet)

      assert errors_on(changeset)[:first] == [
               "must be less than or equal to 20"
             ]
    end

    test "requires order_by parameter" do
      params = %{first: 5}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:order_by] == ["can't be blank"]

      params = %{first: 5, order_by: []}
      assert {:error, changeset} = validate(params)

      assert errors_on(changeset)[:order_by] == [
               "should have at least 1 item(s)"
             ]
    end

    test "uses default order" do
      assert {:ok, %Flop{order_by: [:name], order_directions: [:asc]}} =
               validate(%{first: 2}, for: Fruit)
    end

    test "validates after cursor" do
      # malformed cursor
      params = %{first: 2, after: "a", order_by: [:name]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:after] == ["is invalid"]

      # not a map
      cursor = Cursor.encode(["a", "b"])
      params = %{first: 2, after: cursor, order_by: [:name]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:after] == ["is invalid"]

      # includes atoms that weren't in use before
      cursor = "g3QAAAABZAAGYmFybmV5ZAAGcnViYmxl"
      params = %{first: 2, after: cursor, order_by: [:name]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:after] == ["is invalid"]
    end

    test "validates after cursor params match order params" do
      # valid cursor
      cursor = Cursor.encode(%{name: "a"})
      params = %{first: 2, after: cursor, order_by: [:name]}
      assert {:ok, _} = validate(params)

      # too many cursor fields
      cursor = Cursor.encode(%{name: "a", id: "b"})
      params = %{first: 2, after: cursor, order_by: [:name]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:after] == ["does not match order fields"]

      # missing cursor fields
      cursor = Cursor.encode(%{name: "a"})
      params = %{first: 2, after: cursor, order_by: [:name, :id]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:after] == ["does not match order fields"]
    end
  end

  describe "last/before parameters" do
    test "last must be a positive integer" do
      params = %{last: 0}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:last] == ["must be greater than 0"]
    end

    test "requires last" do
      params = %{before: "a"}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:last] == ["can't be blank"]
    end

    test "uses default limit if last is not set" do
      cursor = Cursor.encode(%{name: "a"})

      assert {:ok, %Flop{last: 50, before: ^cursor}} =
               validate(%{before: cursor, order_by: [:name]}, for: Fruit)
    end

    test "does not set default limit for other pagination types" do
      assert {:ok, %Flop{limit: nil, page_size: nil, first: nil}} =
               validate(%{last: 1, order_by: [:name]}, for: Fruit)
    end

    test "validates max limit if set with Flop.Schema" do
      params = %{last: 21}
      assert {:error, changeset} = validate(params, for: Pet)

      assert errors_on(changeset)[:last] == [
               "must be less than or equal to 20"
             ]
    end

    test "requires order_by parameter" do
      params = %{last: 5}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:order_by] == ["can't be blank"]

      params = %{last: 5, order_by: []}
      assert {:error, changeset} = validate(params)

      assert errors_on(changeset)[:order_by] == [
               "should have at least 1 item(s)"
             ]
    end

    test "uses default order" do
      assert {:ok, %Flop{order_by: [:name], order_directions: [:asc]}} =
               validate(%{last: 2}, for: Fruit)
    end

    test "validates before cursor" do
      # malformed cursor
      params = %{last: 2, before: "a", order_by: [:name]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:before] == ["is invalid"]

      # not a map
      cursor = Cursor.encode(["a", "b"])
      params = %{last: 2, before: cursor, order_by: [:name]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:before] == ["is invalid"]

      # includes atoms that weren't in use before
      cursor = "g3QAAAABZAAGYmFybmV5ZAAGcnViYmxl"
      params = %{last: 2, before: cursor, order_by: [:name]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:before] == ["is invalid"]
    end

    test "validates before cursor params match order params" do
      # valid cursor
      cursor = Cursor.encode(%{name: "a"})
      params = %{last: 2, before: cursor, order_by: [:name]}
      assert {:ok, _} = validate(params)

      # too many cursor fields
      cursor = Cursor.encode(%{name: "a", id: "b"})
      params = %{last: 2, before: cursor, order_by: [:name]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:before] == ["does not match order fields"]

      # missing cursor fields
      cursor = Cursor.encode(%{name: "a"})
      params = %{last: 2, before: cursor, order_by: [:name, :id]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:before] == ["does not match order fields"]
    end
  end

  describe "order parameters" do
    test "applies default order" do
      # struct without configured default order

      assert {:ok, %Flop{order_by: nil, order_directions: nil}} =
               validate(%{}, for: Pet)

      # struct with configured default order

      assert {:ok, %Flop{order_by: [:name], order_directions: [:asc]}} =
               validate(%{}, for: Fruit)
    end

    test "only allows to order by fields marked as sortable" do
      # field exists, but is not sortable

      params = %{order_by: [:social_security_number]}
      assert {:error, changeset} = validate(params, for: Pet)
      assert errors_on(changeset)[:order_by] == ["has an invalid entry"]

      params = %{order_by: ["social_security_number"]}
      assert {:error, changeset} = validate(params, for: Pet)
      assert errors_on(changeset)[:order_by] == ["has an invalid entry"]

      # field does not exist

      params = %{order_by: [:halloween_costume]}
      assert {:error, changeset} = validate(params, for: Pet)
      assert errors_on(changeset)[:order_by] == ["has an invalid entry"]

      params = %{order_by: ["honorific"]}
      assert {:error, changeset} = validate(params, for: Pet)
      assert errors_on(changeset)[:order_by] == ["is invalid"]

      # field exists and is sortable

      params = %{order_by: [:name]}
      assert {:ok, %Flop{order_by: [:name]}} = validate(params, for: Pet)

      params = %{order_by: ["name"]}
      assert {:ok, %Flop{order_by: [:name]}} = validate(params, for: Pet)
    end

    test "validates order directions" do
      params = %{order_directions: [:up, :down]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:order_directions] == ["is invalid"]

      params = %{order_directions: ["up", "down"]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:order_directions] == ["is invalid"]

      params = %{order_by: [:name, :age], order_directions: [:desc, :asc]}

      assert validate(params) ==
               {:ok,
                %Flop{order_by: [:name, :age], order_directions: [:desc, :asc]}}

      params = %{order_by: [:name, :age], order_directions: ["desc", "asc"]}

      assert validate(params) ==
               {:ok,
                %Flop{order_by: [:name, :age], order_directions: [:desc, :asc]}}

      # order directions without order fields get removed
      assert validate(%{order_directions: [:desc]}) ==
               {:ok, %Flop{order_by: nil, order_directions: nil}}
    end

    test "does not cast order fields if ordering is disabled" do
      params = %{order_by: [:name], order_directions: [:desc]}

      assert {:ok, %Flop{order_by: nil, order_directions: nil}} =
               validate(params, ordering: false)
    end

    test "applies default order when ordering is disabled" do
      assert {:ok, %Flop{order_by: [:name], order_directions: [:asc]}} =
               validate(%{order_by: [:family], order_directions: [:desc]},
                 for: Fruit,
                 ordering: false
               )
    end
  end

  describe "filter parameters" do
    test "only allows to filter by fields marked as filterable" do
      # field exists, but is not filterable

      params = %{filters: [%{field: :given_name, op: :==, value: "a"}]}
      assert {:error, changeset} = validate(params, for: Pet)
      assert [%{field: ["is invalid"]}] = errors_on(changeset)[:filters]

      params = %{filters: [%{field: "given_name", op: "==", value: "a"}]}
      assert {:error, changeset} = validate(params, for: Pet)
      assert [%{field: ["is invalid"]}] = errors_on(changeset)[:filters]

      # field does not exist

      params = %{filters: [%{field: :halloween_costume, value: "Pirate"}]}
      assert {:error, changeset} = validate(params, for: Pet)
      assert [%{field: ["is invalid"]}] = errors_on(changeset)[:filters]

      params = %{filters: [%{field: "honorific", value: "Esquire"}]}
      assert {:error, changeset} = validate(params, for: Pet)
      assert [%{field: ["is invalid"]}] = errors_on(changeset)[:filters]

      # field exists and is filterable

      params = %{filters: [%{field: :species, value: "dog"}]}

      assert {:ok, %Flop{filters: [%{field: :species}]}} =
               validate(params, for: Pet)

      params = %{filters: [%{field: "species", value: "dog"}]}

      assert {:ok, %Flop{filters: [%{field: :species}]}} =
               validate(params, for: Pet)
    end

    test "validates filter operator" do
      params = %{filters: [%{field: "a", op: :=, value: "b"}]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:filters] == [%{op: ["is invalid"]}]

      params = %{filters: [%{field: "a", op: "=", value: "b"}]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:filters]

      params = %{filters: [%{field: "a", op: :==, value: "b"}]}
      assert {:ok, %Flop{filters: [%{op: :==}]}} = validate(params)

      params = %{filters: [%{field: "a", op: "==", value: "b"}]}
      assert {:ok, %Flop{filters: [%{op: :==}]}} = validate(params)
    end

    test "does not cast filters if filtering is disabled" do
      params = %{filters: [%{field: "a", op: :==, value: "b"}]}
      assert {:ok, %Flop{filters: []}} = validate(params, filtering: false)
    end
  end
end
