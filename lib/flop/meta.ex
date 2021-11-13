defmodule Flop.Meta do
  @moduledoc """
  Defines a struct for holding meta information of a query result.
  """

  @typedoc """
  Meta information for a query result.

  - `:flop` - The `Flop` struct used in the query.
  - `:current_offset` - The `:offset` value used in the query when using
    offset-based pagination or a derived value when using page-based pagination.
    Always `nil` when using cursor-based pagination.
  - `:current_page` - The `:page` value used in the query when using page-based
    pagination or a derived value when using offset-based pagination. Note that
    the value will be rounded if the offset lies between pages. Always `nil`
    when using cursor-based pagination.
  - `:errors` - Any validation errors that occurred. The format is the same as
    the result of `Ecto.Changeset.traverse_errors(changeset, & &1)`.
  - `:previous_offset`, `:next_offset`, `:previous_page`, `:next_page` - Values
    based on `:current_page` and `:current_offset`/`page_size`. Always `nil`
    when using cursor-based pagination.
  - `:start_cursor`, `:end_cursor` - The cursors of the first and last record
    in the result set. Only set when using cursor-based pagination with
    `:first`/`:after` or `:last`/`:before`.
  - `:has_previous_page?`, `:has_next_page?` - Set in all pagination types.
    Note that `:has_previous_page?` is always `true` when using cursor-based
    pagination with `:first` and `:after` is set; likewise, `:has_next_page?` is
    always `true` when using cursor-based pagination with `:before` and `:last`
    is set.
  - `:page_size` - The page size or limit of the query. Set to the `:first`
    or `:last` parameter when using cursor-based pagination.
  - `:params` - The original, unvalidated params that were passed. Only set
    if validation errors occurred.
  - `:total_count` - The total count of records for the given query. Always
    `nil` when using cursor-based pagination.
  - `:total_pages` - The total page count based on the total record count and
    the page size. Always `nil` when using cursor-based pagination.
  """
  @type t :: %__MODULE__{
          current_offset: non_neg_integer | nil,
          current_page: pos_integer | nil,
          end_cursor: String.t() | nil,
          errors: [{atom, term}],
          flop: Flop.t(),
          has_next_page?: boolean,
          has_previous_page?: boolean,
          next_offset: non_neg_integer | nil,
          next_page: pos_integer | nil,
          page_size: pos_integer | nil,
          params: %{optional(String.t()) => term()},
          previous_offset: non_neg_integer | nil,
          previous_page: pos_integer | nil,
          schema: module | nil,
          start_cursor: String.t() | nil,
          total_count: non_neg_integer | nil,
          total_pages: non_neg_integer | nil
        }

  defstruct [
    :current_offset,
    :current_page,
    :end_cursor,
    :next_offset,
    :next_page,
    :page_size,
    :previous_offset,
    :previous_page,
    :schema,
    :start_cursor,
    :total_count,
    :total_pages,
    errors: [],
    flop: %Flop{},
    has_next_page?: false,
    has_previous_page?: false,
    params: %{}
  ]
end
