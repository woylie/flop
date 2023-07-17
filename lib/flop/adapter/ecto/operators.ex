defmodule Flop.Adapter.Ecto.Operators do
  @moduledoc false

  import Ecto.Query

  defmacro build_dynamic(fragment, binding?, _combinator = nil) do
    binding_arg = binding_arg(binding?)

    quote do
      dynamic(unquote(binding_arg), unquote(fragment))
    end
  end

  defmacro build_dynamic(fragment, binding?, :and) do
    binding_arg = binding_arg(binding?)

    quote do
      filter_condition =
        Enum.reduce(var!(value), true, fn substring, dynamic ->
          dynamic(unquote(binding_arg), ^dynamic and unquote(fragment))
        end)

      dynamic(unquote(binding_arg), ^filter_condition)
    end
  end

  defmacro build_dynamic(fragment, binding?, :or) do
    binding_arg = binding_arg(binding?)

    quote do
      filter_condition =
        Enum.reduce(var!(value), false, fn substring, dynamic ->
          dynamic(unquote(binding_arg), ^dynamic or unquote(fragment))
        end)

      dynamic(unquote(binding_arg), ^filter_condition)
    end
  end

  def reduce_dynamic(:and, values, inner_func) do
    Enum.reduce(values, true, fn value, dynamic ->
      dynamic([r], ^dynamic and ^inner_func.(value))
    end)
  end

  def reduce_dynamic(:or, values, inner_func) do
    Enum.reduce(values, false, fn value, dynamic ->
      dynamic([r], ^dynamic or ^inner_func.(value))
    end)
  end

  defp binding_arg(true) do
    quote do
      [{^var!(binding), r}]
    end
  end

  defp binding_arg(false) do
    quote do
      [r]
    end
  end

  def op_config(:==) do
    fragment =
      quote do
        field(r, ^var!(field)) == ^var!(value)
      end

    {fragment, nil, nil}
  end

  def op_config(:!=) do
    fragment =
      quote do
        field(r, ^var!(field)) != ^var!(value)
      end

    {fragment, nil, nil}
  end

  def op_config(:>=) do
    fragment =
      quote do
        field(r, ^var!(field)) >= ^var!(value)
      end

    {fragment, nil, nil}
  end

  def op_config(:<=) do
    fragment =
      quote do
        field(r, ^var!(field)) <= ^var!(value)
      end

    {fragment, nil, nil}
  end

  def op_config(:>) do
    fragment =
      quote do
        field(r, ^var!(field)) > ^var!(value)
      end

    {fragment, nil, nil}
  end

  def op_config(:<) do
    fragment =
      quote do
        field(r, ^var!(field)) < ^var!(value)
      end

    {fragment, nil, nil}
  end

  def op_config(:empty) do
    fragment = empty()
    {fragment, nil, nil}
  end

  def op_config(:not_empty) do
    fragment =
      quote do
        not unquote(empty())
      end

    {fragment, nil, nil}
  end

  def op_config(:in) do
    fragment =
      quote do
        field(r, ^var!(field)) in ^var!(value)
      end

    {fragment, nil, nil}
  end

  def op_config(:contains) do
    fragment =
      quote do
        ^var!(value) in field(r, ^var!(field))
      end

    {fragment, nil, nil}
  end

  def op_config(:not_contains) do
    fragment =
      quote do
        ^var!(value) not in field(r, ^var!(field))
      end

    {fragment, nil, nil}
  end

  def op_config(:like) do
    fragment =
      quote do
        like(field(r, ^var!(field)), ^var!(value))
      end

    prelude = prelude(:add_wildcard)
    {fragment, prelude, nil}
  end

  def op_config(:not_like) do
    fragment =
      quote do
        not like(field(r, ^var!(field)), ^var!(value))
      end

    prelude = prelude(:add_wildcard)
    {fragment, prelude, nil}
  end

  def op_config(:=~) do
    fragment =
      quote do
        ilike(field(r, ^var!(field)), ^var!(value))
      end

    prelude = prelude(:add_wildcard)
    {fragment, prelude, nil}
  end

  def op_config(:ilike) do
    fragment =
      quote do
        ilike(field(r, ^var!(field)), ^var!(value))
      end

    prelude = prelude(:add_wildcard)
    {fragment, prelude, nil}
  end

  def op_config(:not_ilike) do
    fragment =
      quote do
        not ilike(field(r, ^var!(field)), ^var!(value))
      end

    prelude = prelude(:add_wildcard)
    {fragment, prelude, nil}
  end

  def op_config(:not_in) do
    fragment =
      quote do
        field(r, ^var!(field)) not in ^var!(processed_value) and
          not (^var!(reject_nil?) and is_nil(field(r, ^var!(field))))
      end

    prelude =
      quote do
        var!(reject_nil?) = nil in var!(value)

        var!(processed_value) =
          if var!(reject_nil?),
            do: Enum.reject(var!(value), &is_nil(&1)),
            else: var!(value)
      end

    {fragment, prelude, nil}
  end

  def op_config(:like_and) do
    fragment =
      quote do
        like(field(r, ^var!(field)), ^substring)
      end

    combinator = :and
    prelude = prelude(:maybe_split_search_text)

    {fragment, prelude, combinator}
  end

  def op_config(:like_or) do
    fragment =
      quote do
        like(field(r, ^var!(field)), ^substring)
      end

    combinator = :or
    prelude = prelude(:maybe_split_search_text)

    {fragment, prelude, combinator}
  end

  def op_config(:ilike_and) do
    fragment =
      quote do
        ilike(field(r, ^var!(field)), ^substring)
      end

    combinator = :and
    prelude = prelude(:maybe_split_search_text)

    {fragment, prelude, combinator}
  end

  def op_config(:ilike_or) do
    fragment =
      quote do
        ilike(field(r, ^var!(field)), ^substring)
      end

    combinator = :or
    prelude = prelude(:maybe_split_search_text)

    {fragment, prelude, combinator}
  end

  defp empty do
    quote do
      is_nil(field(r, ^var!(field))) == ^var!(value)
    end
  end

  defmacro empty(:array) do
    quote do
      is_nil(field(r, ^var!(field))) or
        field(r, ^var!(field)) == type(^[], ^var!(ecto_type))
    end
  end

  defmacro empty(:map) do
    quote do
      is_nil(field(r, ^var!(field))) or
        field(r, ^var!(field)) == type(^%{}, ^var!(ecto_type))
    end
  end

  defmacro empty(:other) do
    quote do
      is_nil(field(r, ^var!(field)))
    end
  end

  defp prelude(:add_wildcard) do
    quote do
      var!(value) = Flop.Misc.add_wildcard(var!(value))
    end
  end

  defp prelude(:maybe_split_search_text) do
    quote do
      var!(value) =
        if is_binary(var!(value)) do
          Flop.Misc.split_search_text(var!(value))
        else
          Enum.map(var!(value), &Flop.Misc.add_wildcard/1)
        end
    end
  end
end
