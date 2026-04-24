# Move ValidationIssuesJsonMigration post-runApp with progress dialog and trigger-drop optimization

## Context

On an imported old database (~33 324 rows in `translation_versions.validation_issues` with legacy `Dart List.toString()` / `Map.toString()` shapes), the app startup freezes on a white window for minutes and is eventually killed (by the user or by a watchdog). Root cause:

1. `ValidationIssuesJsonMigration` (`lib/services/database/migrations/migration_validation_issues_json.dart`, priority 110) runs inside `MigrationService.ensurePerformanceIndexes()`, which is awaited by `ServiceLocator.initialize()` **before** `runApp()` in `lib/main.dart:56,86`. No UI is rendered during this time.
2. Each row-level `UPDATE translation_versions SET validation_issues = ?` cascades through three triggers:
   - `trg_translation_versions_fts_update` (`schema.sql:729-737`) — `DELETE` + `INSERT` in the contentless FTS5 index `translation_versions_fts`.
   - `trg_update_cache_on_version_change` (`schema.sql:791-803`) — writes `translation_view_cache`.
   - `trg_translation_versions_updated_at` (`schema.sql:877-882`) — `WHEN NEW.updated_at = OLD.updated_at` fires because the migration does not touch `updated_at`, causing a second self-UPDATE which re-fires the cache trigger.
3. The migration calls `SELECT id, validation_issues FROM translation_versions WHERE validation_issues IS NOT NULL` without `LIMIT` — loads all rows into RAM at once.
4. `_writeMarker()` is written only at the very end. Every kill/crash restarts from scratch; successive runs never converge.

The field is advisory (displayed as a validation hint list), so a temporary format downgrade is tolerable, but the migration must eventually run.

## Goals

- First frame rendered immediately on startup, regardless of how much data the migration must rewrite.
- Progress feedback throughout the migration (step name, counter, percent).
- Migration fast enough that a user will let it finish (target: seconds, not minutes).
- Atomic rollback in case of failure: triggers must always be restored.
- Idempotent — re-running after success is a no-op; re-running after an interrupt rewinds safely to the last known good state.

## Non-goals

- No change to how `validation_issues` is written by new code (`jsonEncode(result.allMessages)` stays).
- No change to the shape of migrated payloads (same `List<String>` JSON array as the current migration produces).
- No localization — strings stay in English, consistent with the existing `DataMigrationDialog`.
- No "Skip" button. The existing `Retry` button covers the error path.
- No resumability across restarts — transaction rollback + restart-from-zero is simple and acceptable given the expected runtime (seconds).

## Architecture

### Overview

```
ServiceLocator.initialize()            ← unchanged; validation_issues step removed from here
  └─ MigrationService.ensurePerformanceIndexes()
       └─ MigrationRegistry (27 migrations, no longer 28)

runApp()                                ← reached immediately after schema migrations
  └─ _AppStartupTasks post-frame callback
       └─ DataMigration.runMigrations()
            ├─ Step 1 (NEW) — ValidationIssuesJsonDataMigration
            ├─ Step 2 — TM rebuild          (existing)
            └─ Step 3 — TM hash migration    (existing)
```

### Components

**`lib/services/database/data_migrations/validation_issues_json_data_migration.dart`** — NEW service class. Extracts the rewrite logic from the old migration but:
- accepts a `void Function(int processed, int total)` progress callback
- uses the `_migration_markers` table (same id `validation_issues_json`, same shape)
- drops cascading triggers during the rewrite (inside a transaction)
- rebuilds the FTS5 index outside the transaction, **before** writing the marker
- paginates with keyset (`WHERE id > ? ORDER BY id LIMIT 500`) instead of loading all rows

**`lib/providers/data_migration_provider.dart`** — extended:
- `needsMigration()` returns `true` if `validation_issues_json` marker is missing (with the same fallback scan as the current migration) OR either existing SharedPreferences key is missing.
- `runMigrations()` runs the new step first, then TM rebuild, then TM hash migration.
- On progress, `state.progressMessage`, `currentProgress`, `totalProgress` are updated exactly like the existing steps.

**`lib/services/database/migrations/migration_registry.dart`** — `ValidationIssuesJsonMigration` entry removed.

**`lib/services/database/migrations/migration_validation_issues_json.dart`** — deleted (logic has moved into the new data-migration service).

**`lib/widgets/dialogs/data_migration_dialog.dart`** — unchanged. Already renders `state.currentStep` + `state.progressMessage` + progress bar + Retry button, which is what the new step needs.

### Data flow per run

1. `DataMigration.needsMigration()` → returns true because marker is missing.
2. `_AppStartupTasks._runDataMigrations()` opens `DataMigrationDialog` modally (barrier black87, non-dismissible).
3. Dialog's `initState` calls `DataMigration.runMigrations()`.
4. Step 1 runs `ValidationIssuesJsonDataMigration.execute(onProgress)`:
   - Open explicit transaction.
   - `DROP TRIGGER IF EXISTS` × 3 (fts_update, cache_on_version_change, versions_updated_at).
   - Count matching rows once to populate `totalProgress`.
   - Keyset loop: `SELECT id, validation_issues FROM translation_versions WHERE validation_issues IS NOT NULL AND TRIM(validation_issues) <> '' AND id > ? ORDER BY id LIMIT 500`. Per row: `_isAlreadyJson` → skip, else `_parseDartListToString` → `UPDATE … SET validation_issues = ?` on same row id. Call `onProgress(processed, total)` after each batch.
   - Recreate the 3 triggers using DDL constants (copied verbatim from `schema.sql`).
   - Commit transaction.
   - `INSERT INTO translation_versions_fts(translation_versions_fts) VALUES('rebuild')` — **outside** the transaction.
   - `INSERT OR REPLACE INTO _migration_markers(id, applied_at) VALUES('validation_issues_json', now)`.
5. Step 2 (TM rebuild) and Step 3 (TM hash migration) proceed unchanged.
6. Dialog auto-closes on `state.isComplete == true`.

### State machine: how failure modes are handled

| Failure point | State after failure | Recovery on next start |
|---|---|---|
| Before DROP TRIGGER | No change to DB | Dialog shows again, full run |
| During the UPDATE loop | Transaction rolls back, triggers still defined | Dialog shows again, full run |
| During CREATE TRIGGER at end | Transaction rolls back, triggers still defined | Dialog shows again, full run |
| Process killed after COMMIT, before FTS rebuild | Triggers recreated. FTS contains stale entries for rewritten rows. Marker **not** written. | Dialog shows again. Loop runs: rewrites are idempotent (already-JSON rows are skipped). FTS rebuild re-runs and reconciles. |
| Process killed during FTS rebuild | Marker **not** written. FTS may be partial. | Same as above — FTS rebuild re-runs. |
| FTS rebuild throws (caught) | Exception logged at warning, swallowed. Marker written anyway. FTS left partial/stale; will resync lazily through normal write triggers or a future forced rebuild. | `needsMigration()` returns false; app is usable. Search results may omit rewritten rows until FTS catches up. |
| After marker insert | Success. | `needsMigration()` returns false. |

**Key invariants:**
- The marker is the last write in the run.
- Everything upstream of the marker is idempotent.
- A thrown exception from the rewrite transaction aborts the run (no marker). A thrown exception from the FTS rebuild is caught and does not abort the run (marker still written).

### Why drop triggers inside the transaction

SQLite allows DDL in transactions, and they rollback atomically. If the rewrite loop fails, the triggers are restored automatically by the rollback — no `try/finally` needed in Dart. Stored DDL constants for recreation are only used on the success path.

### Why rebuild FTS outside the transaction

- `INSERT INTO fts(fts) VALUES('rebuild')` on a contentless FTS5 table re-scans the source table and rewrites the entire FTS index. On 33k rows it is I/O-heavy (several seconds).
- Holding this inside the write transaction would block any other DB reader on the same file for that duration.
- Interruption cost is low: the rebuild is fully idempotent, and the marker sits downstream. Worst case the user sees the dialog again and the rebuild re-runs.

### Why keyset instead of OFFSET

- `OFFSET N` on a 33k-row scan does N row walks each time → O(N²) total.
- Keyset on `id` (primary key) is O(N) total and is friendly to keep in cache.
- Since the rewrite only updates the `validation_issues` column, keyset ordering on `id` is stable across batches (the id of the last row in batch N is the cursor for batch N+1).

## Error handling

- Transaction errors bubble up through `Future.onError` inside `DataMigration.runMigrations()`, which already catches and sets `state.error`. The existing Retry button in `DataMigrationDialog` re-invokes `runMigrations()`.
- Row-level parse failures inside the loop (unrecognisable payload) are logged at `warning` and the row is left as-is. This matches the current migration's behavior.
- FTS rebuild errors are caught, logged at `warning`, and ignored (the marker is still written). FTS will resync lazily. This matches the current `_rebuildFtsIndex()` pattern in `migration_fix_escaped_newlines.dart`.

## Testing

Unit tests in `test/services/database/data_migrations/validation_issues_json_data_migration_test.dart`:

1. **Legacy shapes**: seed rows with `[msg1]`, `[msg1, msg2]`, `[{type: ValidationIssueType.x, severity: ..., autoFixable: false, autoFixValue: null}]`, empty `[]`, already-JSON `["msg"]`, `[{"type":"x"}]`. Run migration. Assert every row is a valid JSON array after.
2. **Idempotence**: run twice. Second run processes zero rewrites.
3. **Marker persisted**: after a successful run, `_migration_markers` has the row with id `validation_issues_json`.
4. **Trigger restoration on throw**: inject a failure mid-loop (e.g. by passing a callback that throws on the second batch). Verify the three triggers exist after, verify no marker written, verify `validation_issues` values are untouched.
5. **FTS rebuild failure is non-fatal**: mock FTS rebuild to throw. Verify the marker is still written and the error is logged at warning.
6. **Progress callback**: verify `onProgress(processed, total)` is called after every batch with monotonically increasing `processed` and stable `total`.

Manual validation:
- Run on the imported old DB. Dialog should appear within 1–2 seconds of app launch, validation_issues step should complete in under 10 s (expected; tune if observed otherwise), TM rebuild and hash migration proceed normally after.
- Restart the app — dialog should not reappear.

## Migration / rollout

- Databases that have never run the old migration: the new step runs as described. Same marker row gets written.
- Databases that already ran the old migration: the marker exists → the new step's `isApplied()` fast-paths to `return true`. No work.
- Databases that had an aborted old migration (marker missing but some rows already JSON): the fallback `LIMIT 1` legacy-shape probe runs. If none found, marker is written and we skip. If found, the loop runs; already-JSON rows are skipped by `_isAlreadyJson`.
- Fresh installs: no rows match → migration writes the marker immediately (via the same early-return path).

## Open deletions

- `lib/services/database/migrations/migration_validation_issues_json.dart` — deleted.
- Import and registry entry in `lib/services/database/migrations/migration_registry.dart` — removed.

## Out of scope

- Applying the same triggers-drop pattern to `FixEscapedNewlinesMigration`, `FixBackslashNewlinesMigration`, or `FixCacheTriggersMigration`. They have the same class of problem but are cheaper in practice (and already post-startup-safe since they log `0 translations` on the current DB). Can be revisited if another DB exhibits a freeze.
- Removing the `_logger.debug` sample of "row contained `, `" — kept at its current 5-sample cap for diagnostics.
- Introducing an abstraction for "data migrations with progress". Only three exist; premature.
