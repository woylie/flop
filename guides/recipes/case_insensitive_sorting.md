# Case-insensitive sorting

Whether ordering is case-sensitive depends on the collation of the database.
With `en_US.utf8` it is not, and only `COLLATE "C"` puts every uppercase letter
first:

```text
ORDER BY name                  apple, Apple, Banana, cherry
ORDER BY name COLLATE "C"      Apple, Banana, apple, cherry
```

So check the collation before changing anything. If it does sort
case-sensitively, there are three ways out, and which one fits depends on what
else the field has to do.

## Sorting only

Select `lower(name)` under a name with `Ecto.Query.API.selected_as/2` and
declare an alias field.

```elixir
@derive {Flop.Schema,
         filterable: [],
         sortable: [:name_lower],
         adapter_opts: [alias_fields: [:name_lower]]}
```

```elixir
from p in MyApp.Pet,
  select_merge: %{
    name_lower: selected_as(fragment("lower(?)", p.name), :name_lower)
  }
```

## Sorting and filtering, or cursor pagination

Alias fields cannot be used for filtering or cursor pagination. You can expose
the lowercased value through a lateral join and a join field instead, as
described in the [computed fields recipe](computed_and_embedded_fields.md).

## A case-insensitive column

In PostgreSQL, you can use a `citext` column to sort, compares and match
`LIKE` case-insensitively. Flop needs no configuration for it.

```sql
CREATE EXTENSION citext;
ALTER TABLE pets ALTER COLUMN name TYPE citext;
```

A nondeterministic ICU collation does the same for sorting and equality, but
PostgreSQL does not support `LIKE` on such a column, so Flop's `:like` and
`:ilike` operators fail on it:

```text
ERROR 0A000 (feature_not_supported)
nondeterministic collations are not supported for LIKE
```
