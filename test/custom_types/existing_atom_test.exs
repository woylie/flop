defmodule Flop.CustomTypes.ExistingAtomTest do
  use ExUnit.Case, async: true
  alias Flop.CustomTypes.ExistingAtom

  describe "cast/1" do
    test "casts strings" do
      assert ExistingAtom.cast("==") == {:ok, :==}
    end

    test "casts atoms" do
      assert ExistingAtom.cast(:==) == {:ok, :==}
    end

    test "doesn't cast to non-existent atoms" do
      assert ExistingAtom.cast("noatomlikethis") == :error
    end
  end

  describe "load/1" do
    test "loads strings" do
      assert ExistingAtom.load("==") == {:ok, :==}
    end

    test "doesn't cast to non-existent atoms" do
      assert ExistingAtom.load("noatomlikethis") == :error
    end
  end

  describe "dump/1" do
    test "dumps atoms" do
      assert ExistingAtom.dump(:==) == {:ok, "=="}
    end

    test "dumps strings" do
      assert ExistingAtom.dump("==") == {:ok, "=="}
    end

    test "doesn't dump other things" do
      assert ExistingAtom.dump(1) == :error
      assert ExistingAtom.dump(%{}) == :error
    end
  end
end
