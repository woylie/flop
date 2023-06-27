defmodule Flop.RelayTest do
  use ExUnit.Case, async: true

  doctest Flop.Relay

  describe "edges_from_result/2" do
    test "allows edges to be nil" do
      flop = %Flop{order_by: [:name]}
      meta = %Flop.Meta{flop: flop}
      items = [{%Flop.Fruit{name: "Apple"}, nil}]
      func = fn {fruit, _edge}, order_by -> Map.take(fruit, order_by) end

      assert Flop.Relay.edges_from_result({items, meta},
               cursor_value_func: func
             ) == [
               %{
                 cursor: "g3QAAAABdwRuYW1lbQAAAAVBcHBsZQ==",
                 node: %Flop.Fruit{name: "Apple"}
               }
             ]
    end
  end
end
