defmodule Flop.SchemaTest do
  use ExUnit.Case, async: true

  alias __MODULE__.Panini
  alias Flop.Schema

  doctest Flop.Schema, import: true

  defmodule Panini do
    use Ecto.Schema
    use Flop.Schema

    @flop_options [
      filterable: [:name, :age],
      sortable: [:name, :age, :topping_count],
      default_limit: 20,
      max_limit: 50,
      max_filters: 5,
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
      ]
    ]

    schema "paninis" do
      field :name, :string
      field :email, :string
      field :age, :integer
    end
  end

  defmodule Chard do
    defstruct [:name]
  end

  defmodule Basil do
    use Flop.Schema

    @flop_options [
      adapter: Flop.TestAdapter,
      adapter_opts: [declared_fields: [name: :string, age: :integer]],
      filterable: [:name],
      sortable: [:name, :age],
      default_limit: 25
    ]
  end

  test "schema_option/2 returns the default order passed as an option" do
    assert Flop.schema_option(Panini, :default_order) == %{
             order_by: [:name, :age],
             order_directions: [:desc, :asc]
           }
  end

  test "schema_option/2 returns the default limit passed as option" do
    assert Flop.schema_option(Panini, :default_limit) == 20
  end

  test "schema_option/2 returns the max filters passed as option" do
    assert Flop.schema_option(Panini, :max_filters) == 5
  end

  test "schema_option/2 returns the max limit passed as option" do
    assert Flop.schema_option(Panini, :max_limit) == 50
  end

  test "schema_option/2 without deriving raises error" do
    assert_raise ArgumentError, fn ->
      Flop.schema_option(Chard, :default_limit)
    end
  end

  test "calling field_info/2 without using Flop.Schema raises error" do
    assert_raise ArgumentError, fn ->
      Schema.field_info(Chard, :field)
    end
  end

  test "field_info/2 raises error for unknown field" do
    error =
      assert_raise Flop.UnknownFieldError, fn ->
        Schema.field_info(Panini, :nonexistent)
      end

    assert Exception.message(error) =~ "unknown field(s)"
    assert Exception.message(error) =~ ":nonexistent"
    assert Exception.message(error) =~ ":topping_count"
  end

  test "get_field/2 raises error for unknown field" do
    assert_raise Flop.UnknownFieldError, fn ->
      Schema.get_field(Panini, %Panini{}, :nonexistent)
    end
  end

  test "calling get_field/3 without using Flop.Schema raises error" do
    assert_raise ArgumentError, fn ->
      Schema.get_field(Chard, %{}, :field)
    end
  end

  describe "schema module without struct" do
    test "implements the behaviour" do
      refute function_exported?(Basil, :__struct__, 0)
      assert function_exported?(Basil, :__flop_schema__, 0)
    end

    test "field_info/2 returns a field declared in adapter_opts" do
      assert Schema.field_info(Basil, :name) == %Flop.FieldInfo{
               ecto_type: :string,
               extra: %{type: :normal, field: :name}
             }
    end

    test "get_field/3 reads the field from a map" do
      assert Schema.get_field(Basil, %{name: "George"}, :name) == "George"
    end

    test "primary_key/1 is empty" do
      assert Schema.primary_key(Basil) == []
    end

    test "the options resolve" do
      assert Flop.get_option(:default_limit, for: Basil) == 25
      assert Flop.allowed_fields(:sortable, for: Basil) == [:name, :age]
      assert Flop.allowed_fields(:filterable, for: Basil) == [:name]
    end

    test "validation applies the declared fields" do
      assert {:ok, %Flop{order_by: [:name]}} =
               Flop.validate(%{order_by: [:name]}, for: Basil)

      assert {:error, %Flop.Meta{errors: errors}} =
               Flop.validate(%{order_by: [:nope]}, for: Basil)

      assert Keyword.has_key?(errors, :order_by)
    end

    test "an unknown sortable field raises at compile time" do
      error =
        assert_raise Flop.UnknownFieldError, fn ->
          defmodule Sage do
            use Flop.Schema

            @flop_options [
              adapter: Flop.TestAdapter,
              adapter_opts: [declared_fields: [name: :string]],
              filterable: [],
              sortable: [:nope]
            ]
          end
        end

      assert Exception.message(error) =~ ":nope"
      assert Exception.message(error) =~ ":name"
    end
  end

  describe "__deriving__/3" do
    test "raises if default_pagination_type is not allowed" do
      assert_raise Flop.InvalidDefaultPaginationTypeError, fn ->
        defmodule Bulgur do
          use Flop.Schema

          @flop_options [
            filterable: [],
            sortable: [],
            default_pagination_type: :first,
            pagination_types: [:page]
          ]
          defstruct [:name]
        end
      end
    end

    test "raises if filterable field is unknown" do
      assert_raise Flop.UnknownFieldError, fn ->
        defmodule Pita do
          use Flop.Schema

          @flop_options [
            filterable: [:smell],
            sortable: []
          ]
          defstruct [:name]
        end
      end
    end

    test "raises if sortable field is unknown" do
      assert_raise Flop.UnknownFieldError, fn ->
        defmodule Marmelade do
          use Flop.Schema

          @flop_options [
            filterable: [],
            sortable: [:smell]
          ]
          defstruct [:name]
        end
      end
    end

    test "raises for a nil ecto_type on a custom field" do
      error =
        assert_raise Flop.InvalidConfigError, fn ->
          defmodule Tabbouleh do
            use Flop.Schema

            @flop_options [
              filterable: [:thing],
              sortable: [],
              adapter_opts: [
                custom_fields: [
                  thing: [filter: {__MODULE__, :filter, []}, ecto_type: nil]
                ]
              ]
            ]
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
            use Flop.Schema

            @flop_options [
              filterable: [:owner_name],
              sortable: [],
              adapter_opts: [
                join_fields: [
                  owner_name: [binding: :owner, field: :name, ecto_type: nil]
                ]
              ]
            ]
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
            use Flop.Schema

            @flop_options [
              filterable: [:thing],
              sortable: [],
              custom_fields: [
                thing: [filter: {__MODULE__, :filter, []}, ecto_type: nil]
              ]
            ]
            defstruct [:name]
          end
        end

      assert Exception.message(error) =~
               "expected an Ecto type such as :string or :map, got: nil"
    end

    test "raises if default order field is not sortable" do
      assert_raise Flop.InvalidDefaultOrderError, fn ->
        defmodule Broomstick do
          use Flop.Schema

          @flop_options [
            filterable: [],
            sortable: [:name],
            default_order: %{order_by: [:age], order_directions: [:desc]}
          ]
          defstruct [:name, :age]
        end
      end
    end

    test "raises if compound field references unknown field" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Potato do
            use Flop.Schema

            @flop_options [
              filterable: [],
              sortable: [],
              compound_fields: [full_name: [:family_name, :given_name]]
            ]
            defstruct [:family_name]
          end
        end

      assert error.message =~ "unknown field"
    end

    test "raises if compound field uses existing join field name" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Cannelloni do
            use Flop.Schema

            @flop_options [
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
            ]
            defstruct [:name, :nickname]
          end
        end

      assert error.message =~ "duplicate field"
    end

    test "raises if alias field uses existing compound field name" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Pickles do
            use Flop.Schema

            @flop_options [
              filterable: [],
              sortable: [],
              compound_fields: [name: [:name, :nickname]],
              alias_fields: [:name]
            ]
            defstruct [:id]
          end
        end

      assert error.message =~ "duplicate field"
    end

    test "raises if alias field uses existing join field name" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Juice do
            use Flop.Schema

            @flop_options [
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
            ]
            defstruct [:id]
          end
        end

      assert error.message =~ "duplicate field"
    end

    test "raises if custom field uses existing compound field name" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Pasta do
            use Flop.Schema

            @flop_options [
              filterable: [],
              sortable: [],
              compound_fields: [name: [:name, :nickname]],
              custom_fields: [
                name: [
                  filter: {__MODULE__, :some_function, []},
                  ecto_type: :string
                ]
              ]
            ]
            defstruct [:id, :nickname]
          end
        end

      assert error.message =~ "duplicate field"
    end

    test "raises if custom field uses existing join field name" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Vegetable do
            use Flop.Schema

            @flop_options [
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
            ]
            defstruct [:id]
          end
        end

      assert error.message =~ "duplicate field"
    end

    test "raises if custom field uses existing alias field name" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Cranberry do
            use Flop.Schema

            @flop_options [
              filterable: [],
              sortable: [],
              alias_fields: [:name],
              custom_fields: [
                name: [
                  filter: {__MODULE__, :some_function, []},
                  ecto_type: :string
                ]
              ]
            ]
            defstruct [:id]
          end
        end

      assert error.message =~ "duplicate field"
    end

    test "does not raise if alias field uses existing schema field name" do
      defmodule Vegetaburu do
        use Flop.Schema

        @flop_options [
          filterable: [],
          sortable: [],
          alias_fields: [:nickname]
        ]
        defstruct [:name, :nickname]
      end
    end

    test "raises error if alias field is added to filterable list" do
      error =
        assert_raise ArgumentError, fn ->
          defmodule Bejitaburu do
            use Flop.Schema

            @flop_options [
              filterable: [:count],
              sortable: [],
              alias_fields: [:count]
            ]
            defstruct [:id]
          end
        end

      assert error.message =~ "cannot filter by alias field"
    end
  end

  test "field_info/2 returns parameterized type for ecto_enum" do
    assert %Flop.FieldInfo{ecto_type: ecto_type} =
             Schema.field_info(MyApp.Owner, :pet_mood_as_enum)

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
          use Flop.Schema

          @flop_options [
            filterable: [],
            sortable: [:inserted_at],
            custom_fields: [
              inserted_at: [
                filter: {__MODULE__, :some_function, []},
                ecto_type: :utc_datetime
              ]
            ]
          ]
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
          use Flop.Schema

          @flop_options [
            filterable: [],
            sortable: [:name],
            tiebreaker: [asc: :nanoid]
          ]
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
          use Flop.Schema

          @flop_options [
            filterable: [],
            sortable: [:full_name],
            tiebreaker: [asc: :full_name],
            compound_fields: [full_name: [:family_name, :given_name]]
          ]
          defstruct [:id, :family_name, :given_name]
        end
      end

    assert error.message =~ "unsupported tiebreaker field"
  end

  test "raises error if a tiebreaker names a custom field without field_dynamic" do
    error =
      assert_raise ArgumentError, fn ->
        defmodule Borage do
          use Flop.Schema

          @flop_options [
            filterable: [:thing],
            sortable: [],
            tiebreaker: [asc: :thing],
            custom_fields: [
              thing: [filter: {__MODULE__, :f, []}, ecto_type: :string]
            ]
          ]
          defstruct [:id, :name]

          def f(q, _, _), do: q
        end
      end

    assert Exception.message(error) =~ "unsupported tiebreaker field"
    assert Exception.message(error) =~ "field_dynamic"
  end

  test "raises error if a filterable custom field has no callback at all" do
    error =
      assert_raise ArgumentError, fn ->
        defmodule Sage do
          use Flop.Schema

          @flop_options [
            filterable: [:inserted_at],
            sortable: [],
            custom_fields: [inserted_at: [ecto_type: :utc_datetime]]
          ]
          defstruct [:id, :inserted_at]
        end
      end

    assert error.message =~
             "custom field without a callback marked as filterable"

    assert error.message =~ ":inserted_at"
  end

  test "allows a filterable custom field with only field_dynamic" do
    defmodule Sorrel do
      use Flop.Schema

      @flop_options [
        filterable: [:inserted_at],
        sortable: [:inserted_at],
        custom_fields: [
          inserted_at: [
            field_dynamic: {__MODULE__, :field_dynamic, []},
            ecto_type: :utc_datetime
          ]
        ]
      ]
      defstruct [:id, :inserted_at]
    end

    assert Flop.schema_option(Sorrel, :filterable) == [:inserted_at]
  end

  test "allows a custom field with only the callback it needs" do
    defmodule Thyme do
      use Flop.Schema

      @flop_options [
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
      ]
      defstruct [:id]
    end

    assert %Flop.FieldInfo{extra: %{type: :custom, field_dynamic: nil}} =
             Schema.field_info(Thyme, :filtered)

    assert %Flop.FieldInfo{extra: %{type: :custom, filter: nil}} =
             Schema.field_info(Thyme, :sorted)
  end
end
