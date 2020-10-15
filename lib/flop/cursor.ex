defmodule Flop.Cursor do
  @moduledoc """
  Functions for encoding, decoding and extracting cursor values.
  """

  @doc """
  Encodes a cursor value.

      iex> Flop.Cursor.encode(%{name: "Peter", email: "peter@mail"})
      "g3QAAAACZAAFZW1haWxtAAAACnBldGVyQG1haWxkAARuYW1lbQAAAAVQZXRlcg=="
  """
  @doc since: "0.8.0"
  @spec encode(map()) :: binary()
  def encode(key) do
    Base.url_encode64(:erlang.term_to_binary(key))
  end

  @doc """
  Decodes a cursor value.

  Returns `:error` if the cursor cannot be decoded or the decoded term is not a
  map with atom keys.

      iex> Flop.Cursor.decode("g3QAAAABZAACaWRiAAACDg==")
      {:ok, %{id: 526}}

      iex> Flop.Cursor.decode("AAAH")
      :error

      iex> f = fn a -> a + 1 end
      iex> cursor = Flop.Cursor.encode(%{a: f})
      iex> Flop.Cursor.decode(cursor)
      :error

      iex> cursor = Flop.Cursor.encode(a: "b")
      iex> Flop.Cursor.decode(cursor)
      :error

      iex> cursor = Flop.Cursor.encode(%{"a" => "b"})
      iex> Flop.Cursor.decode(cursor)
      :error
  """
  @doc since: "0.8.0"
  @spec decode(binary()) :: {:ok, map()} | :error
  def decode(cursor) do
    with {:ok, binary} <- Base.url_decode64(cursor),
         {:ok, term} <- safe_binary_to_term(binary) do
      sanitize(term)

      if is_map(term) && term |> Map.keys() |> Enum.all?(&is_atom/1),
        do: {:ok, term},
        else: :error
    end
  rescue
    _e in RuntimeError -> :error
  end

  @doc """
  Same as `Flop.Cursor.decode/1`, but raises an error if the cursor is invalid.

      iex> Flop.Cursor.decode!("g3QAAAABZAACaWRiAAACDg==")
      %{id: 526}

      iex> Flop.Cursor.decode!("AAAH")
      ** (RuntimeError) invalid cursor
  """
  @doc since: "0.9.0"
  @spec decode!(binary()) :: map()
  def decode!(cursor) do
    case decode(cursor) do
      {:ok, decoded} -> decoded
      :error -> raise "invalid cursor"
    end
  end

  defp safe_binary_to_term(term) do
    {:ok, :erlang.binary_to_term(term, [:safe])}
  rescue
    _e in ArgumentError -> :error
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

      iex> results = [%{name: "Mary"}, %{name: "Paul"}, %{name: "Peter"}]
      iex> order_by = [:name]
      iex>
      iex> {start_cursor, end_cursor} =
      ...>   Flop.Cursor.get_cursors(results, order_by)
      {"g3QAAAABZAAEbmFtZW0AAAAETWFyeQ==", "g3QAAAABZAAEbmFtZW0AAAAFUGV0ZXI="}
      iex>
      iex> Flop.Cursor.decode(start_cursor)
      {:ok, %{name: "Mary"}}
      iex> Flop.Cursor.decode(end_cursor)
      {:ok, %{name: "Peter"}}

  If the result set is empty, the cursor values will be `nil`.

      iex> Flop.Cursor.get_cursors([], [:id])
      {nil, nil}

  If the records in the result set are not maps, you can pass a custom cursor
  value function.

      iex> results = [{"Mary", 1936}, {"Paul", 1937}, {"Peter", 1938}]
      iex> cursor_func = fn {name, year}, order_fields ->
      ...>   Enum.into(order_fields, %{}, fn
      ...>     :name -> {:name, name}
      ...>     :year -> {:year, year}
      ...>   end)
      ...> end
      iex> opts = [get_cursor_value_func: cursor_func]
      iex>
      iex> {start_cursor, end_cursor} =
      ...>   Flop.Cursor.get_cursors(results, [:name, :year], opts)
      {"g3QAAAACZAAEbmFtZW0AAAAETWFyeWQABHllYXJiAAAHkA==",
        "g3QAAAACZAAEbmFtZW0AAAAFUGV0ZXJkAAR5ZWFyYgAAB5I="}
      iex>
      iex> Flop.Cursor.decode(start_cursor)
      {:ok, %{name: "Mary", year: 1936}}
      iex> Flop.Cursor.decode(end_cursor)
      {:ok, %{name: "Peter", year: 1938}}
  """
  @doc since: "0.8.0"
  @spec get_cursors([any], [atom], [Flop.option()]) ::
          {binary(), binary()} | {nil, nil}
  def get_cursors(results, order_by, opts \\ []) do
    get_cursor_value_func = get_cursor_value_func(opts)

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

      iex> record = %{id: 20, name: "George", age: 62}
      iex>
      iex> Flop.Cursor.get_cursor_from_map(record, [:id])
      %{id: 20}
      iex> Flop.Cursor.get_cursor_from_map(record, [:name, :age])
      %{age: 62, name: "George"}
  """
  @doc since: "0.8.0"
  @spec get_cursor_from_map(map, [atom]) :: map
  def get_cursor_from_map(item, order_by) do
    Map.take(item, order_by)
  end

  @doc false
  def get_cursor_value_func(opts \\ []) do
    opts[:get_cursor_value_func] ||
      Application.get_env(:flop, :get_cursor_value_func) ||
      (&get_cursor_from_map/2)
  end
end
