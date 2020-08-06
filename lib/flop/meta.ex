defmodule Flop.Meta do
  @moduledoc """
  Defines a struct for holding meta information of a query result.
  """

  @typedoc """
  Meta information for a query result.
  """
  @type t :: %__MODULE__{
          current_offset: non_neg_integer | nil,
          current_page: pos_integer | nil,
          end_cursor: String.t() | nil,
          flop: Flop.t(),
          has_next_page?: boolean | nil,
          has_previous_page?: boolean | nil,
          next_offset: non_neg_integer | nil,
          next_page: pos_integer | nil,
          page_size: pos_integer | nil,
          previous_offset: non_neg_integer | nil,
          previous_page: pos_integer | nil,
          start_cursor: String.t() | nil,
          total_count: non_neg_integer | nil,
          total_pages: non_neg_integer | nil
        }

  @enforce_keys [
    :current_offset,
    :current_page,
    :end_cursor,
    :flop,
    :has_next_page?,
    :has_previous_page?,
    :next_offset,
    :next_page,
    :page_size,
    :previous_offset,
    :previous_page,
    :start_cursor,
    :total_count,
    :total_pages
  ]

  defstruct [
    :current_offset,
    :current_page,
    :end_cursor,
    :flop,
    :has_next_page?,
    :has_previous_page?,
    :next_offset,
    :next_page,
    :page_size,
    :previous_offset,
    :previous_page,
    :start_cursor,
    :total_count,
    :total_pages
  ]
end
