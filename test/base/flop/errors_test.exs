defmodule Flop.ErrorsTest do
  use ExUnit.Case, async: true

  describe "Flop.InvalidConfigError" do
    test "renders message for backend option" do
      message =
        Exception.message(%Flop.InvalidConfigError{
          caller: MyApp.Flop,
          module: Flop,
          message: "unknown options [:repos]"
        })

      assert message =~ "invalid Flop configuration"
      assert message =~ "passed to `use Flop` in the module `MyApp.Flop`"
      assert message =~ "unknown options [:repos]"
    end

    test "renders message for schema option" do
      message =
        Exception.message(%Flop.InvalidConfigError{
          caller: MyApp.Pet,
          module: Flop.Schema,
          message: "unknown options [:filterables]"
        })

      assert message =~ "passed to `@derive Flop.Schema` in the module"
      assert message =~ "MyApp.Pet"
    end

    test "renders message for unknown module" do
      message =
        Exception.message(%Flop.InvalidConfigError{
          caller: MyApp.Pet,
          module: Flop.Adapter.Ecto,
          message: "unknown options [:join_field]"
        })

      assert message =~ "Flop.Adapter.Ecto"
      assert message =~ "unknown options [:join_field]"
    end
  end

  describe "Flop.InvalidDefaultOrderError" do
    test "renders message" do
      message =
        Exception.message(
          Flop.InvalidDefaultOrderError.exception(
            sortable_fields: [:name],
            unsortable_fields: [:age]
          )
        )

      assert message =~ "invalid default order"
      assert message =~ "[:age]"
      assert message =~ "[:name]"
    end
  end

  describe "Flop.InvalidDefaultPaginationTypeError" do
    test "renders message" do
      message =
        Exception.message(%Flop.InvalidDefaultPaginationTypeError{
          default_pagination_type: :first,
          pagination_types: [:offset]
        })

      assert message =~ "default pagination type not allowed"
      assert message =~ "default_pagination_type: :first"
      assert message =~ "pagination_types: [:offset]"
    end
  end

  describe "Flop.NoRepoError" do
    test "renders message" do
      message = Exception.message(%Flop.NoRepoError{function_name: :all})

      assert message =~ "no Ecto repo configured"
      assert message =~ "`Flop.all/3`"
      assert message =~ "config :flop, repo: MyApp.Repo"
    end
  end

  describe "Flop.UnknownFieldError" do
    test "renders message with option" do
      message =
        Exception.message(
          Flop.UnknownFieldError.exception(
            known_fields: [:name, :age],
            unknown_fields: [:species],
            option: "filterable"
          )
        )

      assert message =~ "unknown filterable field(s)"
      assert message =~ "unknown filterable fields in your schema configuration"
      assert message =~ "[:species]"
      assert message =~ "[:age, :name]"
    end

    test "renders message without option" do
      message =
        Exception.message(
          Flop.UnknownFieldError.exception(
            known_fields: [:name, :age],
            unknown_fields: [:species]
          )
        )

      assert message =~ "unknown field(s)"
      assert message =~ "not configured in your Flop schema"
      assert message =~ "[:species]"
      assert message =~ "[:age, :name]"
    end
  end
end
