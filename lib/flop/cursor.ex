defmodule Flop.Cursor do
  @moduledoc """
  Functions for encoding, decoding and extracting cursor values.
  """

  @doc """
  Encodes a cursor value.

      Flop.Cursor.encode(%{email: "peter@mail", name: "Peter"})
      "g3QAAAACdwRuYW1lbQAAAAVQZXRlcncFZW1haWxtAAAACnBldGVyQG1haWw="
  """
  @doc since: "0.8.0"
  @spec encode(map()) :: binary()
  def encode(key) do
    Base.url_encode64(:erlang.term_to_binary(key, minor_version: 2))
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

  Trying to decode a cursor that contains non-existent atoms also results in an
  error.

      iex> Flop.Cursor.decode("g3QAAAABZAAGYmFybmV5ZAAGcnViYmVs")
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
  """
  @doc since: "0.9.0"
  @spec decode!(binary()) :: map()
  def decode!(cursor) do
    case decode(cursor) do
      {:ok, decoded} -> decoded
      :error -> raise Flop.InvalidCursorError, cursor: cursor
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
      {"g3QAAAABdwRuYW1lbQAAAARNYXJ5", "g3QAAAABdwRuYW1lbQAAAAVQZXRlcg=="}
      iex>
      iex> Flop.Cursor.decode(start_cursor)
      {:ok, %{name: "Mary"}}
      iex> Flop.Cursor.decode(end_cursor)
      {:ok, %{name: "Peter"}}

  If the result set is empty, the cursor values will be `nil`.

      iex> Flop.Cursor.get_cursors([], [:id])
      {nil, nil}

  The default function to retrieve the cursor value from the query result is
  `Flop.Cursor.get_cursor_from_node/2`, which expects the query result to be a
  map or a 2-tuple. You can set the `cursor_value_func` option to use
  another function. Flop also comes with `Flop.Cursor.get_cursor_from_edge/2`.

  If the records in the result set are not maps, you can define a custom cursor
  value function like this:

      iex> results = [{"Mary", 1936}, {"Paul", 1937}, {"Peter", 1938}]
      iex> cursor_func = fn {name, year}, order_fields ->
      ...>   Enum.into(order_fields, %{}, fn
      ...>     :name -> {:name, name}
      ...>     :year -> {:year, year}
      ...>   end)
      ...> end
      iex> opts = [cursor_value_func: cursor_func]
      iex>
      iex> {start_cursor, end_cursor} =
      ...>   Flop.Cursor.get_cursors(results, [:name, :year], opts)
      {"g3QAAAACdwRuYW1lbQAAAARNYXJ5dwR5ZWFyYgAAB5A=",
        "g3QAAAACdwRuYW1lbQAAAAVQZXRlcncEeWVhcmIAAAeS"}
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
    cursor_value_func = cursor_value_func(opts)

    case results do
      [] ->
        {nil, nil}

      [first | _] ->
        {
          first |> cursor_value_func.(order_by) |> encode(),
          results
          |> List.last()
          |> cursor_value_func.(order_by)
          |> encode()
        }
    end
  end

  @doc """
  Takes a tuple with the node and the edge and the `order_by` field list and
  returns the cursor value derived from the edge map.

  If a map is passed instead of a tuple, it retrieves the cursor value from that
  map.

  This function can be used for the `:cursor_value_func` option. See also
  `Flop.Cursor.get_cursor_from_node/2`.

      iex> record = %{id: 20, name: "George", age: 62}
      iex> edge = %{id: 25, relation: "sibling"}
      iex>
      iex> Flop.Cursor.get_cursor_from_edge({record, edge}, [:id])
      %{id: 25}
      iex> Flop.Cursor.get_cursor_from_edge({record, edge}, [:id, :relation])
      %{id: 25, relation: "sibling"}
      iex> Flop.Cursor.get_cursor_from_edge(record, [:id])
      %{id: 20}

  If the edge is a struct that derives `Flop.Schema`, join and compound fields
  are resolved according to the configuration.

      iex> record = %{id: 25, relation: "sibling"}
      iex> edge = %MyApp.Pet{
      ...>   name: "George",
      ...>   owner: %MyApp.Owner{name: "Carl"}
      ...> }
      iex>
      iex> Flop.Cursor.get_cursor_from_edge({record, edge}, [:owner_name])
      %{owner_name: "Carl"}
      iex> Flop.Cursor.get_cursor_from_edge(edge, [:owner_name])
      %{owner_name: "Carl"}

      iex> record = %{id: 25, relation: "sibling"}
      iex> edge = %MyApp.Pet{
      ...>   given_name: "George",
      ...>   family_name: "Gooney"
      ...> }
      iex> Flop.Cursor.get_cursor_from_edge({record, edge}, [:full_name])
      %{full_name: "Gooney George"}
      iex> Flop.Cursor.get_cursor_from_edge(edge, [:full_name])
      %{full_name: "Gooney George"}
  """
  @doc since: "0.11.0"
  @spec get_cursor_from_edge({map, map} | map, [atom]) :: map
  def get_cursor_from_edge({_, %{} = item}, order_by) do
    Enum.into(order_by, %{}, fn field ->
      {field, Flop.Schema.get_field(item, field)}
    end)
  end

  def get_cursor_from_edge(%{} = item, order_by) do
    Enum.into(order_by, %{}, fn field ->
      {field, Flop.Schema.get_field(item, field)}
    end)
  end

  @doc """
  Takes a tuple with the node and the edge and the `order_by` field list and
  returns the cursor value derived from the node map.

  If a map is passed instead of a tuple, it retrieves the cursor value from that
  map.

  This function is used as a default if no `:cursor_value_func` option is
  set. See also `Flop.Cursor.get_cursor_from_edge/2`.

      iex> record = %{id: 20, name: "George", age: 62}
      iex> edge = %{id: 25, relation: "sibling"}
      iex>
      iex> Flop.Cursor.get_cursor_from_node({record, edge}, [:id])
      %{id: 20}
      iex> Flop.Cursor.get_cursor_from_node({record, edge}, [:id, :name])
      %{id: 20, name: "George"}
      iex> Flop.Cursor.get_cursor_from_node(record, [:id])
      %{id: 20}

  If the node is a struct that derives `Flop.Schema`, join and compound fields
  are resolved according to the configuration.

      iex> record = %MyApp.Pet{
      ...>   name: "George",
      ...>   owner: %MyApp.Owner{name: "Carl"}
      ...> }
      iex> edge = %{id: 25, relation: "sibling"}
      iex>
      iex> Flop.Cursor.get_cursor_from_node({record, edge}, [:owner_name])
      %{owner_name: "Carl"}
      iex> Flop.Cursor.get_cursor_from_node(record, [:owner_name])
      %{owner_name: "Carl"}

      iex> record = %MyApp.Pet{
      ...>   given_name: "George",
      ...>   family_name: "Gooney"
      ...> }
      iex> edge = %{id: 25, relation: "sibling"}
      iex> Flop.Cursor.get_cursor_from_node({record, edge}, [:full_name])
      %{full_name: "Gooney George"}
      iex> Flop.Cursor.get_cursor_from_node(record, [:full_name])
      %{full_name: "Gooney George"}
  """
  @doc since: "0.11.0"
  @spec get_cursor_from_node({map, map} | map, [atom]) :: map
  def get_cursor_from_node({%{} = item, _}, order_by) do
    Enum.into(order_by, %{}, fn field ->
      {field, Flop.Schema.get_field(item, field)}
    end)
  end

  def get_cursor_from_node(%{} = item, order_by) do
    Enum.into(order_by, %{}, fn field ->
      {field, Flop.Schema.get_field(item, field)}
    end)
  end

  @doc false
  def cursor_value_func(opts \\ []) do
    opts[:cursor_value_func] ||
      Application.get_env(:flop, :cursor_value_func) ||
      (&get_cursor_from_node/2)
  end
end
