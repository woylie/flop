defmodule Flop.Factory do
  @moduledoc false
  use ExMachina.Ecto, repo: Flop.Repo

  alias Flop.Fruit
  alias Flop.Owner
  alias Flop.Pet

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
      family_name: sequence(:name, @family_name),
      given_name: sequence(:name, @given_name),
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

  def pet_with_owner_factory do
    %Pet{
      name: build(:name),
      age: :rand.uniform(30),
      species: build(:species),
      owner: build(:owner)
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
    sequence(:name, @given_name) <> sequence(:name, @family_name)
  end

  def species_factory(_) do
    sequence(:species, @species)
  end
end
