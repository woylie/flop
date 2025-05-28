defmodule Flop.Meta do
  @moduledoc """
  Defines a struct for holding meta information of a query result.
  """

  @typedoc """
  Meta information for a query result.

  - `:flop` - The `Flop` struct used in the query.
  - `:schema` - The schema module passed as `for` option.
  - `:backend` - The backend module if the query was made using a module with
    `use Flop`.
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
          backend: module | nil,
          current_offset: non_neg_integer | nil,
          current_page: pos_integer | nil,
          end_cursor: String.t() | nil,
          errors: [{atom, term}],
          flop: Flop.t(),
          has_next_page?: boolean,
          has_previous_page?: boolean,
          next_offset: non_neg_integer | nil,
          next_page: pos_integer | nil,
          opts: keyword,
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
    :backend,
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
    opts: [],
    params: %{}
  ]

  @doc """
  Returns a `Flop.Meta` struct with the given params, errors, and opts.

  This function is used internally to build error responses in case of
  validation errors. You can use it to add additional parameter validation.

  The given parameters parameters are normalized before being added to the
  struct. The errors have to be passed as a keyword list (same format as the
  result of `Ecto.Changeset.traverse_errors(changeset, & &1)`).

  ## Example

  In this list function, the given parameters are first validated with
  `Flop.validate/2`, which returns a `Flop` struct on success. You can then pass
  that struct to a custom validation function, along with the original
  parameters and the opts, which both are needed to call this function.

      def list_pets(%{} = params) do
        opts = [for: Pet]

        with {:ok, %Flop{} = flop} <- Flop.validate(params, opts),
             {:ok, %Flop{} = flop} <- custom_validation(flop, params, opts) do
          Flop.run(Pet, flop, for: Pet)
        end
      end

  In your custom validation function, you can retrieve and manipulate the filter
  values in the `Flop` struct with the functions defined in the `Flop.Filter`
  module.

      defp custom_validation(%Flop{} = flop, %{} = params, opts) do
        %{value: date} = Flop.Filter.get(flop.filters, :date)

        if date && Date.compare(date, Date.utc_today()) != :lt do
          errors = [filters: [{"date must be in the past", []}]]
          {:error, Flop.Meta.with_errors(params, errors, opts)}
        else
          {:ok, flop}
        end
      end

  Note that in this example, `Flop.Filter.get/2` is used, which only returns the
  first filter in the given filter list. Depending on how you use Flop, the
  filter list may have multiple entries for the same field. In that case, you
  may need to either use `Flop.Filter.get_all/2` and apply the validation on all
  returned filters, or reduce over the whole filter list. The latter has the
  advantage that you can attach the error to the actual list entry.

      def custom_validation(%Flop{} = flop, %{} = params, opts) do
        filter_errors =
          flop.filters
          |> Enum.reduce([], &validate_filter/2)
          |> Enum.reverse()

        if Enum.any?(filter_errors, &(&1 != [])) do
          errors = [filters: filter_errors]
          {:error, Flop.Meta.with_errors(params, errors, opts)}
        else
          {:ok, flop}
        end
      end

      defp validate_filter(%Flop.Filter{field: :date, value: date}, acc)
           when is_binary(date) do
        date = Date.from_iso8601!(date)

        if Date.compare(date, Date.utc_today()) != :lt,
          do: [[value: [{"date must be in the past", []}]] | acc],
          else: [[] | acc]
      end

      defp validate_filter(%Flop.Filter{}, acc), do: [[] | acc]
  """
  @doc since: "0.19.0"
  @spec with_errors(map, keyword, keyword) :: t()
  def with_errors(%{} = params, errors, opts)
      when is_list(errors) and is_list(opts) do
    %__MODULE__{
      backend: opts[:backend],
      errors: errors,
      opts: opts,
      params: convert_params(params),
      schema: opts[:for]
    }
  end

  defp convert_params(params) do
    params
    |> map_to_string_keys()
    |> filters_to_list()
  end

  defp filters_to_list(%{"filters" => filters} = params) when is_map(filters) do
    filters =
      filters
      |> Enum.map(fn {index, filter} -> {String.to_integer(index), filter} end)
      |> Enum.sort_by(fn {index, _} -> index end)
      |> Enum.map(fn {_, filter} -> filter end)

    Map.put(params, "filters", filters)
  end

  defp filters_to_list(params), do: params

  defp map_to_string_keys(value) when is_struct(value), do: value

  defp map_to_string_keys(%{} = params) do
    Enum.into(params, %{}, fn
      {key, value} when is_atom(key) ->
        {Atom.to_string(key), map_to_string_keys(value)}

      {key, value} when is_binary(key) ->
        {key, map_to_string_keys(value)}
    end)
  end

  defp map_to_string_keys(values) when is_list(values),
    do: Enum.map(values, &map_to_string_keys/1)

  defp map_to_string_keys(value), do: value
end
