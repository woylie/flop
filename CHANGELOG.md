# Changelog

## Unreleased

### Added

- Allow restricting pagination types globally, for a schema or by passing an
  option.
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
