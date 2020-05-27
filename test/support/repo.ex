defmodule Flop.Repo do
  use Ecto.Repo,
    otp_app: :flop,
    adapter: Ecto.Adapters.Postgres
end
