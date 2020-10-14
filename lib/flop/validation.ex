defmodule Flop.Validation do
  @moduledoc false

  import Ecto.Changeset
  import Flop.Schema

  alias Ecto.Changeset
  alias Flop.Filter

  @spec changeset(map, [Flop.option()]) :: Changeset.t()
  def changeset(%{} = params, opts) do
    %Flop{}
    |> cast(params, [
      :after,
      :before,
      :first,
      :last,
      :limit,
      :offset,
      :order_by,
      :order_directions,
      :page,
      :page_size
    ])
    |> cast_embed(:filters, with: {Filter, :changeset, [opts]})
    |> validate_exclusive(
      [
        [:limit, :offset],
        [:page, :page_size],
        [:first, :after],
        [:last, :before]
      ],
      message: "cannot combine multiple pagination types"
    )
    |> validate_number(:first, greater_than: 0)
    |> validate_number(:last, greater_than: 0)
    |> validate_page_and_page_size(opts[:for])
    |> validate_offset_and_limit(opts[:for])
    |> validate_pagination_types(opts)
    |> validate_sortable(opts[:for])
    |> put_default_order(opts[:for])
    |> validate_order_by_for_cursor_pagination()
  end

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

  defp validate_pagination_types(changeset, opts) do
    pagination_types =
      opts[:pagination_types] ||
        pagination_types_for_schema(opts[:for]) ||
        Application.get_env(:flop, :pagination_types)

    if is_nil(pagination_types) do
      changeset
    else
      case get_pagination_type(changeset) do
        nil ->
          changeset

        pagination_type ->
          if pagination_type in pagination_types,
            do: changeset,
            else: add_pagination_type_error(changeset, pagination_type)
      end
    end
  end

  defp pagination_types_for_schema(nil), do: nil

  defp pagination_types_for_schema(module),
    do: module |> struct() |> pagination_types()

  defp get_pagination_type(changeset) do
    cond do
      get_field(changeset, :first) -> :first
      get_field(changeset, :last) -> :last
      get_field(changeset, :page) -> :page
      get_field(changeset, :limit) -> :offset
      true -> nil
    end
  end

  defp add_pagination_type_error(changeset, pagination_type) do
    case pagination_type do
      :first ->
        add_error(
          changeset,
          :first,
          "cursor-based pagination with first/after is not allowed"
        )

      :last ->
        add_error(
          changeset,
          :last,
          "cursor-based pagination with last/before is not allowed"
        )

      :offset ->
        add_error(
          changeset,
          :limit,
          "offset/limit pagination is not allowed"
        )

      :page ->
        add_error(
          changeset,
          :page,
          "page-based pagination is not allowed"
        )
    end
  end

  defp validate_order_by_for_cursor_pagination(changeset) do
    if get_field(changeset, :first) || get_field(changeset, :last) do
      validate_required(changeset, [:order_by])
    else
      changeset
    end
  end

  @spec validate_sortable(Changeset.t(), module | nil) :: Changeset.t()
  defp validate_sortable(changeset, nil), do: changeset

  defp validate_sortable(changeset, module) do
    sortable_fields =
      module
      |> struct()
      |> sortable()

    validate_subset(changeset, :order_by, sortable_fields)
  end

  @spec validate_page_and_page_size(Changeset.t(), module | nil) ::
          Changeset.t()
  defp validate_page_and_page_size(changeset, module) do
    page = get_field(changeset, :page)
    page_size = get_field(changeset, :page_size)

    if !is_nil(page) || !is_nil(page_size) do
      changeset
      |> validate_required([:page_size])
      |> validate_number(:page, greater_than: 0)
      |> validate_number(:page_size, greater_than: 0)
      |> validate_within_max_limit(:page_size, module)
      |> put_default_page()
    else
      changeset
    end
  end

  defp put_default_page(
         %Changeset{valid?: true, changes: %{page_size: page_size}} = changeset
       )
       when is_integer(page_size) do
    if is_nil(get_field(changeset, :page)),
      do: put_change(changeset, :page, 1),
      else: changeset
  end

  defp put_default_page(changeset), do: changeset

  @spec validate_offset_and_limit(Changeset.t(), module | nil) :: Changeset.t()
  defp validate_offset_and_limit(changeset, module) do
    changeset
    |> validate_number(:limit, greater_than: 0)
    |> validate_within_max_limit(:limit, module)
    |> validate_within_max_limit(:first, module)
    |> validate_within_max_limit(:last, module)
    |> validate_number(:offset, greater_than_or_equal_to: 0)
    |> put_default_limit(module)
    |> put_default_offset()
  end

  defp put_default_limit(changeset, nil), do: changeset

  defp put_default_limit(%Changeset{valid?: false} = changeset, _),
    do: changeset

  defp put_default_limit(changeset, module) do
    default_limit =
      module |> struct() |> default_limit() ||
        Application.get_env(:flop, :default_limit)

    if is_nil(default_limit) do
      changeset
    else
      limit = get_field(changeset, :limit)
      page_size = get_field(changeset, :page_size)
      first = get_field(changeset, :first)
      last = get_field(changeset, :last)

      if is_nil(limit) && is_nil(page_size) && is_nil(first) && is_nil(last) do
        put_change(changeset, :limit, default_limit)
      else
        changeset
      end
    end
  end

  defp put_default_offset(
         %Changeset{valid?: true, changes: %{limit: limit}} = changeset
       )
       when is_integer(limit) do
    if is_nil(get_field(changeset, :offset)),
      do: put_change(changeset, :offset, 0),
      else: changeset
  end

  defp put_default_offset(changeset), do: changeset

  defp put_default_order(changeset, nil), do: changeset

  defp put_default_order(changeset, module) do
    order_by = get_field(changeset, :order_by)

    if is_nil(order_by) do
      default_order = module |> struct() |> default_order()

      changeset
      |> put_change(:order_by, default_order[:order_by])
      |> put_change(:order_directions, default_order[:order_directions])
    else
      changeset
    end
  end

  @spec validate_within_max_limit(Changeset.t(), atom, module | nil) ::
          Changeset.t()
  defp validate_within_max_limit(changeset, _field, nil), do: changeset

  defp validate_within_max_limit(changeset, field, module) do
    max_limit =
      module |> struct() |> max_limit() ||
        Application.get_env(:flop, :max_limit)

    if is_nil(max_limit),
      do: changeset,
      else: validate_number(changeset, field, less_than_or_equal_to: max_limit)
  end
end
