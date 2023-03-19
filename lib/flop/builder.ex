defmodule Flop.Builder do
  @moduledoc false

  import Ecto.Query
  import Flop.Operators

  alias Flop.Filter

  require Logger

  @operators [
    :==,
    :!=,
    :empty,
    :not_empty,
    :>=,
    :<=,
    :>,
    :<,
    :in,
    :contains,
    :not_contains,
    :like,
    :not_like,
    :=~,
    :ilike,
    :not_ilike,
    :not_in,
    :like_and,
    :like_or,
    :ilike_and,
    :ilike_or
  ]

  def filter(query, schema_struct, filters, extra_opts) do
    Enum.reduce(
      filters,
      query,
      &apply_filter(&2, &1, schema_struct, extra_opts)
    )
  end

  defp apply_filter(query, %Filter{field: nil}, _, _), do: query
  defp apply_filter(query, %Filter{value: nil}, _, _), do: query

  defp apply_filter(
         query,
         %Filter{field: field} = filter,
         schema_struct,
         extra_opts
       ) do
    case get_field_type(schema_struct, field) do
      {:custom, %{} = custom_opts} ->
        {mod, fun, opts} = Map.fetch!(custom_opts, :filter)
        opts = Keyword.merge(extra_opts, opts)
        apply(mod, fun, [query, filter, opts])

      field_type ->
        where(query, ^build_op(schema_struct, field_type, filter))
    end
  end

  for op <- [:like_and, :like_or, :ilike_and, :ilike_or] do
    {field_op, combinator} =
      case op do
        :ilike_and -> {:ilike, :and}
        :ilike_or -> {:ilike, :or}
        :like_and -> {:like, :and}
        :like_or -> {:like, :or}
      end

    defp build_op(
           schema_struct,
           {:compound, fields},
           %Filter{op: unquote(op), value: value}
         ) do
      fields = Enum.map(fields, &get_field_type(schema_struct, &1))

      value =
        case value do
          v when is_binary(v) -> String.split(v)
          v when is_list(v) -> v
        end

      reduce_dynamic(unquote(combinator), value, fn substring ->
        Enum.reduce(fields, false, fn field, inner_dynamic ->
          dynamic_for_field =
            build_op(schema_struct, field, %Filter{
              field: field,
              op: unquote(field_op),
              value: substring
            })

          dynamic([r], ^inner_dynamic or ^dynamic_for_field)
        end)
      end)
    end
  end

  defp build_op(
         schema_struct,
         {:compound, fields},
         %Filter{op: op} = filter
       )
       when op in [:=~, :like, :not_like, :ilike, :not_ilike, :not_empty] do
    fields
    |> Enum.map(&get_field_type(schema_struct, &1))
    |> Enum.reduce(false, fn field, dynamic ->
      dynamic_for_field =
        build_op(schema_struct, field, %{filter | field: field})

      dynamic([r], ^dynamic or ^dynamic_for_field)
    end)
  end

  defp build_op(
         schema_struct,
         {:compound, fields},
         %Filter{op: :empty} = filter
       ) do
    fields
    |> Enum.map(&get_field_type(schema_struct, &1))
    |> Enum.reduce(true, fn field, dynamic ->
      dynamic_for_field =
        build_op(schema_struct, field, %{filter | field: field})

      dynamic([r], ^dynamic and ^dynamic_for_field)
    end)
  end

  defp build_op(
         _schema_struct,
         {:compound, _fields},
         %Filter{op: op, value: _value} = _filter
       )
       when op in [
              :==,
              :!=,
              :<=,
              :<,
              :>=,
              :>,
              :in,
              :not_in,
              :contains,
              :not_contains
            ] do
    # value = value |> String.split() |> Enum.join(" ")
    # filter = %{filter | value: value}
    # compare value with concatenated fields
    Logger.warn(
      "Flop: Operator '#{op}' not supported for compound fields. Ignored."
    )

    true
  end

  defp build_op(%module{}, {:normal, field}, %Filter{op: op, value: value})
       when op in [:empty, :not_empty] do
    ecto_type = module.__schema__(:type, field)
    value = value in [true, "true"]
    value = if op == :not_empty, do: !value, else: value

    case array_or_map(ecto_type) do
      :array -> dynamic([r], empty(:array) == ^value)
      :map -> dynamic([r], empty(:map) == ^value)
      :other -> dynamic([r], empty(:other) == ^value)
    end
  end

  defp build_op(
         _schema_struct,
         {:join, %{binding: binding, ecto_type: ecto_type, field: field}},
         %Filter{op: op, value: value}
       )
       when op in [:empty, :not_empty] do
    value = value in [true, "true"]
    value = if op == :not_empty, do: !value, else: value

    case array_or_map(ecto_type) do
      :array -> dynamic([{^binding, r}], empty(:array) == ^value)
      :map -> dynamic([{^binding, r}], empty(:map) == ^value)
      :other -> dynamic([{^binding, r}], empty(:other) == ^value)
    end
  end

  for op <- @operators do
    {fragment, prelude, combinator} = op_config(op)

    defp build_op(
           _schema_struct,
           {:normal, field},
           %Filter{op: unquote(op), value: value}
         ) do
      unquote(prelude)
      build_dynamic(unquote(fragment), false, unquote(combinator))
    end

    defp build_op(
           _schema_struct,
           {:join, %{binding: binding, field: field}},
           %Filter{op: unquote(op), value: value}
         ) do
      unquote(prelude)
      build_dynamic(unquote(fragment), true, unquote(combinator))
    end
  end

  defp array_or_map({:array, _}), do: :array
  defp array_or_map({:map, _}), do: :map
  defp array_or_map(:map), do: :map
  defp array_or_map(_), do: :other

  defp get_field_type(nil, field), do: {:normal, field}

  defp get_field_type(struct, field) when is_atom(field) do
    Flop.Schema.field_type(struct, field)
  end
end
