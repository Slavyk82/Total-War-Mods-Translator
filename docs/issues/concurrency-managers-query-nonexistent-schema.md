# Concurrency managers query tables/columns that don't exist in the shipped schema

**Labels:** bug, services/concurrency, dead-code

## Summary

The `lib/services/concurrency/` managers were wired up (instantiated in
`core_service_locator.dart`, `translation_service_locator.dart`,
`translation_orchestrator_impl.dart`, `tm_lookup_handler.dart`) but several of
their queries target **tables and columns that exist in no `schema.sql` block
and no migration**. Every affected call hits a `DatabaseException`, is caught,
and returns `Err(...)`. The feature therefore silently no-ops in production.

This was surfaced while adding unit-test coverage for the concurrency layer
(tests now assert the broken paths return `Err`, and exercise the happy paths
against reverse-engineered tables created in `setUp`).

## 1. Phantom tables (created nowhere)

These tables are referenced by manager SQL but have no `CREATE TABLE` anywhere
in the codebase (not in `lib/database/schema.sql`, not in
`lib/services/database/migrations/`, not self-created by the managers):

| Table | Used by |
|---|---|
| `entry_locks` | `pessimistic_lock_manager.dart` (acquire/release/renew/break/getOwnerLocks/cleanup) |
| `conflict_resolutions` | `conflict_resolver.dart` (`_storeResolution`, `getConflictHistory`, `getConflictStatistics`) |
| `batch_entry_reservations` | `batch_isolation_manager.dart` (reserve/release/getAvailable/extend/cleanup/stats) |

Every method on `PessimisticLockManager` and `BatchIsolationManager`, plus the
persistence/history/stats methods of `ConflictResolver`, fail with
`no such table` → `Err`.

## 2. Wrong columns against real tables

### `OptimisticLockManager.getVersionHistory` (`optimistic_lock_manager.dart:~443`)

```dart
await _db.query(
  'translation_version_history',
  where: 'translation_version_id = ?',   // column does not exist
  whereArgs: [recordId],
  orderBy: 'version DESC',               // column does not exist
);
```

Actual `translation_version_history` columns (schema.sql):
`id, version_id, translated_text, status, changed_by, change_reason, created_at`.
There is **no `translation_version_id`** (it's `version_id`) and **no `version`**
column → always throws → `Err(GET_HISTORY_FAILED)`.

### `ConflictResolver.checkForConflicts` (`conflict_resolver.dart:~412`)

```dart
await _db.query(
  'translation_versions',
  columns: ['version', 'translated_text', 'updated_by', 'updated_at'], // version + updated_by don't exist
  ...
);
```

Actual `translation_versions` columns (schema.sql):
`id, unit_id, project_language_id, translated_text, is_manually_edited, status,
translation_source, validation_issues, created_at, updated_at`.
There is **no `version`** and **no `updated_by`** column → always throws →
`Err(CONFLICT_CHECK_FAILED)`.

## Impact

- Optimistic and pessimistic locking, conflict detection/resolution, and batch
  entry isolation are effectively **inert** — callers get `Err` and fall back to
  the unlocked / no-conflict path. This matches the existing note in
  `event_bus.dart` that event persistence is "disabled due to transaction
  conflicts."
- No data corruption observed (the managers fail closed / are best-effort), but
  the concurrency guarantees they advertise are not actually in force.

## Suggested resolution (pick one)

1. **Make it real:** add migrations creating `entry_locks`,
   `conflict_resolutions`, `batch_entry_reservations`, and fix the two column
   mismatches (`translation_version_id`→`version_id`, and add/replace the
   `version`/`updated_by` references with real columns). The new unit tests
   already encode the expected table shapes.
2. **Remove the dead code:** if the concurrency feature isn't needed, delete the
   managers and their wiring to avoid the false impression of active locking.

## Tests

Coverage added in `test/unit/services/concurrency/` documents both the broken
paths (asserting `Err`) and the intended behavior (happy paths run against the
reverse-engineered tables). See the `*_test.dart` files for the inferred schemas.
