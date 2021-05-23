defmodule Flop.Repo.Migrations.CreatePetsInSecondSchema do
  use Ecto.Migration

  def change do
    execute("CREATE SCHEMA other_schema;", "DROP SCHEMA other_schema;")

    create table(:pets, prefix: "other_schema") do
      add(:name, :string)
      add(:age, :integer)
      add(:species, :string)
    end
  end
end
