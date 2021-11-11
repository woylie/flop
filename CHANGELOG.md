# Changelog

## Unreleased

### Added

- Add `Flop.reset_filters/1` and `Flop.reset_order/1`.
- Add `Flop.current_order/2` to retrieve the order of a given field.
- Add `Flop.to_next_page/2` and `Flop.to_previous_page/1`.
- Add `Flop.set_offset/2`, `Flop.to_previous_offset/1` and
  `Flop.to_next_offset_2`.
- Add `Flop.nest_filters/3` for converting filters between a key/value map and
  a list of `Flop.Filter` parameters.

### Changed

- `Flop.map_to_filter_params/2` returns maps with string keys if the original
  map has string keys now.

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
