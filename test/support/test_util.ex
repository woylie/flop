defmodule Flop.TestUtil do
  @moduledoc false

  use ExUnitProperties

  alias Flop.Filter
  alias Flop.CustomTypes.Operator

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  Brought to you by Phoenix.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Generates a filter struct.
  """
  def filter do
    gen all field <- member_of([:age, :name]),
            op <- member_of(Operator.__operators__()),
            value = one_of([integer(), float(), string(:alphanumeric)]) do
      %Filter{field: field, op: op, value: value}
    end
  end
end
