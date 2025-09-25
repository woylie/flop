defmodule Flop.Repo.Mysql.Migration do
  use Ecto.Migration

  def change do
    create table(:owners) do
      add(:age, :integer)
      add(:email, :string)
      add(:name, :string)
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
    end

    create table(:fruits, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:family, :string)
      add(:name, :string)
      add(:attributes, :map)
      add(:extra, {:map, :string})
      add(:references, {:array, :binary_id})
      add(:owner_id, references(:owners))
    end
  end
end
