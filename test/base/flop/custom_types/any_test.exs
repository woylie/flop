defmodule Flop.CustomTypes.AnyTest do
  use ExUnit.Case, async: true
  alias Flop.CustomTypes.Any

  describe "cast/1" do
    test "casts any value" do
      assert Any.cast(1) == {:ok, 1}
      assert Any.cast(1.2) == {:ok, 1.2}
      assert Any.cast(nil) == {:ok, nil}
      assert Any.cast(true) == {:ok, true}
      assert Any.cast("a") == {:ok, "a"}
    end
  end
end
