defmodule Flop.Builder do
  @moduledoc false

  import Ecto.Query
  import Flop.Misc

  alias Flop.Filter
  alias Flop.Misc

  require Logger

  def filter(_, %Filter{field: nil}, c), do: c

  def filter(_, %Filter{op: op, value: nil}, c)
      when op not in [:empty, :not_empty],
      do: c

  def filter(
        schema_struct,
        %Filter{field: field} = filter,
        conditions
      ) do
    build_op(
      conditions,
      schema_struct,
      get_field_type(schema_struct, field),
      filter
    )
  end

  operator_opts = [
    {:==, quote(do: field(r, ^var!(field)) == ^var!(value))},
    {:!=, quote(do: field(r, ^var!(field)) != ^var!(value))},
    {:empty, quote(do: is_nil(field(r, ^var!(field))))},
    {:not_empty, quote(do: not is_nil(field(r, ^var!(field))))},
    {:>=, quote(do: field(r, ^var!(field)) >= ^var!(value))},
    {:<=, quote(do: field(r, ^var!(field)) <= ^var!(value))},
    {:>, quote(do: field(r, ^var!(field)) > ^var!(value))},
    {:<, quote(do: field(r, ^var!(field)) < ^var!(value))},
    {:in, quote(do: field(r, ^var!(field)) in ^var!(value))},
    {:contains, quote(do: ^var!(value) in field(r, ^var!(field)))},
    {:like, quote(do: like(field(r, ^var!(field)), ^var!(value))),
     :add_wildcard},
    {:=~, quote(do: ilike(field(r, ^var!(field)), ^var!(value))),
     :add_wildcard},
    {:ilike, quote(do: ilike(field(r, ^var!(field)), ^var!(value))),
     :add_wildcard},
    {:like_and, quote(do: ^var!(d)), :split_search_text,
     """
     d =
       Enum.reduce(value, true, fn value, dynamic ->
         dynamic(<<<binding>>>, ^dynamic and like(field(r, ^field), ^value))
       end)
     """},
    {:like_or, quote(do: ^var!(d)), :split_search_text,
     """
     d =
       Enum.reduce(value, false, fn value, dynamic ->
         dynamic(<<<binding>>>, ^dynamic or like(field(r, ^field), ^value))
       end)
     """},
    {:ilike_and, quote(do: ^var!(d)), :split_search_text,
     """
     d =
       Enum.reduce(value, true, fn value, dynamic ->
         dynamic(<<<binding>>>, ^dynamic and ilike(field(r, ^field), ^value))
       end)
     """},
    {:ilike_or, quote(do: ^var!(d)), :split_search_text,
     """
     d =
       Enum.reduce(value, false, fn value, dynamic ->
         dynamic(<<<binding>>>, ^dynamic or ilike(field(r, ^field), ^value))
       end)
     """}
  ]

  defp build_op(c, schema_struct, {:compound, fields}, %Filter{op: op} = filter)
       when op in [
              :=~,
              :like,
              :like_and,
              :like_or,
              :ilike,
              :ilike_and,
              :ilike_or,
              :not_empty
            ] do
    compound_dynamic =
      fields
      |> Enum.map(&get_field_type(schema_struct, &1))
      |> Enum.reduce(false, fn field, dynamic ->
        dynamic_for_field =
          build_op(true, schema_struct, field, %{filter | field: field})

        dynamic([r], ^dynamic or ^dynamic_for_field)
      end)

    dynamic([r], ^c and ^compound_dynamic)
  end

  defp build_op(
         c,
         schema_struct,
         {:compound, fields},
         %Filter{op: :empty} = filter
       ) do
    compound_dynamic =
      fields
      |> Enum.map(&get_field_type(schema_struct, &1))
      |> Enum.reduce(true, fn field, dynamic ->
        dynamic_for_field =
          build_op(true, schema_struct, field, %{filter | field: field})

        dynamic([r], ^dynamic and ^dynamic_for_field)
      end)

    dynamic([r], ^c and ^compound_dynamic)
  end

  defp build_op(
         c,
         _schema_struct,
         {:compound, _fields},
         %Filter{op: op, value: _value} = _filter
       )
       when op in [:==, :!=, :<=, :<, :>=, :>, :in, :contains] do
    # value = value |> String.split() |> Enum.join(" ")
    # filter = %{filter | value: value}
    # compare value with concatenated fields
    Logger.warn(
      "Flop: Operator '#{op}' not supported for compound fields. Ignored."
    )

    c
  end

  for operator_and_condition <- operator_opts do
    {op, condition, preprocessor, dynamic_builder} =
      case operator_and_condition do
        {operator, condition} -> {operator, condition, nil, nil}
        {operator, condition, func} -> {operator, condition, func, nil}
        {operator, condition, func, df} -> {operator, condition, func, df}
      end

    preprocessing =
      unless is_nil(preprocessor) do
        quote do
          var!(value) = Misc.unquote(preprocessor)(var!(value))
        end
      end

    defp build_op(c, _schema_struct, {:normal, field}, %Filter{
           op: unquote(op),
           value: value
         }) do
      unquote(preprocessing)

      # prevent unused variable warning for operators that don't use value
      _ = value

      unquote(quote_dynamic(dynamic_builder, "[r]"))

      unquote(
        quote do
          dynamic([r], ^var!(c) and unquote(condition))
        end
      )
    end

    defp build_op(
           c,
           _schema_struct,
           {:join, %{binding: binding, field: field}},
           %Filter{
             op: unquote(op),
             value: value
           }
         ) do
      unquote(preprocessing)

      # prevent unused variable warning for operators that don't use value
      _ = value

      unquote(quote_dynamic(dynamic_builder, "[{^binding, r}]"))

      unquote(
        quote do
          dynamic([{^var!(binding), r}], ^var!(c) and unquote(condition))
        end
      )
    end
  end

  defp get_field_type(nil, field), do: {:normal, field}

  defp get_field_type(struct, field) when is_atom(field) do
    Flop.Schema.field_type(struct, field)
  end
end
