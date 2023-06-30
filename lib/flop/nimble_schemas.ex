defmodule Flop.NimbleSchemas do
  @moduledoc false

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

  @schema_option NimbleOptions.new!(@schema_option)

  @doc false
  def __schema_option__, do: @schema_option
end
