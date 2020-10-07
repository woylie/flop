defmodule Flop.CursorTest do
  use ExUnit.Case, async: true

  alias Flop.Cursor

  describe "encoding/decoding" do
    test "encoding and decoding returns original value" do
      value = %{a: "b", c: [:d], e: {:f, "g", 5}}
      assert value |> Cursor.encode() |> Cursor.decode() == value
    end

    test "cursor value containing function results in error" do
      value = %{a: fn b -> b * 2 end}

      assert_raise RuntimeError, fn ->
        value |> Cursor.encode() |> Cursor.decode()
      end
    end
  end
end
