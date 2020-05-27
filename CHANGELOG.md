# Changelog

## Unreleased

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
