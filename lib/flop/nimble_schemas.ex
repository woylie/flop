defmodule Flop.NimbleSchemas do
  @moduledoc false

  @backend_option [
    adapter: [type: :atom, default: Flop.Adapter.Ecto],
    adapter_opts: [
      type: :keyword_list,
      default: []
    ],
    cursor_value_func: [
      type: {:custom, __MODULE__, :validate_cursor_value_func, []}
    ],
    default_limit: [type: {:or, [:pos_integer, {:in, [false]}]}, default: 50],
    max_cursor_size: [type: :pos_integer],
    max_filters: [type: {:or, [:pos_integer, {:in, [false]}]}, default: 20],
    max_limit: [type: {:or, [:pos_integer, {:in, [false]}]}, default: 1000],
    replace_invalid_params: [type: :boolean],
    tiebreaker: [
      type: {:custom, __MODULE__, :validate_schemaless_tiebreaker, []}
    ],
    default_pagination_type: [
      type: {:in, [:offset, :page, :first, :last]},
      default: :offset
    ],
    filtering: [
      type: :boolean,
      default: true
    ],
    ordering: [
      type: :boolean,
      default: true
    ],
    pagination: [
      type: :boolean,
      default: true
    ],
    pagination_types: [
      type: {:list, {:in, [:offset, :page, :first, :last]}},
      default: [:offset, :page, :first, :last]
    ],
    repo: [],
    query_opts: [type: :keyword_list, default: []]
  ]

  @schema_option [
    adapter: [type: :atom, default: Flop.Adapter.Ecto],
    adapter_opts: [
      type: :keyword_list,
      default: []
    ],
    filterable: [type: {:list, :atom}, required: true],
    sortable: [type: {:list, :atom}, required: true],
    default_order: [
      type: :map,
      keys: [
        order_by: [type: {:list, :atom}],
        order_directions: [
          type:
            {:list,
             {:in,
              [
                :asc,
                :asc_nulls_first,
                :asc_nulls_last,
                :desc,
                :desc_nulls_first,
                :desc_nulls_last
              ]}}
        ]
      ]
    ],
    default_limit: [type: {:or, [:pos_integer, {:in, [false]}]}],
    max_limit: [type: {:or, [:pos_integer, {:in, [false]}]}],
    tiebreaker: [type: {:custom, __MODULE__, :validate_tiebreaker, []}],
    pagination_types: [
      type: {:list, {:in, [:offset, :page, :first, :last]}}
    ],
    default_pagination_type: [
      type: {:in, [:offset, :page, :first, :last]}
    ],
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
              type: {:custom, __MODULE__, :validate_ecto_type, []},
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
              type: {:custom, __MODULE__, :validate_ecto_type, []},
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

  @schema_option_schema @schema_option
  def schema_option_schema, do: @schema_option_schema

  @backend_option_keys Keyword.keys(@backend_option)

  @doc """
  Returns the options that can be set on a backend module.

  The application environment accepts the same options.
  """
  def backend_option_keys, do: @backend_option_keys

  @backend_option NimbleOptions.new!(@backend_option)
  @schema_option NimbleOptions.new!(@schema_option)

  def validate!(opts, schema_id, module, caller) when is_atom(schema_id) do
    validate!(opts, schema(schema_id), module, caller)
  end

  def validate!(opts, %NimbleOptions{} = schema, module, caller) do
    case NimbleOptions.validate(opts, schema) do
      {:ok, opts} ->
        opts

      {:error, err} ->
        raise Flop.InvalidConfigError.from_nimble(err,
                caller: caller,
                module: module
              )
    end
  end

  defp schema(:backend_option), do: @backend_option
  defp schema(:schema_option), do: @schema_option

  @doc false
  def validate_ecto_type(nil) do
    {:error, "expected an Ecto type such as :string or :map, got: nil"}
  end

  def validate_ecto_type(ecto_type), do: {:ok, ecto_type}

  @order_directions [
    :asc,
    :asc_nulls_first,
    :asc_nulls_last,
    :desc,
    :desc_nulls_first,
    :desc_nulls_last
  ]

  @doc """
  Returns the valid order directions.
  """
  def order_directions, do: @order_directions

  @doc false
  def validate_schemaless_tiebreaker(fields) when is_list(fields) do
    {:error,
     """
     a tiebreaker that names fields can only be set on a schema or passed to a \
     query function, got: #{inspect(fields)}\
     """}
  end

  def validate_schemaless_tiebreaker(value), do: validate_tiebreaker(value)

  @doc false
  def validate_tiebreaker(false), do: {:ok, false}
  def validate_tiebreaker(:primary_key), do: {:ok, :primary_key}

  def validate_tiebreaker({:primary_key, direction})
      when direction in @order_directions do
    {:ok, {:primary_key, direction}}
  end

  def validate_tiebreaker(fields) when is_list(fields) and fields != [] do
    if Enum.all?(fields, fn
         {direction, field} when is_atom(field) ->
           direction in @order_directions

         _ ->
           false
       end) do
      {:ok, fields}
    else
      {:error, tiebreaker_error(fields)}
    end
  end

  def validate_tiebreaker(value), do: {:error, tiebreaker_error(value)}

  defp tiebreaker_error(value) do
    """
    expected false, :primary_key, {:primary_key, direction} or a keyword list \
    of order directions and fields, got: #{inspect(value)}\
    """
  end

  @doc false
  def validate_cursor_value_func(value) do
    if cursor_value_func?(value) do
      {:ok, value}
    else
      {:error, "expected a function of arity 2, got: #{inspect(value)}"}
    end
  end

  defp cursor_value_func?(value) when is_function(value, 2), do: true

  # `use Flop` validates its options before they are expanded, where a function
  # literal is still a capture or an anonymous function node. `{:fun, 2}` would
  # reject every value.
  defp cursor_value_func?({:&, _, _}), do: true
  defp cursor_value_func?({:fn, _, _}), do: true
  defp cursor_value_func?(_), do: false
end
