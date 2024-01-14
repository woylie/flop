# Changelog

## Unreleased

## [0.25.0] - 2024-01-14

### Added

- Added `Flop.Filter.update_value/3` for updating the filter value for a field
  in a list of filters.

### Fixed

- Determine pagination type if pagination parameter has errors.

## [0.24.1] - 2023-11-18

### Changed

- `Flop.push_order/3` now allows you to use a descending order as the initial
  sort order.

## [0.24.0] - 2023-11-14

### Changed

- If an invalid operator is passed in a filter, the error will now include the
  list of allowed operators for that field.

## [0.23.0] - 2023-09-26

### Added

- Added `directions` option to `Flop.push_order/3`.

### Fixed

- Escape backlash character in queries using one of the `like` operators.

## [0.22.1] - 2023-07-18

### Fixed

- Updated version requirement for Ecto to `~> 3.10.3`. Flop 0.22.0 relies
  on a feature added in that version and doesn't compile with lower versions.

## [0.22.0] - 2023-07-17

This release includes a substantial refactoring to lay the groundwork for the
upcoming adapter feature. While this release contains deprecations and changes,
they are either backward compatible or affect functions that are unlikely to be
used by end users. The primary aim has been to ensure a seamless transition and
maintain compatibility with previous versions.

### Added

- Added a `Flop.FieldInfo` struct that contains metadata for a field for use
  by adapters.
- Added the `Flop.Schema.field_info/2` function, which derives field information
  and replaces the previous `Flop.Schema.field_type/2` function with a more
  standardized and structured output.

### Changed

- The Ecto-specific options `alias_fields`, `compound_fields`, `custom_fields`,
  and `join_fields` within `Flop.Schema`, as well as `repo` and `query_opts`
  within `use Flop`, are now nested under the `adapter_opts` keyword. The old
  configuration format is still supported.

### Deprecated

- `Flop.Schema.field_type/2` was deprecated in favor of
  `Flop.Schema.field_info/2`.

### Removed

- Removed `Flop.Schema.apply_order_by/3`.
- Removed `Flop.Schema.cursor_dynamic/3`.

### Upgrade guide

While the old configuration format is still supported, you are invited to
update your application to the new structure to prepare for future versions.

To do this, place the field configuration for `Flop.Schema` under
`adapter_opts`:

```diff
@derive {
  Flop.Schema,
  filterable: [],
  sortable: [],
-  alias_fields: [],
-  compound_fields: [],
-  custom_fields: [],
-  join_fields: []
+  adapter_opts: [
+    alias_fields: [],
+    compound_fields: [],
+    custom_fields: [],
+    join_fields: []
+  ]
}
```

Similarly for `use Flop`, you can nest `repo` and `query_opts` under
`adapter_opts`:

```diff
use Flop,
  default_limit: 50,
-  repo: MyApp.Repo,
-  query_opts: [prefix: "some-prefix"]
+  adapter_opts: [
+    repo: MyApp.Repo,
+    query_opts: [prefix: "some-prefix"]
+  ]
```

## [0.21.0] - 2023-07-02

### Added

- Introduced `operators` as a new option for restricting acceptable operators
  for a custom field.
- Added bindings option for custom fields, allowing required named bindings to
  be added via `Flop.with_named_bindings/4`.
- The `ecto_type` option on join and custom fields now supports
  references: `{:from_schema, MySchema, :some_field}`.
- The `ecto_type` option now supports a convenient syntax for adhoc enums:
  `{:ecto_enum, [:one, :two]}`.
- Improved documentation with added type definitions: `t:Flop.Schema.option/0`,
  `t:Flop.Schema.join_field_option/0`, `t:Flop.Schema.custom_field_option/0`,
  and `t:Flop.Schema.ecto_type/0`, describing options available when deriving
  the `Flop.Schema` protocol.

### Changed

- **Breaking change:** Filter values are now dynamically cast based on the
  field type and operator, instead of allowing any arbitrary filter value. This
  change ensures that invalid filter values cause validation errors instead of
  cast errors.
- The options for deriving the `Flop.Schema` protocol and for `use Flop`
  now undergo stricter validation with `NimbleOptions`.
- `Flop.Cursor.encode/1` now explicitly sets the minor version option for
  `:erlang.term_to_binary/2` to `2`, aligning with the new default in OTP 26.
  Before, this option was not set at all.
- Added a `decoded_cursor` field to the `Flop` struct. This field temporarily
  stores the decoded cursor between validation and querying and is
  discarded when generating the meta data.

### Deprecated

- The tuple syntax for defining join fields has been deprecated in favor of a
  keyword list.

### Fixed

- Resolved an issue where setting `replace_invalid_params` to `true` still
  caused validation errors for pagination and sorting parameters due to cast
  errors, instead of defaulting to valid parameters.
- Fixed the type specification for `Flop.Filter.allowed_operators/1`.

### Upgrade notes

The newly implemented dynamic casting of filter values could impact your code:

- Filter values failing to cast into the determined type will now yield a
  validation error or result in the removal of the invalid filter if the
  `replace_invalid_params` option is enabled.
- The `value` field of the `Flop.Filter` struct now holds the cast value
  instead of the original parameter value. For instance, while handling
  parameters generated via an HTML form with Flop, previously all filter values
  would be represented as strings in the struct. However, they may now be
  integers, `DateTime` structs, and so forth. Look out for this if you are
  directly reading or manipulating `Flop.Filter` structs.
- For join and custom fields, the type is determined with the `ecto_type`
  option. Previously, this option was only used for operator validation.
  Ensure the correct Ecto type is set. If the option is omitted, the filter
  values will continue to use their incoming format.
- Manual casting of filter values in a custom filter function is no longer
  required if the `ecto_type` option is set.
- If join fields point to `Ecto.Enum` fields, previously you could simply set
  `ecto_type` to string. This will continue to work if the filter value is
  passed as a string, but passing it as an atom will cause an error. Make sure
  to correctly reference the schema field
  (`{:from_schema, MySchema, :some_field}`) or directly pass the Enum values
  (`{:ecto_enum, [:one, :two}`).
- To enable `Flop.Phoenix` to build a query string for filter parameters, the
  filter value must be convertible into a string via `to_string/1`. If
  `ecto_type` is set to a custom Ecto type that casts values into a struct, the
  `String.Chars` protocol must be implemented for that struct.
- If you use the result of `Flop.Phoenix.to_query/2` in a `~p` sigil for
  verified routes or in a route helper function, Phoenix converts filter values
  into a string using the `Phoenix.Param` protocol. If you use `Date`,
  `DateTime`, `NaiveDateTime`, `Time` filters, or filters using custom structs,
  you need to implement that protocol for these structs in your application.

Please review the newly added "Ecto type option" section in the `Flop.Schema`
module documentation.

#### Join field syntax

If you are using tuples to define join fields when deriving `Flop.Schema`,
update the configuration to use keyword lists instead:

```diff
@derive {
  Flop.Schema,
  join_fields: [
-    owner_name: {:owner, :name}
+    owner_name: [binding: :owner, field: :name]
  ]
}
```

## [0.20.3] - 2023-06-23

### Changed

- `Flop.count/3` will now wrap queries that have `GROUP BY` clauses in a
  subquery.

### Fixed

- Fixed cursor-based pagination on composite types.

## [0.20.2] - 2023-06-09

### Changed

- Added nutrition facts about `use Flop` and `@derive Flop.Schema`.
- The minimum Elixir version is now 1.11.

### Fixed

- Fixed a deprecation warning about `Logger.warn/1`.
- Fixed a deprecation warning about passing an MFA to `:with` in
  cast_assoc/cast_embed introduced in Ecto 3.10.2.

## [0.20.1] - 2023-05-19

### Added

- Added the `:count` override option to `Flop.count/3`.

### Changed

- The `default_pagination_type` can now be set in the schema.

### Fixed

- Don't raise function clause error in `Flop.to_previous_cursor/1` and
  `Flop.to_next_cursor/1` when the start cursor or end cursor are `nil`.

## [0.20.0] - 2023-03-21

### Added

- Added `Flop.unnest_filters/3` as a reverse operation of `Flop.nest_filters/3`
  after retrieving data from the database.
- Added `Flop.Filter.fetch_value/2`, `Flop.Filter.get_value/2`,
  `Flop.Filter.put_value/4`, `Flop.Filter.put_new_value/4`,
  `Flop.Filter.pop_value/3` and `Flop.Filter.pop_first_value/3`.

### Changed

- Several of the functions for manipulating lists of filters in the
  `Flop.Filter` module now accept lists of maps with atom keys, lists of maps
  with string keys, and indexed maps as produced by Phoenix HTML forms as
  argument.
- The `empty` and `not_empty` operators now treat empty maps as empty values on
  map fields and empty arrays as empty values on array fields.
- `%` and `_` characters in filter values for the `like`, `ilike` and `=~`
  operators are now escaped.

### Fixed

- Fixed an issue that caused filter conditions for `like_and`, `like_or`,
  `ilike_and` and `ilike_or` to be incorrectly combined when applied to compound
  fields.

## [0.19.0] - 2023-01-15

### Added

- Support for custom fields. These fields allow you to run custom filter
  functions for anything that cannot be expressed with Flop filters.
- Added `Flop.with_named_bindings/4` for dynamically adding bindings needed for
  a Flop query.
- Added `fetch`, `get`, `get_all`, `delete`, `delete_first`, `drop`, `new`,
  `take`, `pop`, `pop_first`, `put` and `put_new` functions to `Flop.Filter`.
- Added `Flop.Meta.with_errors/3`.
- Added `ecto_type` option to join fields.
- Added `not_like` and `not_ilike` filter operators.
- Added a cheatsheet for schema configuration.
- Added `opts` field to `Flop.Meta` struct.

### Changed

- Renamed `Flop.bindings/3` to `Flop.named_bindings/3`.
- `Flop.Filter.allowed_operators/2` now tries to determine the Ecto type by
  reading the Flop field type from the schema module. This function is used
  during parameter validation, which means the validation step will be a bit
  stricter now. For join and custom fields, the Ecto type is determined via the
  new `ecto_type` option. If the option is not set, the function returns all
  operators as before. For compound fields, only the supported operators are
  returned.

## [0.18.4] - 2022-11-17

### Changed

- The `:ilike_and`, `:ilike_or`, `:like_and` and `:like_or` filter operators can
  now also be used with a list of strings as filter value.

## [0.18.3] - 2022-10-27

### Fixed

- `default_pagination_type` can be overridden by passing `false` now.

## [0.18.2] - 2022-10-19

### Fixed

- `Flop.bindings/3` did not consider join fields that are used as part of a
  compound field.

## [0.18.1] - 2022-10-14

### Changed

- If the given map already has a `:filters` / `"filters"` key,
  `Flop.nest_filters/3` will now merge the derived filters into the existing
  filters. If the existing filters are formatted as a map (as produced by an
  HTML form), they are converted to a list first.
- `use Flop` will now also compile `validate/2` and `validate!/2` functions that
  apply the options of your config module.
- Allow setting `default_limit` and `max_limit` to `false`, which removes the
  default/max limit without falling back to global options.

### Fixed

- `Flop.bindings/3` was returning bindings for filters with `nil` values.

## [0.18.0] - 2022-10-10

### Added

- Added `alias_fields` option to `Flop.Schema`, which allows you to sort by
  field aliases defined with `Ecto.Query.API.selected_as/2`.
- Added `aliases/2` for getting the alias fields needed for a query.
- Added documentation example for filtering by calculated values.
- New option `rename` for `Flop.map_to_filter_params/2` and
  `Flop.nest_filters/3`.
- New option `:replace_invalid_params`. This option can be passed to the
  `validate` and `validate_and_run` functions or set in the global configuration
  or in a config module. Setting the value to `true` will cause Flop to replace
  invalid parameters with default values where possible or remove the parameter
  otherwise during the validation step, instead of returning validation errors.

### Changed

- Require `ecto ~> 3.9.0`.
- `Flop.Schema` does not raise an error anymore if a compound or join field is
  defined with the same name as a regular Ecto schema field. This was done so that
  you can add virtual fields with the same name. It is not possible to
  differentiate between non-virtual and virtual fields at compile time (at least
  I don't know how), so we cannot differentiate in the validation step.
- Flop applies a default limit of `50` and a max limit of `1000` now, unless
  other values are set.
- In offset/limit based pagination, the `limit` parameter is now required, in
  line with the other pagination types. If not set, it will fall back to a
  default limit.

## [0.17.2] - 2022-10-03

### Fixed

- Fixed an issue where the `repo` option was not read from a backend module.

## [0.17.1] - 2022-10-02

### Added

- Added a `backend` field to the `Flop.Meta` struct.

### Fixed

- Fixed an issue where the schema options were overridden by the backend module
  options.

## [0.17.0] - 2022-08-26

### Added

- Added the filter operators `not_in` and `not_contains`.
- Added examples for integration with Relay to the documentation.
- Added examples for the parameter format to the documentation.

### Changed

- Refactored the query builder. This does not affect users of the library, but
  makes the code base more readable and lays the groundwork for upcoming
  features.
- Added the `:query_opts` option to Flop callbacks to pass on options to the
  Ecto repo on query execution. If you are already using the `:prefix` option
  you now have to pass this through `:query_opts`.

If you configured the Repo `:prefix` in the application config:

```diff
config :flop,
-  prefix: "some-prefix"
+  query_opts: [prefix: "some-prefix"]
```

If you set the `:prefix` when calling the Flop functions:

```diff
- Flop.validate_and_run(Pet, params, prefix: "some-prefix")
+ Flop.validate_and_run(Pet, params, query_opts: [prefix: "some-prefix"])
```

## [0.16.1] - 2022-04-05

### Fixed

- Wrong type spec for `Flop.Schema.default_order/1` callback.

## [0.16.0] - 2022-03-22

### Added

- You can now define a configuration module with `use Flop` to set defaults
  instead of or in addition to the application configuration. This makes it
  easier to work with multiple Ecto repos.
- The new function `Flop.bindings/3` returns the necessary bindings for a
  given Flop query. You can use it in case you want to optimize your queries by
  only joining tables that are actually needed.
- Added a `count_query` option to override the count query used by
  `Flop.run/3`, `Flop.validate_and_run/3` and `Flop.validate_and_run!/3`.
- You can get a list of allowed operators for a given Ecto type or a given
  schema field with `Flop.Filter.allowed_operators/1` and
  `Flop.Filter.allowed_operators/2` now.

### Changed

- Breaking: The `:empty` and `:not_empty` filters now require a boolean value.
  If no value is passed, the filter is ignored, just as it is handled for all
  other filter operators. This change was necessary to make the integration
  with filter forms (checkboxes) easier.
- Breaking: The default order needs to be passed as a map now when deriving
  `Flop.Schema`. The previous implementation already converted the two separate
  configuration keys to a map. This meant that the configuration passed when
  deriving `Flop.Schema` had a different format from the one you had to pass
  when overriding the default order with the `opts`.
  With this change, the configuration format is the same everywhere. A compile
  time exception is raised if you are still using the old format, guiding you in
  the update.
- It is now validated that the filter operator matches the field type.
- The compile time validation of the options passed when deriving `Flop.Schema`
  has been improved.
- Allow passing page as string to `Flop.set_page/2`.
- Allow passing offset as string to `Flop.set_offset/2`.

## [0.15.0] - 2021-11-14

### Added

- Add `Flop.reset_filters/1` and `Flop.reset_order/1`.
- Add `Flop.current_order/2` to retrieve the order of a given field.
- Add `Flop.to_next_page/2` and `Flop.to_previous_page/1`.
- Add `Flop.set_cursor/2`, `Flop.to_next_cursor/1` and
  `Flop.to_previous_cursor/1`.
- Add `Flop.set_offset/2`, `Flop.to_previous_offset/1`, `Flop.to_next_offset_2`
  and `Flop.reset_cursors/2`.
- Add `Flop.nest_filters/3` for converting filters between a key/value map and
  a list of `Flop.Filter` parameters.
- You can now set the `default_pagination_type` option, which forces a certain
  set of parameters when defaults are applied and the pagination type cannot
  be determined from the given parameters.
- Add optional `default` argument to `get_option`.
- Add `pagination` option. If set to `true`, pagination parameters are not cast.

### Changed

- `Flop.map_to_filter_params/2` returns maps with string keys if the original
  map has string keys now.
- The `has_previous_page?` value of the `Flop.Meta` struct is now always `true`
  if `first` is used with `after`. `has_next_page?` is always `true` when
  `last` is used with `before`.
- `push_order/2` resets the `:after` and `:before` parameters now, since the
  cursors depend on the order.
- `validate_and_run/3` and `validate_and_run!/3` pass all given options to
  the validate functions now, allowing you to override defaults set in the
  schema.
- If the `pagination_types` option is used, parameters for other pagination
  types will not be cast now instead of casting them and returning validation
  errors.

### Removed

- Remove `Flop.Cursor.get_cursor_from_map/2`. Use
  `Flop.Cursor.get_cursor_from_node/2` instead.

## [0.14.0] - 2021-11-08

### Added

- Add `:contains` operator.
- Add `Flop.map_to_filter_params/2`.

### Changed

- `Flop.validate/2` and `Flop.validate_and_run/3` return `{:error, Flop.Meta.t}`
  instead of `{:error, Ecto.Changeset.t}` now. The Meta struct has the new
  fields `:errors` and `:params`, which are set when validation errors occur.
  This accompanies the changes in `Flop.Phoenix`, which include the
  implementation of the `Phoenix.HTML.FormData` protocol for the `Flop.Meta`
  struct.
- `Flop.validate!/2` and `Flop.validate_and_run!/3` raise a
  `Flop.InvalidParamsError` instead of an `Ecto.InvalidChangesetError` now.
- Add `:schema` key to `Flop.Meta`. This field points to the schema module set
  by passing the `:for` option.
- Minimum Ecto version changed to 3.5.
- Replace `Operator` and `OrderDirection` custom Ecto types with Ecto.Enum.
- Update `Flop.Meta` struct default values for the fields `:flop`,
  `:has_next_page?` and `:has_previous_page?`.

## [0.13.2] - 2021-10-16

### Fixed

- Fix error when sorting by a compound field that consists of at least one
  join field.
- Fix import conflict when importing `Ecto.Changeset` in a module that derives
  `Flop.Schema` and configures a compound field.

## [0.13.1] - 2021-08-23

### Fixed

- Wrong type spec for cursor_dynamic/3 callback.

## [0.13.0] - 2021-08-22

### Added

- Support ordering by join fields.
- Support ordering by compound fields.
- Support join fields as cursor fields.
- New function `Flop.Schema.get_field/2`.
- `Flop.Cursor.get_cursor_from_edge/2` and `Flop.Cursor.get_cursor_from_node/2`
  can get cursor values from join and compound fields now.

### Changed

To get the pagination cursor value from a join field, Flop needs to know how
to access the field value from the returned struct or map. The configuration
format for join fields has been changed to allow specifying the path to the
nested field.

Before:

```elixir
@derive {
  Flop.Schema,
  join_fields: [
    owner_name: {:owner, :name}
  ]
}
```

After:

```elixir
@derive {
  Flop.Schema,
  join_fields: [
    owner_name: [binding: :owner, field: :name, path: [:owner, :name]]
  ]
}
```

The `:path` is optional and inferred from the `:binding` and `:field` options,
if omitted.

The old configuration format is still accepted. All of these settings are
equivalent:

```
[owner_name: {:owner, :name}]

[owner_name: [binding: :owner, field: :name]]

[owner_name: [binding: :owner, field: :name, path: [:owner, :name]]]
```

### Fixed

- Cursor pagination failed when one of the cursor field values was `nil`.

## [0.12.0] - 2021-08-11

### Added

- Allow to define join fields in `Flop.Schema`.
- Allow to define compound fields in `Flop.Schema`.
- Support filtering by join fields.
- Support filtering by compound fields.
- New filter operator `empty`.
- New filter operator `not_empty`.
- New function `Flop.set_page/2`.

### Changed

- Rename option `get_cursor_value_func` to `cursor_value_func`.
- Silently ignore filters with `nil` value for the field or the value instead of
  raising an `ArgumentError`.
- Allow passing a string as the second argument to `Flop.push_order/2`.

## [0.11.0] - 2021-06-13

### Added

- New functions `Flop.Cursor.get_cursor_from_node/2` and
  `Flop.Cursor.get_cursor_from_edge/2`.
- New function `Flop.get_option/2`.
- Support Ecto prefixes.

### Changed

- Use `Flop.Cursor.get_cursor_from_node/2` as default for the
  `:get_cursor_value_func` option.
- `Flop.Relay.edges_from_result/2` can now handle `nil` instead of a map as
  edge information in a query result.

### Deprecated

- Deprecate `Flop.Cursor.get_cursor_from_map/2`. Use
  `Flop.Cursor.get_cursor_from_node/2` instead.

## [0.10.0] - 2021-05-03

### Added

- Add function `Flop.push_order/2` for updating the `order_by` and
  `order_directions` values of a Flop struct.

## [0.9.1] - 2020-10-21

### Fixed

- Fixed type spec of `Flop.Schema.default_order/1`.

## [0.9.0] - 2020-10-16

### Added

- Add `like`, `like_and`, `like_or`, `ilike`, `ilike_and` and `ilike_or` filter
  operators.
- Add option to disable pagination types globally, for a schema or locally.
- Add options to disable ordering or filtering.
- Allow global configuration of `get_cursor_value_func`, `max_limit` and
  `default_limit`.
- Add `Flop.option` type, improve documentation of available options.
- Add `Flop.Cursor.decode!/1`.

### Changed

- Refactored the parameter validation. Default limits are now applied to all
  pagination types. Added validation for the `after` / `before` cursor values.
- `Flop.Cursor.decode/1` returns `:ok` tuple or `:error` now instead of raising
  an error if the cursor is invalid.
- `Flop.Cursor.decode/1` returns an error if the decoded cursor value is not a
  map with atom keys.
- Improved documentation.

## [0.8.4] - 2020-10-14

### Fixed

- Default limit was overriding `first` / `last` parameters when building query.

## [0.8.3] - 2020-10-14

### Fixed

- Cursor-based pagination: `has_next_page?` was set when querying with `last`
  based on `before` being set. Likewise, `has_previous_page?` was set when
  querying with `first` based on `after` being set. Both assumptions are wrong.
  In both cases, the values are always set to `false` now.

## [0.8.2] - 2020-10-08

### Changed

- Order directions are not restricted anymore for cursor-based pagination.

### Fixed

- Query for cursor-based pagination returned wrong results when using more than
  one cursor field.
- Query for cursor-based pagination returned wrong results when using
  `last`/`before`.

## [0.8.1] - 2020-10-07

### Changed

- Allow structs in cursor values.

## [0.8.0] - 2020-10-07

### Added

- Support for cursor-based pagination. Thanks to @bunker-inspector.
- Add functions to turn query results into Relay connection format when using
  cursor-based pagination.

## [0.7.1] - 2020-09-04

### Fixed

- Calculation of `has_next_page?` was wrong.

## [0.7.0] - 2020-08-04

### Added

- `Flop.Schema` now allows to set a default sort order.

### Changed

- Passing a limit without an offset will now set the offset to 0.
- Passing a page size without a page will now set the page to 1.

## [0.6.1] - 2020-06-17

### Changed

- Add Flop to Meta struct.

### Fixed

- Type `Flop.Filter.op` didn't include all operators.

## [0.6.0] - 2020-06-14

### Added

- New struct `Flop.Meta`.
- New function `Flop.all/3`.
- New function `Flop.count/3`.
- New function `Flop.meta/3`.
- New function `Flop.run/3`.
- New function `Flop.validate_and_run/3`.
- New function `Flop.validate_and_run!/3`.

## [0.5.0] - 2020-05-28

### Added

- New function `Flop.validate!/2`.
- New filter operator `:in`.

### Fixed

- Filter validation was using sortable fields instead of filterable fields.

## [0.4.0] - 2020-05-27

### Added

- Added `=~` filter operator.

### Fixed

- Query function wasn't generating valid where clauses for filters.

## [0.3.0] - 2020-05-22

### Added

- Added a `default_limit` option to `Flop.Schema`.

## [0.2.0] - 2020-05-20

### Added

- Added a `max_limit` option to `Flop.Schema`. When set, Flop validates that the
  `limit` and `page_size` parameters don't exceed the configured max limit.

## [0.1.0] - 2019-10-19

initial release
