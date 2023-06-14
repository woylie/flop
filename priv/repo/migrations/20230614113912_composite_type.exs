defmodule Sibill.Repo.Migrations.CompositeType do
  use Ecto.Migration

  def up do
    execute("CREATE TYPE public.distance AS (unit varchar, value float);")
  end

  def down do
    execute("DROP TYPE public.distance;")
  end
end
