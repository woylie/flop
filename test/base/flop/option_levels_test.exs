defmodule Flop.OptionLevelsTest do
  # async: false because the application environment is modified
  use ExUnit.Case, async: false

  alias Flop.Meta
  alias MyApp.Pet

  defmodule BackendWithoutPolicyOptions do
    use Flop, repo: Flop.Repo
  end

  setup do
    on_exit(fn ->
      Application.delete_env(:flop, :replace_invalid_params)
      Application.delete_env(:flop, :max_cursor_size)
      Application.delete_env(:flop, :default_order)
      Application.delete_env(:flop, :tiebreaker)
      Application.put_env(:flop, :repo, Flop.Repo)
    end)
  end

  describe "replace_invalid_params" do
    test "can be set in the application environment" do
      params = %{limit: 20_000}

      assert {:error, %Meta{}} = Flop.validate(params, for: Pet)

      Application.put_env(:flop, :replace_invalid_params, true)

      assert {:ok, %Flop{limit: 50}} = Flop.validate(params, for: Pet)
    end

    test "is read from the application environment with a backend module" do
      Application.put_env(:flop, :replace_invalid_params, true)

      assert {:ok, %Flop{limit: 50}} =
               Flop.validate(%{limit: 20_000},
                 backend: BackendWithoutPolicyOptions,
                 for: Pet
               )
    end

    test "is overridden at the call site" do
      Application.put_env(:flop, :replace_invalid_params, true)

      assert {:error, %Meta{}} =
               Flop.validate(%{limit: 20_000},
                 for: Pet,
                 replace_invalid_params: false
               )
    end
  end

  describe "max_cursor_size" do
    test "can be set in the application environment" do
      cursor = Flop.Cursor.encode(%{name: String.duplicate("a", 100)})
      params = %{first: 2, after: cursor, order_by: [:name]}

      assert {:ok, %Flop{}} = Flop.validate(params, for: Pet)

      Application.put_env(:flop, :max_cursor_size, 10)

      assert {:error, %Meta{errors: [after: _]}} =
               Flop.validate(params, for: Pet)
    end
  end

  describe "default_order" do
    test "is not read from the application environment" do
      Application.put_env(:flop, :default_order, %{order_by: [:name]})

      assert {:ok, %Flop{order_by: nil, order_directions: nil}} =
               Flop.validate(%{}, for: Pet)
    end
  end

  describe "schema and call-site options" do
    test "are not read from the application environment" do
      for key <- [
            :sortable,
            :filterable,
            :default_order,
            :for,
            :count,
            :count_query,
            :extra_opts
          ] do
        Application.put_env(:flop, key, :from_the_application_environment)
        on_exit(fn -> Application.delete_env(:flop, key) end)

        assert Flop.get_option(key, [], :not_set) == :not_set
      end
    end
  end

  describe "tiebreaker" do
    test "can be set in the application environment" do
      assert Flop.ordering(%Flop{order_by: [:name]}, for: Pet) ==
               [asc: :name, asc: :id]

      Application.put_env(:flop, :tiebreaker, false)

      assert Flop.ordering(%Flop{order_by: [:name]}, for: Pet) == [asc: :name]
    end

    test "raises when it names fields in the application environment" do
      Application.put_env(:flop, :tiebreaker, asc: :id)

      assert_raise ArgumentError,
                   ~r/invalid tiebreaker in the application environment/,
                   fn -> Flop.ordering(%Flop{order_by: [:name]}, for: Pet) end
    end
  end

  describe "repo" do
    test "raises when it is set at no level" do
      Application.delete_env(:flop, :repo)

      for fun <- [:all, :count, :run] do
        error =
          assert_raise Flop.NoRepoError, fn ->
            apply(Flop, fun, [Pet, %Flop{}])
          end

        assert Exception.message(error) =~ "no Ecto repo configured"
      end
    end
  end
end
