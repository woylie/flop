defmodule Flop.Repo.Migrations.CreateTestTables do
  use Ecto.Migration

  def change do
    create table(:owners) do
      add :given_name, :string
      add :family_name, :string
      add :name, :string
      add :email, :string
      add :age, :integer
    end

    create table(:pets) do
      add :name, :string
      add :age, :integer
      add :species, :string
      add :owner_id, references(:owners)
    end

    create table(:fruits) do
      add :name, :string
      add :familiy, :string
    end
  end
end
