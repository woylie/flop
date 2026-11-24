defmodule MyApp.Event do
  @moduledoc false

  use Ecto.Schema
  use Flop.Schema

  import Ecto.Query

  @flop_options [
    filterable: [],
    sortable: [:occurred_on, :occurred_at, :amount, :occurred_at_custom],
    adapter_opts: [
      custom_fields: [
        occurred_at_custom: [
          field_dynamic: {__MODULE__, :occurred_at_dynamic, []},
          ecto_type: :naive_datetime_usec
        ]
      ]
    ]
  ]

  schema "events" do
    field :occurred_on, :date
    field :occurred_at, :naive_datetime_usec
    field :amount, :decimal
    field :occurred_at_custom, :naive_datetime_usec, virtual: true
  end

  def occurred_at_dynamic(_opts) do
    dynamic([event], event.occurred_at)
  end
end
