defmodule Flop.InvalidParamsError do
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
