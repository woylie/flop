defmodule Flop.Cursor do
  @moduledoc """
  Functions for encoding, decoding and extracting cursor values.
  """

  @doc """
  Encodes a cursor value.
  """
  @doc since: "0.8.0"
  @spec encode(map()) :: binary()
  def encode(key) do
    Base.url_encode64(:erlang.term_to_binary(key))
  end

  @doc """
  Decodes a cursor value.
  """
  @doc since: "0.8.0"
  @spec decode(binary()) :: map()
  def decode(encoded) do
    term =
      encoded
      |> Base.url_decode64!()
      |> :erlang.binary_to_term([:safe])

    sanitize(term)
    term
  end

  defp sanitize(term)
       when is_atom(term) or is_number(term) or is_binary(term) do
    term
  end

  defp sanitize([]), do: []
  defp sanitize([h | t]), do: [sanitize(h) | sanitize(t)]

  defp sanitize(%{} = term) do
    :maps.fold(
      fn key, value, acc ->
        sanitize(key)
        sanitize(value)
        acc
      end,
      term,
      term
    )
  end

  defp sanitize(term) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> sanitize()
  end

  defp sanitize(_) do
    raise "invalid cursor value"
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
          first |> get_cursor_value_func.(order_by) |> encode(),
          results
          |> List.last()
          |> get_cursor_value_func.(order_by)
          |> encode()
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
