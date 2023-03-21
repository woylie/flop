# Flop

![CI](https://github.com/woylie/flop/workflows/CI/badge.svg) [![Hex](https://img.shields.io/hexpm/v/flop)](https://hex.pm/packages/flop) [![codecov](https://codecov.io/gh/woylie/flop/branch/main/graph/badge.svg?token=32BSY8O2LI)](https://codecov.io/gh/woylie/flop)

Flop is an Elixir library that applies filtering, ordering and pagination
parameters to your Ecto queries.

## Features

- offset-based pagination with `offset`/`limit` or `page`/`page_size`
- cursor-based pagination (aka key set pagination), compatible with Relay pagination arguments
- ordering by multiple fields in multiple directions
- filtering by multiple conditions with various operators on multiple fields
- parameter validation
- configurable filterable and sortable fields
- join fields
- compound fields
- query and meta data helpers
- Relay connection formatter (edges, nodes and page info)
- UI helpers and URL builders through [Flop Phoenix](https://hex.pm/packages/flop_phoenix).

## Installation

Add `flop` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:flop, "~> 0.20.0"}
  ]
end
```

If you want to configure a default repo, add this to your config file:

```elixir
config :flop, repo: MyApp.Repo
```

Alternatively, you can add a configuration module. For more information, refer
to the Flop module documentation.

## Usage

### Define sortable and filterable fields

To configure the sortable and filterable fields, derive `Flop.Schema` in your
Ecto schema. While this step is optional, it is highly recommend, since the
parameters you will pass to the Flop functions will come from the user side and
should be validated. Deriving `Flop.Schema` will ensure that Flop only
applies filtering and sorting parameters on the configured fields.

```elixir
defmodule MyApp.Pet do
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:name, :species],
    sortable: [:name, :age, :species]
  }

  schema "pets" do
    field :name, :string
    field :age, :integer
    field :species, :string
    field :social_security_number, :string
  end
end
```

You can also define join fields, compound fields, max and default limit, and
more. See the [Flop.Schema documentation](https://hexdocs.pm/flop/Flop.Schema.html)
for all the options.

### Query data

You can use `Flop.validate_and_run/3` or `Flop.validate_and_run!/3` to validate
the Flop parameters, retrieve the data from the database and get the meta data
for pagination in one go.

```elixir
defmodule MyApp.Pets do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MyApp.{Pet, Repo}

  @spec list_pets(map) ::
          {:ok, {[Pet.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_pets(params \\ %{}) do
    Flop.validate_and_run(Pet, params, for: Pet)
  end
end
```

The `for` option sets the Ecto schema for which you derived `Flop.Schema`. If
you didn't derive Flop.Schema as described above and don't care to do so,
you can omit this option (not recommended, unless you only deal with internally
generated, safe parameters).

On success, `Flop.validate_and_run/3` returns an `:ok` tuple, with the second
element being a tuple with the data and the meta data.

```elixir
{:ok, {[%Pet{}], %Flop.Meta{}}}
```

Consult the [docs](https://hexdocs.pm/flop/Flop.Meta.html) for more info on the
`Meta` struct.

If you prefer to validate the parameters in your controllers, you can use
`Flop.validate/2` or `Flop.validate!/2` and `Flop.run/3` instead.

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

  @spec list_pets(Flop.t()) :: {[Pet.t()], Flop.Meta.t}
  def list_pets(flop \\ %Flop{}) do
    Flop.run(Pet, flop, for: Pet)
  end
end
```

If you only need the data, or if you only need the meta data, you can also
call `Flop.all/3`, `Flop.meta/3` or `Flop.count/3` directly. Note that these
functions do not apply parameter validation. If the parameters are generated
through a user action, always use `Flop.validate/2` or `Flop.validate!/2`
first.

If you didn't configure a default repo as described above or if you want to
override the default repo, you can pass it as an option to any function that
uses the repo:

```elixir
Flop.validate_and_run(Pet, flop, repo: MyApp.Repo)
Flop.all(Pet, flop, repo: MyApp.Repo)
Flop.meta(Pet, flop, repo: MyApp.Repo)
# etc.
```

See the [docs](https://hexdocs.pm/flop/readme.html) for more detailed
information.

## Parameter format

Below are some examples for the parameter format, including the equivalent query
parameter strings that could be used with Phoenix.

### Pagination

#### Offset / limit

```elixir
%{offset: 20, limit: 10}
```

```html
?offset=20&limit=10
```

#### Page / page size

```elixir
%{page: 2, page_size: 10}
```

```html
?page=2&page_size=10
```

#### Cursor

```elixir
%{first: 10, after: "g3QAAAABZAACaWRiAAACDg=="}
```

```html
?first=10&after=g3QAAAABZAACaWRiAAACDg==
```

```elixir
%{last: 10, before: "g3QAAAABZAACaWRiAAACDg=="}
```

```html
?last=10&before=g3QAAAABZAACaWRiAAACDg==
```

### Ordering

The order parameters are split into `order_by` and `order_directions`, so that
they can be translated into query parameters.

```elixir
%{order_by: [:name, :age], order_directions: [:asc, :desc]}
```

```html
?order_by[]=name&order_by[]=age&order_directions[]=asc&order_directions[]=desc
```

### Filters

A complete filter consists of the field, the operator, and the value. The
operator is optional and defaults to `==`. Filters need to be passed as a list
and are combined with a logical `AND`. It is currently not possible to combine
filters with an `OR`.

```elixir
%{filters: [%{field: :name, op: :ilike_and, value: "Jane"}]}
```

```html
?filters[0][field]=name&filters[0][op]=ilike_and&filters[0][value]=Jane
```

See the documentation of `Flop.Filter` and the type documentation of
`t:Flop.t/0` for more details.

## Internal parameters

Flop is built to handle parameters generated by a user. While you could
manipulate those parameters and add additional filters when you receive them, it
is recommended to cleanly separate the parameters you get from the outside and
the parameters that your application needs to add internally.

For example, if you need to scope a query depending on the current user, it is
preferred to add a separate function that adds the necessary `WHERE` clauses:

```elixir
def list_pets(%{} = params, %User{} = current_user) do
  Pet
  |> scope(current_user)
  |> Flop.validate_and_run(params, for: Pet)
end

defp scope(q, %User{role: :admin}), do: q
defp scope(q, %User{id: user_id}), do: where(q, user_id: ^user_id)
```

To add additional filters that can only be used internally without exposing them
to the user, you can pass them as a separate argument. You can use the same
argument to override certain options depending on where the function is used.

```elixir
def list_pets(%{} = args, opts \\ [], %User{} = current_user) do
  flop_opts =
    opts
    |> Keyword.take([
      :default_limit,
      :default_pagination_type,
      :pagination_types
    ])
    |> Keyword.put(:for, Pet)

  Pet
  |> scope(current_user)
  |> apply_filters(opts)
  |> Flop.validate_and_run(flop, flop_opts)
end

defp scope(q, %User{role: :admin}), do: q
defp scope(q, %User{id: user_id}), do: where(q, user_id: ^user_id)

defp apply_filters(q, opts) do
  Enum.reduce(opts, q, fn
    {:last_health_check, dt}, q -> where(q, [p], p.last_health_check < ^dt)
    {:reminder_service, bool}, q -> where(q, [p], p.reminder_service == ^bool)
    _, q -> q
  end)
end
```

## Relay and Absinthe

If you are serving a GraphQL API using
[absinthe](https://hex.pm/packages/absinthe) and
[absinthe_relay](https://hex.pm/packages/absinthe_relay) (or even if you just
need to support the Relay cursor specification), you can use the
functions in the `Flop.Relay` module to turn the query responses into the format
that is expected by Relay.

Let's say you defined node objects for owners and pets, and a connection field
for pets on the owner node object.

```elixir
node object(:owner) do
  field :name, non_null(:string)
  field :email, non_null(:string)

  connection field :pets, node_type: :pet do
    resolve &MyAppWeb.Resolvers.Pet.list_pets/2
  end
end

node object(:pet) do
  field :name, non_null(:string)
  field :age, non_null(:integer)
  field :species, non_null(:string)
end

connection(node_type: :pet)
```

Absinthe Relay will define the arguments `after`, `before`, `first` and `last`
on the `pets` field. These are the same argument names that Flop uses, so it
will already know how to apply them.

We're going to define a `list_pets_by_owner/2` function in the `Pets` context.

```elixir
defmodule MyApp.Pets do
  import Ecto.Query

  alias MyApp.{Owner, Pet, Repo}

  @spec list_pets_by_owner(Owner.t(), map) ::
          {:ok, {[Pet.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_pets_by_owner(%Owner{id: owner_id}, params \\ %{}) do
    Pet
    |> where(owner_id: ^owner_id)
    |> Flop.validate_and_run(params, for: Pet)
  end
end
```

Now all you need to do in your resolver is to call that function and to call
`Flop.Relay.connection_from_result/1`, which turns the result into a tuple
consisting of the edges and the `page_info`, as expected by `absinthe_relay`.

```elixir
defmodule MyAppWeb.Resolvers.Pet do
  alias MyApp.{Owner, Pet}

  def list_pets(args, %{source: %Owner{} = owner} = resolution) do
    with {:ok, result} <- Pets.list_pets_by_owner(owner, args) do
      {:ok, Flop.Relay.connection_from_result(result)}
    end
  end
end
```

If you want to add additional filter arguments, you can use
`Flop.nest_filters/3` to convert simple filter arguments into Flop filters
without requiring users of your API to know about the Flop filter format.

Let's add `name` and `species` filter arguments to the `pets` connection field.

```elixir
node object(:owner) do
  field :name, non_null(:string)
  field :email, non_null(:string)

  connection field :pets, node_type: :pet do
    arg :name, :string
    arg :species, :string

    resolve &MyAppWeb.Resolvers.Pet.list_pets/2
  end
end
```

Assuming that these fields were already configured as filterable with
`Flop.Schema`, we can use `Flop.nest_filters/3` to take the filter arguments and
convert them into a list of Flop filters.

```elixir
defmodule MyAppWeb.Resolvers.Pet do
  alias MyApp.{Owner, Pet}

  def list_pets(args, %{source: %Owner{} = owner} = resolution) do
    args = nest_filters(args, [:name, :species])

    with {:ok, result} <- Pets.list_pets_by_owner(owner, args) do
      {:ok, Flop.Relay.connection_from_result(result)}
    end
  end
end
```

`Flop.nest_filters/3` uses the the equality operator `:==` by default.
You can override the default operator per field.

```elixir
args = nest_filters(args, [:name, :species], operators: %{name: :ilike_and})
```

## Flop Phoenix

[Flop Phoenix](https://hex.pm/packages/flop_phoenix) is a companion library that
defines view helpers for use in Phoenix templates.
