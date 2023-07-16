defmodule Flop.Adapter.Ecto do
  @moduledoc false

  @behaviour Flop.Adapter

  import Ecto.Query
  import Flop.Operators

  alias Ecto.Query
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

  @backend_options [
    repo: [required: true],
    query_opts: [type: :keyword_list, default: []]
  ]

  @schema_options [
    join_fields: [
      type: :keyword_list,
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
      keys: [
        *: [
          type: {:list, :atom}
        ]
      ]
    ],
    custom_fields: [
      type: :keyword_list,
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
      type: {:list, :atom}
    ]
  ]

  @backend_options NimbleOptions.new!(@backend_options)
  @schema_options NimbleOptions.new!(@schema_options)

  @impl Flop.Adapter
  def backend_options, do: @backend_options

  @impl Flop.Adapter
  def schema_options, do: @schema_options

  @impl Flop.Adapter
  def apply_filter(
        query,
        %Flop.Filter{field: field} = filter,
        schema_struct,
        opts
      ) do
    case get_field_type(schema_struct, field) do
      {:custom, %{} = custom_opts} ->
        {mod, fun, custom_filter_opts} = Map.fetch!(custom_opts, :filter)

        opts =
          opts
          |> Keyword.get(:extra_opts, [])
          |> Keyword.merge(custom_filter_opts)

        apply(mod, fun, [query, filter, opts])

      field_type ->
        Query.where(query, ^build_op(schema_struct, field_type, filter))
    end
  end

  @impl Flop.Adapter
  def apply_order_by(query, directions, opts) do
    case opts[:for] do
      nil ->
        Query.order_by(query, ^directions)

      module ->
        struct = struct(module)

        Enum.reduce(directions, query, fn expr, acc_query ->
          Flop.Schema.apply_order_by(struct, acc_query, expr)
        end)
    end
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
  def apply_cursor(q, %{} = decoded_cursor, ordering, opts) do
    where_dynamic =
      case opts[:for] do
        nil ->
          cursor_dynamic(ordering, decoded_cursor)

        module ->
          module
          |> struct()
          |> Flop.Schema.cursor_dynamic(ordering, decoded_cursor)
      end

    Query.where(q, ^where_dynamic)
  end

  defp cursor_dynamic([], _), do: true

  defp cursor_dynamic([{direction, field}], decoded_cursor) do
    field_cursor = decoded_cursor[field]

    if is_nil(field_cursor) do
      true
    else
      case direction do
        dir when dir in [:asc, :asc_nulls_first, :asc_nulls_last] ->
          Query.dynamic([r], field(r, ^field) > ^field_cursor)

        dir when dir in [:desc, :desc_nulls_first, :desc_nulls_last] ->
          Query.dynamic([r], field(r, ^field) < ^field_cursor)
      end
    end
  end

  defp cursor_dynamic([{direction, field} | [{_, _} | _] = tail], cursor) do
    field_cursor = cursor[field]

    if is_nil(field_cursor) do
      cursor_dynamic(tail, cursor)
    else
      case direction do
        dir when dir in [:asc, :asc_nulls_first, :asc_nulls_last] ->
          Query.dynamic(
            [r],
            field(r, ^field) >= ^field_cursor and
              (field(r, ^field) > ^field_cursor or
                 ^cursor_dynamic(tail, cursor))
          )

        dir when dir in [:desc, :desc_nulls_first, :desc_nulls_last] ->
          Query.dynamic(
            [r],
            field(r, ^field) <= ^field_cursor and
              (field(r, ^field) < ^field_cursor or
                 ^cursor_dynamic(tail, cursor))
          )
      end
    end
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

    repo = Flop.get_option(:repo, opts) || raise no_repo_error(flop_fn)
    opts = query_opts(opts)

    apply(repo, repo_fn, args ++ [opts])
  end

  defp query_opts(opts) do
    default_opts = Application.get_env(:flop, :query_opts, [])
    Keyword.merge(default_opts, Keyword.get(opts, :query_opts, []))
  end

  # coveralls-ignore-start

  defp no_repo_error(function_name),
    do: """
    No repo specified. You can specify the repo either by passing it
    explicitly:

        Flop.#{function_name}(MyApp.Item, %Flop{}, repo: MyApp.Repo)

    Or configure a default repo in your config:

        config :flop, repo: MyApp.Repo

    Or configure a repo with a backend module:

        defmodule MyApp.Flop do
          use Flop, repo: MyApp.Repo
        end
    """

  # coveralls-ignore-end

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
    Logger.warning(
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
