defmodule Flop.FilterTest do
  use ExUnit.Case, async: true

  alias Flop.Filter
  alias MyApp.Pet

  doctest Flop.Filter, import: true

  defmodule SchemaWithoutDerive do
    use Ecto.Schema

    schema "whatever" do
      field :name, :string
      field :age, :integer
    end
  end

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

    test "returns a list of operators for a schema without derive" do
      assert Filter.allowed_operators(SchemaWithoutDerive, :name) == [
               :==,
               :!=,
               :=~,
               :empty,
               :not_empty,
               :<=,
               :<,
               :>=,
               :>,
               :in,
               :not_in,
               :like,
               :not_like,
               :like_and,
               :like_or,
               :ilike,
               :not_ilike,
               :ilike_and,
               :ilike_or
             ]

      assert Filter.allowed_operators(SchemaWithoutDerive, :age) == [
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

    test "returns a list of operators for a join field with ecto_type" do
      assert Filter.allowed_operators(Pet, :owner_name) ==
               Filter.allowed_operators(:string)
    end

    test "returns a list of operators for a join field without ecto_type" do
      assert Filter.allowed_operators(Pet, :owner_age) ==
               Filter.allowed_operators(:unknown)
    end

    test "returns a list of operators for a custom field with ecto_type" do
      assert Filter.allowed_operators(Pet, :reverse_name) ==
               Filter.allowed_operators(:string)
    end

    test "returns a list of operators for a custom field without ecto_type" do
      assert Filter.allowed_operators(Pet, :custom) ==
               Filter.allowed_operators(:unknown)
    end

    test "returns a list of operators for a compound field" do
      assert Filter.allowed_operators(Pet, :full_name) == [
               :=~,
               :like,
               :not_like,
               :like_and,
               :like_or,
               :ilike,
               :not_ilike,
               :ilike_and,
               :ilike_or,
               :empty,
               :not_empty
             ]
    end
  end
end
