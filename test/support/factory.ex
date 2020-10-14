defmodule Flop.Factory do
  @moduledoc false
  use ExMachina.Ecto, repo: Flop.Repo

  alias Flop.Fruit
  alias Flop.Pet

  @family [
    "Rosaceae",
    "Lecythidaceae",
    "Rubiaceae",
    "Salicaceae",
    "Sapotaceae"
  ]

  @name [
    "Flossie Blackwell",
    "Casey Pierce",
    "Ingrid Gallagher",
    "Emil Smith",
    "Brittney Johnson",
    "Rodney Carter",
    "Brittany Villegas",
    "Etta Romero",
    "Loretta Norris",
    "Eddie Becker",
    "Floyd Holland",
    "Bernardo Wade",
    "Gay Rich",
    "Harrison Brooks",
    "Frederic Snow",
    "Clay Sutton",
    "Genevieve Singh",
    "Albert Adkins",
    "Bianca Schroeder",
    "Rolando Barker",
    "Billy Francis",
    "Jody Hanna",
    "Marisa Williamson",
    "Kenton Hess",
    "Carrol Simon"
  ]

  @species [
    "C. lupus",
    "F. catus",
    "O. cuniculus",
    "C. porcellus",
    "V. pacos",
    "C. bactrianus",
    "E. africanus",
    "M. putorius",
    "C. aegagrus",
    "L. glama",
    "S. scrofa",
    "R. norvegicus",
    "O. aries"
  ]

  def fruit_factory do
    %Fruit{
      family: build(:fruit_family),
      name: build(:name)
    }
  end

  def pet_factory do
    %Pet{
      name: build(:name),
      age: :rand.uniform(30),
      species: build(:species)
    }
  end

  def pet_downcase_factory do
    Map.update!(build(:pet), :name, &String.downcase/1)
  end

  def fruit_family_factory(_) do
    sequence(:fruit_family, @family)
  end

  def name_factory(_) do
    sequence(:name, @name)
  end

  def species_factory(_) do
    sequence(:species, @species)
  end
end
