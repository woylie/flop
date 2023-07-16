defmodule Flop.SchemaTest do
  use ExUnit.Case, async: true

  alias __MODULE__.Panini
  alias Flop.Schema

  doctest Flop.Schema, import: true

  defmodule Panini do
    @derive {Flop.Schema,
             filterable: [:name, :age],
             sortable: [:name, :age, :topping_count],
             default_limit: 20,
             max_limit: 50,
             default_order: %{
               order_by: [:name, :age],
               order_directions: [:desc, :asc]
             },
             compound_fields: [name_or_email: [:name, :email]],
             join_fields: [topping_name: {:toppings, :name}],
             alias_fields: [:topping_count],
             custom_fields: [
               inserted_at: [
                 filter: {__MODULE__, :date_filter, [some: "option"]},
                 ecto_type: :date
               ]
             ]}

    defstruct [:name, :email, :age]
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

  test "field_type/2 returns :normal tuple for normal fields" do
    assert Schema.field_type(%Panini{}, :name) == {:normal, :name}
    assert Schema.field_type(%Panini{}, :age) == {:normal, :age}
  end

  test "field_type/2 returns config for compound fields" do
    assert Schema.field_type(%Panini{}, :name_or_email) ==
             {:compound, [:name, :email]}
  end

  test "field_type/2 returns config for join fields" do
    assert Schema.field_type(%Panini{}, :topping_name) ==
             {:join,
              %{
                binding: :toppings,
                field: :name,
                path: [:toppings, :name],
                ecto_type: nil
              }}
  end

  test "field_type/2 returns config for custom fields" do
    assert Schema.field_type(%Panini{}, :inserted_at) ==
             {:custom,
              %{
                filter: {Panini, :date_filter, [some: "option"]},
                ecto_type: :date,
                operators: nil,
                bindings: []
              }}
  end

  test "max_limit/1 returns the max limit passed as option" do
    assert Schema.max_limit(%Panini{}) == 50
  end

  test "calling apply_order_by/3 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.apply_order_by(%{}, nil, nil)
    end
  end

  test "calling cursor_dynamic/3 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.cursor_dynamic(%{}, nil, nil)
    end
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

  test "calling field_type/2 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.field_type(%{}, :field)
    end
  end

  test "calling field_info/2 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.field_info(%{}, :field)
    end
  end

  test "calling filterable/1 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.filterable(%{})
    end
  end

  test "calling get_field/2 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.get_field(:a, :field)
    end
  end

  test "get_field/2 has default implementation for maps" do
    assert Schema.get_field(%{wait: "what?"}, :wait) == "what?"
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

  test "calling pagination_types/1 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.pagination_types(%{})
    end
  end

  test "calling default_pagination_type/1 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.default_pagination_type(%{})
    end
  end

  describe "__deriving__/3" do
    test "raises if default_pagination_type is not allowed" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Bulgur do
            @derive {
              Flop.Schema,
              filterable: [],
              sortable: [],
              default_pagination_type: :first,
              pagination_types: [:page]
            }
            defstruct [:name]
          end
        end

      assert error.message =~ "default pagination type not among allowed types"
    end

    test "raises if filterable field is unknown" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Pita do
            @derive {Flop.Schema, filterable: [:smell], sortable: []}
            defstruct [:name]
          end
        end

      assert error.message =~ "unknown filterable field"
    end

    test "raises if sortable field is unknown" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Marmelade do
            @derive {Flop.Schema, filterable: [], sortable: [:smell]}
            defstruct [:name]
          end
        end

      assert error.message =~ "unknown sortable field"
    end

    test "raises if default order field is not sortable" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Broomstick do
            @derive {
              Flop.Schema,
              filterable: [],
              sortable: [:name],
              default_order: %{order_by: [:age], order_directions: [:desc]}
            }
            defstruct [:name, :age]
          end
        end

      assert error.message =~ "invalid default order"
      assert error.message =~ "must be sortable"
    end

    test "raises if compound field references unknown field" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Potato do
            @derive {
              Flop.Schema,
              filterable: [],
              sortable: [],
              compound_fields: [full_name: [:family_name, :given_name]]
            }
            defstruct [:family_name]
          end
        end

      assert error.message =~ "unknown field"
    end

    test "raises if compound field uses existing join field name" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Cannelloni do
            @derive {
              Flop.Schema,
              filterable: [],
              sortable: [],
              join_fields: [name: {:eater, :name}],
              compound_fields: [name: [:name, :nickname]]
            }
            defstruct [:name, :nickname]
          end
        end

      assert error.message =~ "duplicate field"
    end

    test "raises if alias field uses existing compound field name" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Pickles do
            @derive {
              Flop.Schema,
              filterable: [],
              sortable: [],
              compound_fields: [name: [:name, :nickname]],
              alias_fields: [:name]
            }
            defstruct [:id]
          end
        end

      assert error.message =~ "duplicate field"
    end

    test "raises if alias field uses existing join field name" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Juice do
            @derive {
              Flop.Schema,
              filterable: [],
              sortable: [],
              join_fields: [owner_name: {:owner, :name}],
              alias_fields: [:owner_name]
            }
            defstruct [:id]
          end
        end

      assert error.message =~ "duplicate field"
    end

    test "raises if custom field uses existing compound field name" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Pasta do
            @derive {
              Flop.Schema,
              filterable: [],
              sortable: [],
              compound_fields: [name: [:name, :nickname]],
              custom_fields: [
                name: [
                  filter: {__MODULE__, :some_function, []}
                ]
              ]
            }
            defstruct [:id, :nickname]
          end
        end

      assert error.message =~ "duplicate field"
    end

    test "raises if custom field uses existing join field name" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Vegetable do
            @derive {
              Flop.Schema,
              filterable: [],
              sortable: [],
              join_fields: [owner_name: {:owner, :name}],
              custom_fields: [
                owner_name: [
                  filter: {__MODULE__, :some_function, []}
                ]
              ]
            }
            defstruct [:id]
          end
        end

      assert error.message =~ "duplicate field"
    end

    test "raises if custom field uses existing alias field name" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Cranberry do
            @derive {
              Flop.Schema,
              filterable: [],
              sortable: [],
              alias_fields: [:name],
              custom_fields: [
                name: [
                  filter: {__MODULE__, :some_function, []}
                ]
              ]
            }
            defstruct [:id]
          end
        end

      assert error.message =~ "duplicate field"
    end

    test "does not raise if alias field uses existing schema field name" do
      defmodule Vegetaburu do
        @derive {
          Flop.Schema,
          filterable: [], sortable: [], alias_fields: [:nickname]
        }
        defstruct [:name, :nickname]
      end
    end

    test "raises error if alias field is added to filterable list" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Bejitaburu do
            @derive {
              Flop.Schema,
              filterable: [:count], sortable: [], alias_fields: [:count]
            }
            defstruct [:id]
          end
        end

      assert error.message =~ "cannot filter by alias field"
    end
  end

  test "raises error if custom field is added to sortable list" do
    error =
      assert_raise ArgumentError, fn ->
        defmodule Parsley do
          @derive {
            Flop.Schema,
            filterable: [],
            sortable: [:inserted_at],
            custom_fields: [
              inserted_at: [filter: {__MODULE__, :some_function, []}]
            ]
          }
          defstruct [:id, :inserted_at]
        end
      end

    assert error.message =~ "cannot sort by custom field"
  end
end
