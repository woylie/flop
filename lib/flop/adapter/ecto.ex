defmodule Flop.Adapter.Ecto do
  @moduledoc false

  @behaviour Flop.Adapter

  import Ecto.Query
  import Flop.Adapter.Ecto.Operators

  alias Ecto.Query
  alias Flop.Adapter.Ecto.Dialect
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
    :ilike_or,
    :starts_with,
    :ends_with
  ]

  # operators built from ILIKE, which is a PostgreSQL extension
  @ilike_operators [
    :=~,
    :ilike,
    :not_ilike,
    :ilike_and,
    :ilike_or,
    :starts_with,
    :ends_with
  ]

  @compound_operators [
    :=~,
    :like,
    :not_like,
    :like_and,
    :like_or,
    :ilike,
    :not_ilike,
    :ilike_and,
    :ilike_or,
    :starts_with,
    :ends_with,
    :empty,
    :not_empty
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
          type: :keyword_list,
          keys: [
            binding: [type: :atom, required: true],
            field: [type: :atom, required: true],
            ecto_type: [
              type: {:custom, NimbleSchemas, :validate_ecto_type, []},
              required: true
            ],
            path: [type: {:list, :atom}]
          ]
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
            filter: [type: {:tuple, [:atom, :atom, :keyword_list]}],
            field_dynamic: [type: {:tuple, [:atom, :atom, :keyword_list]}],
            ecto_type: [
              type: {:custom, NimbleSchemas, :validate_ecto_type, []},
              required: true
            ],
            bindings: [type: {:list, :atom}],
            operators: [type: {:list, :atom}],
            path: [type: {:list, :atom}]
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
    Enum.uniq_by(
      alias_fields(opts) ++
        compound_fields(opts) ++
        custom_fields(opts) ++
        join_fields(opts) ++
        schema_fields(struct),
      fn {name, _} -> name end
    )
  end

  defp alias_fields(%{alias_fields: alias_fields}) do
    Enum.map(alias_fields, &{&1, %FieldInfo{extra: %{type: :alias}}})
  end

  defp compound_fields(%{compound_fields: compound_fields}) do
    Enum.map(compound_fields, fn {field, fields} ->
      {field,
       %FieldInfo{
         ecto_type: :string,
         operators: @compound_operators,
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
        extra: %{type: :custom, path: path}
      }) do
    walk_path(item, path)
  end

  def get_field(%{} = item, _field, %FieldInfo{
        extra: %{type: :join, path: path}
      }) do
    walk_path(item, path)
  end

  def get_field(%{} = item, field, %FieldInfo{}) do
    Map.get(item, field)
  end

  defp walk_path(item, path) do
    Enum.reduce(path, item, fn
      field, %{} = acc -> Map.get(acc, field)
      _, _ -> nil
    end)
  end

  @impl Flop.Adapter
  def apply_filter(
        query,
        %Flop.Filter{field: field} = filter,
        schema_struct,
        opts
      ) do
    case get_field_info(schema_struct, field) do
      %FieldInfo{
        extra: %{type: :custom, filter: {mod, fun, custom_filter_opts}}
      } ->
        opts =
          opts
          |> Keyword.get(:extra_opts, [])
          |> Keyword.merge(custom_filter_opts)

        apply(mod, fun, [query, filter, opts])

      %FieldInfo{
        ecto_type: ecto_type,
        extra: %{type: :custom, field_dynamic: {mod, fun, field_dynamic_opts}}
      } ->
        Query.where(
          query,
          ^build_op_dynamic(
            filter,
            dialect(opts),
            custom_field_dynamic(mod, fun, field_dynamic_opts, opts),
            Flop.Misc.expand_type(ecto_type)
          )
        )

      # only reachable with an unvalidated Flop struct
      %FieldInfo{extra: %{type: :custom}} ->
        raise ArgumentError, """
        filtering by a custom field requires a filter function

        No filter function is configured for #{inspect(field)}, so it cannot be
        used as a filter field.

        Use Flop.validate/2 to turn this exception into a validation error.
        """

      field_info ->
        Query.where(
          query,
          ^build_op(schema_struct, field_info, filter, dialect(opts))
        )
    end
  end

  @impl Flop.Adapter
  def apply_order_by(query, directions, opts) do
    if has_order_bys?(query) do
      Logger.warning(
        "The query you passed to flop includes order_by. This may interfere with Flop's ordering and pagination features."
      )
    end

    dialect = dialect(opts)

    directions =
      Enum.map(directions, fn {direction, field} ->
        {Dialect.order_direction(dialect, direction), field}
      end)

    case opts[:for] do
      nil ->
        Enum.reduce(directions, query, fn {order_direction, field}, acc_query ->
          order_by_direction(
            acc_query,
            order_direction,
            dynamic([r], field(r, ^field))
          )
        end)

      module ->
        struct = struct(module)

        Enum.reduce(directions, query, fn {_, field} = expr, acc_query ->
          field_info = Flop.Schema.field_info(struct, field)
          apply_order_by_field(acc_query, expr, field_info, struct, opts)
        end)
    end
  end

  defp order_by_direction(q, {:native, direction}, field) do
    order_by(q, ^[{direction, field}])
  end

  defp order_by_direction(q, {:emulated, direction}, field) do
    order_by(
      q,
      ^[
        {direction, dynamic(fragment("? IS NULL", ^field))},
        {direction, field}
      ]
    )
  end

  defp custom_field_dynamic(mod, fun, field_dynamic_opts, opts) do
    opts =
      opts
      |> Keyword.get(:extra_opts, [])
      |> Keyword.merge(field_dynamic_opts)

    apply(mod, fun, [opts])
  end

  defp dialect(opts) do
    opts |> Flop.adapter_opts() |> Keyword.get(:repo) |> Dialect.new()
  end

  defp has_order_bys?(query) when is_atom(query), do: false
  defp has_order_bys?(%Ecto.Query{order_bys: []}), do: false
  defp has_order_bys?(%Ecto.Query{order_bys: [_ | _]}), do: true

  defp apply_order_by_field(
         q,
         {order_direction, _},
         %FieldInfo{
           extra: %{type: :join, binding: binding, field: field}
         },
         _,
         _opts
       ) do
    order_by_direction(
      q,
      order_direction,
      dynamic([{^binding, r}], field(r, ^field))
    )
  end

  defp apply_order_by_field(
         q,
         {direction, _},
         %FieldInfo{
           extra: %{type: :compound, fields: fields}
         },
         struct,
         opts
       ) do
    Enum.reduce(fields, q, fn field, acc_query ->
      field_info = Flop.Schema.field_info(struct, field)

      apply_order_by_field(
        acc_query,
        {direction, field},
        field_info,
        struct,
        opts
      )
    end)
  end

  defp apply_order_by_field(
         q,
         {order_direction, field},
         %FieldInfo{extra: %{type: :alias}},
         _,
         _opts
       ) do
    order_by_direction(q, order_direction, dynamic(selected_as(^field)))
  end

  defp apply_order_by_field(
         q,
         {order_direction, _},
         %FieldInfo{
           extra: %{
             type: :custom,
             field_dynamic: {mod, fun, field_dynamic_opts}
           }
         },
         _,
         opts
       ) do
    opts =
      opts
      |> Keyword.get(:extra_opts, [])
      |> Keyword.merge(field_dynamic_opts)

    order_by_direction(q, order_direction, apply(mod, fun, [opts]))
  end

  # only reachable with an unvalidated Flop struct
  defp apply_order_by_field(
         _q,
         {_, field},
         %FieldInfo{extra: %{type: :custom}},
         _,
         _opts
       ) do
    raise ArgumentError, """
    ordering by a custom field requires a field_dynamic function

    No field_dynamic function is configured for #{inspect(field)}, so it cannot
    be used as an order field.

    Use Flop.validate/2 to turn this exception into a validation error.
    """
  end

  defp apply_order_by_field(q, {order_direction, field}, _, _, _opts) do
    order_by_direction(q, order_direction, dynamic([r], field(r, ^field)))
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

  @asc_directions [:asc, :asc_nulls_first, :asc_nulls_last]

  @impl Flop.Adapter
  def apply_cursor(q, cursor_fields, opts) do
    where_dynamic = cursor_dynamic(cursor_fields, dialect(opts), opts)
    Query.where(q, ^where_dynamic)
  end

  defp cursor_dynamic([], _dialect, _opts), do: true

  # only reachable with an unvalidated Flop struct
  defp cursor_dynamic([{_, _, _, %FieldInfo{extra: %{type: type}}} | _], _, _)
       when type in [:compound, :alias] do
    raise ArgumentError, """
    cursor pagination is not supported for #{type} fields

    The order fields of a Flop used for cursor pagination must be normal, join
    or custom fields. #{String.capitalize(to_string(type))} fields can only be
    used with offset or page based pagination.

    Use Flop.validate/2 to turn this exception into a validation error.
    """
  end

  defp cursor_dynamic([{direction, _, _, _} | _], %Dialect{adapter: nil}, _)
       when direction in [:asc, :desc] do
    raise ArgumentError, """
    cursor pagination with :asc or :desc requires the repo

    Flop determines where the database sorts NULL values from the repo's Ecto
    adapter, but no repo is configured.

    You can pass the repo as an option:

        Flop.query(MyApp.Pet, flop, for: MyApp.Pet, repo: MyApp.Repo)

    Or you can set it in the application environment or on a backend module.

    Alternatively, use the order directions :asc_nulls_first or :asc_nulls_last,
    and :desc_nulls_first or :desc_nulls_last.
    """
  end

  defp cursor_dynamic(
         [{direction, field, cursor_value, field_info} | tail],
         dialect,
         opts
       ) do
    tail_dynamic =
      if tail == [], do: nil, else: cursor_dynamic(tail, dialect, opts)

    seek(
      direction,
      Dialect.null_placement(dialect, direction),
      cursor_value,
      field_source(field, field_info, opts),
      tail_dynamic
    )
  end

  defp field_source(
         _field,
         %FieldInfo{
           extra: %{type: :custom, field_dynamic: {mod, fun, dyn_opts}}
         },
         opts
       ) do
    {:dynamic, custom_field_dynamic(mod, fun, dyn_opts, opts)}
  end

  # only reachable with an unvalidated Flop struct
  defp field_source(field, %FieldInfo{extra: %{type: :custom}}, _opts) do
    raise ArgumentError, """
    cursor pagination by a custom field requires a field_dynamic function

    No field_dynamic function is configured for #{inspect(field)}, so it cannot
    be used as an order field.

    Use Flop.validate/2 to turn this exception into a validation error.
    """
  end

  defp field_source(
         _field,
         %FieldInfo{extra: %{binding: binding, field: field, type: :join}},
         _opts
       ) do
    {:join, binding, field}
  end

  defp field_source(field, _field_info, _opts), do: {:column, field}

  # no cursor value, nulls last, last cursor field
  defp seek(_direction, :last, nil, _source, nil), do: false

  # no cursor value, nulls last, more cursor fields to come
  defp seek(_direction, :last, nil, source, tail) do
    dynamic(^null_dynamic(source) and ^tail)
  end

  # no cursor value, nulls first, last cursor field
  defp seek(_direction, :first, nil, source, nil), do: not_null_dynamic(source)

  # no cursor value, nulls first, more cursor fields to come
  defp seek(_direction, :first, nil, source, tail) do
    dynamic(^not_null_dynamic(source) or (^null_dynamic(source) and ^tail))
  end

  # cursor value, last cursor field
  defp seek(direction, placement, cursor_value, source, nil) do
    strictly_after(direction, placement, cursor_value, source)
  end

  # cursor value, more cursor fields to come
  defp seek(direction, placement, cursor_value, source, tail) do
    dynamic(
      ^strictly_after(direction, placement, cursor_value, source) or
        (^compare(:==, source, cursor_value) and ^tail)
    )
  end

  # ascending, nulls last, so the null rows follow the cursor row
  defp strictly_after(direction, :last, cursor_value, source)
       when direction in @asc_directions do
    dynamic(^compare(:>, source, cursor_value) or ^null_dynamic(source))
  end

  # descending, nulls last, so the null rows follow the cursor row
  defp strictly_after(_direction, :last, cursor_value, source) do
    dynamic(^compare(:<, source, cursor_value) or ^null_dynamic(source))
  end

  # ascending, nulls first, so the cursor row has passed the null rows
  defp strictly_after(direction, :first, cursor_value, source)
       when direction in @asc_directions do
    compare(:>, source, cursor_value)
  end

  # descending, nulls first, so the cursor row has passed the null rows
  defp strictly_after(_direction, :first, cursor_value, source) do
    compare(:<, source, cursor_value)
  end

  defp compare(op, {:join, binding, field}, value) do
    case op do
      :> ->
        dynamic(
          [{^binding, r}],
          field(r, ^field) > type(^value, field(r, ^field))
        )

      :< ->
        dynamic(
          [{^binding, r}],
          field(r, ^field) < type(^value, field(r, ^field))
        )

      :== ->
        dynamic(
          [{^binding, r}],
          field(r, ^field) == type(^value, field(r, ^field))
        )
    end
  end

  defp compare(op, {:dynamic, field_dynamic}, value) do
    case op do
      :> -> dynamic(^field_dynamic > ^value)
      :< -> dynamic(^field_dynamic < ^value)
      :== -> dynamic(^field_dynamic == ^value)
    end
  end

  defp compare(op, {:column, field}, value) do
    case op do
      :> -> dynamic([r], field(r, ^field) > type(^value, field(r, ^field)))
      :< -> dynamic([r], field(r, ^field) < type(^value, field(r, ^field)))
      :== -> dynamic([r], field(r, ^field) == type(^value, field(r, ^field)))
    end
  end

  defp null_dynamic({:join, binding, field}) do
    dynamic([{^binding, r}], is_nil(field(r, ^field)))
  end

  defp null_dynamic({:dynamic, field_dynamic}) do
    dynamic(is_nil(^field_dynamic))
  end

  defp null_dynamic({:column, field}) do
    dynamic([r], is_nil(field(r, ^field)))
  end

  defp not_null_dynamic({:join, binding, field}) do
    dynamic([{^binding, r}], not is_nil(field(r, ^field)))
  end

  defp not_null_dynamic({:dynamic, field_dynamic}) do
    dynamic(not is_nil(^field_dynamic))
  end

  defp not_null_dynamic({:column, field}) do
    dynamic([r], not is_nil(field(r, ^field)))
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
    adapter_opts = Flop.adapter_opts(opts)
    repo = adapter_opts[:repo] || raise Flop.NoRepoError, function_name: flop_fn
    query_opts = Keyword.get(adapter_opts, :query_opts, [])

    apply(repo, repo_fn, args ++ [query_opts])
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
           %Filter{op: unquote(op), value: value},
           dialect
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
            build_op(
              schema_struct,
              field,
              %Filter{
                field: field,
                op: unquote(field_op),
                value: substring
              },
              dialect
            )

          dynamic([r], ^inner_dynamic or ^dynamic_for_field)
        end)
      end)
    end
  end

  defp build_op(
         schema_struct,
         %FieldInfo{extra: %{type: :compound, fields: fields}},
         %Filter{op: op} = filter,
         dialect
       )
       when op in [
              :=~,
              :like,
              :not_like,
              :ilike,
              :not_ilike,
              :starts_with,
              :ends_with
            ] do
    fields
    |> Enum.map(&get_field_info(schema_struct, &1))
    |> Enum.reduce(false, fn field, dynamic ->
      dynamic_for_field =
        build_op(
          schema_struct,
          field,
          %{filter | field: field},
          dialect
        )

      dynamic([r], ^dynamic or ^dynamic_for_field)
    end)
  end

  defp build_op(
         schema_struct,
         %FieldInfo{extra: %{type: :compound, fields: fields}},
         %Filter{op: op, value: value} = filter,
         dialect
       )
       when op in [:empty, :not_empty] do
    # a compound field is empty when every subfield is, and not empty when any
    # subfield is
    combinator = if match_empty?(op, value), do: :and, else: :or
    fields = Enum.map(fields, &get_field_info(schema_struct, &1))

    reduce_dynamic(combinator, fields, fn field ->
      build_op(
        schema_struct,
        field,
        %{filter | field: field},
        dialect
      )
    end)
  end

  # only reachable with an unvalidated Flop struct
  defp build_op(
         _schema_struct,
         %FieldInfo{extra: %{type: :compound}},
         %Filter{field: field, op: op},
         _dialect
       )
       when op not in @compound_operators do
    raise ArgumentError, """
    operator #{inspect(op)} is not supported for compound fields

    The filter on #{inspect(field)} cannot be applied. Compound fields support
    these operators:

    #{Flop.Misc.indent(@compound_operators)}

    Use Flop.validate/2 to turn this exception into a validation error.
    """
  end

  defp build_op(
         %module{},
         %FieldInfo{extra: %{type: :normal, field: field}},
         %Filter{op: op, value: value},
         dialect
       )
       when op in [:empty, :not_empty] do
    ecto_type = module.__schema__(:type, field)

    condition =
      case {array_or_map(ecto_type), dialect} do
        {:array, %Dialect{arrays?: false}} -> dynamic([r], empty(:json_array))
        {:array, _} -> dynamic([r], empty(:array))
        {:map, _} -> dynamic([r], empty(:map))
        {:other, _} -> dynamic([r], empty(:other))
      end

    match_empty(condition, op, value)
  end

  # without a schema there is no field type, so an empty array or map cannot be
  # told apart from a nil and only the nil check is available
  defp build_op(
         _schema_struct,
         %FieldInfo{extra: %{type: :normal, field: field}},
         %Filter{op: op, value: value},
         _dialect
       )
       when op in [:empty, :not_empty] do
    match_empty(dynamic([r], empty(:other)), op, value)
  end

  defp build_op(
         _schema_struct,
         %FieldInfo{
           ecto_type: ecto_type,
           extra: %{type: :join, binding: binding, field: field}
         },
         %Filter{op: op, value: value},
         dialect
       )
       when op in [:empty, :not_empty] do
    condition =
      case {array_or_map(ecto_type), dialect} do
        {:array, %Dialect{arrays?: false}} ->
          dynamic([{^binding, r}], empty(:json_array))

        {:array, _} ->
          dynamic([{^binding, r}], empty(:array))

        {:map, _} ->
          dynamic([{^binding, r}], empty(:map))

        {:other, _} ->
          dynamic([{^binding, r}], empty(:other))
      end

    match_empty(condition, op, value)
  end

  # Ecto's MyXQL adapter cannot build array operations, so the array operators
  # are built with MySQL's JSON functions instead. See the Dialect module.
  defp build_op(
         %module{},
         %FieldInfo{extra: %{type: :normal, field: field}},
         %Filter{op: op, value: value},
         %Dialect{arrays?: false}
       )
       when op in [:contains, :not_contains] do
    ecto_type = module.__schema__(:type, field)
    match_contains(dynamic([r], json_contains()), op)
  end

  # without a schema there is no field type to dump the value with
  defp build_op(
         _schema_struct,
         %FieldInfo{extra: %{type: :normal, field: field}},
         %Filter{op: op, value: value},
         %Dialect{arrays?: false}
       )
       when op in [:contains, :not_contains] do
    ecto_type = nil
    match_contains(dynamic([r], json_contains()), op)
  end

  defp build_op(
         _schema_struct,
         %FieldInfo{
           ecto_type: ecto_type,
           extra: %{type: :join, binding: binding, field: field}
         },
         %Filter{op: op, value: value},
         %Dialect{arrays?: false}
       )
       when op in [:contains, :not_contains] do
    ecto_type = Flop.Misc.expand_type(ecto_type)
    match_contains(dynamic([{^binding, r}], json_contains()), op)
  end

  # operators whose SQL does not depend on the adapter
  for op <- @operators, op not in [:empty, :not_empty | @ilike_operators] do
    {fragment, prelude, combinator} = op_config(op, :column)

    defp build_op(
           _schema_struct,
           %FieldInfo{extra: %{type: :normal, field: field}},
           %Filter{op: unquote(op), value: value},
           _dialect
         ) do
      unquote(prelude)
      build_dynamic(unquote(fragment), false, unquote(combinator))
    end

    defp build_op(
           _schema_struct,
           %FieldInfo{extra: %{type: :join, binding: binding, field: field}},
           %Filter{op: unquote(op), value: value},
           _dialect
         ) do
      unquote(prelude)
      build_dynamic(unquote(fragment), true, unquote(combinator))
    end
  end

  # operators whose SQL depends on whether the Ecto adapter supports ilike
  for op <- @ilike_operators, ilike? <- [true, false] do
    {fragment, prelude, combinator} = op_config(op, ilike?, :column)

    defp build_op(
           _schema_struct,
           %FieldInfo{extra: %{type: :normal, field: field}},
           %Filter{op: unquote(op), value: value},
           %Dialect{ilike?: unquote(ilike?)}
         ) do
      unquote(prelude)
      build_dynamic(unquote(fragment), false, unquote(combinator))
    end

    defp build_op(
           _schema_struct,
           %FieldInfo{extra: %{type: :join, binding: binding, field: field}},
           %Filter{op: unquote(op), value: value},
           %Dialect{ilike?: unquote(ilike?)}
         ) do
      unquote(prelude)
      build_dynamic(unquote(fragment), true, unquote(combinator))
    end
  end

  defp build_op_dynamic(
         %Filter{op: op, value: value},
         dialect,
         field_dynamic,
         ecto_type
       )
       when op in [:empty, :not_empty] do
    condition =
      case {array_or_map(ecto_type), dialect} do
        {:array, %Dialect{arrays?: false}} ->
          dynamic([r], empty_dynamic(:json_array))

        {:array, _} ->
          empty_value = dynamic([r], type(^[], ^ecto_type))
          dynamic([r], empty_dynamic(:array))

        {:map, _} ->
          empty_value = dynamic([r], type(^%{}, ^ecto_type))
          dynamic([r], empty_dynamic(:map))

        {:other, _} ->
          dynamic([r], empty_dynamic(:other))
      end

    match_empty(condition, op, value)
  end

  for op <- @operators, op not in [:empty, :not_empty | @ilike_operators] do
    {fragment, prelude, combinator} = op_config(op, :dynamic)

    defp build_op_dynamic(
           %Filter{op: unquote(op), value: value},
           _dialect,
           field_dynamic,
           _ecto_type
         ) do
      unquote(prelude)
      build_dynamic(unquote(fragment), false, unquote(combinator))
    end
  end

  for op <- @ilike_operators, ilike? <- [true, false] do
    {fragment, prelude, combinator} = op_config(op, ilike?, :dynamic)

    defp build_op_dynamic(
           %Filter{op: unquote(op), value: value},
           %Dialect{ilike?: unquote(ilike?)},
           field_dynamic,
           _ecto_type
         ) do
      unquote(prelude)
      build_dynamic(unquote(fragment), false, unquote(combinator))
    end
  end

  defp match_contains(condition, :contains), do: condition
  defp match_contains(condition, :not_contains), do: dynamic(not (^condition))

  defp match_empty(condition, op, value) do
    if match_empty?(op, value),
      do: condition,
      else: dynamic([r], not (^condition))
  end

  defp match_empty?(op, value) do
    empty? = value in [true, "true"]
    if op == :not_empty, do: !empty?, else: empty?
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
      filter: Keyword.get(opts, :filter),
      field_dynamic: Keyword.get(opts, :field_dynamic),
      ecto_type: Keyword.fetch!(opts, :ecto_type),
      operators: Keyword.get(opts, :operators),
      bindings: Keyword.get(opts, :bindings, []),
      path: Keyword.get(opts, :path) || [name]
    }

    {name, opts}
  end

  defp normalize_join_fields(fields) do
    Enum.into(fields, %{}, &normalize_join_field_opts/1)
  end

  defp normalize_join_field_opts({name, opts}) when is_list(opts) do
    binding = Keyword.fetch!(opts, :binding)
    field = Keyword.fetch!(opts, :field)

    opts = %{
      binding: binding,
      field: field,
      path: opts[:path] || [binding, field],
      ecto_type: Keyword.fetch!(opts, :ecto_type)
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

  defp validate_filterable_custom_fields!(custom_fields, filterable) do
    missing =
      for {name, opts} <- custom_fields,
          name in filterable,
          is_nil(opts[:filter]) and is_nil(opts[:field_dynamic]),
          do: name

    if missing != [] do
      raise ArgumentError, """
      custom field without a callback marked as filterable

      A custom field needs either a filter or a field_dynamic function to be
      filterable. These fields have neither:

          #{inspect(missing)}
      """
    end
  end

  defp validate_custom_field_callback!(custom_fields, fields, callback, usage) do
    missing =
      for {name, opts} <- custom_fields,
          name in fields,
          is_nil(opts[callback]),
          do: name

    if missing != [] do
      raise ArgumentError, """
      custom field without #{callback} function marked as #{usage}

      A custom field needs a #{callback} function to be #{usage}. These fields
      have none:

          #{inspect(missing)}

      Configure it like this:

          custom_fields: [
            #{hd(missing)}: [
              #{callback}: {MyApp.CustomFields, :#{callback}, []}
            ]
          ]
      """
    end
  end

  defp validate_custom_fields!(
         %{custom_fields: custom_fields} = adapter_opts,
         opts
       ) do
    validate_filterable_custom_fields!(
      custom_fields,
      Keyword.fetch!(opts, :filterable)
    )

    validate_custom_field_callback!(
      custom_fields,
      Keyword.fetch!(opts, :sortable),
      :field_dynamic,
      "sortable"
    )

    adapter_opts
  end

  defp duplicates(fields) do
    fields
    |> Enum.frequencies()
    |> Enum.filter(fn {_, count} -> count > 1 end)
    |> Enum.map(fn {field, _} -> field end)
  end
end
