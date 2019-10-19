# Flop

![CI](https://github.com/woylie/flop/workflows/CI/badge.svg)

Flop is an Elixir library for making filtering, ordering and pagination with
Ecto a bit easier.

## Features

- ordering by multiple fields in multiple directions
- offset/limit based pagination
- page number/page size based pagination
- filtering by multiple conditions with diverse operators on multiple fields
- parameter validation
- configurable filterable and sortable fields

## To Do

See https://github.com/woylie/flop/projects/1

## Installation

Add `flop` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:flop, "~> 0.1.0"}
  ]
end
```

## Usage

### Define sortable and filterable fields

If you want the order by and filter fields to be validated, configure the
sortable and filterable fields in your Ecto schema like this:

```elixir
defmodule MyApp.Pet do
  use Ecto.Schema

  @derive {Flop.Schema,
           filterable: [:name, :species], sortable: [:name, :age, :species]}

  schema "pets" do
    field :name, :string
    field :age, :integer
    field :species, :string
    field :social_security_number, :string
  end
end
```

Note that if you don't pass the `filterable` and `sortable` options, `[]` is
set as a default for both, which means that `Flop` will not allow any ordering
or filtering if you pass the `for` option to `Flop.validate/2`.

### Querying

The most important functions are `Flop.query/2` and `Flop.validate/2`. You can
use them like this:

```elixir
defmodule MyApp.Pets do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Flop
  alias MyApp.{Pet, Repo}

  @spec list_pets(Flop.t()) :: {:ok, Pet.t()} | {:error, Changeset.t()}
  def list_pets(flop \\ %Flop{}) do
    with {:ok, flop} <- Flop.validate(flop, for: Pet) do
      pets =
        Pet
        |> Flop.query(flop)
        |> Repo.all()

      {:ok, pets}
    end
  end
end
```

If you didn't derive Flop.Schema as described above and don't care to do so,
just call the validate function without the second parameter:
`Flop.validate(flop)`.

### Phoenix

If you are using Phoenix, you might prefer to validate the Flop parameters in
your controller instead.

```elixir
defmodule MyAppWeb.PetController do
  use MyAppWeb, :controller

  alias Flop
  alias MyApp.Pets
  alias MyApp.Pets.Pet

  action_fallback MyAppWeb.FallbackController

  def index(conn, params) do
    with {:ok, flop} <- Flop.validate(params, for: Pet) do
      pets = Pets.list_pets(flop)
      render(conn, "index.html", pets: pets)
    end
  end
end

defmodule MyAppWeb.PetController do
  import Ecto.Query, warn: false

  alias Flop
  alias MyApp.{Pet, Repo}

  @spec list_pets(Flop.t()) :: [Pet.t()]
  def list_pets(flop \\ %Flop{}) do
    Pet
    |> Flop.query(flop)
    |> Repo.all()
  end
end
```
