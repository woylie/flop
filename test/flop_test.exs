defmodule FlopTest do
  use ExUnit.Case
  doctest Flop

  import Ecto.Query, only: [from: 2]

  alias Flop
  alias Pet

  @base_query from p in Pet, where: p.age > 8, select: p.name

  describe "query/2" do
    test "adds order_by to query if set" do
      flop = %Flop{order_by: [:species, :name], order_directions: [:asc, :desc]}

      assert [
               %Ecto.Query.QueryExpr{
                 expr: [
                   asc: {{_, _, [_, :species]}, _, _},
                   desc: {{_, _, [_, :name]}, _, _}
                 ]
               }
             ] = Flop.query(Pet, flop).order_bys

      assert [
               %Ecto.Query.QueryExpr{
                 expr: [
                   asc: {{_, _, [_, :species]}, _, _},
                   desc: {{_, _, [_, :name]}, _, _}
                 ]
               }
             ] = Flop.query(@base_query, flop).order_bys
    end

    test "uses :asc as default direction" do
      flop = %Flop{order_by: [:species, :name], order_directions: nil}

      assert [
               %Ecto.Query.QueryExpr{
                 expr: [
                   asc: {{_, _, [_, :species]}, _, _},
                   asc: {{_, _, [_, :name]}, _, _}
                 ]
               }
             ] = Flop.query(Pet, flop).order_bys

      flop = %Flop{order_by: [:species, :name], order_directions: [:desc]}

      assert [
               %Ecto.Query.QueryExpr{
                 expr: [
                   desc: {{_, _, [_, :species]}, _, _},
                   asc: {{_, _, [_, :name]}, _, _}
                 ]
               }
             ] = Flop.query(Pet, flop).order_bys

      flop = %Flop{order_by: [:species], order_directions: [:desc]}

      assert [
               %Ecto.Query.QueryExpr{
                 expr: [desc: {{_, _, [_, :species]}, _, _}]
               }
             ] = Flop.query(Pet, flop).order_bys

      flop = %Flop{order_by: [:species], order_directions: [:desc, :desc]}

      assert [
               %Ecto.Query.QueryExpr{
                 expr: [desc: {{_, _, [_, :species]}, _, _}]
               }
             ] = Flop.query(Pet, flop).order_bys
    end

    test "leaves query unchanged if nil" do
      flop = %Flop{order_by: nil}

      assert Flop.query(Pet, flop) == Pet
      assert Flop.query(@base_query, flop) == @base_query
    end
  end
end
