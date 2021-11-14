defmodule Flop.Validation do
  @moduledoc false

  import Ecto.Changeset

  alias Ecto.Changeset
  alias Flop.Cursor
  alias Flop.Filter

  @spec changeset(map, [Flop.option()]) :: Changeset.t()
  def changeset(%{} = params, opts) do
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
      message: "cannot combine multiple pagination types"
    )
    |> put_default_order(opts)
    |> validate_sortable(opts)
    |> validate_pagination(opts)
  end

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

      add_error(
        changeset,
        key,
        opts[:message] || "invalid combination of field groups"
      )
    else
      changeset
    end
  end

  defp validate_pagination(changeset, opts) do
    pagination_type = get_pagination_type(changeset, opts)
    validate_by_pagination_type(changeset, pagination_type, opts)
  end

  defp validate_by_pagination_type(changeset, :first, opts) do
    changeset
    |> put_default_limit(:first, opts)
    |> validate_required([:first, :order_by])
    |> validate_number(:first, greater_than: 0)
    |> validate_within_max_limit(:first, opts)
    |> validate_length(:order_by, min: 1)
    |> validate_cursor(:after)
  end

  defp validate_by_pagination_type(changeset, :last, opts) do
    changeset
    |> put_default_limit(:last, opts)
    |> validate_required([:last, :order_by])
    |> validate_number(:last, greater_than: 0)
    |> validate_within_max_limit(:last, opts)
    |> validate_length(:order_by, min: 1)
    |> validate_cursor(:before)
  end

  defp validate_by_pagination_type(changeset, :offset, opts) do
    changeset
    |> put_default_limit(:limit, opts)
    |> put_default_value(:offset, 0)
    |> validate_number(:limit, greater_than: 0)
    |> validate_number(:offset, greater_than_or_equal_to: 0)
    |> validate_within_max_limit(:limit, opts)
  end

  defp validate_by_pagination_type(changeset, :page, opts) do
    changeset
    |> put_default_limit(:page_size, opts)
    |> put_default_value(:page, 1)
    |> validate_required([:page_size])
    |> validate_number(:page, greater_than: 0)
    |> validate_number(:page_size, greater_than: 0)
    |> validate_within_max_limit(:page_size, opts)
  end

  defp validate_by_pagination_type(changeset, nil, opts) do
    put_default_limit(changeset, :limit, opts)
  end

  defp validate_sortable(changeset, opts) do
    sortable_fields = Flop.get_option(:sortable, opts)

    if sortable_fields,
      do: validate_subset(changeset, :order_by, sortable_fields),
      else: changeset
  end

  defp validate_within_max_limit(changeset, field, opts) do
    max_limit = Flop.get_option(:max_limit, opts)

    if is_nil(max_limit),
      do: changeset,
      else: validate_number(changeset, field, less_than_or_equal_to: max_limit)
  end

  defp validate_cursor(changeset, field) do
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
