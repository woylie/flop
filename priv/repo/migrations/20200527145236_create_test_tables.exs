defmodule Flop.Repo.Migrations.CreateTestTables do
  use Ecto.Migration

  def change do
    create table(:pets) do
      add(:name, :string)
      add(:age, :integer)
      add(:species, :string)
    end

    create table(:fruits) do
      add(:name, :string)
      add(:familiy, :string)
    end
  end
end
