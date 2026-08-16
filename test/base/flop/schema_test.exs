defmodule Flop.SchemaTest do
  use ExUnit.Case, async: true

  alias __MODULE__.Panini
  alias Flop.Schema

  doctest Flop.Schema, import: true

  defmodule Panini do
    use Ecto.Schema

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
             join_fields: [
               topping_name: [
                 binding: :toppings,
                 field: :name,
                 ecto_type: :string
               ]
             ],
             alias_fields: [:topping_count],
             custom_fields: [
               inserted_at: [
                 filter: {__MODULE__, :date_filter, [some: "option"]},
                 ecto_type: :date
               ]
             ]}

    schema "paninis" do
      field :name, :string
      field :email, :string
      field :age, :integer
    end
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

  test "calling field_info/2 without deriving raises error" do
    assert_raise Protocol.UndefinedError, fn ->
      Schema.field_info(%{}, :field)
    end
  end

  test "field_info/2 raises error for unknown field" do
    error =
      assert_raise Flop.UnknownFieldError, fn ->
        Schema.field_info(%Panini{}, :nonexistent)
      end

    assert Exception.message(error) =~ "unknown field(s)"
    assert Exception.message(error) =~ ":nonexistent"
    assert Exception.message(error) =~ ":topping_count"
  end

  test "get_field/2 raises error for unknown field" do
    assert_raise Flop.UnknownFieldError, fn ->
      Schema.get_field(%Panini{}, :nonexistent)
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
      assert_raise Flop.InvalidDefaultPaginationTypeError, fn ->
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
    end

    test "raises if filterable field is unknown" do
      assert_raise Flop.UnknownFieldError, fn ->
        defmodule Pita do
          @derive {Flop.Schema, filterable: [:smell], sortable: []}
          defstruct [:name]
        end
      end
    end

    test "raises if sortable field is unknown" do
      assert_raise Flop.UnknownFieldError, fn ->
        defmodule Marmelade do
          @derive {Flop.Schema, filterable: [], sortable: [:smell]}
          defstruct [:name]
        end
      end
    end

    test "raises for a nil ecto_type on a custom field" do
      error =
        assert_raise Flop.InvalidConfigError, fn ->
          defmodule Tabbouleh do
            @derive {
              Flop.Schema,
              filterable: [:thing],
              sortable: [],
              adapter_opts: [
                custom_fields: [
                  thing: [filter: {__MODULE__, :filter, []}, ecto_type: nil]
                ]
              ]
            }
            defstruct [:name]
          end
        end

      assert Exception.message(error) =~
               "expected an Ecto type such as :string or :map, got: nil"
    end

    test "raises for a nil ecto_type on a join field" do
      error =
        assert_raise Flop.InvalidConfigError, fn ->
          defmodule Falafel do
            @derive {
              Flop.Schema,
              filterable: [:owner_name],
              sortable: [],
              adapter_opts: [
                join_fields: [
                  owner_name: [binding: :owner, field: :name, ecto_type: nil]
                ]
              ]
            }
            defstruct [:name]
          end
        end

      assert Exception.message(error) =~
               "expected an Ecto type such as :string or :map, got: nil"
    end

    test "raises for a nil ecto_type given with the legacy syntax" do
      error =
        assert_raise Flop.InvalidConfigError, fn ->
          defmodule Baklava do
            @derive {
              Flop.Schema,
              filterable: [:thing],
              sortable: [],
              custom_fields: [
                thing: [filter: {__MODULE__, :filter, []}, ecto_type: nil]
              ]
            }
            defstruct [:name]
          end
        end

      assert Exception.message(error) =~
               "expected an Ecto type such as :string or :map, got: nil"
    end

    test "raises if default order field is not sortable" do
      assert_raise Flop.InvalidDefaultOrderError, fn ->
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
              join_fields: [
                name: [
                  binding: :eater,
                  field: :name,
                  ecto_type: :string
                ]
              ],
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
              join_fields: [
                owner_name: [
                  binding: :owner,
                  field: :name,
                  ecto_type: :string
                ]
              ],
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
                  filter: {__MODULE__, :some_function, []},
                  ecto_type: :string
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
              join_fields: [
                owner_name: [
                  binding: :owner,
                  field: :name,
                  ecto_type: :string
                ]
              ],
              custom_fields: [
                owner_name: [
                  filter: {__MODULE__, :some_function, []},
                  ecto_type: :string
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
                  filter: {__MODULE__, :some_function, []},
                  ecto_type: :string
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

  test "field_info/2 returns parameterized type for ecto_enum" do
    assert %Flop.FieldInfo{ecto_type: ecto_type} =
             Schema.field_info(%MyApp.Owner{}, :pet_mood_as_enum)

    assert ecto_type ==
             Ecto.ParameterizedType.init(Ecto.Enum, values: [:happy, :playful])
  end

  test "casts filter values with ecto_enum type" do
    params = %{
      filters: [%{field: :pet_mood_as_enum, op: :==, value: "happy"}]
    }

    assert {:ok, %Flop{filters: [filter]}} =
             Flop.validate(params, for: MyApp.Owner)

    assert filter.value == :happy

    assert {:error, %Flop.Meta{}} =
             Flop.validate(
               %{filters: [%{field: :pet_mood_as_enum, op: :==, value: "sad"}]},
               for: MyApp.Owner
             )
  end

  test "raises error if a sortable custom field has no field_dynamic" do
    error =
      assert_raise ArgumentError, fn ->
        defmodule Parsley do
          @derive {
            Flop.Schema,
            filterable: [],
            sortable: [:inserted_at],
            custom_fields: [
              inserted_at: [
                filter: {__MODULE__, :some_function, []},
                ecto_type: :utc_datetime
              ]
            ]
          }
          defstruct [:id, :inserted_at]
        end
      end

    assert error.message =~
             "custom field without field_dynamic function marked as sortable"

    assert error.message =~ ":inserted_at"
  end

  test "raises error if a tiebreaker names an unknown field" do
    error =
      assert_raise Flop.UnknownFieldError, fn ->
        defmodule Chervil do
          @derive {
            Flop.Schema,
            filterable: [], sortable: [:name], tiebreaker: [asc: :nanoid]
          }
          defstruct [:id, :name]
        end
      end

    assert Exception.message(error) =~ "tiebreaker"
    assert Exception.message(error) =~ ":nanoid"
  end

  test "raises error if a tiebreaker names a compound field" do
    error =
      assert_raise ArgumentError, fn ->
        defmodule Lovage do
          @derive {
            Flop.Schema,
            filterable: [],
            sortable: [:full_name],
            tiebreaker: [asc: :full_name],
            compound_fields: [full_name: [:family_name, :given_name]]
          }
          defstruct [:id, :family_name, :given_name]
        end
      end

    assert error.message =~ "unsupported tiebreaker field"
  end

  test "raises error if a filterable custom field has no callback at all" do
    error =
      assert_raise ArgumentError, fn ->
        defmodule Sage do
          @derive {
            Flop.Schema,
            filterable: [:inserted_at],
            sortable: [],
            custom_fields: [inserted_at: [ecto_type: :utc_datetime]]
          }
          defstruct [:id, :inserted_at]
        end
      end

    assert error.message =~
             "custom field without a callback marked as filterable"

    assert error.message =~ ":inserted_at"
  end

  test "allows a filterable custom field with only field_dynamic" do
    defmodule Sorrel do
      @derive {
        Flop.Schema,
        filterable: [:inserted_at],
        sortable: [:inserted_at],
        custom_fields: [
          inserted_at: [
            field_dynamic: {__MODULE__, :field_dynamic, []},
            ecto_type: :utc_datetime
          ]
        ]
      }
      defstruct [:id, :inserted_at]
    end

    assert Schema.filterable(struct(Sorrel)) == [:inserted_at]
  end

  test "allows a custom field with only the callback it needs" do
    defmodule Thyme do
      @derive {
        Flop.Schema,
        filterable: [:filtered],
        sortable: [:sorted],
        custom_fields: [
          filtered: [
            filter: {__MODULE__, :filter, []},
            ecto_type: :string
          ],
          sorted: [
            field_dynamic: {__MODULE__, :field_dynamic, []},
            ecto_type: :string
          ]
        ]
      }
      defstruct [:id]
    end

    assert %Flop.FieldInfo{extra: %{type: :custom, field_dynamic: nil}} =
             Schema.field_info(struct(Thyme), :filtered)

    assert %Flop.FieldInfo{extra: %{type: :custom, filter: nil}} =
             Schema.field_info(struct(Thyme), :sorted)
  end
end
