defmodule Flop.Meta do
  @moduledoc """
  Defines a struct for holding meta information of a query result.
  """

  @typedoc """
  Meta information for a query result.
  """
  @type t :: %__MODULE__{
          current_offset: non_neg_integer,
          current_page: pos_integer,
          flop: Flop.t(),
          has_next_page?: boolean,
          has_previous_page?: boolean,
          next_cursor: String.t(),
          next_offset: non_neg_integer | nil,
          next_page: pos_integer | nil,
          page_size: pos_integer | nil,
          previous_cursor: String.t(),
          previous_offset: non_neg_integer | nil,
          previous_page: pos_integer | nil,
          total_count: non_neg_integer,
          total_pages: non_neg_integer
        }

  @enforce_keys [
    :current_offset,
    :current_page,
    :flop,
    :has_next_page?,
    :has_previous_page?,
    :next_cursor,
    :next_offset,
    :next_page,
    :page_size,
    :previous_cursor,
    :previous_offset,
    :previous_page,
    :total_count,
    :total_pages
  ]

  defstruct [
    :current_offset,
    :current_page,
    :flop,
    :has_next_page?,
    :has_previous_page?,
    :next_cursor,
    :previous_cursor,
    :next_offset,
    :next_page,
    :page_size,
    :previous_offset,
    :previous_page,
    :total_count,
    :total_pages
  ]
end
