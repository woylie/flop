defmodule Flop.FilterTest do
  use ExUnit.Case, async: true

  alias Flop.Filter
  alias Flop.Pet

  doctest Flop.Filter, import: true

  describe "allowed_operators/1" do
    test "returns a list of operators for each native Ecto type" do
      types = [
        :id,
        :binary_id,
        :integer,
        :float,
        :boolean,
        :string,
        :binary,
        {:array, :integer},
        :map,
        {:map, :integer},
        :decimal,
        :date,
        :time,
        :time_usec,
        :naive_datetime,
        :naive_datetime_usec,
        :utc_datetime,
        :utc_datetime_usec,
        {:parameterized, Ecto.Enum, type: :string}
      ]

      for type <- types do
        assert [op | _] = Filter.allowed_operators(type)
        assert is_atom(op)
      end
    end

    test "returns a list of operators for unknown types" do
      assert [op | _] = Filter.allowed_operators(:unicorn)
      assert is_atom(op)
    end
  end

  describe "allowed_operators/2" do
    test "returns a list of operators for the given module and field" do
      assert Filter.allowed_operators(Pet, :age) == [
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
    end
  end
end
