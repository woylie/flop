defmodule Flop.InvalidConfigError do
  @moduledoc false

  defexception [:caller, :key, :message, :value, :keys_path, :module]

  def message(%{} = err) do
    """
    invalid Flop configuration

    #{hint(err.module, module_name(err.caller))}

    #{err.message}
    """
  end

  @doc false
  def from_nimble(%NimbleOptions.ValidationError{} = error, opts) do
    %__MODULE__{
      caller: Keyword.fetch!(opts, :caller),
      key: error.key,
      keys_path: error.keys_path,
      message: Exception.message(error),
      module: Keyword.fetch!(opts, :module),
      value: error.value
    }
  end

  defp hint(Flop, caller_name) do
    "An invalid option was passed to `use Flop` in the module `#{caller_name}`."
  end

  defp hint(Flop.Schema, caller_name) do
    "An invalid option was passed to `@derive Flop.Schema` in the module `#{caller_name}`."
  end

  defp module_name(module) do
    module
    |> Module.split()
    |> Enum.reject(&(&1 == Elixir))
    |> Enum.join(".")
  end
end

defmodule Flop.InvalidCursorError do
  @moduledoc """
  Raised when an invalid cursor is passed to the decode function.

  A cursor might be invalid if it is malformed, not in the expected format, or
  contains unexpected data types.
  """

  defexception [:cursor]

  def message(%{cursor: cursor}) do
    """
    invalid cursor

    Attempted to decode an invalid pagination cursor:

        #{inspect(cursor)}
    """
  end
end

defmodule Flop.InvalidParamsError do
  @moduledoc """
  Raised when parameter validation fails.

  This can occur under a number of circumstances, such as:

  - Pagination parameters are improperly formatted or invalid.
  - Filter values are incompatible with the respective field's type or specified
    operator.
  - Filters are applied on fields that have not been configured as filterable.
  - Ordering parameters are applied on fields that have not been configured as
    sortable.

  """

  @type t :: %__MODULE__{
          errors: keyword,
          params: map
        }

  defexception [:errors, :params]

  def message(%{errors: errors, params: params}) do
    """
    invalid Flop parameters

    The parameters provided to Flop:

    #{format(params)}

    Resulted in the following validation errors:

    #{format(errors)}
    """
  end

  defp format(s) do
    s
    |> inspect(pretty: true)
    |> String.split("\n")
    |> Enum.map_join("\n", fn s -> "    " <> s end)
  end
end

defmodule Flop.InvalidDirectionsError do
  @moduledoc """
  An error that is raised when invalid directions are passed.
  """

  defexception [:directions]

  def message(%{directions: directions}) do
    """
    invalid `:directions` option

    Expected: A 2-tuple of order directions, e.g. `{:asc, :desc}`.

    Received: #{inspect(directions)}"

    The valid order directions are:

    - :asc
    - :asc_nulls_first
    - :asc_nulls_last
    - :desc
    - :desc_nulls_first
    - :desc_nulls_last
    """
  end
end

defmodule Flop.InvalidDefaultOrderError do
  defexception [:sortable_fields, :unsortable_fields]

  def exception(args) do
    %__MODULE__{
      sortable_fields: Enum.sort(args[:sortable_fields]),
      unsortable_fields: Enum.sort(args[:unsortable_fields])
    }
  end

  def message(%{
        sortable_fields: sortable_fields,
        unsortable_fields: unsortable_fields
      }) do
    """
    invalid default order

    The following fields are not sortable, but were used for the default order:

        #{inspect(unsortable_fields, pretty: true, width: 76)}

    The sortable fields in your schema are:

        #{inspect(sortable_fields, pretty: true, width: 76)}
    """
  end
end

defmodule Flop.InvalidDefaultPaginationTypeError do
  defexception [:default_pagination_type, :pagination_types]

  def message(%{
        default_pagination_type: default_pagination_type,
        pagination_types: pagination_types
      }) do
    """
    default pagination type not allowed

    The default pagination type (#{inspect(default_pagination_type)}) set on the
    schema is not included in the allowed pagination types.

    You derived your schema configuration similar to:

        @derive {
          Flop.Schema,
          # ...
          default_pagination_type: #{inspect(default_pagination_type)}
          pagination_types: #{inspect(pagination_types)}
        }

    Here are a few ways to address this issue:

        - add the default pagination type to the `pagination_types`
          option of the schema
        - change the `default_pagination_type` option to one of the
          types set with the `pagination_types` option
        - remove the `default_pagination_type` option from the schema
        - remove the `pagination_types` option from the schema
    """
  end
end

defmodule Flop.NoRepoError do
  defexception [:function_name]

  def message(%{function_name: function_name}) do
    """
    no Ecto repo configured

    You attempted to call `Flop.#{function_name}/3` (or its equivalent in a Flop
    backend module), but no Ecto repo was specified.

    Specify the repo in one of the following ways.

    Explicitly pass the repo to the function:

        Flop.#{function_name}(MyApp.Item, %Flop{}, repo: MyApp.Repo)

    Set a global default repo in your config:

        config :flop, repo: MyApp.Repo

    Define a backend module and pass the repo as an option:

        defmodule MyApp.Flop do
          use Flop, repo: MyApp.Repo
        end
    """
  end
end

defmodule Flop.UnknownFieldError do
  defexception [:known_fields, :unknown_fields, :option]

  def exception(args) do
    %__MODULE__{
      known_fields: Enum.sort(args[:known_fields]),
      unknown_fields: Enum.sort(args[:unknown_fields]),
      option: args[:option]
    }
  end

  def message(%{
        known_fields: known_fields,
        unknown_fields: unknown_fields,
        option: option
      }) do
    """
    unknown #{option} field(s)

    There are unknown #{option} fields in your schema configuration:

        #{inspect(unknown_fields, pretty: true, width: 76)}

    The known fields in your schema are:

        #{inspect(known_fields, pretty: true, width: 76)}
    """
  end
end
