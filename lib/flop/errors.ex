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
  An error that is raised when an invalid cursor is passed to the decode
  function.
  """

  defexception [:cursor]

  def message(%{cursor: cursor}) do
    """
    invalid cursor

    Received an invalid pagination cursor:

        #{inspect(cursor)}
    """
  end
end

defmodule Flop.InvalidParamsError do
  @moduledoc """
  An error that is raised if the parameter validation fails.
  """

  @type t :: %__MODULE__{
          errors: keyword,
          params: map
        }

  defexception [:errors, :params]

  def message(%{errors: errors, params: params}) do
    """
    invalid Flop params

    Params
    #{format(params)}

    Errors
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

    Expected a 2-tuple of order directions, e.g. `{:asc, :desc}`.

    Got: #{inspect(directions)}"

    Valid order directions:

    - :asc
    - :asc_nulls_first
    - :asc_nulls_last
    - :desc
    - :desc_nulls_first
    - :desc_nulls_last
    """
  end
end
