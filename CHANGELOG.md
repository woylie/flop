# Changelog

## Unreleased

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
