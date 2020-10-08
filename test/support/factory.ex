defmodule Flop.Factory do
  @moduledoc false
  use ExMachina.Ecto, repo: Flop.Repo
  use ExUnitProperties

  alias Flop.Filter
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

  def pet_generator do
    gen all name <- string(:alphanumeric),
            age <- integer(1..500),
            species <- string(:alphanumeric) do
      %{name: name, age: age, species: species}
    end
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

  @doc """
  Generates a filter struct.
  """
  def filter do
    gen all field <- member_of([:age, :name]),
            value <- value_by_field(field),
            op <- operator_by_type(value) do
      %Filter{field: field, op: op, value: value}
    end
  end

  def value_by_field(:age), do: integer()
  def value_by_field(:name), do: string(:alphanumeric, min_length: 1)

  def compare_value_by_field(:age), do: integer(1..30)

  def compare_value_by_field(:name),
    do: string(?a..?z, min_length: 1, max_length: 3)

  defp operator_by_type(a) when is_binary(a),
    do: member_of([:==, :!=, :=~, :<=, :<, :>=, :>])

  defp operator_by_type(a) when is_number(a),
    do: member_of([:==, :!=, :<=, :<, :>=, :>])
end
