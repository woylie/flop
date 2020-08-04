defmodule Flop.SchemaTest do
  use ExUnit.Case, async: true

  alias __MODULE__.Panini
  alias Flop.Schema

  doctest Flop.Schema

  defmodule Panini do
    @derive {Flop.Schema,
             filterable: [],
             sortable: [],
             default_limit: 20,
             max_limit: 50,
             default_order_by: [:name, :age],
             default_order_directions: [:desc, :asc]}
    defstruct [:name, :age]
  end

  test "default_order/1 returns the default order passed as an option" do
    assert Schema.default_order(%Panini{}) == %{
             order_by: [:name, :age],
             order_directions: [:desc, :asc]
           }
  end

  test "default_limit/1 returns the default limit passed as option" do
    assert Schema.default_limit(%Panini{}) == 20
  end

  test "max_limit/1 returns the max limit passed as option" do
    assert Schema.max_limit(%Panini{}) == 50
  end

  test "__deriving__/3 raises if no filterable fields are set" do
    error =
      assert_raise ArgumentError, fn ->
        defmodule Vegetable do
          @derive {Flop.Schema, sortable: [:name]}
          defstruct [:name]
        end
      end

    assert error.message =~
             "have to set both the filterable and the sortable option"
  end

  test "__deriving__/3 raises if no sortable fields are set" do
    error =
      assert_raise ArgumentError, fn ->
        defmodule Beverage do
          use Ecto.Schema
          @derive {Flop.Schema, filterable: [:name]}
          defstruct [:name]
        end
      end

    assert error.message =~
             "have to set both the filterable and the sortable option"
  end

  test "calling default_limit/1 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.default_limit(%{})
    end
  end

  test "calling default_order/1 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.default_order(%{})
    end
  end

  test "calling filterable/1 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.filterable(%{})
    end
  end

  test "calling max_limit/1 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.max_limit(%{})
    end
  end

  test "calling sortable/1 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.sortable(%{})
    end
  end
end
