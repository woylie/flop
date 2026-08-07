defmodule Flop.CursorTest do
  use ExUnit.Case, async: true

  alias Flop.Cursor

  doctest Flop.Cursor

  describe "encoding/decoding" do
    test "encoding and decoding returns original value" do
      value = %{a: "b", c: [:d], e: {:f, "g", 5}, h: ~U[2020-09-25 11:09:41Z]}
      assert value |> Cursor.encode() |> Cursor.decode() == {:ok, value}
    end

    test "cursor value containing function results in error" do
      value = %{a: fn b -> b * 2 end}
      assert value |> Cursor.encode() |> Cursor.decode() == :error
    end

    test "decode!/1 raises error for invalid cursor" do
      assert_raise Flop.InvalidCursorError, fn ->
        Cursor.decode!("AAAH")
      end
    end

    test "rejects a cursor above the maximum size" do
      cursor = Cursor.encode(%{name: String.duplicate("a", 10_000)})

      assert byte_size(cursor) > 8_192
      assert Cursor.decode(cursor) == :error
    end

    test "accepts a cursor below the maximum size" do
      value = %{name: String.duplicate("a", 6_000)}
      cursor = Cursor.encode(value)

      assert byte_size(cursor) <= 8_192
      assert Cursor.decode(cursor) == {:ok, value}
    end

    test "default maximum size can be overridden" do
      value = %{name: String.duplicate("a", 10_000)}
      cursor = Cursor.encode(value)

      assert Cursor.decode(cursor) == :error

      assert Cursor.decode(cursor, max_cursor_size: 100_000) == {:ok, value}

      assert_raise Flop.InvalidCursorError, fn ->
        Cursor.decode!(cursor)
      end

      assert Cursor.decode!(cursor, max_cursor_size: 100_000) == value
    end
  end
end
