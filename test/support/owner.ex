defmodule MyApp.Owner do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema

  alias MyApp.Pet

  @derive {
    Flop.Schema,
    filterable: [
      :name,
      :pet_mood_as_reference,
      :pet_mood_as_enum,
      :pet_mood_as_parameterized_type
    ],
    sortable: [:name, :age],
    join_fields: [
      pet_age: [
        binding: :pets,
        field: :age
      ],
      pet_mood_as_reference: [
        binding: :pets,
        field: :mood,
        ecto_type: {:from_schema, Pet, :mood}
      ],
      pet_mood_as_enum: [
        binding: :pets,
        field: :mood,
        ecto_type: {:ecto_enum, [:happy, :playful]}
      ],
      pet_mood_as_parameterized_type: [
        binding: :pets,
        field: :mood,
        ecto_type:
          Ecto.ParameterizedType.init(Ecto.Enum, values: [:happy, :playful])
      ]
    ],
    compound_fields: [age_and_pet_age: [:age, :pet_age]],
    alias_fields: [:pet_count],
    default_pagination_type: :page
  }

  schema "owners" do
    field :age, :integer
    field :email, :string
    field :name, :string
    field :tags, {:array, :string}, default: []
    field :pet_count, :integer, virtual: true
    field :attributes, :map
    field :extra, {:map, :string}

    has_many :pets, Pet
  end
end
