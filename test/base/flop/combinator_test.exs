defmodule Flop.CombinatorTest do
  use ExUnit.Case, async: true

  import Flop.TestUtil
  import Ecto.Changeset

  alias Flop.Combinator

  defp validate(params, opts \\ []) do
    %Combinator{}
    |> Combinator.changeset(params, opts)
    |> apply_action(:validate)
  end

  describe "changeset/3" do
    test "combinator type must be a valid type" do
      params = %{
        type: :invalid,
        filters: [
          %{field: :name, op: :==, value: "Harry"}
        ]
      }

      {:error, changeset} = validate(params)

      assert errors_on(changeset)[:type] == ["is invalid"]
    end

    test "combinator with empty filters is invalid" do
      params = %{
        type: :or,
        filters: []
      }

      {:error, changeset} = validate(params)

      assert errors_on(changeset)[:filters] == [
               "must have at least two filters or one combinator"
             ]
    end

    test "combinator with single filter is invalid" do
      params = %{
        type: :or,
        filters: [
          %{field: :name, op: :==, value: "Harry"}
        ]
      }

      {:error, changeset} = validate(params)

      assert errors_on(changeset)[:filters] == [
               "must have at least two filters or one combinator"
             ]
    end

    test "validates simple combinator with OR type" do
      params = %{
        type: :or,
        filters: [
          %{field: :name, op: :==, value: "Harry"},
          %{field: :name, op: :==, value: "Maggie"}
        ]
      }

      {:ok, combinator} = validate(params)

      assert combinator.type == :or
      assert length(combinator.filters) == 2
    end

    test "validates simple combinator with AND type" do
      params = %{
        type: :and,
        filters: [
          %{field: :age, op: :>, value: 1},
          %{field: :species, op: :==, value: "C. lupus"}
        ]
      }

      {:ok, combinator} = validate(params)

      assert combinator.type == :and
      assert length(combinator.filters) == 2
    end

    test "validates nested combinators" do
      params = %{
        type: :and,
        filters: [
          %{field: :age, op: :>, value: 1},
          %{
            type: :or,
            filters: [
              %{field: :name, op: :==, value: "Harry"},
              %{field: :name, op: :==, value: "Maggie"}
            ]
          }
        ]
      }

      {:ok, combinator} = validate(params)

      assert combinator.type == :and
      assert length(combinator.filters) == 2

      [filter, nested_combinator] = combinator.filters
      assert filter.__struct__ == Flop.Filter
      assert nested_combinator.__struct__ == Combinator
      assert nested_combinator.type == :or
      assert length(nested_combinator.filters) == 2
    end

    test "defaults to :and type when not specified" do
      params = %{
        filters: [
          %{field: :name, op: :==, value: "Harry"},
          %{field: :age, op: :>, value: 5}
        ]
      }

      {:ok, combinator} = validate(params)

      assert combinator.type == :and
    end
  end
end
