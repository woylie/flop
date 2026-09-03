defmodule Flop.SchemaDependenciesTest do
  # async: false because the test installs a global compiler tracer.
  use ExUnit.Case, async: false

  @collector :flop_schema_dependencies_test

  defmodule Tracer do
    def trace({:alias_reference, _meta, module}, env) do
      send(
        :flop_schema_dependencies_test,
        {:alias_reference, module, env.function}
      )

      :ok
    end

    def trace(_event, _env), do: :ok
  end

  setup do
    Process.register(self(), @collector)
    :ok
  end

  test "an alias in an ecto_type creates no compile dependency" do
    source = """
    defmodule Flop.SchemaDependenciesTest.WithAttribute do
      use Ecto.Schema
      use Flop.Schema

      alias MyApp.Pet

      @flop_options [
        filterable: [:name],
        sortable: [:name],
        join_fields: [
          pet_mood: [
            binding: :pets,
            field: :mood,
            ecto_type: {:from_schema, Pet, :mood}
          ]
        ]
      ]

      schema "with_attribute" do
        field :name, :string
      end
    end
    """

    assert compile_time_references(source, MyApp.Pet) == []
  end

  # test a known case that causes a compile reference to ensure this test setup
  # works
  test "a compile-time call on an aliased module creates a compile dependency" do
    source = """
    defmodule Flop.SchemaDependenciesTest.CompileTimeCall do
      alias MyApp.Pet

      @source Pet.__schema__(:source)

      def source, do: @source
    end
    """

    assert compile_time_references(source, MyApp.Pet) != []
  end

  defp compile_time_references(source, module) do
    Code.put_compiler_option(:tracers, [Tracer])

    try do
      Code.compile_string(source)
    after
      Code.put_compiler_option(:tracers, [])
    end

    {:messages, messages} = Process.info(self(), :messages)

    for {:alias_reference, ^module, nil} <- messages, do: module
  end
end
