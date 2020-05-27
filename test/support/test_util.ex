defmodule Flop.TestUtil do
  @moduledoc false

  use ExUnitProperties

  alias Flop.Filter

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
            value <- value_by_field(field),
            op <- operator_by_type(value) do
      %Filter{field: field, op: op, value: value}
    end
  end

  def value_by_field(:age), do: integer()
  def value_by_field(:name), do: string(:alphanumeric, min_length: 1)

  def compare_value_by_field(:age), do: integer(1..30)

  def compare_value_by_field(:name),
    do: string(?a..?z, min_length: 1, max_length: 3)

  defp operator_by_type(a) when is_binary(a),
    do: member_of([:==, :!=, :=~, :<=, :<, :>=, :>])

  defp operator_by_type(a) when is_number(a),
    do: member_of([:==, :!=, :<=, :<, :>=, :>])
end
