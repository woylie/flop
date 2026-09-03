defmodule Flop.CursorTest do
  use ExUnit.Case, async: true

  alias Flop.Cursor

  doctest Flop.Cursor

  describe "get_cursor_from_node/3" do
    test "resolves a field path against the schema for a plain map" do
      map = %{name: "George", owner: %{name: "Ann"}}

      assert Cursor.get_cursor_from_node(map, [:owner_name], for: MyApp.Pet) ==
               %{owner_name: "Ann"}
    end

    test "without a schema a plain map reads the field name at the top level" do
      map = %{name: "George", owner: %{name: "Ann"}}

      assert Cursor.get_cursor_from_node(map, [:owner_name]) ==
               %{owner_name: nil}
    end

    test "a struct resolves the path either way" do
      pet = %MyApp.Pet{name: "George", owner: %MyApp.Owner{name: "Ann"}}

      assert Cursor.get_cursor_from_node(pet, [:owner_name]) ==
               %{owner_name: "Ann"}

      assert Cursor.get_cursor_from_node(pet, [:owner_name], for: MyApp.Pet) ==
               %{owner_name: "Ann"}
    end
  end

  describe "get_cursors/3" do
    test "passes the schema to an arity-3 cursor value function" do
      map = %{name: "George", owner: %{name: "Ann"}}

      {start_cursor, _} =
        Cursor.get_cursors([map], [:owner_name], for: MyApp.Pet)

      assert Cursor.decode!(start_cursor) == %{owner_name: "Ann"}
    end

    test "an arity-2 cursor value function is called with two arguments" do
      func = fn item, order_by -> Map.take(item, order_by) end

      {start_cursor, _} =
        Cursor.get_cursors([%{name: "George"}], [:name],
          for: MyApp.Pet,
          cursor_value_func: func
        )

      assert Cursor.decode!(start_cursor) == %{name: "George"}
    end

    test "an arity-3 cursor value function receives the options" do
      func = fn _item, _order_by, opts -> %{schema: opts[:for]} end

      {start_cursor, _} =
        Cursor.get_cursors([%{}], [:name],
          for: MyApp.Pet,
          cursor_value_func: func
        )

      assert Cursor.decode!(start_cursor) == %{schema: MyApp.Pet}
    end

    test "an arity-3 cursor value function can read extra_opts" do
      func = fn _item, _order_by, opts ->
        %{tz: opts[:extra_opts][:timezone]}
      end

      {start_cursor, _} =
        Cursor.get_cursors([%{}], [:name],
          for: MyApp.Pet,
          extra_opts: [timezone: "Asia/Tokyo"],
          cursor_value_func: func
        )

      assert Cursor.decode!(start_cursor) == %{tz: "Asia/Tokyo"}
    end
  end

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

    test "rejects a compressed term" do
      payload = %{name: String.duplicate("a", 1_000_000)}

      cursor =
        payload
        |> :erlang.term_to_binary(compressed: 9)
        |> Base.url_encode64()

      # cursor is below maximum size when compressed, but exceeds it when
      # uncompressed
      assert byte_size(cursor) < 8_192
      assert byte_size(:erlang.term_to_binary(payload)) > 1_000_000

      assert Cursor.decode(cursor) == :error
      assert_raise Flop.InvalidCursorError, fn -> Cursor.decode!(cursor) end
    end
  end
end
