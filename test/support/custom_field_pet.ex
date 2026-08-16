defmodule MyApp.CustomFieldPet do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Query

  alias MyApp.Owner

  @derive {
    Flop.Schema,
    filterable: [:age_score, :name_lower, :tag_list, :owner_age_score],
    sortable: [:age_score, :owner_age_score],
    adapter_opts: [
      custom_fields: [
        age_score: [
          field_dynamic:
            {__MODULE__, :age_score_dynamic,
             [factor: 2, compile_only: :available]},
          ecto_type: :integer
        ],
        owner_age_score: [
          field_dynamic: {__MODULE__, :owner_age_score_dynamic, []},
          bindings: [:owner],
          ecto_type: :integer,
          path: [:owner_age]
        ],
        name_lower: [
          field_dynamic: {__MODULE__, :name_lower_dynamic, []},
          ecto_type: :string
        ],
        tag_list: [
          field_dynamic: {__MODULE__, :tag_list_dynamic, []},
          ecto_type: {:array, :string}
        ]
      ]
    ]
  }

  schema "pets" do
    field :age, :integer
    field :name, :string
    field :tags, {:array, :string}
    field :age_score, :integer, virtual: true
    field :owner_age, :integer, virtual: true
    belongs_to :owner, Owner
  end

  def age_score_dynamic(opts) do
    if test_pid = opts[:test_pid] do
      send(test_pid, {:age_score_dynamic_opts, opts})
    end

    factor = Keyword.fetch!(opts, :factor)
    dynamic([pet], fragment("? * ?", pet.age, ^factor))
  end

  def owner_age_score_dynamic(_opts) do
    dynamic([owner: owner], owner.age)
  end

  def name_lower_dynamic(_opts) do
    dynamic([pet], fragment("lower(?)", pet.name))
  end

  def tag_list_dynamic(_opts) do
    dynamic([pet], pet.tags)
  end
end
