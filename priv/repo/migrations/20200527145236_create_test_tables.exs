defmodule Flop.Repo.Migrations.CreateTestTables do
  use Ecto.Migration

  def change do
    create table(:owners) do
      add :age, :integer
      add :email, :string
      add :name, :string
      add :tags, {:array, :string}
    end

    create table(:pets) do
      add :age, :integer
      add :family_name, :string
      add :given_name, :string
      add :name, :string
      add :owner_id, references(:owners)
      add :species, :string
      add :tags, {:array, :string}
    end

    create table(:fruits) do
      add :family, :string
      add :name, :string
    end
  end
end
