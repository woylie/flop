defmodule Flop.Repo.Postgres.Migration do
  use Ecto.Migration

  def change do
    execute(
      "CREATE TYPE public.distance AS (unit varchar, value float);",
      "DROP TYPE public.distance;"
    )

    create table(:owners) do
      add(:age, :integer)
      add(:email, :string)
      add(:name, :string)
      add(:tags, {:array, :string})
      add(:attributes, :map)
      add(:extra, {:map, :string})
    end

    create table(:pets) do
      add(:age, :integer)
      add(:family_name, :string)
      add(:given_name, :string)
      add(:name, :string)
      add(:owner_id, references(:owners))
      add(:species, :string)
      add(:mood, :string)
      add(:tags, {:array, :string})
    end

    create table(:fruits, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:family, :string)
      add(:name, :string)
      add(:attributes, :map)
      add(:extra, {:map, :string})
      add(:owner_id, references(:owners))
    end

    create table(:walking_distances) do
      add(:trip, :distance)
    end

    # create pets table in other schema

    execute("CREATE SCHEMA other_schema;", "DROP SCHEMA other_schema;")

    create table(:pets, prefix: "other_schema") do
      add(:age, :integer)
      add(:family_name, :string)
      add(:given_name, :string)
      add(:name, :string)
      add(:owner_id, :integer)
      add(:species, :string)
      add(:mood, :string)
      add(:tags, {:array, :string})
    end
  end
end
