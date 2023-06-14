defmodule Sibill.Repo.Migrations.CreateDistanceTable do
  use Ecto.Migration

  def change do
    create table(:walking_distances) do
      add(:trip, :distance)
    end
  end
end
