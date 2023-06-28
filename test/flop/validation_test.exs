defmodule Flop.ValidationTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Ecto.Changeset
  import Flop.Generators
  import Flop.TestUtil

  alias Flop.Cursor
  alias Flop.Validation
  alias MyApp.Fruit
  alias MyApp.Owner
  alias MyApp.Pet
  alias MyApp.Vegetable

  defmodule TestProviderWithDefaultPaginationType do
    use Flop,
      repo: Flop.Repo,
      default_pagination_type: :first,
      pagination_types: [:first, :last]
  end

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

  property "optionally removes pagination params for mixed methods" do
    pagination_types = [:offset, :page, :first, :last]

    check all type_1 <- member_of(pagination_types),
              type_2 <- member_of(pagination_types -- [type_1]),
              params_1 <- pagination_parameters(type_1),
              params_2 <- pagination_parameters(type_2) do
      params = Map.merge(params_1, params_2)
      assert {:ok, flop} = validate(params, replace_invalid_params: true)
      assert flop == %Flop{limit: 50}
    end
  end

  test "returns empty Flop if everything is disabled" do
    assert validate(%{page: 1},
             ordering: false,
             filtering: false,
             pagination: false
           ) == {:ok, %Flop{limit: 50}}
  end

  test "does not raise if only filtering is enabled" do
    assert {:ok, %Flop{}} =
             validate(%{filters: [%{field: :name, op: :==, value: "George"}]},
               ordering: false,
               pagination: false
             )
  end

  test "only casts configured pagination types if used with Flop.Schema" do
    assert {:ok, %{page: nil, page_size: nil}} =
             validate(%{page: 1}, for: Fruit)

    assert {:ok, %{first: 1}} =
             validate(%{first: 1, order_by: [:name]}, for: Fruit)

    assert {:ok, %{last: 1}} =
             validate(%{last: 1, order_by: [:name]}, for: Fruit)

    assert {:ok, %{offset: 1}} = validate(%{offset: 1}, for: Fruit)

    assert {:ok, %{first: nil}} =
             validate(%{first: 1, order_by: [:name]}, for: Vegetable)

    assert {:ok, %{last: nil}} =
             validate(%{last: 1, order_by: [:name]}, for: Vegetable)

    assert {:ok, %{offset: nil}} = validate(%{offset: 1}, for: Vegetable)
  end

  test "does not cast pagination fields if pagination is disabled" do
    params = %{
      offset: 2,
      limit: 5,
      page: 1,
      page_size: 8,
      first: 4,
      after: "A",
      last: 6,
      before: "B"
    }

    # still applies default limit
    assert validate(params, pagination: false) == {:ok, %Flop{limit: 50}}
  end

  describe "offset/limit parameters" do
    test "limit must be a positive integer" do
      params = %{limit: 0}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:limit] == ["must be greater than 0"]
    end

    test "resets invalid limit with replace_invalid_params" do
      params = %{limit: 0}

      # struct without configured default limit

      assert {:ok, %Flop{} = flop} =
               validate(params, replace_invalid_params: true, for: Pet)

      assert flop.limit == 50

      # struct with configured default limit

      assert {:ok, %Flop{} = flop} =
               validate(params, replace_invalid_params: true, for: Fruit)

      assert flop.limit == 60
    end

    test "offset must be a non-negative integer" do
      params = %{offset: -1}
      assert {:error, changeset} = validate(params)

      assert errors_on(changeset)[:offset] == [
               "must be greater than or equal to 0"
             ]
    end

    test "replaces invalid offset with replace_invalid_params" do
      params = %{offset: -1}

      assert {:ok, %Flop{} = flop} =
               validate(params, replace_invalid_params: true)

      assert flop.offset == 0
    end

    test "validates max limit if set with Flop.Schema" do
      params = %{limit: 1001}
      assert {:error, changeset} = validate(params, for: Pet)

      assert errors_on(changeset)[:limit] == [
               "must be less than or equal to 1000"
             ]
    end

    test "replaces invalid max limit with replace_invalid_params" do
      params = %{limit: 1001}

      # struct without configured default limit

      assert {:ok, %Flop{} = flop} =
               validate(params, replace_invalid_params: true, for: Pet)

      assert flop.limit == 50

      # struct with configured default limit

      assert {:ok, %Flop{} = flop} =
               validate(params,
                 replace_invalid_params: true,
                 for: Fruit,
                 max_limit: 100
               )

      assert flop.limit == 60
    end

    test "applies default limit" do
      # struct without configured default limit
      assert {:ok, %Flop{limit: 50}} = validate(%{}, for: Pet)
      assert {:ok, %Flop{limit: 50}} = validate(%{offset: 10}, for: Pet)
      assert {:ok, %Flop{limit: 1}} = validate(%{limit: 1, offset: 2}, for: Pet)

      # struct with configured default limit
      assert {:ok, %Flop{limit: 60}} = validate(%{offset: 10}, for: Fruit)
      assert {:ok, %Flop{limit: 1}} = validate(%{limit: 1}, for: Fruit)
    end

    test "sets default limit if no pagination parameters are set" do
      assert {:ok, %Flop{limit: 60}} = validate(%{}, for: Fruit)
    end

    test "sets default limit with default pagination type" do
      assert {:ok, %Flop{limit: 60}} =
               validate(%{}, for: Fruit, default_pagination_type: :offset)

      assert {:ok, %Flop{page_size: 60}} =
               validate(%{}, for: Vegetable, default_pagination_type: :page)

      assert {:ok, %Flop{first: 60}} =
               validate(%{}, for: Fruit, default_pagination_type: :first)

      assert {:ok, %Flop{last: 60}} =
               validate(%{}, for: Fruit, default_pagination_type: :last)
    end

    test "sets default limit with default pagination type from schema" do
      assert {:ok, %Flop{page_size: 50}} = validate(%{}, for: Owner)
    end

    test "can override default pagination type" do
      assert {:ok, %Flop{limit: nil}} =
               TestProviderWithDefaultPaginationType.validate(%Flop{},
                 default_limit: false,
                 pagination: false,
                 default_pagination_type: false
               )
    end

    test "does not set default limit if false" do
      assert {:ok, %Flop{limit: 60}} = validate(%{}, for: Fruit)

      assert {:ok, %Flop{limit: nil}} =
               validate(%{}, for: Fruit, default_limit: false)
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

    test "replaces invalid page with replace_invalid_params" do
      params = %{page: 0, page_size: 10}

      assert {:ok, %Flop{page: 1}} =
               validate(params, replace_invalid_params: true)
    end

    test "replaces malformed page with replace_invalid_params" do
      params = %{page: "a", page_size: 10}

      assert {:ok, %Flop{page: 1}} =
               validate(params, replace_invalid_params: true)
    end

    test "page size must be a positive integer" do
      params = %{page_size: 0}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:page_size] == ["must be greater than 0"]
    end

    test "resets invalid page size with replace_invalid_params" do
      params = %{page_size: 0}

      assert {:ok, %Flop{} = flop} =
               validate(params,
                 replace_invalid_params: true,
                 for: Pet,
                 default_limit: 50
               )

      assert flop.page_size == 50
    end

    test "falls back to default page size" do
      params = %{page: 1}
      assert {:ok, %Flop{page_size: 50}} = validate(params)

      assert {:ok, %Flop{page_size: 50}} =
               validate(params, replace_invalid_params: true)
    end

    test "uses default limit if page size is not set" do
      assert {:ok, %Flop{page: 2, page_size: 60}} =
               validate(%{page: 2}, for: Vegetable)
    end

    test "validates max limit if set with Flop.Schema" do
      params = %{page: 1, page_size: 1001}
      assert {:error, changeset} = validate(params, for: Pet)

      assert errors_on(changeset)[:page_size] == [
               "must be less than or equal to 1000"
             ]
    end

    test "does not set max limit if set to false" do
      params = %{page: 1, page_size: 1001}
      assert {:ok, _} = validate(params, for: Pet, max_limit: false)
    end

    test "replaces invalid max limit with replace_invalid_params" do
      params = %{page: 1, page_size: 1001}

      assert {:ok, %Flop{page_size: 50}} =
               validate(params,
                 replace_invalid_params: true,
                 for: Pet,
                 default_limit: 50,
                 max_size: 1000
               )
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

    test "resets invalid first with replace_invalid_params" do
      params = %{first: 0}

      assert {:ok, %Flop{} = flop} =
               validate(params, replace_invalid_params: true, for: Fruit)

      assert flop.first == 60
    end

    test "first falls back to default" do
      params = %{after: "a", order_by: [:name]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:first] == nil
      assert changeset.changes.first == 50

      assert {:ok, %Flop{first: 50}} =
               validate(params, replace_invalid_params: true)
    end

    test "uses default limit if first is not set" do
      cursor = Cursor.encode(%{name: "a"})

      assert {:ok, %Flop{first: 60, after: ^cursor}} =
               validate(%{after: cursor, order_by: [:name]}, for: Fruit)
    end

    test "does not set default limit for other pagination types" do
      assert {:ok, %Flop{limit: nil, page_size: nil, last: nil}} =
               validate(%{first: 1, order_by: [:name]}, for: Fruit)
    end

    test "validates max limit if set with Flop.Schema" do
      params = %{first: 1001}
      assert {:error, changeset} = validate(params, for: Pet)

      assert errors_on(changeset)[:first] == [
               "must be less than or equal to 1000"
             ]
    end

    test "replaces invalid max limit with replace_invalid_params" do
      params = %{first: 1001, order_by: [:name]}

      assert {:ok, %Flop{first: 50}} =
               validate(params,
                 replace_invalid_params: true,
                 for: Pet,
                 default_limit: 50
               )
    end

    test "requires order_by parameter" do
      params = %{first: 5}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:order_by] == ["can't be blank"]

      params = %{first: 5, order_by: []}
      assert {:error, changeset} = validate(params)

      assert errors_on(changeset)[:order_by] == [
               "can't be blank"
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

    test "replaces invalid after cursor with replace_invalid_params" do
      # malformed cursor
      params = %{first: 2, after: "a", order_by: [:name]}

      assert {:ok, %Flop{after: nil}} =
               validate(params, replace_invalid_params: true)

      # not a map
      cursor = Cursor.encode(["a", "b"])
      params = %{first: 2, after: cursor, order_by: [:name]}

      assert {:ok, %Flop{after: nil}} =
               validate(params, replace_invalid_params: true)

      # includes atoms that weren't in use before
      cursor = "g3QAAAABZAAGYmFybmV5ZAAGcnViYmxl"
      params = %{first: 2, after: cursor, order_by: [:name]}

      assert {:ok, %Flop{after: nil}} =
               validate(params, replace_invalid_params: true)
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

    test "replaces cursor if it does not match order params" do
      # too many cursor fields
      cursor = Cursor.encode(%{name: "a", id: "b"})
      params = %{first: 2, after: cursor, order_by: [:name]}

      assert {:ok, %Flop{after: nil}} =
               validate(params, replace_invalid_params: true)

      # missing cursor fields
      cursor = Cursor.encode(%{name: "a"})
      params = %{first: 2, after: cursor, order_by: [:name, :id]}

      assert {:ok, %Flop{after: nil}} =
               validate(params, replace_invalid_params: true)
    end
  end

  describe "last/before parameters" do
    test "last must be a positive integer" do
      params = %{last: 0}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:last] == ["must be greater than 0"]
    end

    test "resets invalid last with replace_invalid_params" do
      params = %{last: 0}

      assert {:ok, %Flop{} = flop} =
               validate(params, replace_invalid_params: true, for: Fruit)

      assert flop.last == 60
    end

    test "last falls back to default" do
      params = %{before: "a", order_by: [:name]}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:last] == nil
      assert changeset.changes.last == 50

      assert {:ok, %Flop{last: 50}} =
               validate(params, replace_invalid_params: true)
    end

    test "uses default limit if last is not set" do
      cursor = Cursor.encode(%{name: "a"})

      assert {:ok, %Flop{last: 60, before: ^cursor}} =
               validate(%{before: cursor, order_by: [:name]}, for: Fruit)
    end

    test "does not set default limit for other pagination types" do
      assert {:ok, %Flop{limit: nil, page_size: nil, first: nil}} =
               validate(%{last: 1, order_by: [:name]}, for: Fruit)
    end

    test "validates max limit if set with Flop.Schema" do
      params = %{last: 1100}
      assert {:error, changeset} = validate(params, for: Pet)

      assert errors_on(changeset)[:last] == [
               "must be less than or equal to 1000"
             ]
    end

    test "replaces invalid max limit with replace_invalid_params" do
      params = %{last: 1001, order_by: [:name]}

      assert {:ok, %Flop{last: 50}} =
               validate(params,
                 replace_invalid_params: true,
                 for: Pet,
                 default_limit: 50
               )
    end

    test "requires order_by parameter" do
      params = %{last: 5}
      assert {:error, changeset} = validate(params)
      assert errors_on(changeset)[:order_by] == ["can't be blank"]

      params = %{last: 5, order_by: []}
      assert {:error, changeset} = validate(params)

      assert errors_on(changeset)[:order_by] == [
               "can't be blank"
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

    test "replaces invalid before cursor with replace_invalid_params" do
      # malformed cursor
      params = %{last: 2, before: "a", order_by: [:name]}

      assert {:ok, %Flop{before: nil}} =
               validate(params, replace_invalid_params: true)

      # not a map
      cursor = Cursor.encode(["a", "b"])
      params = %{last: 2, before: cursor, order_by: [:name]}

      assert {:ok, %Flop{before: nil}} =
               validate(params, replace_invalid_params: true)

      # includes atoms that weren't in use before
      cursor = "g3QAAAABZAAGYmFybmV5ZAAGcnViYmxl"
      params = %{last: 2, before: cursor, order_by: [:name]}

      assert {:ok, %Flop{before: nil}} =
               validate(params, replace_invalid_params: true)
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

    test "replace before cursor params match order params" do
      # too many cursor fields
      cursor = Cursor.encode(%{name: "a", id: "b"})
      params = %{last: 2, before: cursor, order_by: [:name]}

      assert {:ok, %Flop{before: nil}} =
               validate(params, replace_invalid_params: true)

      # missing cursor fields
      cursor = Cursor.encode(%{name: "a"})
      params = %{last: 2, before: cursor, order_by: [:name, :id]}

      assert {:ok, %Flop{before: nil}} =
               validate(params, replace_invalid_params: true)
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

    test "replaces invalid order fields with replace_invalid_params" do
      params = %{
        order_by: [:social_security_number, :name, :halloween_costume],
        order_directions: [:desc, :desc_nulls_first, :asc]
      }

      assert {:ok,
              %Flop{order_by: [:name], order_directions: [:desc_nulls_first]}} =
               validate(params, for: Pet, replace_invalid_params: true)
    end

    test "replaces malformed order fields with replace_invalid_params" do
      params = %{
        order_by: 5,
        order_directions: true
      }

      assert {:ok, %Flop{order_by: [:name], order_directions: [:asc]}} =
               validate(params, for: Fruit, replace_invalid_params: true)
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
                %Flop{
                  limit: 50,
                  order_by: [:name, :age],
                  order_directions: [:desc, :asc]
                }}

      params = %{order_by: [:name, :age], order_directions: ["desc", "asc"]}

      assert validate(params) ==
               {:ok,
                %Flop{
                  limit: 50,
                  order_by: [:name, :age],
                  order_directions: [:desc, :asc]
                }}

      # order directions without order fields get removed
      assert validate(%{order_directions: [:desc]}) ==
               {:ok, %Flop{limit: 50, order_by: nil, order_directions: nil}}
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

    test "removes invalid filters with replace_invalid_params" do
      params = %{
        filters: [
          %{field: :given_name, op: :==, value: "a"},
          %{field: :species, value: "dog"},
          %{field: :halloween_costume, value: "Pirate"}
        ]
      }

      assert {:ok, %Flop{filters: [%{field: :species}]}} =
               validate(params, for: Pet, replace_invalid_params: true)
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

    test "validates filter value for normal string fields" do
      params = %{filters: [%{field: :name, value: "Hanna"}]}
      assert {:ok, %{filters: [%{value: "Hanna"}]}} = validate(params, for: Pet)

      params = %{filters: [%{field: :name, value: 2}]}
      assert {:error, changeset} = validate(params, for: Pet)
      assert [%{value: ["is invalid"]}] = errors_on(changeset)[:filters]
    end

    test "validates filter value for normal integer fields" do
      params = %{filters: [%{field: :age, value: "5"}]}
      assert {:ok, %Flop{filters: [%{value: 5}]}} = validate(params, for: Pet)

      params = %{filters: [%{field: :age, value: "8y"}]}
      assert {:error, changeset} = validate(params, for: Pet)
      assert [%{value: ["is invalid"]}] = errors_on(changeset)[:filters]
    end

    test "casts filter values for in/not_in operators as arrays" do
      for op <- [:in, :not_in] do
        params = %{filters: [%{field: :age, op: op, value: 5}]}
        assert {:error, changeset} = validate(params, for: Pet)
        assert [%{value: ["is invalid"]}] = errors_on(changeset)[:filters]

        params = %{filters: [%{field: :age, op: op, value: [5]}]}
        assert {:ok, %{filters: [%{value: [5]}]}} = validate(params, for: Pet)

        params = %{filters: [%{field: :age, op: op, value: ["5"]}]}
        assert {:ok, %{filters: [%{value: [5]}]}} = validate(params, for: Pet)

        params = %{filters: [%{field: :age, value: ["five"]}]}
        assert {:error, changeset} = validate(params, for: Pet)
        assert [%{value: ["is invalid"]}] = errors_on(changeset)[:filters]
      end
    end

    test "casts filter values for contains/not_contains as inner type" do
      for op <- [:contains, :not_contains] do
        params = %{filters: [%{field: :tags, op: op, value: "a"}]}
        assert {:ok, %{filters: [%{value: "a"}]}} = validate(params, for: Pet)

        params = %{filters: [%{field: :tags, op: op, value: 5}]}
        assert {:error, changeset} = validate(params, for: Pet)
        assert [%{value: ["is invalid"]}] = errors_on(changeset)[:filters]

        params = %{filters: [%{field: :tags, op: op, value: ["5"]}]}
        assert {:error, changeset} = validate(params, for: Pet)
        assert [%{value: ["is invalid"]}] = errors_on(changeset)[:filters]
      end
    end

    test "casts filter values for compound fields as strings" do
      params = %{filters: [%{field: :full_name, op: :=~, value: "Carl"}]}
      assert {:ok, %{filters: [%{value: "Carl"}]}} = validate(params, for: Pet)

      params = %{filters: [%{field: :full_name, op: :=~, value: 2}]}
      assert {:error, changeset} = validate(params, for: Pet)
      assert [%{value: ["is invalid"]}] = errors_on(changeset)[:filters]
    end

    test "cast filter value for join fields with binding option" do
      params = %{filters: [%{field: :owner_name, value: "Harry"}]}
      assert {:ok, %{filters: [%{value: "Harry"}]}} = validate(params, for: Pet)

      params = %{filters: [%{field: :owner_name, value: 5}]}
      assert {:error, changeset} = validate(params, for: Pet)
      assert [%{value: ["is invalid"]}] = errors_on(changeset)[:filters]
    end

    test "casts any filter value for join fields without binding option" do
      params = %{filters: [%{field: :owner_age, value: 5}]}
      assert {:ok, %Flop{filters: [%{value: 5}]}} = validate(params, for: Pet)

      params = %{filters: [%{field: :owner_age, value: "five"}]}
      assert {:ok, %{filters: [%{value: "five"}]}} = validate(params, for: Pet)
    end

    test "casts filter value (i)like_and/or as string or array of strings" do
      for op <- [:like_and, :like_or, :ilike_and, :ilike_or] do
        params = %{filters: [%{field: :name, op: op, value: "a"}]}
        assert {:ok, %{filters: [%{value: "a"}]}} = validate(params, for: Pet)

        params = %{filters: [%{field: :name, op: op, value: ["a"]}]}
        assert {:ok, %{filters: [%{value: ["a"]}]}} = validate(params, for: Pet)

        params = %{filters: [%{field: :name, op: op, value: 5}]}
        assert {:error, changeset} = validate(params, for: Pet)
        assert [%{value: ["is invalid"]}] = errors_on(changeset)[:filters]

        params = %{filters: [%{field: :name, op: op, value: [5]}]}
        assert {:error, changeset} = validate(params, for: Pet)
        assert [%{value: ["is invalid"]}] = errors_on(changeset)[:filters]
      end
    end

    test "casts filter values for empty/not_empty operators as booleans" do
      params = %{filters: [%{field: :name, op: :empty, value: "true"}]}
      assert {:ok, %{filters: [%{value: true}]}} = validate(params, for: Pet)

      params = %{filters: [%{field: :name, op: "not_empty", value: "false"}]}
      assert {:ok, %{filters: [%{value: false}]}} = validate(params, for: Pet)

      params = %{filters: [%{field: :name, op: :empty, value: "maybe"}]}
      assert {:error, changeset} = validate(params, for: Pet)
      assert [%{value: ["is invalid"]}] = errors_on(changeset)[:filters]
    end
  end
end
