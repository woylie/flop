defmodule Flop.CustomTypes.OrderDirectionTest do
  use ExUnit.Case, async: true
  alias Flop.CustomTypes.OrderDirection

  describe "cast/1" do
    test "casts strings" do
      assert OrderDirection.cast("asc") == {:ok, :asc}
    end

    test "casts atoms" do
      assert OrderDirection.cast(:asc) == {:ok, :asc}
    end

    test "doesn't cast unknown order directions" do
      assert OrderDirection.cast("sideways") == :error
      assert OrderDirection.cast(:upside_down) == :error
    end
  end

  describe "load/1" do
    test "loads strings" do
      assert OrderDirection.load("asc") == {:ok, :asc}
    end
  end

  describe "dump/1" do
    test "dumps atoms" do
      assert OrderDirection.dump(:asc) == {:ok, "asc"}
    end

    test "dumps strings" do
      assert OrderDirection.dump("asc") == {:ok, "asc"}
    end

    test "doesn't dump other things" do
      assert OrderDirection.dump(1) == :error
      assert OrderDirection.dump(%{}) == :error
    end
  end
end
