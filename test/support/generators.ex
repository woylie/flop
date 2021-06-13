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
    gen all name <- string(:printable),
            age <- integer(1..500),
            species <- string(:printable) do
      %{name: name, age: age, species: species}
    end
  end

  def uniq_list_of_pets(opts) do
    length_range = Keyword.fetch!(opts, :length)

    gen all length <- integer(length_range),
            names <- uniq_list_of(string(:printable), length: length),
            ages <- uniq_list_of(integer(1..500), length: length),
            species <- uniq_list_of(string(:printable), length: length) do
      [names, ages, species]
      |> Enum.zip()
      |> Enum.map(fn {name, age, species} ->
        %{name: name, age: age, species: species}
      end)
    end
  end

  def pagination_parameters(type) when type in [:offset, :page] do
    gen all val_1 <- positive_integer(),
            val_2 <- one_of([positive_integer(), constant(nil)]) do
      [a, b] = Enum.shuffle([val_1, val_2])

      case type do
        :offset -> %{offset: a, limit: b}
        :page -> %{page: a, page_size: b}
      end
    end
  end

  def pagination_parameters(type) when type in [:first, :last] do
    gen all val_1 <- positive_integer(),
            val_2 <- one_of([string(:alphanumeric), constant(nil)]) do
      case type do
        :first -> %{first: val_1, after: val_2}
        :last -> %{last: val_1, before: val_2}
      end
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
    do:
      member_of([
        :==,
        :!=,
        :=~,
        :<=,
        :<,
        :>=,
        :>,
        :like,
        :like_and,
        :like_or,
        :ilike,
        :ilike_and,
        :ilike_or
      ])

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
