defmodule Flop.MetaTest do
  use ExUnit.Case, async: true

  doctest Flop.Meta, import: true

  describe "with_errors/3" do
    test "sorts filters by numeric index, not lexicographic" do
      params = %{
        "filters" => %{
          "10" => %{"field" => "name", "value" => "z"},
          "2" => %{"field" => "name", "value" => "a"}
        }
      }

      meta = Flop.Meta.with_errors(params, [], [])

      assert meta.params["filters"] == [
               %{"field" => "name", "value" => "a"},
               %{"field" => "name", "value" => "z"}
             ]
    end

    test "preserves the original map when any key is non-integer" do
      # Round-trips the malformed shape into meta.params so the caller can
      # see exactly what they sent, instead of partially normalising it.
      params = %{
        "filters" => %{
          "0" => %{"field" => "name", "value" => "a"},
          "bogus_xyz" => "x"
        }
      }

      meta = Flop.Meta.with_errors(params, [], [])

      assert meta.params["filters"] == %{
               "0" => %{"field" => "name", "value" => "a"},
               "bogus_xyz" => "x"
             }
    end

    test "does not raise on a filter map keyed entirely by field names" do
      params = %{"filters" => %{"transport_type_code" => "SEA"}}

      meta = Flop.Meta.with_errors(params, [], [])

      assert meta.params["filters"] == %{"transport_type_code" => "SEA"}
    end

    test "leaves list-form filters untouched" do
      params = %{"filters" => [%{"field" => "name", "value" => "a"}]}

      meta = Flop.Meta.with_errors(params, [], [])

      assert meta.params["filters"] == [%{"field" => "name", "value" => "a"}]
    end
  end

  describe "Flop.validate/2" do
    test "does not raise when filters is a map keyed by field names" do
      # Regression: previously raised ArgumentError in
      # Flop.Meta.filters_to_list/1 via with_errors/3, before validate/2
      # could return its usual {:error, %Flop.Meta{}} tuple.
      assert {:error, %Flop.Meta{} = meta} =
               Flop.validate(%{"filters" => %{"transport_type_code" => "SEA"}})

      # Original shape preserved so callers can see what they sent.
      assert meta.params["filters"] == %{"transport_type_code" => "SEA"}
    end
  end
end
