defmodule Flop.NimbleSchemas do
  @moduledoc false

  @backend_option [
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
    query_opts: [type: :keyword_list]
  ]

  @schema_option [
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
            operators: [type: {:list, :atom}]
          ]
        ]
      ]
    ],
    alias_fields: [
      type: {:list, :atom}
    ]
  ]

  @backend_option NimbleOptions.new!(@backend_option)
  @schema_option NimbleOptions.new!(@schema_option)

  def __backend_option__, do: @backend_option
  def __schema_option__, do: @schema_option
end
