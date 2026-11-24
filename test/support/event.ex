defmodule MyApp.Event do
  @moduledoc false

  use Ecto.Schema

  @derive {Flop.Schema,
           filterable: [], sortable: [:occurred_on, :occurred_at, :amount]}

  schema "events" do
    field :occurred_on, :date
    field :occurred_at, :naive_datetime_usec
    field :amount, :decimal
  end
end
