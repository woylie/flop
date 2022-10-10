defmodule Flop.Validation do
  @moduledoc false

  import Ecto.Changeset

  alias Ecto.Changeset
  alias Flop.Cursor
  alias Flop.Filter

  # todo: set global default limit and max limit
  # todo: make limit required for every pagination type

  @spec changeset(map, [Flop.option()]) :: Changeset.t()
  def changeset(%{} = params, opts) do
    replace_invalid_values? = Keyword.get(opts, :replace_invalid_values, false)

    %Flop{}
    |> cast(params, [])
    |> cast_pagination(params, opts)
    |> cast_order(params, opts)
    |> cast_filters(opts)
    |> validate_exclusive(
      [
        [:first, :after],
        [:last, :before],
        [:limit, :offset],
        [:page, :page_size]
      ],
      message: "cannot combine multiple pagination types",
      replace_invalid_values: replace_invalid_values?
    )
    |> put_default_order(opts)
    |> validate_sortable(opts)
    |> validate_pagination(opts)
    |> maybe_remove_invalid_filters(replace_invalid_values?)
  end

  defp maybe_remove_invalid_filters(changeset, true) do
    changeset =
      update_change(changeset, :filters, fn
        nil ->
          nil

        changesets when is_list(changesets) ->
          Enum.filter(changesets, fn %Changeset{valid?: valid?} -> valid? end)
      end)

    if changeset.errors == [], do: %{changeset | valid?: true}, else: changeset
  end

  defp maybe_remove_invalid_filters(changeset, _), do: changeset

  defp cast_pagination(changeset, params, opts) do
    if Flop.get_option(:pagination, opts, true) do
      fields =
        :pagination_types
        |> Flop.get_option(opts, [:first, :last, :offset, :page])
        |> Enum.flat_map(&pagination_params_for_type/1)

      cast(changeset, params, fields)
    else
      changeset
    end
  end

  defp pagination_params_for_type(:page), do: [:page, :page_size]
  defp pagination_params_for_type(:offset), do: [:limit, :offset]
  defp pagination_params_for_type(:first), do: [:first, :after]
  defp pagination_params_for_type(:last), do: [:last, :before]

  defp cast_order(changeset, params, opts) do
    if Flop.get_option(:ordering, opts, true),
      do: cast(changeset, params, [:order_by, :order_directions]),
      else: changeset
  end

  defp cast_filters(changeset, opts) do
    if Flop.get_option(:filtering, opts, true),
      do: cast_embed(changeset, :filters, with: {Filter, :changeset, [opts]}),
      else: changeset
  end

  # Takes a list of field groups and validates that no fields from multiple
  # groups are set.
  @spec validate_exclusive(Changeset.t(), [[atom]], keyword) :: Changeset.t()
  defp validate_exclusive(changeset, field_groups, opts) do
    changed_field_groups =
      Enum.filter(field_groups, fn fields ->
        Enum.any?(fields, fn field -> !is_nil(get_field(changeset, field)) end)
      end)

    if length(changed_field_groups) > 1 do
      key =
        changed_field_groups
        |> List.first()
        |> Enum.reject(&is_nil(get_field(changeset, &1)))
        |> List.first()

      if opts[:replace_invalid_values] do
        field_groups
        |> List.flatten()
        |> Enum.reduce(changeset, fn field, acc ->
          delete_change(acc, field)
        end)
      else
        add_error(
          changeset,
          key,
          opts[:message] || "invalid combination of field groups"
        )
      end
    else
      changeset
    end
  end

  defp validate_pagination(changeset, opts) do
    pagination_type = get_pagination_type(changeset, opts)
    validate_by_pagination_type(changeset, pagination_type, opts)
  end

  defp validate_by_pagination_type(changeset, :first, opts) do
    replace_invalid_values? = opts[:replace_invalid_values]

    changeset
    |> validate_and_maybe_delete(
      :first,
      &validate_limit/3,
      opts,
      replace_invalid_values?
    )
    |> put_default_limit(:first, opts)
    |> validate_required([:first, :order_by])
    |> validate_length(:order_by, min: 1)
    |> validate_and_maybe_delete(
      :after,
      &validate_cursor/3,
      opts,
      replace_invalid_values?
    )
  end

  defp validate_by_pagination_type(changeset, :last, opts) do
    replace_invalid_values? = opts[:replace_invalid_values]

    changeset
    |> validate_and_maybe_delete(
      :last,
      &validate_limit/3,
      opts,
      replace_invalid_values?
    )
    |> put_default_limit(:last, opts)
    |> validate_required([:last, :order_by])
    |> validate_length(:order_by, min: 1)
    |> validate_and_maybe_delete(
      :before,
      &validate_cursor/3,
      opts,
      replace_invalid_values?
    )
  end

  defp validate_by_pagination_type(changeset, :offset, opts) do
    replace_invalid_values? = opts[:replace_invalid_values]

    changeset
    |> validate_and_maybe_delete(
      :limit,
      &validate_limit/3,
      opts,
      replace_invalid_values?
    )
    |> put_default_limit(:limit, opts)
    |> validate_and_maybe_delete(
      :offset,
      &validate_offset/3,
      opts,
      replace_invalid_values?
    )
    |> put_default_value(:offset, 0)
  end

  defp validate_by_pagination_type(changeset, :page, opts) do
    replace_invalid_values? = opts[:replace_invalid_values]

    changeset
    |> validate_and_maybe_delete(
      :page_size,
      &validate_limit/3,
      opts,
      replace_invalid_values?
    )
    |> put_default_limit(:page_size, opts)
    |> validate_required([:page_size])
    |> validate_and_maybe_delete(
      :page,
      &validate_page/3,
      opts,
      replace_invalid_values?
    )
    |> put_default_value(:page, 1)
  end

  defp validate_by_pagination_type(changeset, nil, opts) do
    put_default_limit(changeset, :limit, opts)
  end

  defp validate_and_maybe_delete(
         changeset,
         field,
         validate_func,
         opts,
         true
       ) do
    validated_changeset = validate_func.(changeset, field, opts)

    if validated_changeset.errors[field] do
      delete_change(changeset, field)
    else
      validated_changeset
    end
  end

  defp validate_and_maybe_delete(
         changeset,
         field,
         validate_func,
         opts,
         _
       ) do
    validate_func.(changeset, field, opts)
  end

  defp validate_offset(changeset, field, _opts) do
    validate_number(changeset, field, greater_than_or_equal_to: 0)
  end

  defp validate_limit(changeset, field, opts) do
    changeset
    |> validate_number(field, greater_than: 0)
    |> validate_within_max_limit(field, opts)
  end

  defp validate_page(changeset, field, _opts) do
    validate_number(changeset, field, greater_than: 0)
  end

  defp validate_sortable(changeset, opts) do
    sortable_fields = Flop.get_option(:sortable, opts)

    if sortable_fields do
      if opts[:replace_invalid_values] do
        order_by = get_field(changeset, :order_by) || []
        order_directions = get_field(changeset, :order_directions) || []

        {order_by, order_directions} =
          Enum.reduce(
            order_by,
            {order_by, order_directions},
            fn field, {order_by, order_directions} ->
              if field in sortable_fields do
                {order_by, order_directions}
              else
                index = Enum.find_index(order_by, &(&1 == field))

                {List.delete_at(order_by, index),
                 List.delete_at(order_directions, index)}
              end
            end
          )

        changeset
        |> put_change(:order_by, order_by)
        |> put_change(:order_directions, order_directions)
      else
        validate_subset(changeset, :order_by, sortable_fields)
      end
    else
      changeset
    end
  end

  defp validate_within_max_limit(changeset, field, opts) do
    max_limit = Flop.get_option(:max_limit, opts)

    if is_nil(max_limit),
      do: changeset,
      else: validate_number(changeset, field, less_than_or_equal_to: max_limit)
  end

  defp validate_cursor(changeset, field, _opts) do
    encoded_cursor = get_field(changeset, field)
    order_fields = get_field(changeset, :order_by)

    if encoded_cursor && order_fields do
      case Cursor.decode(encoded_cursor) do
        {:ok, cursor_map} ->
          if Enum.sort(Map.keys(cursor_map)) == Enum.sort(order_fields),
            do: changeset,
            else: add_error(changeset, field, "does not match order fields")

        :error ->
          add_error(changeset, field, "is invalid")
      end
    else
      changeset
    end
  end

  defp put_default_limit(changeset, field, opts) do
    default_limit = Flop.get_option(:default_limit, opts)
    put_default_value(changeset, field, default_limit)
  end

  defp put_default_order(changeset, opts) do
    if is_nil(get_field(changeset, :order_by)) do
      default_order = Flop.get_option(:default_order, opts)

      changeset
      |> put_change(:order_by, default_order[:order_by])
      |> put_change(:order_directions, default_order[:order_directions])
    else
      changeset
    end
  end

  defp put_default_value(changeset, field, default) do
    if !is_nil(default) && is_nil(get_field(changeset, field)),
      do: put_change(changeset, field, default),
      else: changeset
  end

  defp get_pagination_type(changeset, opts) do
    cond do
      any_field_set?(changeset, :first, :after) -> :first
      any_field_set?(changeset, :last, :before) -> :last
      any_field_set?(changeset, :page, :page_size) -> :page
      any_field_set?(changeset, :limit, :offset) -> :offset
      true -> Flop.get_option(:default_pagination_type, opts)
    end
  end

  defp any_field_set?(changeset, field_a, field_b) do
    get_field(changeset, field_a) || get_field(changeset, field_b)
  end
end
