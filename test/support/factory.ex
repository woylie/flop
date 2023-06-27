defmodule Flop.Factory do
  @moduledoc false
  use ExMachina.Ecto, repo: Flop.Repo

  alias MyApp.Fruit
  alias MyApp.Owner
  alias MyApp.Pet

  @family [
    "Rosaceae",
    "Lecythidaceae",
    "Rubiaceae",
    "Salicaceae",
    "Sapotaceae"
  ]

  @given_name [
    "Albert",
    "Bernardo",
    "Bianca",
    "Billy",
    "Brittany",
    "Brittney",
    "Carrol",
    "Casey",
    "Clay",
    "Eddie",
    "Emil",
    "Etta",
    "Flossie",
    "Floyd",
    "Frederic",
    "Gay",
    "Genevieve",
    "Harrison",
    "Ingrid",
    "Jody",
    "Kenton",
    "Loretta",
    "Marisa",
    "Rodney",
    "Rolando"
  ]

  @family_name [
    "Adkins",
    "Barker",
    "Becker",
    "Blackwell",
    "Brooks",
    "Carter",
    "Francis",
    "Gallagher",
    "Hanna",
    "Hess",
    "Holland",
    "Johnson",
    "Norris",
    "Pierce",
    "Rich",
    "Romero",
    "Schroeder",
    "Simon",
    "Singh",
    "Smith",
    "Snow",
    "Sutton",
    "Villegas",
    "Wade",
    "Williamson"
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

  @tags [
    "catalunya",
    "cateyes",
    "catlady",
    "catlife",
    "catlove",
    "caturday",
    "doge",
    "doggie",
    "doggo",
    "doglife",
    "doglove",
    "dogmodel",
    "dogmom",
    "dogscorner",
    "petscorner"
  ]

  def fruit_factory do
    %Fruit{
      family: build(:fruit_family),
      name: build(:name)
    }
  end

  def owner_factory do
    %Owner{
      age: :rand.uniform(100),
      email: build(:species),
      name: build(:name),
      tags: Enum.take_random(@tags, Enum.random(1..5))
    }
  end

  def pet_factory do
    %Pet{
      age: :rand.uniform(30),
      family_name: sequence(:family_name, @family_name),
      given_name: sequence(:given_name, @given_name),
      name: build(:name),
      species: build(:species),
      tags: Enum.take_random(@tags, Enum.random(1..5))
    }
  end

  def pet_with_owner_factory do
    %Pet{
      age: :rand.uniform(30),
      family_name: sequence(:family_name, @family_name),
      given_name: sequence(:given_name, @given_name),
      name: build(:name),
      owner: build(:owner),
      species: build(:species),
      tags: Enum.take_random(@tags, Enum.random(1..5))
    }
  end

  def pet_downcase_factory do
    Map.update!(build(:pet), :name, &String.downcase/1)
  end

  def fruit_family_factory(_) do
    sequence(:fruit_family, @family)
  end

  def email_factory(_) do
    prefix =
      :name
      |> build()
      |> String.downcase()
      |> String.replace(" ", "@")

    prefix <> ".com"
  end

  def name_factory(_) do
    sequence(:name, @given_name) <> " " <> sequence(:name, @family_name)
  end

  def species_factory(_) do
    sequence(:species, @species)
  end
end
