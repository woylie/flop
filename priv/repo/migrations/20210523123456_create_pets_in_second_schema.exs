defmodule Flop.Repo.Migrations.CreatePetsInSecondSchema do
  use Ecto.Migration

  def change do
    execute("CREATE SCHEMA other_schema;", "DROP SCHEMA other_schema;")

    create table(:pets, prefix: "other_schema") do
      add :age, :integer
      add :family_name, :string
      add :given_name, :string
      add :name, :string
      add :owner_id, :integer
      add :species, :string
      add :tags, {:array, :string}
    end
  end
end
