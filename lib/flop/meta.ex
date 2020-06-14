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
          has_next_page?: boolean,
          has_previous_page?: boolean,
          page_size: pos_integer,
          total_count: non_neg_integer,
          total_pages: non_neg_integer
        }

  @enforce_keys [
    :current_offset,
    :current_page,
    :has_next_page?,
    :has_previous_page?,
    :page_size,
    :total_count,
    :total_pages
  ]

  defstruct [
    :current_offset,
    :current_page,
    :has_next_page?,
    :has_previous_page?,
    :page_size,
    :total_count,
    :total_pages
  ]
end
