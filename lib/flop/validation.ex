defmodule Flop.Validation do
  @moduledoc false

  alias Ecto.Changeset
  alias Flop.Cursor
  alias Flop.Filter

  @spec changeset(map, [Flop.option()]) :: Changeset.t()
  def changeset(%{} = params, opts) do
    replace_invalid_params? = Keyword.get(opts, :replace_invalid_params, false)

    %Flop{}
    |> Changeset.cast(params, [])
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
      replace_invalid_params: replace_invalid_params?
    )
    |> validate_sortable(opts)
    |> put_default_order(opts)
    |> validate_pagination(opts)
    |> maybe_remove_invalid_filters(replace_invalid_params?)
  end

  defp maybe_remove_invalid_filters(changeset, true) do
    changeset =
      Changeset.update_change(changeset, :filters, fn
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

      Changeset.cast(changeset, params, fields)
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
      do: Changeset.cast(changeset, params, [:order_by, :order_directions]),
      else: changeset
  end

  defp cast_filters(changeset, opts) do
    if Flop.get_option(:filtering, opts, true) do
      Changeset.cast_embed(changeset, :filters,
        with: &Filter.changeset(&1, &2, opts)
      )
    else
      changeset
    end
  end

  # Takes a list of field groups and validates that no fields from multiple
  # groups are set.
  @spec validate_exclusive(Changeset.t(), [[atom]], keyword) :: Changeset.t()
  defp validate_exclusive(changeset, field_groups, opts) do
    changes = changeset.changes

    changed_field_groups =
      Enum.filter(field_groups, fn fields ->
        Enum.any?(fields, &Map.has_key?(changes, &1))
      end)

    if length(changed_field_groups) > 1 do
      key = List.first(List.first(changed_field_groups))

      if opts[:replace_invalid_params] do
        field_groups
        |> List.flatten()
        |> Enum.reduce(changeset, &Changeset.delete_change(&2, &1))
      else
        Changeset.add_error(
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
    replace_invalid_params? = opts[:replace_invalid_params]

    changeset
    |> validate_and_maybe_delete(
      :first,
      &validate_limit/3,
      opts,
      replace_invalid_params?
    )
    |> put_default_limit(:first, opts)
    |> Changeset.validate_required([:first, :order_by])
    |> Changeset.validate_length(:order_by, min: 1)
    |> validate_and_maybe_delete(
      :after,
      &validate_cursor/3,
      opts,
      replace_invalid_params?
    )
  end

  defp validate_by_pagination_type(changeset, :last, opts) do
    replace_invalid_params? = opts[:replace_invalid_params]

    changeset
    |> validate_and_maybe_delete(
      :last,
      &validate_limit/3,
      opts,
      replace_invalid_params?
    )
    |> put_default_limit(:last, opts)
    |> Changeset.validate_required([:last, :order_by])
    |> Changeset.validate_length(:order_by, min: 1)
    |> validate_and_maybe_delete(
      :before,
      &validate_cursor/3,
      opts,
      replace_invalid_params?
    )
  end

  defp validate_by_pagination_type(changeset, :offset, opts) do
    replace_invalid_params? = opts[:replace_invalid_params]

    changeset
    |> validate_and_maybe_delete(
      :limit,
      &validate_limit/3,
      opts,
      replace_invalid_params?
    )
    |> put_default_limit(:limit, opts)
    |> Changeset.validate_required([:limit])
    |> validate_and_maybe_delete(
      :offset,
      &validate_offset/3,
      opts,
      replace_invalid_params?
    )
    |> put_default_value(:offset, 0)
  end

  defp validate_by_pagination_type(changeset, :page, opts) do
    replace_invalid_params? = opts[:replace_invalid_params]

    changeset
    |> validate_and_maybe_delete(
      :page_size,
      &validate_limit/3,
      opts,
      replace_invalid_params?
    )
    |> put_default_limit(:page_size, opts)
    |> Changeset.validate_required([:page_size])
    |> validate_and_maybe_delete(
      :page,
      &validate_page/3,
      opts,
      replace_invalid_params?
    )
    |> put_default_value(:page, 1)
  end

  defp validate_by_pagination_type(changeset, pagination_type, opts)
       when pagination_type in [nil, false] do
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
      changeset
      |> Changeset.delete_change(field)
      |> Map.update!(:errors, &Keyword.delete(&1, field))
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
    Changeset.validate_number(changeset, field, greater_than_or_equal_to: 0)
  end

  defp validate_limit(changeset, field, opts) do
    changeset
    |> Changeset.validate_number(field, greater_than: 0)
    |> validate_within_max_limit(field, opts)
  end

  defp validate_page(changeset, field, _opts) do
    Changeset.validate_number(changeset, field, greater_than: 0)
  end

  defp validate_sortable(changeset, opts) do
    sortable_fields = Flop.get_option(:sortable, opts)

    if sortable_fields do
      if opts[:replace_invalid_params] do
        order_by = get_value(changeset, :order_by) || []

        order_directions =
          get_value(changeset, :order_directions) || []

        {new_order_by, new_order_directions} =
          remove_unsortable_fields(order_by, order_directions, sortable_fields)

        changeset
        |> Changeset.put_change(:order_by, new_order_by)
        |> Changeset.put_change(:order_directions, new_order_directions)
        |> Map.update!(
          :errors,
          &Keyword.drop(&1, [:order_by, :order_directions])
        )
      else
        Changeset.validate_subset(changeset, :order_by, sortable_fields)
      end
    else
      changeset
    end
  end

  defp remove_unsortable_fields(order_by, order_directions, sortable_fields) do
    Enum.reduce(
      order_by,
      {order_by, order_directions},
      fn field, {acc_order_by, acc_order_directions} ->
        if field in sortable_fields do
          {acc_order_by, acc_order_directions}
        else
          index = Enum.find_index(acc_order_by, &(&1 == field))

          {List.delete_at(acc_order_by, index),
           List.delete_at(acc_order_directions, index)}
        end
      end
    )
  end

  defp validate_within_max_limit(changeset, field, opts) do
    if max_limit = Flop.get_option(:max_limit, opts) do
      Changeset.validate_number(changeset, field,
        less_than_or_equal_to: max_limit
      )
    else
      changeset
    end
  end

  defp validate_cursor(changeset, field, _opts) do
    encoded_cursor = get_value(changeset, field)
    order_fields = get_value(changeset, :order_by)

    if encoded_cursor && order_fields do
      validate_cursors_match_order_fields(
        changeset,
        field,
        encoded_cursor,
        order_fields
      )
    else
      changeset
    end
  end

  defp validate_cursors_match_order_fields(
         changeset,
         field,
         encoded_cursor,
         order_fields
       ) do
    case Cursor.decode(encoded_cursor) do
      {:ok, cursor_map} ->
        if Enum.sort(Map.keys(cursor_map)) == Enum.sort(order_fields),
          do: Changeset.put_change(changeset, :decoded_cursor, cursor_map),
          else:
            Changeset.add_error(changeset, field, "does not match order fields")

      :error ->
        Changeset.add_error(changeset, field, "is invalid")
    end
  end

  defp put_default_limit(changeset, field, opts) do
    default_limit = Flop.get_option(:default_limit, opts)
    put_default_value(changeset, field, default_limit)
  end

  defp put_default_order(changeset, opts) do
    order_by = get_value(changeset, :order_by)

    if is_nil(order_by) || order_by == [] do
      default_order = Flop.get_option(:default_order, opts)

      changeset
      |> Changeset.put_change(:order_by, default_order[:order_by])
      |> Changeset.put_change(
        :order_directions,
        default_order[:order_directions]
      )
    else
      changeset
    end
  end

  defp put_default_value(changeset, _, nil), do: changeset
  defp put_default_value(changeset, _, false), do: changeset

  defp put_default_value(%{changes: changes} = changeset, field, default) do
    case changes do
      %{^field => value} when not is_nil(value) -> changeset
      _ -> Changeset.put_change(changeset, field, default)
    end
  end

  defp get_pagination_type(%Changeset{} = changeset, opts) do
    cond do
      any_change_or_errors?(changeset, :first, :after) -> :first
      any_change_or_errors?(changeset, :last, :before) -> :last
      any_change_or_errors?(changeset, :page, :page_size) -> :page
      any_change_or_errors?(changeset, :limit, :offset) -> :offset
      true -> Flop.get_option(:default_pagination_type, opts)
    end
  end

  defp any_change_or_errors?(
         %Changeset{changes: changes, errors: errors},
         field_a,
         field_b
       ) do
    case changes do
      %{^field_a => value} when not is_nil(value) ->
        true

      %{^field_b => value} when not is_nil(value) ->
        true

      _ ->
        Keyword.has_key?(errors, field_a) || Keyword.has_key?(errors, field_b)
    end
  end

  defp get_value(%Changeset{changes: changes}, field) do
    case changes do
      %{^field => value} -> value
      _ -> nil
    end
  end
end
