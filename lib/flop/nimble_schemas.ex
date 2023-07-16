defmodule Flop.NimbleSchemas do
  @moduledoc false

  @backend_option [
    adapter: [type: :atom, default: Flop.Adapter.Ecto],
    adapter_opts: [
      type: :keyword_list,
      default: []
    ],
    cursor_value_func: [type: {:fun, 2}],
    default_limit: [type: :integer, default: 50],
    max_limit: [type: :integer, default: 1000],
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
    default_limit: [type: :integer],
    max_limit: [type: :integer],
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

  @schema_option_schema @schema_option
  def schema_option_schema, do: @schema_option_schema

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
end
