defmodule Flop.Pet do
  @moduledoc """
  Defines an Ecto schema for testing.
  """
  use Ecto.Schema
  import Ecto.Query

  alias Flop.Owner

  @derive {
    Flop.Schema,
    filterable: [
      :age,
      :full_name,
      :name,
      :owner_age,
      :owner_name,
      :owner_tags,
      :pet_and_owner_name,
      :species,
      :tags,
      :custom,
      :reverse_name
    ],
    sortable: [:name, :age, :owner_name, :owner_age],
    max_limit: 1000,
    compound_fields: [
      full_name: [:family_name, :given_name],
      pet_and_owner_name: [:name, :owner_name]
    ],
    join_fields: [
      owner_age: {:owner, :age},
      owner_name: [
        binding: :owner,
        field: :name,
        path: [:owner, :name],
        ecto_type: :string
      ],
      owner_tags: {:owner, :tags}
    ],
    custom_fields: [
      custom: [
        filter: {__MODULE__, :test_custom_filter, [some: :options]}
      ],
      reverse_name: [
        filter: {__MODULE__, :reverse_name_filter, []},
        ecto_type: :string
      ]
    ]
  }

  schema "pets" do
    field :age, :integer
    field :family_name, :string
    field :given_name, :string
    field :name, :string
    field :species, :string
    field :tags, {:array, :string}, default: []

    belongs_to :owner, Owner
  end

  def test_custom_filter(query, %Flop.Filter{value: value} = filter, opts) do
    :options = Keyword.fetch!(opts, :some)
    send(self(), {:filter, {filter, opts}})

    if value == "some_value" do
      where(query, false)
    else
      query
    end
  end

  def reverse_name_filter(query, %Flop.Filter{value: value}, _) do
    reversed = value
    where(query, [p], p.name == ^reversed)
  end

  def get_field(%__MODULE__{owner: %Owner{age: age}}, :owner_age), do: age
  def get_field(%__MODULE__{owner: nil}, :owner_age), do: nil
  def get_field(%__MODULE__{owner: %Owner{name: name}}, :owner_name), do: name
  def get_field(%__MODULE__{owner: nil}, :owner_name), do: nil
  def get_field(%__MODULE__{owner: %Owner{tags: tags}}, :owner_tags), do: tags
  def get_field(%__MODULE__{owner: nil}, :owner_tags), do: nil

  def get_field(%__MODULE__{} = pet, field)
      when field in [:name, :age, :species, :tags],
      do: Map.get(pet, field)

  def get_field(%__MODULE__{} = pet, field)
      when field in [:full_name, :pet_and_owner_name],
      do: random_value_for_compound_field(pet, field)

  def random_value_for_compound_field(
        %__MODULE__{family_name: family_name, given_name: given_name},
        :full_name
      ),
      do: Enum.random([family_name, given_name])

  def random_value_for_compound_field(
        %__MODULE__{name: name, owner: %Owner{name: owner_name}},
        :pet_and_owner_name
      ),
      do: Enum.random([name, owner_name])

  def concatenated_value_for_compound_field(
        %__MODULE__{family_name: family_name, given_name: given_name},
        :full_name
      ),
      do: family_name <> " " <> given_name

  def concatenated_value_for_compound_field(
        %__MODULE__{name: name, owner: %Owner{name: owner_name}},
        :pet_and_owner_name
      ),
      do: name <> " " <> owner_name
end
