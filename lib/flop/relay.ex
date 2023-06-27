defmodule Flop.Relay do
  @moduledoc """
  Helpers to turn query results into Relay formats.
  """

  alias Flop.Cursor
  alias Flop.Meta

  @type connection :: %{
          edges: [edge()],
          page_info: page_info()
        }

  @type edge :: %{
          cursor: binary,
          node: any
        }

  @type page_info :: %{
          has_previous_page: boolean,
          has_next_page: boolean,
          start_cursor: binary,
          end_cursor: binary
        }

  @doc """
  Takes the query results returned by `Flop.run/3`, `Flop.validate_and_run/3`
  or `Flop.validate_and_run!/3` and turns them into the Relay connection
  format.

  ## Example

      iex> flop = %Flop{order_by: [:name]}
      iex> meta = %Flop.Meta{flop: flop, start_cursor: "a", end_cursor: "b"}
      iex> result = {[%MyApp.Fruit{name: "Apple", family: "Rosaceae"}], meta}
      iex> Flop.Relay.connection_from_result(result)
      %{
        edges: [
          %{
            cursor: "g3QAAAABdwRuYW1lbQAAAAVBcHBsZQ==",
            node: %MyApp.Fruit{family: "Rosaceae", id: nil, name: "Apple"}
          }
        ],
        page_info: %{
          end_cursor: "b",
          has_next_page: false,
          has_previous_page: false,
          start_cursor: "a"
        }
      }

  See `Flop.Relay.edges_from_result/2` for an example of adding additional
  fields to the edge.

  ## Options

  - `:cursor_value_func`: 2-arity function that takes an item from the query
    result and the `order_by` fields and returns the unencoded cursor value.
  """
  @doc since: "0.8.0"
  @spec connection_from_result({[any], Meta.t()}, [Flop.option()]) ::
          connection()
  def connection_from_result({items, meta}, opts \\ []) when is_list(items) do
    %{
      edges: edges_from_result({items, meta}, opts),
      page_info: page_info_from_meta(meta)
    }
  end

  @doc """
  Takes a `Flop.Meta` struct and returns a map with the Relay page info.

  ## Example

      iex> Flop.Relay.page_info_from_meta(%Flop.Meta{
      ...>    has_previous_page?: true,
      ...>    has_next_page?: true,
      ...>    start_cursor: "a",
      ...>    end_cursor: "b"
      ...> })
      %{
        has_previous_page: true,
        has_next_page: true,
        start_cursor: "a",
        end_cursor: "b"
      }
  """
  @doc since: "0.8.0"
  @spec page_info_from_meta(Meta.t()) :: page_info()
  def page_info_from_meta(%Meta{} = meta) do
    %{
      has_previous_page: meta.has_previous_page? || false,
      has_next_page: meta.has_next_page? || false,
      start_cursor: meta.start_cursor,
      end_cursor: meta.end_cursor
    }
  end

  @doc """
  Turns a list of query results into Relay edges.

  ## Simple queries

  If your query returns a list of maps or structs, the function will return
  the a list of edges with `:cursor` and `:node` as only fields.

      iex> flop = %Flop{order_by: [:name]}
      iex> meta = %Flop.Meta{flop: flop}
      iex> result = {[%MyApp.Fruit{name: "Apple", family: "Rosaceae"}], meta}
      iex> Flop.Relay.edges_from_result(result)
      [
        %{
          cursor: "g3QAAAABdwRuYW1lbQAAAAVBcHBsZQ==",
          node: %MyApp.Fruit{name: "Apple", family: "Rosaceae"}
        }
      ]

  ## Supplying additional edge information

  If the query result is a list of 2-tuples, this is interpreted as a tuple
  of the node information and the edge information. For example, if you have a
  query like this:

      Group
      |> where([g], g.id == ^group_id)
      |> join(:left, [g], m in assoc(g, :members))
      |> select([g, m], {m, map(m, [:role])})

  Then your query result looks something like:

      [{%Member{id: 242, name: "Carl"}, %{role: :owner}}]

  In this case, the members are the nodes, and the maps with the roles is seen
  as edge information.

      [
        %{
          cursor: "AE98RNSTNGN",
          node: %Member{id: 242, name: "Carl"},
          role: :owner
        }
      ]

  Note that in this case, the whole tuple will be passed to the cursor value
  function, so that the cursor can be based on both node and edge fields.

  Here's an example with fruit that overrides the cursor value function:

      iex> flop = %Flop{order_by: [:name]}
      iex> meta = %Flop.Meta{flop: flop}
      iex> items = [{%MyApp.Fruit{name: "Apple"}, %{preparation:  :grated}}]
      iex> func = fn {fruit, _edge}, order_by -> Map.take(fruit, order_by) end
      iex> Flop.Relay.edges_from_result(
      ...>   {items, meta},
      ...>   cursor_value_func: func
      ...> )
      [
        %{
          cursor: "g3QAAAABdwRuYW1lbQAAAAVBcHBsZQ==",
          node: %MyApp.Fruit{name: "Apple"},
          preparation: :grated
        }
      ]

  ## Options

  - `:cursor_value_func`: 2-arity function that takes an item from the query
    result and the `order_by` fields and returns the unencoded cursor value.
  """
  @doc since: "0.8.0"
  @spec edges_from_result({[{any, any}] | [any], Meta.t()}, [Flop.option()]) ::
          [edge()]
  def edges_from_result(
        {items, %Meta{flop: %Flop{order_by: order_by}}},
        opts \\ []
      ) do
    cursor_value_func = Cursor.cursor_value_func(opts)
    Enum.map(items, &build_edge(&1, order_by, cursor_value_func))
  end

  defp build_edge({node, nil}, order_by, cursor_value_func) do
    build_edge({node, %{}}, order_by, cursor_value_func)
  end

  defp build_edge({node, edge_info} = item, order_by, cursor_value_func) do
    edge_info
    |> Map.put(:cursor, get_cursor(item, order_by, cursor_value_func))
    |> Map.put(:node, node)
  end

  defp build_edge(node, order_by, cursor_value_func) do
    %{
      cursor: get_cursor(node, order_by, cursor_value_func),
      node: node
    }
  end

  defp get_cursor(node, order_by, cursor_value_func) do
    node |> cursor_value_func.(order_by) |> Cursor.encode()
  end
end
