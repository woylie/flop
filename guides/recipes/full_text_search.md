# Full text search

An `ilike` filter matches literal substrings, so searching for "run" also
matches "brunch", while searching for "running" does not match "run". It also
has no notion of how well a row matches. PostgreSQL full text search matches
word stems, so "run" and "running" find each other, "brunch" is unrelated, and
the results can be ranked.

In Flop, full text search can be implemented with a custom field, and the rank
with an alias field. This recipe is specific to PostgreSQL.

## Search column

Store the document in a `tsvector` column and index it. A generated column keeps
it in sync with the source columns, so nothing in your application has to
remember to update it.

```elixir
defmodule MyApp.Repo.Migrations.AddPetSearchColumn do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE pets
    ADD COLUMN searchable tsvector
    GENERATED ALWAYS AS (
      to_tsvector(
        'english',
        coalesce(name, '') || ' ' || coalesce(description, '')
      )
    ) STORED
    """

    execute "CREATE INDEX pets_searchable_idx ON pets USING GIN (searchable)"
  end

  def down do
    execute "DROP INDEX pets_searchable_idx"
    execute "ALTER TABLE pets DROP COLUMN searchable"
  end
end
```

Concatenating with `||` yields `NULL` if any operand is `NULL`, which would
leave the whole document empty for a pet without a description. The `coalesce`
calls prevent this.

Add the column to the schema, so that you can refer to it in a query.

```elixir
schema "pets" do
  field :name, :string
  field :description, :string
  field :searchable, :string, load_in_query: false
end
```

Ecto has no `tsvector` type. The column is only ever used in the `WHERE` clause,
and `load_in_query: false` keeps it out of the select clause.

## Filter

The search is a custom field, because `@@` is not one of Flop's operators.

```elixir
defmodule MyApp.Filters do
  import Ecto.Query

  def search(query, %Flop.Filter{value: value}, _opts) do
    where(
      query,
      [p],
      fragment(
        "? @@ websearch_to_tsquery('english', ?)",
        p.searchable,
        ^value
      )
    )
  end
end
```

```elixir
use Flop.Schema

@flop_options [
  filterable: [:search],
  sortable: [:name],
  adapter_opts: [
    custom_fields: [
      search: [
        filter: {MyApp.Filters, :search, []},
        ecto_type: :string,
        operators: [:like]
      ]
    ]
  ]
]
```

The function needs no guard for an empty search box. `Flop.validate/2` casts a
blank string to `nil`, and Flop skips filters with a `nil` value, so the
function is only called with something to search for.

Use `websearch_to_tsquery` rather than `to_tsquery`. It reads what a user types
into a search box, including quoted phrases, `or` and a leading `-`, and it
never raises. `to_tsquery` expects operator syntax and raises a syntax error on
input like `pet &`. Use `plainto_tsquery` if you do not want users to have
operators at all.

The filter function ignores the operator. We set `operators: [:like]` to avoid
offering operators that are not supported.

## Accents

A search for "cafe" does not find "Café", because the two are different lexemes.
The `unaccent` extension removes the diacritics.

```sql
CREATE EXTENSION unaccent;
```

Adding it to the generated column and to the index is where it gets in the way,
because both of them fail:

```text
ERROR 42P17 (invalid_object_definition) generation expression is not immutable
ERROR 42P17 (invalid_object_definition) functions in index expression
must be marked IMMUTABLE
```

A generated column and an index both store the result of the expression, so
PostgreSQL only accepts functions it can rely on to return the same result for
the same argument forever, which it calls `IMMUTABLE`. `unaccent/1` is one step
weaker, `STABLE`: it looks up the default dictionary at run time, and that
dictionary can be changed.

The two-argument form takes the dictionary as an argument instead of looking it
up, so a wrapper around it can be declared immutable.

```sql
CREATE FUNCTION immutable_unaccent(text) RETURNS text
  LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
  AS $$ SELECT unaccent('unaccent', $1) $$;
```

Use it on both sides. In the generated column:

```sql
to_tsvector('simple', immutable_unaccent(coalesce(name, '')))
```

And on the search term:

```elixir
fragment(
  "? @@ websearch_to_tsquery('simple', immutable_unaccent(?))",
  p.searchable,
  ^value
)
```

The `'simple'` configuration is deliberate here. The language configurations
stem words, which is usually what you want for a description, but they also
expect their own language's spelling, so combine them with `unaccent` only if
that suits your data.

## Ranking

`ts_rank` scores a row against the query. Sorting by it needs the score in the
select clause under a name. You can use `Ecto.Query.API.selected_as/2` and an
alias field for this.

```elixir
use Flop.Schema

@flop_options [
  filterable: [:search],
  sortable: [:name, :rank],
  adapter_opts: [
    alias_fields: [:rank],
    custom_fields: [
      search: [
        filter: {MyApp.Filters, :search, []},
        ecto_type: :string,
        operators: [:like]
      ]
    ]
  ]
]
```

`ts_rank` takes the search term as an argument, and the term arrives as a filter
parameter, so the select clause can only be built once the parameters are
validated. That is why we use `Flop.validate/2` and `Flop.run/3` rather than
`Flop.validate_and_run/3` here.

```elixir
def list_pets(params) do
  opts = [for: Pet]

  with {:ok, flop} <- Flop.validate(params, opts) do
    flop.filters
    |> Flop.Filter.get_value(:search)
    |> ranked_query()
    |> Flop.run(flop, opts)
  end
end

defp ranked_query(term) when is_binary(term) do
  from p in Pet,
    select_merge: %{
      rank:
        selected_as(
          fragment(
            "ts_rank(?, websearch_to_tsquery('english', ?))",
            p.searchable,
            ^term
          ),
          :rank
        )
    }
end

defp ranked_query(_) do
  from p in Pet, select_merge: %{rank: selected_as(fragment("0.0"), :rank)}
end
```

The second clause matters: a client can order by `rank` without a search term,
and PostgreSQL rejects an `ORDER BY` on a name the select clause does not
define.

Ranking has two limits that come from the alias field:

- An alias field cannot be filterable, since PostgreSQL does not allow a select
  alias in a `WHERE` clause.
- Cursor pagination cannot use an alias field as cursor for the same reason.
  `Flop.validate/2` returns a validation error for that combination, so use
  offset or page based pagination when you sort by rank.

## Complete example

```elixir
defmodule MyApp.Pet do
  use Ecto.Schema
  use Flop.Schema

  @flop_options [
    filterable: [:search],
    sortable: [:name, :rank],
    default_order: %{
      order_by: [:name],
      order_directions: [:asc]
    },
    pagination_types: [:page, :offset],
    adapter_opts: [
      alias_fields: [:rank],
      custom_fields: [
        search: [
          filter: {MyApp.Filters, :search, []},
          ecto_type: :string,
          operators: [:like]
        ]
      ]
    ]
  ]

  schema "pets" do
    field :name, :string
    field :description, :string
    field :searchable, :string, load_in_query: false
    field :rank, :float, virtual: true
  end
end

defmodule MyApp.Filters do
  import Ecto.Query

  def search(query, %Flop.Filter{value: value}, _opts) do
    where(
      query,
      [p],
      fragment(
        "? @@ websearch_to_tsquery('english', ?)",
        p.searchable,
        ^value
      )
    )
  end
end

defmodule MyApp.Pets do
  import Ecto.Query

  alias MyApp.Pet

  def list_pets(params) do
    opts = [for: Pet]

    with {:ok, flop} <- Flop.validate(params, opts) do
      flop.filters
      |> Flop.Filter.get_value(:search)
      |> ranked_query()
      |> Flop.run(flop, opts)
    end
  end

  defp ranked_query(term) when is_binary(term) do
    from p in Pet,
      select_merge: %{
        rank:
          selected_as(
            fragment(
              "ts_rank(?, websearch_to_tsquery('english', ?))",
              p.searchable,
              ^term
            ),
            :rank
          )
      }
  end

  defp ranked_query(_) do
    from p in Pet, select_merge: %{rank: selected_as(fragment("0.0"), :rank)}
  end
end
```
