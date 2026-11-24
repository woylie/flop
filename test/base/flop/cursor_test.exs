defmodule Flop.CursorTest do
  use ExUnit.Case, async: true

  alias Flop.Cursor

  doctest Flop.Cursor

  describe "encoding/decoding" do
    test "encoding and decoding returns original value" do
      value = %{a: "b", c: [:d], e: {:f, "g", 5}}
      assert value |> Cursor.encode() |> Cursor.decode() == {:ok, value}
    end

    test "encodes date, time and decimal structs as strings" do
      value = %{
        date: ~D[2020-09-25],
        datetime: ~U[2020-09-25 11:09:41.123Z],
        decimal: Decimal.new("1.50"),
        naive_datetime: ~N[2020-09-25 11:09:41],
        time: ~T[11:09:41.123456]
      }

      assert value |> Cursor.encode() |> Cursor.decode() ==
               {:ok,
                %{
                  date: "2020-09-25",
                  datetime: "2020-09-25T11:09:41.123Z",
                  decimal: "1.50",
                  naive_datetime: "2020-09-25T11:09:41",
                  time: "11:09:41.123456"
                }}
    end

    test "encodes other structs as maps" do
      value = %{a: [{%URI{host: "example.com"}}]}

      assert {:ok, %{a: [{%{host: "example.com"} = uri}]}} =
               value |> Cursor.encode() |> Cursor.decode()

      refute is_map_key(uri, :__struct__)
    end

    test "rejects a cursor that contains a struct" do
      cursor =
        %{inserted_at: %{DateTime.utc_now() | year: %URI{}}}
        |> :erlang.term_to_binary()
        |> Base.url_encode64()

      assert Cursor.decode(cursor) == :error
    end

    test "rejects a cursor that contains a map with a struct key" do
      cursor =
        %{a: %{__struct__: "Date", year: 2020}}
        |> :erlang.term_to_binary()
        |> Base.url_encode64()

      assert Cursor.decode(cursor) == :error
    end

    test "rejects a cursor that contains an improper list" do
      cursor =
        %{a: ["PT1S" | "PT2S"]}
        |> :erlang.term_to_binary()
        |> Base.url_encode64()

      assert Cursor.decode(cursor) == :error
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

    test "leaves the cursor out of the error message" do
      error =
        assert_raise Flop.InvalidCursorError, fn -> Cursor.decode!("AAAH") end

      assert error.cursor == "AAAH"
      refute Exception.message(error) =~ "AAAH"
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
