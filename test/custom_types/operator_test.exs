defmodule Flop.CustomTypes.OperatorTest do
  use ExUnit.Case, async: true
  alias Flop.CustomTypes.Operator

  describe "cast/1" do
    test "casts strings" do
      assert Operator.cast("==") == {:ok, :==}
    end

    test "casts atoms" do
      assert Operator.cast(:==) == {:ok, :==}
    end

    test "doesn't cast unknown operators" do
      assert Operator.cast("===") == :error
      assert Operator.cast(:===) == :error
    end
  end

  describe "load/1" do
    test "loads strings" do
      assert Operator.load("==") == {:ok, :==}
    end
  end

  describe "dump/1" do
    test "dumps atoms" do
      assert Operator.dump(:==) == {:ok, "=="}
    end

    test "dumps strings" do
      assert Operator.dump("==") == {:ok, "=="}
    end

    test "doesn't dump other things" do
      assert Operator.dump(1) == :error
      assert Operator.dump(%{}) == :error
    end
  end

  describe "__operators__/0" do
    test "returns a list of allowed operators as atoms" do
      operators = Operator.__operators__()
      assert is_list(operators)
      assert Enum.all?(operators, &is_atom/1)
    end
  end
end
