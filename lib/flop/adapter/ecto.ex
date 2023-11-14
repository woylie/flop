defmodule Flop.Adapter.Ecto do
  @moduledoc false

  @behaviour Flop.Adapter

  import Ecto.Query
  import Flop.Adapter.Ecto.Operators

  alias Ecto.Query
  alias Flop.FieldInfo
  alias Flop.Filter
  alias Flop.NimbleSchemas

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

  @backend_options [
    repo: [required: true],
    query_opts: [type: :keyword_list, default: []]
  ]

  @schema_options [
    join_fields: [
      type: :keyword_list,
      default: [],
      keys: [
        *: [
          type:
            {:or,
             [
               keyword_list: [
                 binding: [type: :atom, required: true],
                 field: [type: :atom, required: true],
                 ecto_type: [type: :any],
                 path: [type: {:list, :atom}]
               ],
               tuple: [:atom, :atom]
             ]}
        ]
      ]
    ],
    compound_fields: [
      type: :keyword_list,
      default: [],
      keys: [
        *: [
          type: {:list, :atom}
        ]
      ]
    ],
    custom_fields: [
      type: :keyword_list,
      default: [],
      keys: [
        *: [
          type: :keyword_list,
          keys: [
            filter: [
              type: {:tuple, [:atom, :atom, :keyword_list]},
              required: true
            ],
            ecto_type: [type: :any],
            bindings: [type: {:list, :atom}],
            operators: [type: {:list, :atom}]
          ]
        ]
      ]
    ],
    alias_fields: [
      type: {:list, :atom},
      default: []
    ]
  ]

  @backend_options NimbleOptions.new!(@backend_options)
  @schema_options NimbleOptions.new!(@schema_options)

  defp __backend_options__, do: @backend_options
  defp __schema_options__, do: @schema_options

  @impl Flop.Adapter
  def init_backend_opts(_opts, backend_opts, caller_module) do
    NimbleSchemas.validate!(
      backend_opts,
      __backend_options__(),
      Flop,
      caller_module
    )
  end

  @impl Flop.Adapter
  def init_schema_opts(opts, schema_opts, caller_module, struct) do
    schema_opts =
      NimbleSchemas.validate!(
        schema_opts,
        __schema_options__(),
        Flop.Schema,
        caller_module
      )

    schema_opts
    |> validate_no_duplicate_fields!()
    |> normalize_schema_opts()
    |> validate_alias_fields!(opts)
    |> validate_compound_fields!(struct)
    |> validate_custom_fields!(opts)
  end

  @impl Flop.Adapter
  def fields(struct, opts) do
    alias_fields(opts) ++
      compound_fields(opts) ++
      custom_fields(opts) ++
      join_fields(opts) ++
      schema_fields(struct)
  end

  defp alias_fields(%{alias_fields: alias_fields}) do
    Enum.map(alias_fields, &{&1, %FieldInfo{extra: %{type: :alias}}})
  end

  defp compound_fields(%{compound_fields: compound_fields}) do
    Enum.map(compound_fields, fn {field, fields} ->
      {field,
       %FieldInfo{
         ecto_type: :string,
         operators: [
           :=~,
           :like,
           :not_like,
           :like_and,
           :like_or,
           :ilike,
           :not_ilike,
           :ilike_and,
           :ilike_or,
           :empty,
           :not_empty
         ],
         extra: %{fields: fields, type: :compound}
       }}
    end)
  end

  defp join_fields(%{join_fields: join_fields}) do
    Enum.map(join_fields, fn
      {field, %{} = field_opts} ->
        extra = field_opts |> Map.delete(:ecto_type) |> Map.put(:type, :join)

        {field,
         %FieldInfo{
           ecto_type: field_opts.ecto_type,
           extra: extra
         }}
    end)
  end

  defp custom_fields(%{custom_fields: custom_fields}) do
    Enum.map(custom_fields, fn {field, field_opts} ->
      extra =
        field_opts
        |> Map.drop([:ecto_type, :operators])
        |> Map.put(:type, :custom)

      {field,
       %FieldInfo{
         ecto_type: field_opts.ecto_type,
         operators: field_opts.operators,
         extra: extra
       }}
    end)
  end

  defp schema_fields(%module{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn
      {_, %Ecto.Association.NotLoaded{}} -> true
      {:__meta__, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {field, _} ->
      {field,
       %FieldInfo{
         ecto_type: {:from_schema, module, field},
         extra: %{type: :normal, field: field}
       }}
    end)
  end

  @impl Flop.Adapter
  def get_field(%{} = item, _field, %FieldInfo{
        extra: %{type: :compound, fields: fields}
      }) do
    Enum.map_join(fields, " ", &get_field(item, &1, %FieldInfo{}))
  end

  def get_field(%{} = item, _field, %FieldInfo{
        extra: %{type: :join, path: path}
      }) do
    Enum.reduce(path, item, fn
      field, %{} = acc -> Map.get(acc, field)
      _, _ -> nil
    end)
  end

  def get_field(%{} = item, field, %FieldInfo{}) do
    Map.get(item, field)
  end

  @impl Flop.Adapter
  def apply_filter(
        query,
        %Flop.Filter{field: field} = filter,
        schema_struct,
        opts
      ) do
    case get_field_info(schema_struct, field) do
      %FieldInfo{extra: %{type: :custom} = custom_opts} ->
        {mod, fun, custom_filter_opts} = Map.fetch!(custom_opts, :filter)

        opts =
          opts
          |> Keyword.get(:extra_opts, [])
          |> Keyword.merge(custom_filter_opts)

        apply(mod, fun, [query, filter, opts])

      field_info ->
        Query.where(query, ^build_op(schema_struct, field_info, filter))
    end
  end

  @impl Flop.Adapter
  def apply_order_by(query, directions, opts) do
    case opts[:for] do
      nil ->
        Query.order_by(query, ^directions)

      module ->
        struct = struct(module)

        Enum.reduce(directions, query, fn {_, field} = expr, acc_query ->
          field_info = Flop.Schema.field_info(struct, field)
          apply_order_by_field(acc_query, expr, field_info, struct)
        end)
    end
  end

  defp apply_order_by_field(
         q,
         {direction, _},
         %FieldInfo{
           extra: %{type: :join, binding: binding, field: field}
         },
         _
       ) do
    order_by(q, [{^binding, r}], [{^direction, field(r, ^field)}])
  end

  defp apply_order_by_field(
         q,
         {direction, _},
         %FieldInfo{
           extra: %{type: :compound, fields: fields}
         },
         struct
       ) do
    Enum.reduce(fields, q, fn field, acc_query ->
      field_info = Flop.Schema.field_info(struct, field)
      apply_order_by_field(acc_query, {direction, field}, field_info, struct)
    end)
  end

  defp apply_order_by_field(
         q,
         {direction, field},
         %FieldInfo{extra: %{type: :alias}},
         _
       ) do
    order_by(q, [{^direction, selected_as(^field)}])
  end

  defp apply_order_by_field(q, order_expr, _, _) do
    order_by(q, ^order_expr)
  end

  @impl Flop.Adapter
  def apply_limit_offset(query, limit, offset, _opts) do
    query
    |> apply_limit(limit)
    |> apply_offset(offset)
  end

  defp apply_limit(q, nil), do: q
  defp apply_limit(q, limit), do: Query.limit(q, ^limit)

  defp apply_offset(q, nil), do: q
  defp apply_offset(q, offset), do: Query.offset(q, ^offset)

  @impl Flop.Adapter
  def apply_page_page_size(query, page, page_size, _opts) do
    offset_for_page = (page - 1) * page_size

    query
    |> limit(^page_size)
    |> offset(^offset_for_page)
  end

  @impl Flop.Adapter
  def apply_cursor(q, cursor_fields, _opts) do
    where_dynamic = cursor_dynamic(cursor_fields)
    Query.where(q, ^where_dynamic)
  end

  defp cursor_dynamic([]), do: true

  defp cursor_dynamic([{_, _, _, %FieldInfo{extra: %{type: :compound}}} | t]) do
    Logger.warning(
      "Flop: Cursor pagination is not supported for compound fields. Ignored."
    )

    cursor_dynamic(t)
  end

  defp cursor_dynamic([{_, _, _, %FieldInfo{extra: %{type: :alias}}} | _]) do
    raise "alias fields are not supported in cursor pagination"
  end

  # no cursor value, last cursor field
  defp cursor_dynamic([{_, _, nil, _}]) do
    true
  end

  # no cursor value, more cursor fields to come
  defp cursor_dynamic([{_, _, nil, _} | [{_, _, _, _} | _] = tail]) do
    cursor_dynamic(tail)
  end

  # join field ascending, last cursor field
  defp cursor_dynamic([
         {direction, _, cursor_value,
          %FieldInfo{extra: %{binding: binding, field: field, type: :join}}}
       ])
       when direction in [:asc, :asc_nulls_first, :asc_nulls_last] do
    dynamic(
      [{^binding, r}],
      field(r, ^field) > type(^cursor_value, field(r, ^field))
    )
  end

  # join field descending, last cursor field
  defp cursor_dynamic([
         {direction, _, cursor_value,
          %FieldInfo{extra: %{binding: binding, field: field, type: :join}}}
       ])
       when direction in [:desc, :desc_nulls_first, :desc_nulls_last] do
    dynamic(
      [{^binding, r}],
      field(r, ^field) < type(^cursor_value, field(r, ^field))
    )
  end

  # join field ascending, more cursor fields to come
  defp cursor_dynamic([
         {direction, _, cursor_value,
          %FieldInfo{extra: %{binding: binding, field: field, type: :join}}}
         | [{_, _, _, _} | _] = tail
       ])
       when direction in [:asc, :asc_nulls_first, :asc_nulls_last] do
    dynamic(
      [{^binding, r}],
      field(r, ^field) >= type(^cursor_value, field(r, ^field)) and
        (field(r, ^field) > type(^cursor_value, field(r, ^field)) or
           ^cursor_dynamic(tail))
    )
  end

  # join field descending, more cursor fields to come
  defp cursor_dynamic([
         {direction, _, cursor_value,
          %FieldInfo{extra: %{binding: binding, field: field, type: :join}}}
         | [{_, _, _, _} | _] = tail
       ])
       when direction in [:desc, :desc_nulls_first, :desc_nulls_last] do
    dynamic(
      [{^binding, r}],
      field(r, ^field) <= type(^cursor_value, field(r, ^field)) and
        (field(r, ^field) < type(^cursor_value, field(r, ^field)) or
           ^cursor_dynamic(tail))
    )
  end

  # any other field type ascending, last cursor field
  defp cursor_dynamic([{direction, field, cursor_value, _}])
       when direction in [:asc, :asc_nulls_first, :asc_nulls_last] do
    dynamic([r], field(r, ^field) > type(^cursor_value, field(r, ^field)))
  end

  # any other field type descending, last cursor field
  defp cursor_dynamic([{direction, field, cursor_value, _}])
       when direction in [:desc, :desc_nulls_first, :desc_nulls_last] do
    dynamic([r], field(r, ^field) < type(^cursor_value, field(r, ^field)))
  end

  # any other field type ascending, more cursor fields to come
  defp cursor_dynamic([
         {direction, field, cursor_value, _} | [{_, _, _, _} | _] = tail
       ])
       when direction in [:asc, :asc_nulls_first, :asc_nulls_last] do
    dynamic(
      [r],
      field(r, ^field) >= type(^cursor_value, field(r, ^field)) and
        (field(r, ^field) > type(^cursor_value, field(r, ^field)) or
           ^cursor_dynamic(tail))
    )
  end

  # any other field type descending, more cursor fields to come
  defp cursor_dynamic([
         {direction, field, cursor_value, _} | [{_, _, _, _} | _] = tail
       ])
       when direction in [:desc, :desc_nulls_first, :desc_nulls_last] do
    dynamic(
      [r],
      field(r, ^field) <= type(^cursor_value, field(r, ^field)) and
        (field(r, ^field) < type(^cursor_value, field(r, ^field)) or
           ^cursor_dynamic(tail))
    )
  end

  @impl Flop.Adapter
  def list(query, opts) do
    apply_on_repo(:all, "all", [query], opts)
  end

  @impl Flop.Adapter
  def count(query, opts) do
    query = count_query(query)
    apply_on_repo(:aggregate, "count", [query, :count], opts)
  end

  defp count_query(query) do
    query =
      query
      |> Query.exclude(:preload)
      |> Query.exclude(:order_by)
      |> Query.exclude(:select)

    case query do
      %{group_bys: group_bys} = query when group_bys != [] ->
        query
        |> Query.select(%{})
        |> Query.subquery()

      query ->
        query
    end
  end

  defp apply_on_repo(repo_fn, flop_fn, args, opts) do
    # use nested adapter_opts if set
    opts = Flop.get_option(:adapter_opts, opts) || opts

    repo =
      Flop.get_option(:repo, opts) ||
        raise Flop.NoRepoError, function_name: flop_fn

    opts = query_opts(opts)

    apply(repo, repo_fn, args ++ [opts])
  end

  defp query_opts(opts) do
    default_opts = Application.get_env(:flop, :query_opts, [])
    Keyword.merge(default_opts, Keyword.get(opts, :query_opts, []))
  end

  ## Filter query builder

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
           %FieldInfo{extra: %{type: :compound, fields: fields}},
           %Filter{op: unquote(op), value: value}
         ) do
      fields = Enum.map(fields, &get_field_info(schema_struct, &1))

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
         %FieldInfo{extra: %{type: :compound, fields: fields}},
         %Filter{op: op} = filter
       )
       when op in [:=~, :like, :not_like, :ilike, :not_ilike, :not_empty] do
    fields
    |> Enum.map(&get_field_info(schema_struct, &1))
    |> Enum.reduce(false, fn field, dynamic ->
      dynamic_for_field =
        build_op(schema_struct, field, %{filter | field: field})

      dynamic([r], ^dynamic or ^dynamic_for_field)
    end)
  end

  defp build_op(
         schema_struct,
         %FieldInfo{extra: %{type: :compound, fields: fields}},
         %Filter{op: :empty} = filter
       ) do
    fields
    |> Enum.map(&get_field_info(schema_struct, &1))
    |> Enum.reduce(true, fn field, dynamic ->
      dynamic_for_field =
        build_op(schema_struct, field, %{filter | field: field})

      dynamic([r], ^dynamic and ^dynamic_for_field)
    end)
  end

  defp build_op(
         _schema_struct,
         %FieldInfo{extra: %{type: :compound}},
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
    Logger.warning(
      "Flop: Operator '#{op}' not supported for compound fields. Ignored."
    )

    true
  end

  defp build_op(
         %module{},
         %FieldInfo{extra: %{type: :normal, field: field}},
         %Filter{op: op, value: value}
       )
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
         %FieldInfo{
           ecto_type: ecto_type,
           extra: %{type: :join, binding: binding, field: field}
         },
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
           %FieldInfo{extra: %{type: :normal, field: field}},
           %Filter{op: unquote(op), value: value}
         ) do
      unquote(prelude)
      build_dynamic(unquote(fragment), false, unquote(combinator))
    end

    defp build_op(
           _schema_struct,
           %FieldInfo{extra: %{type: :join, binding: binding, field: field}},
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

  defp get_field_info(nil, field),
    do: %FieldInfo{extra: %{type: :normal, field: field}}

  defp get_field_info(struct, field) when is_atom(field) do
    Flop.Schema.field_info(struct, field)
  end

  ## Option normalization

  defp normalize_schema_opts(opts) do
    opts
    |> Map.new()
    |> Map.update!(:compound_fields, &normalize_compound_fields/1)
    |> Map.update!(:custom_fields, &normalize_custom_fields/1)
    |> Map.update!(:join_fields, &normalize_join_fields/1)
  end

  defp normalize_compound_fields(fields) do
    Enum.into(fields, %{})
  end

  defp normalize_custom_fields(fields) do
    Enum.into(fields, %{}, &normalize_custom_field_opts/1)
  end

  defp normalize_custom_field_opts({name, opts}) when is_list(opts) do
    opts = %{
      filter: Keyword.fetch!(opts, :filter),
      ecto_type: Keyword.get(opts, :ecto_type),
      operators: Keyword.get(opts, :operators),
      bindings: Keyword.get(opts, :bindings, [])
    }

    {name, opts}
  end

  defp normalize_join_fields(fields) do
    Enum.into(fields, %{}, &normalize_join_field_opts/1)
  end

  defp normalize_join_field_opts({name, {binding, field}}) do
    Logger.warning(
      "The tuple syntax for defining Flop join fields has been deprecated. Use a keyword list instead."
    )

    opts = %{
      binding: binding,
      field: field,
      path: [binding, field],
      ecto_type: nil
    }

    {name, opts}
  end

  defp normalize_join_field_opts({name, opts}) when is_list(opts) do
    binding = Keyword.fetch!(opts, :binding)
    field = Keyword.fetch!(opts, :field)

    opts = %{
      binding: binding,
      field: field,
      path: opts[:path] || [binding, field],
      ecto_type: Keyword.get(opts, :ecto_type)
    }

    {name, opts}
  end

  ## Option validation

  defp validate_no_duplicate_fields!(opts) when is_list(opts) do
    duplicates =
      opts
      |> Keyword.take([
        :alias_fields,
        :compound_fields,
        :custom_fields,
        :join_fields
      ])
      |> Enum.flat_map(fn
        {:alias_fields, fields} -> fields
        {_, fields} -> Keyword.keys(fields)
      end)
      |> duplicates()

    if duplicates != [] do
      raise ArgumentError, """
      duplicate fields

      Alias field, compound field, custom field and join field names must be
      unique. These field names were used multiple times:

          #{inspect(duplicates)}
      """
    end

    opts
  end

  defp validate_alias_fields!(
         %{alias_fields: alias_fields} = adapter_opts,
         opts
       ) do
    filterable = Keyword.fetch!(opts, :filterable)
    illegal_fields = Enum.filter(alias_fields, &(&1 in filterable))

    if illegal_fields != [] do
      raise ArgumentError, """
      cannot filter by alias fields

      Alias fields are not allowed to be filterable. These alias fields were
      configured as filterable:

          #{inspect(illegal_fields)}

      Use custom fields if you want to implement custom filtering.
      """
    end

    adapter_opts
  end

  defp validate_compound_fields!(
         %{compound_fields: compound_fields} = adapter_opts,
         struct
       ) do
    known_fields =
      Keyword.keys(schema_fields(struct) ++ join_fields(adapter_opts))

    Enum.each(compound_fields, fn {field, fields} ->
      unknown_fields = Enum.reject(fields, &(&1 in known_fields))

      if unknown_fields != [] do
        raise ArgumentError, """
        compound field references unknown field(s)

        Compound fields must reference existing fields, but #{inspect(field)}
        references:

            #{inspect(unknown_fields)}
        """
      end
    end)

    adapter_opts
  end

  defp validate_custom_fields!(
         %{custom_fields: custom_fields} = adapter_opts,
         opts
       ) do
    sortable = Keyword.fetch!(opts, :sortable)

    illegal_fields =
      custom_fields
      |> Map.keys()
      |> Enum.filter(&(&1 in sortable))

    if illegal_fields != [] do
      raise ArgumentError, """
      cannot sort by custom fields

      Custom fields are not allowed to be sortable. These custom fields were
      configured as sortable:

          #{inspect(illegal_fields)}

      Use alias fields if you want to implement custom sorting.
      """
    end

    adapter_opts
  end

  defp duplicates(fields) do
    fields
    |> Enum.frequencies()
    |> Enum.filter(fn {_, count} -> count > 1 end)
    |> Enum.map(fn {field, _} -> field end)
  end
end
