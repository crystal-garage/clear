# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added expression `after?` and `before?` predicates for readable greater-than and less-than comparisons between SQL expressions or literal values.
- `JSON::Any` model columns now accept JSON-serializable Crystal collections such as hashes, arrays, and named tuples.
- Added `Model#modified?` for checking whether a new or changed model requires database persistence.
- Added a typed `Collection#sum` overload for returning PostgreSQL aggregate results in an explicitly requested Crystal type.
- Added `Model.insert` and `Model.insert_all` for PostgreSQL inserts with duplicate skipping, affected-row counts, and typed `RETURNING` results.
- Added `Model.upsert` and `Model.upsert_all` for PostgreSQL `ON CONFLICT` inserts, with affected-row counts, typed `RETURNING` results, and `on_duplicate: :update` or `:skip`.
- Added custom `Model.upsert` and `Model.upsert_all` conflict updates with `Lustra::SQL.unsafe`.
- Added PostgreSQL `RETURNING` support to bulk updates and deletes, including typed results from `Collection#update_all` and `Collection#delete_all`.
- Added `where.associated(:association)` and `where.missing(:association)` relation filters for querying records with or without associated rows.
- Added `with_count(:association)` for selecting related record counts without loading the associated records.
- Added polymorphic `has_many ..., as:` associations backed by `<name>_id` and `<name>_type` columns.
- Added polymorphic `belongs_to ..., polymorphic: true` associations for explicit union target types, including `with_<association>` eager loading.
- Added concrete `belongs_to ..., polymorphic_type:` aliases for joining and eager loading one polymorphic target type through a shared foreign key.

### Deprecated
- Deprecated expression `between(a, b)` in favor of the predicate-style `between?(a, b)`.

### Changed
- `Collection#to_a` now avoids allocating and copying an intermediate model array.
- SQL query errors now include the original exception type in their message, including when the original exception has no message.
- `Collection#delete_all` now returns the number of affected rows instead of the collection.
- Unknown association errors now include available association names and operation-specific correction guidance.
- Read-only model save errors now explain that read-only models commonly map database views or system catalogs.
- Association append and unlink errors now explain that the operation requires a writable association collection.
- Missing primary key errors now retain essential setup guidance in release builds.

### Fixed
- Model lifecycle transactions now use the model's connection, so callback failures roll back creates, updates, and destroys on named connections.
- `belongs_to` associations using both `counter_cache` and `touch: true` now combine their parent counter and timestamp changes into one atomic `UPDATE` when a child is created.
- Appending a persisted record to a direct `has_many` association now persists the changed foreign key.
- Creating a record through a direct `has_many` association no longer performs a redundant second save or opens an empty transaction.
- Collection-based `build`, `create`, and `create!` now pass non-SQL attribute values through model converters, including Crystal collections assigned to `JSON::Any` columns.
- `Collection#find_or_create` no longer saves or re-appends an unchanged existing record after finding it, avoiding empty transactions and redundant association queries.
- `Collection#ids` now preserves computed selections required by ordering and pagination.
- Eager loading now preserves computed aliases, filters, ordering, limits, and offsets while keeping association key subqueries single-column.
- Transactions and savepoints now execute `BEGIN`, `COMMIT`, and `ROLLBACK` on the selected named connection.
- Cursor fetching, bulk updates and deletes, wrapped aggregates, existence checks, counter caches, and increment reloads now preserve the model or query connection.
- `Collection#first` and `Collection#last` now restore the collection's ordering and limit after fetching while preserving eager-loading constraints.
- Collection index and range accessors now restore their offset and limit after fetching while preserving eager-loading constraints.
- Collection finders now restore filters and model-building attributes after fetching while preserving eager-loading constraints.
- Low-level `fetch_first` and `first` queries now restore their original limit after fetching.
- Counter updates now use escaped query expressions, support string primary keys safely, and reject nonnumeric increment and decrement amounts.
- `Collection#create!` now raises `Lustra::Model::InvalidError` for invalid NamedTuple input, matching its keyword-argument overload.
- Non-persisting `increment` and `decrement` now use the model's current in-memory value without querying the database.
- Zero-argument `Lustra::SQL.insert` now supports fluent query construction with `into`.

### Maintenance
- Deduplicated internal condition-node construction for `where`, `not`, `or`, and `having` queries without changing generated SQL.
- Deduplicated internal OR-clause grouping for `where` and `having` queries without changing generated SQL.
- Deduplicated internal row handling for `InsertQuery#values` without changing accepted inputs or generated SQL.
- Deduplicated model construction between normal collection iteration and cursor iteration.
- Deduplicated the internal direct column-update workflow without changing public overloads or persistence behavior.

### Removed
- Removed the unused internal `Lustra::Expression::Node::NotBetween` node; negate `between?` expressions with `not(...)`.
- Removed deprecated condition-based `Collection#find` and `Collection#find!` overloads; use `find_by` and `find_by!` instead.

## [v0.18.3] - 2026-06-11

### Fixed
- `pluck` and `pluck_col` no longer mutate the collection query or run eager-loading hooks.

## [v0.18.2] - 2026-06-10

### Fixed
- `Collection#any?` and `Collection#empty?` no longer mutate the collection query or run eager-loading hooks while checking for matching rows.

## [v0.18.1] - 2026-06-09

### Maintenance
- Maintenance release without new features.

## [v0.17.2] - 2026-05-08

### Added
- Collections/Queries: `in_order_of(column, values)` for custom-sequence ordering via a SQL `CASE` expression (e.g. `Post.query.in_order_of(:status, ["started", "enrolled", "completed"])`).

### Fixed
- SQL: `SelectQuery#to_a` now consumes and closes result sets inside the active connection checkout.

## [v0.17.1] - 2026-03-06

### Fixed
- `Lustra::SQL::ConnectionPool#with_connection`: when a fiber-cached connection raises `DB::ConnectionLost`, clear the cached connection before retrying so retries can acquire a fresh connection.

## [v0.17.0] - 2026-02-19

### Fixed
- `Lustra::SQL::ConnectionPool#with_connection`: use `DB::Database#retry`.

## [v0.16.3] - 2026-02-18
### Maintenance
- Internal improvements and optimizations


## [v0.16.2] - 2026-02-16

### Added
- Expression: added `true?` and `false?` predicate helpers for boolean expression nodes.

## [v0.16.1] - 2026-02-16

### Added
- Expression: Added `null?` predicate to the expression engine as syntactic sugar for `== nil` (e.g. `where { deleted_at.null? }` renders as `deleted_at IS NULL`).

## [v0.16.0] - 2026-01-16

### Added
- Migrations: `change_column_null` operation to toggle NULL constraints with optional default backfill.
- Migrations: `add_index` helper supports `using` (e.g., `gin`, `gist`, `btree`) for index type selection.
- Column comments: `add_column(..., comment: String?)` emits `COMMENT ON COLUMN` on creation.
- Column comments: `change_column_comment(table, column, to : String?)` and `change_column_comment(table, column, changes : NamedTuple(from: String?, to: String?))` for reversible comment changes.
- Models: `schema_description` to query table columns and indexes programmatically.
- Migrations: `change_column_default(table, column, default_or_changes)` to set, drop, or make column default changes reversible.
- Collections: `Collection.none` added; `Model.none`/`Model.find`/`Model.find_by` now reuse collection implementations to reduce duplication.
- Tests: additional specs covering collection helper methods and schema introspection.

### Deprecated
- Passing a NamedTuple and block to `find` is deprecated; prefer `find_by` or `Model.find(ids)` for ID arrays.

## [v0.15.0] - 2026-01-10

### Added
- `has_one` eager loading with `with_<relation>` now caches results and avoids N+1 queries

### Fixed
- `has_one` now works with target models that do not define a primary key.

## [v0.14.4] - 2026-01-06

### Fixed
- Aggregate functions (`sum`, `min`, `max`, `avg`, `agg`) now properly handle LIMIT and OFFSET by wrapping queries in subqueries, preventing invalid SQL generation.

## [v0.14.3] - 2026-01-06

### Fixed
- `limit` and `offset` methods now accept concrete integer types (`Int32 | Int64 | Nil`) instead of abstract `Int?` which caused compiler errors.

## [v0.14.2] - 2026-01-06

### Added
- `Model.none` returns an empty, chainable relation.

## [v0.14.1] - 2026-01-06

### Fixed
- Aggregate functions (`sum`, `min`, `max`, `avg`, `agg`) now correctly clear ORDER BY clauses to prevent meaningless SQL.

## [v0.14.0] - 2026-01-05

### Added
- **Range Support in WHERE/HAVING Clauses** - Full support for all Crystal range types with any comparable type (Int, Time, etc.):
  - Normal ranges: `where { age.in?(18..65) }` -> `BETWEEN 18 AND 65`
  - Exclusive ranges: `where { age.in?(18...65) }` -> `>= 18 AND < 65`
  - Endless ranges: `where { age.in?(18..) }` -> `>= 18`
  - Beginless ranges: `where { age.in?(..65) }` -> `<= 65`
  - Beginless exclusive: `where { age.in?(...65) }` -> `< 65`
  - Full range: `where { age.in?(...) }` -> `TRUE` (matches all values)
  - Works with Time ranges: `where { created_at.in?(start_time..end_time) }`
  - `between()` method also supports Time values: `where { created_at.between(start_time, end_time) }`

### Fixed
- `belongs_to` now correctly supports optional relations (`User?`) by making the foreign key nilable and skipping presence validation.

## [v0.13.0] - 2025-11-14
### Added
- **PostgreSQL Geometric Types** - Comprehensive support for all PostgreSQL geometric data types:
  - Point, Circle, Polygon, Box, Line, Path, LineSegment support through crystal-pg
  - Expression engine with natural syntax for spatial queries
  - Distance, containment, overlap, intersection, and positioning operations

## [v0.12.0] - 2025-10-13
### Added
- `update_all` - Bulk updates without loading models (bypasses validations and callbacks)
- `find_by` / `find_by!` - Convenient finder methods for ActiveRecord-style querying
- `find([ids])` - Multiple ID lookup with array of IDs
- `increment!` / `decrement!` - Atomic counter updates for thread-safe operations
- `update_column` / `update_columns` - Direct column updates without validations/callbacks
- `touch` - Update timestamps without running validations/callbacks
- `destroy` / `destroy_all` - Rails-compatible deletion with callbacks
- `default_scope` - Automatically apply filters to all queries (soft deletes, multi-tenancy)
- `query.unscoped` - Bypass default_scope when needed
- Attribute change tracking - `column.change`, `changes`, `changed` for auditing
- `ids` - Convenient shortcut for getting array of primary keys
- `explain` / `explain_analyze` - PostgreSQL query performance analysis

### Changed
- **BREAKING:** `delete` now skips callbacks (fast deletion)
- **BREAKING:** `destroy` triggers callbacks (safe deletion)
- **BREAKING:** Callback event renamed: `:delete` -> `:destroy`
- Use `before(:destroy)` and `after(:destroy)` instead of `before(:delete)` and `after(:delete)`

### Dedication
- In memory of cat Sviatoslav (26.04.2023 - 13.10.2025) 💔😿

## [v0.11.0] - 2025-10-09
### Changed
- **BREAKING:** `or_where` -> `where.or` - Improved chaining syntax for OR conditions
- More consistent query builder API

## [v0.10.1] - 2025-10-09
### Fixed
- Fix model without primary_key support
- Improved handling of models that don't have primary keys defined

## [v0.10.0] - 2025-10-08
### Added
- Handle `append_operation` for has_many through relationships
- Prevent duplicate associations in relationships
- Join a relation using association name (auto-joins)
- Autosave functionality for associated models

### Improved
- Better association handling and relationship management
- Enhanced join operations with automatic detection

## [v0.9.0] - 2025-10-06
### Added
- Test callbacks implementation
- Counter cache functionality for associations
- Improved supported features documentation

### Changed
- **BREAKING:** Clear -> Lustra - Complete rebranding from Clear to Lustra
- Removed Kemal CLI generator (no longer supported)
- Enhanced join SQL construction with better specs

### Improved
- Better callback system with comprehensive testing
- Enhanced association features

## [v0.8.24] - 2025-09-26
### Added
- Touch functionality for belongs_to associations
- Automatic timestamp updates when parent records change

## [v0.8.23] - 2025-06-09
### Maintenance
- Internal improvements and optimizations

## [v0.8.22] - 2025-06-09
### Maintenance
- Internal improvements and optimizations

## [v0.8.21] - 2025-01-13
### Maintenance
- Internal improvements and optimizations

### Fixed
- Fix `Collection#each` method functionality

## [v0.8.20] - 2024-11-05
### Dependencies
- Use crystal-pg 0.29.0
- Use `::sleep(Time::Span)` instead of deprecated sleep methods

## [v0.8.19] - 2024-04-18
### Fixed
- Fix nested module support
- Better handling of nested Crystal modules

## [v0.8.18] - 2024-01-12
### Maintenance
- Internal improvements and optimizations

## [v0.8.17] - 2023-06-25
### Dependencies
- Use crystal-pg 0.27.0

## [v0.8.16] - 2023-06-25
### Fixed
- Fix specs implementation
- Fix migrations functionality

## [v0.8.15] - 2022-11-28
### Added
- Add `Collection#find` with parameters
- Enhanced collection querying capabilities

## [v0.8.14] - 2022-11-27
### Maintenance
- Internal improvements

## [v0.8.13] - 2022-11-12
### Code Quality
- Avoid using `not_nil!` for better null safety
- Add comprehensive specs
- Refactoring - major code improvements
- Refactor relations system

## [v0.8.12] - 2022-11-08
### Maintenance
- Version bump and internal improvements

## [v0.8.11] - 2022-10-10
### Maintenance
- Internal improvements and optimizations

## [v0.8.10] - 2022-06-21
### Maintenance
- Internal improvements and optimizations

## [v0.8.9] - 2022-01-27
### Dependencies
- Bump PostgreSQL dependency version

## [v0.8.8] - 2022-01-07
### Added
- Support Crystal 1.3 compatibility
- Updated for latest Crystal language features

## [v0.8.7] - 2021-10-14
### Maintenance
- Internal improvements and optimizations

## [v0.8.6] - 2021-09-09
### Maintenance
- Internal improvements and optimizations

## [v0.8.5] - 2021-07-18
### Maintenance
- Internal improvements and optimizations

## [v0.8.4] - 2021-06-28
### Maintenance
- Internal improvements and optimizations

## [v0.8.2] - 2021-03-23
### Maintenance
- Internal improvements and optimizations

## [v0.8.1] - 2021-02-16 - "Fork"
### Added
- Initial fork from Clear ORM
- GitHub workflow implementation
- CI/CD pipeline setup
- PostgreSQL client integration

### Infrastructure
- Add GitHub Actions workflow
- Code formatting standards
- Database connection setup
- Remove Travis CI configuration
- Initial project cleanup

### Notes
- This marks the beginning of Lustra as an independent project, forked from Clear v0.8
- Established foundation for future development and Crystal compatibility

---

## Release Links

- [v0.17.1](https://github.com/crystal-garage/lustra/releases/tag/v0.17.2)
- [v0.17.1](https://github.com/crystal-garage/lustra/releases/tag/v0.17.1)
- [v0.17.0](https://github.com/crystal-garage/lustra/releases/tag/v0.17.0)
- [v0.16.3](https://github.com/crystal-garage/lustra/releases/tag/v0.16.3)
- [v0.16.2](https://github.com/crystal-garage/lustra/releases/tag/v0.16.2)
- [v0.16.1](https://github.com/crystal-garage/lustra/releases/tag/v0.16.1)
- [v0.16.0](https://github.com/crystal-garage/lustra/releases/tag/v0.16.0)
- [v0.15.0](https://github.com/crystal-garage/lustra/releases/tag/v0.15.0)
- [v0.14.4](https://github.com/crystal-garage/lustra/releases/tag/v0.14.4)
- [v0.14.3](https://github.com/crystal-garage/lustra/releases/tag/v0.14.3)
- [v0.14.2](https://github.com/crystal-garage/lustra/releases/tag/v0.14.2)
- [v0.14.1](https://github.com/crystal-garage/lustra/releases/tag/v0.14.1)
- [v0.14.0](https://github.com/crystal-garage/lustra/releases/tag/v0.14.0)
- [v0.13.0](https://github.com/crystal-garage/lustra/releases/tag/v0.13.0)
- [v0.12.0](https://github.com/crystal-garage/lustra/releases/tag/v0.12.0)
- [v0.11.0](https://github.com/crystal-garage/lustra/releases/tag/v0.11.0)
- [v0.10.1](https://github.com/crystal-garage/lustra/releases/tag/v0.10.1)
- [v0.10.0](https://github.com/crystal-garage/lustra/releases/tag/v0.10.0)
- [v0.9.0](https://github.com/crystal-garage/lustra/releases/tag/v0.9.0)
- [v0.8.24](https://github.com/crystal-garage/lustra/releases/tag/v0.8.24)
- [v0.8.23](https://github.com/crystal-garage/lustra/releases/tag/v0.8.23)
- [v0.8.22](https://github.com/crystal-garage/lustra/releases/tag/v0.8.22)
- [v0.8.21](https://github.com/crystal-garage/lustra/releases/tag/v0.8.21)
- [v0.8.20](https://github.com/crystal-garage/lustra/releases/tag/v0.8.20)
- [v0.8.19](https://github.com/crystal-garage/lustra/releases/tag/v0.8.19)
- [v0.8.18](https://github.com/crystal-garage/lustra/releases/tag/v0.8.18)
- [v0.8.17](https://github.com/crystal-garage/lustra/releases/tag/v0.8.17)
- [v0.8.16](https://github.com/crystal-garage/lustra/releases/tag/v0.8.16)
- [v0.8.15](https://github.com/crystal-garage/lustra/releases/tag/v0.8.15)
- [v0.8.14](https://github.com/crystal-garage/lustra/releases/tag/v0.8.14)
- [v0.8.13](https://github.com/crystal-garage/lustra/releases/tag/v0.8.13)
- [v0.8.12](https://github.com/crystal-garage/lustra/releases/tag/v0.8.12)
- [v0.8.11](https://github.com/crystal-garage/lustra/releases/tag/v0.8.11)
- [v0.8.10](https://github.com/crystal-garage/lustra/releases/tag/v0.8.10)
- [v0.8.9](https://github.com/crystal-garage/lustra/releases/tag/v0.8.9)
- [v0.8.8](https://github.com/crystal-garage/lustra/releases/tag/v0.8.8)
- [v0.8.7](https://github.com/crystal-garage/lustra/releases/tag/v0.8.7)
- [v0.8.6](https://github.com/crystal-garage/lustra/releases/tag/v0.8.6)
- [v0.8.5](https://github.com/crystal-garage/lustra/releases/tag/v0.8.5)
- [v0.8.4](https://github.com/crystal-garage/lustra/releases/tag/v0.8.4)
- [v0.8.2](https://github.com/crystal-garage/lustra/releases/tag/v0.8.2)
- [v0.8.1](https://github.com/crystal-garage/lustra/releases/tag/v0.8.1)
