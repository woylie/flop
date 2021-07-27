defmodule Flop.Builder do
  @moduledoc false

  import Ecto.Query

  alias Flop.Filter
  alias Flop.Misc

  def filter(_, %Filter{field: nil}, c), do: c

  def filter(_, %Filter{op: op, value: nil}, c)
      when op not in [:empty, :not_empty],
      do: c

  def filter(
        schema_struct,
        %Filter{field: field} = filter,
        conditions
      ) do
    case get_field_type(schema_struct, field) do
      :normal ->
        build_op(conditions, nil, filter)

      {:join, {_binding_name, _field_name} = binding} ->
        build_op(conditions, binding, filter)
    end
  end

  @operator_opts [
    {:==, "field(r, ^field) == ^value"},
    {:!=, "field(r, ^field) != ^value"},
    {:empty, "is_nil(field(r, ^field))"},
    {:not_empty, "not is_nil(field(r, ^field))"},
    {:=~, "ilike(field(r, ^field), ^value)", :add_wildcard},
    {:ilike, "ilike(field(r, ^field), ^value)", :add_wildcard},
    {:>=, "field(r, ^field) >= ^value"},
    {:<=, "field(r, ^field) <= ^value"},
    {:>, "field(r, ^field) > ^value"},
    {:<, "field(r, ^field) < ^value"},
    {:in, "field(r, ^field) in ^value"},
    {:like, "like(field(r, ^field), ^value)", :add_wildcard}
  ]

  for operator_and_condition <- @operator_opts do
    {op, condition, preprocessor, _dynamic_builder} =
      case operator_and_condition do
        {operator, condition} -> {operator, condition, nil, nil}
        {operator, condition, func} -> {operator, condition, func, nil}
        {operator, condition, func, df} -> {operator, condition, func, df}
      end

    preprocessing =
      unless is_nil(preprocessor),
        do: Code.string_to_quoted!("value = Misc.#{preprocessor}(value)")

    defp build_op(c, nil, %Filter{
           field: field,
           op: unquote(op),
           value: value
         }) do
      unquote(preprocessing)

      # prevent unused variable warning for operators that don't use value
      _ = value

      unquote(Code.string_to_quoted!("dynamic([r], ^c and #{condition})"))
    end

    defp build_op(c, {binding, field}, %Filter{
           op: unquote(op),
           value: value
         }) do
      unquote(preprocessing)

      # prevent unused variable warning for operators that don't use value
      _ = value

      unquote(
        Code.string_to_quoted!("dynamic([{^binding, r}], ^c and #{condition})")
      )
    end
  end

  defp build_op(c, nil, %Filter{field: field, op: :like_and, value: value}) do
    query_values = Misc.split_search_text(value)

    dynamic =
      Enum.reduce(query_values, true, fn value, dynamic ->
        dynamic([r], ^dynamic and like(field(r, ^field), ^value))
      end)

    dynamic([r], ^c and ^dynamic)
  end

  defp build_op(c, nil, %Filter{field: field, op: :like_or, value: value}) do
    query_values = Misc.split_search_text(value)

    dynamic =
      Enum.reduce(query_values, false, fn value, dynamic ->
        dynamic([r], ^dynamic or like(field(r, ^field), ^value))
      end)

    dynamic([r], ^c and ^dynamic)
  end

  defp build_op(c, nil, %Filter{field: field, op: :ilike_and, value: value}) do
    query_values = Misc.split_search_text(value)

    dynamic =
      Enum.reduce(query_values, true, fn value, dynamic ->
        dynamic([r], ^dynamic and ilike(field(r, ^field), ^value))
      end)

    dynamic([r], ^c and ^dynamic)
  end

  defp build_op(c, nil, %Filter{field: field, op: :ilike_or, value: value}) do
    query_values = Misc.split_search_text(value)

    dynamic =
      Enum.reduce(query_values, false, fn value, dynamic ->
        dynamic([r], ^dynamic or ilike(field(r, ^field), ^value))
      end)

    dynamic([r], ^c and ^dynamic)
  end

  defp get_field_type(nil, _), do: :normal

  defp get_field_type(struct, field) when is_atom(field) do
    Flop.Schema.field_type(struct, field)
  end
end
