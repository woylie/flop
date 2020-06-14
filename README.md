# Flop

![CI](https://github.com/woylie/flop/workflows/CI/badge.svg) [![Hex](https://img.shields.io/hexpm/v/flop)](https://hex.pm/packages/flop) [![Coverage Status](https://coveralls.io/repos/github/woylie/flop/badge.svg)](https://coveralls.io/github/woylie/flop)

Flop is an Elixir library for making filtering, ordering and pagination with
Ecto a bit easier.

**This library is in early development.**

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
    {:flop, "~> 0.5.0"}
  ]
end
```

If you want to configure a default repo, add this to your config file:

```elixir
config :flop, repo: MyApp.Repo
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

### Validation and querying

You can validate Flop parameters with `Flop.validate/2` or `Flop.validate!/2`
and apply the Flop options to a query with `Flop.query/2`.

```elixir
defmodule MyApp.Pets do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Flop
  alias MyApp.{Pet, Repo}

  @spec list_pets(Flop.t()) :: {:ok, [Pet.t()]} | {:error, Changeset.t()}
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
you can call the validate function without the second parameter:
`Flop.validate(flop)`.

## Wrapper functions and counting

There is also a wrapper function for `Ecto.Repo.all/2` called `Flop.all/3`.
which allows you to write the code above as:

```elixir
@spec list_pets(Flop.t()) :: {:ok, [Pet.t()]} | {:error, Changeset.t()}
def list_pets(flop \\ %Flop{}) do
  with {:ok, flop} <- Flop.validate(flop, for: Pet) do
    {:ok, Flop.all(Pet, flop)}
  end
end
```

Additionally, you can use `Flop.count/3` to get the total count of matching
entries. The pagination options of the given Flop are ignored, so you will get
the correct total count that you need for building the pagination links.

```elixir
@spec count_pets(Flop.t()) :: non_neg_integer
def count_pets(flop \\ %Flop{}) do
  flop = Flop.validate!(flop, for: Pet)
  Flop.count(Pet, flop)
end
```

If you didn't configure a default repo as described above or if you want to
override the default repo, you can pass it as a parameter to both functions:

```elixir
Flop.all(Pet, flop, repo: MyApp.Repo)
Flop.count(Pet, flop, repo: MyApp.Repo)
```

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

defmodule MyApp.Pets do
  import Ecto.Query, warn: false

  alias Flop
  alias MyApp.Pets.Pet
  alias MyApp.Repo

  @spec list_pets(Flop.t()) :: [Pet.t()]
  def list_pets(flop \\ %Flop{}) do
    Flop.all(Pet, flop)
  end
end
```
