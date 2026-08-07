defmodule Flop.MiscTest do
  use ExUnit.Case, async: true

  alias Flop.Misc

  doctest Flop.Misc, import: true

  describe "wildcard helpers" do
    test "raise if called with a non-string value" do
      for value <- [["George"], %{"a" => "George"}, 8, nil] do
        for fun <- [
              &Misc.add_wildcard/1,
              &Misc.add_wildcard_suffix/1,
              &Misc.add_wildcard_prefix/1
            ] do
          assert_raise ArgumentError,
                       ~r/invalid filter value for pattern operator/,
                       fn -> fun.(value) end
        end
      end
    end
  end
end
