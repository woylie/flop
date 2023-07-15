defmodule Flop.Adapter do
  @moduledoc false

  @type queryable :: term
  @type opts :: keyword

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

  @callback apply_cursor(queryable, decoded_cursor, order_directions, opts) ::
              queryable
            when decoded_cursor: map, order_directions: keyword

  @callback count(queryable, opts) :: non_neg_integer

  @callback list(queryable, opts) :: [any]
end
