defmodule Flop.Adapter do
  @moduledoc false

  @type queryable :: term
  @type opts :: keyword
  @type cursor_fields :: [
          {Flop.order_direction(), atom, any, Flop.FieldInfo.t() | nil}
        ]

  @callback init_backend_opts(keyword, keyword, module) :: keyword

  # Struct is available when deriving protocol. Change when protocol is
  # replaced.
  @callback init_schema_opts(keyword, keyword, module, struct) :: map

  @callback fields(struct, adapter_opts) :: [{field, Flop.FieldInfo.t()}]
            when adapter_opts: map,
                 field: atom

  @callback apply_filter(queryable, Flop.Filter.t(), struct, keyword) ::
              queryable

  @callback apply_order_by(queryable, keyword, opts) :: queryable

  @callback apply_limit_offset(
              queryable,
              limit | nil,
              offset | nil,
              opts
            ) :: queryable
            when limit: non_neg_integer, offset: non_neg_integer

  @callback apply_page_page_size(queryable, page, page_size, opts) :: queryable
            when page: pos_integer, page_size: pos_integer

  @callback apply_cursor(queryable, cursor_fields, opts) :: queryable

  @doc """
  Takes a queryable and returns the total count.

  Flop will pass the queryable with filter parameters applied, but without
  pagination or sorting parameters.
  """
  @callback count(queryable, opts) :: non_neg_integer

  @doc """
  Executes a list query.

  The first argument is a queryable, for example an `Ecto.Queryable.t()` or any
  other format depending on the adapter.
  """
  @callback list(queryable, opts) :: [any]

  @callback get_field(any, atom, Flop.FieldInfo.t()) :: any
end
