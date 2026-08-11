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
end
