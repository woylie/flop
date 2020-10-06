defmodule Flop.Cursor do
  @moduledoc """
  Functions for encoding, decoding and extracting cursor values.
  """

  @doc """
  Encodes a cursor value.
  """
  @doc since: "0.8.0"
  @spec encode_cursor(map()) :: binary()
  def encode_cursor(key) do
    Base.url_encode64(:erlang.term_to_binary(key))
  end

  @doc """
  Decodes a cursor value.
  """
  @doc since: "0.8.0"
  @spec decode_cursor(binary()) :: map()
  def decode_cursor(encoded) do
    :erlang.binary_to_term(Base.url_decode64!(encoded), [:safe])
  end

  @doc """
  Retrieves the start and end cursors from a query result.
  """
  @doc since: "0.8.0"
  @spec get_cursors([any], [atom], keyword) :: {binary(), binary()} | {nil, nil}
  def get_cursors(results, order_by, opts) do
    get_cursor_value_func =
      Keyword.get(opts, :get_cursor_value_func, &get_cursor_from_map/2)

    case results do
      [] ->
        {nil, nil}

      [first | _] ->
        {
          first |> get_cursor_value_func.(order_by) |> encode_cursor(),
          results
          |> List.last()
          |> get_cursor_value_func.(order_by)
          |> encode_cursor()
        }
    end
  end

  @doc """
  Takes a map or a struct and the `order_by` field list and returns the cursor
  value.

  This function is used as a default if no `:get_cursor_value_func` option is
  set.
  """
  @doc since: "0.8.0"
  @spec get_cursor_from_map(map, [atom]) :: map
  def get_cursor_from_map(item, order_by) do
    Map.take(item, order_by)
  end
end
