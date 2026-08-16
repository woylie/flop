defmodule Flop.RelayTest do
  use ExUnit.Case, async: true

  doctest Flop.Relay

  describe "edges_from_result/2" do
    test "allows edges to be nil" do
      flop = %Flop{order_by: [:name]}
      meta = %Flop.Meta{flop: flop}
      items = [{%MyApp.Fruit{name: "Apple"}, nil}]
      func = fn {fruit, _edge}, order_by -> Map.take(fruit, order_by) end

      assert Flop.Relay.edges_from_result({items, meta},
               cursor_value_func: func
             ) == [
               %{
                 cursor: "g3QAAAABdwRuYW1lbQAAAAVBcHBsZQ==",
                 node: %MyApp.Fruit{name: "Apple"}
               }
             ]
    end

    test "includes the tiebreaker, like the cursors in the meta struct" do
      flop = %Flop{order_by: [:name]}
      meta = %Flop.Meta{flop: flop, opts: [for: MyApp.Fruit]}
      items = [%MyApp.Fruit{id: "1", name: "Apple"}]

      assert [%{cursor: cursor}] = Flop.Relay.edges_from_result({items, meta})

      assert cursor |> Flop.Cursor.decode!() |> Map.keys() |> Enum.sort() ==
               [:id, :name]
    end
  end
end
