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

    test "returns error for other types" do
      assert ExistingAtom.cast(1) == :error
    end
  end
end
