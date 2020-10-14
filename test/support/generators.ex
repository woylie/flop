defmodule Flop.Generators do
  @moduledoc false
  use ExUnitProperties

  alias Flop.Filter

  @order_directions [
    :asc,
    :asc_nulls_first,
    :asc_nulls_last,
    :desc,
    :desc_nulls_first,
    :desc_nulls_last
  ]

  def pet do
    gen all name <- string(:alphanumeric),
            age <- integer(1..500),
            species <- string(:alphanumeric) do
      %{name: name, age: age, species: species}
    end
  end

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

  def cursor_fields(%{} = schema) do
    schema
    |> Flop.Schema.sortable()
    |> Enum.shuffle()
    |> constant()
  end

  def order_directions(%{} = schema) do
    field_count =
      schema
      |> Flop.Schema.sortable()
      |> length()

    @order_directions
    |> member_of()
    |> list_of(length: field_count)
  end
end
