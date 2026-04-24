# TM Bulk Apply Optimization — Design

**Date:** 2026-04-24
**Status:** Approved for planning
**Scope:** Performance optimization of the Translation Memory apply phase during batch translation.

## Problem

When translating a batch with many Translation Memory matches (observed: 10 000+ matches), the phase "Checking Translation Memory (Exact) — Applying 15 exact TM matches..." becomes extremely slow. A screenshot taken mid-run showed 33 seconds elapsed with progress still far from complete. Extrapolated, 10 000 matches takes several minutes.

### Root causes

Analysis of `lib/services/translation/handlers/tm_lookup_handler.dart` and `lib/repositories/mixins/translation_version_batch_mixin.dart` identified four compounding bottlenecks:

1. **Per-row SELECT before every upsert.** `upsertWithTransaction()` performs one `SELECT id FROM translation_versions WHERE unit_id = ? AND project_language_id = ?` per match (≈20 000 serial DB ops for 10 000 matches).
2. **Triggers fire per row.** `trg_update_project_language_progress` runs a full `COUNT(*)` aggregation on `translation_versions JOIN translation_units` on every UPDATE — O(N²) over the phase. `trg_translation_versions_fts_update` and `trg_update_cache_on_version_change` also fire per row.
3. **667 mini-transactions.** Chunks of 15 → 667 SQLite commits (each with fsync under WAL+NORMAL) for 10 000 matches.
4. **History recorded one-by-one after transaction.** `_historyService.recordChange()` is called serially for every applied match.

### Existing precedent

`TranslationVersionBatchMixin.importBatch()` (same file, lines 211‑424) already implements the correct pattern for bulk writes: drop triggers, single transaction with `txn.batch()` in chunks of 500, rebuild FTS / cache / progress via set-based SQL at the end, re-create triggers in `finally`. The TM apply path predates this pattern and does not use it.

## Goal

Bring the TM apply time for 10 000 matches from minutes to the low-single-digit-seconds range, with the same correctness and safety guarantees. Both the exact and fuzzy auto-accept paths must benefit, since they share `_applyTmMatchesBatch()`.

## Non-goals

- Changing the TM lookup algorithm itself (hash / FTS5 strategy is fine).
- Changing auto-accept thresholds.
- Moving translation work to a background isolate. (Separate concern, not needed to hit the target.)
- Optimizing other batch translation phases (AI, validation) — not part of the reported slowdown.
- Changing cancellation granularity during lookup (already at chunk boundary, stays that way).

## Architecture

Switch from the current *"lookup chunk → apply chunk"* model to a *"collect all → bulk apply"* model, **per match type**.

For each phase (exact, then fuzzy):

- **Phase A — Lookup.** Parallel TM reads in chunks (size increased from 15 to 50). Matches are accumulated into a `List<_PendingTmMatch>` in memory. Pause/cancel is checked between chunks.
- **Phase B — Bulk apply.** One optimized bulk write for all matches collected in the phase. Uses the `importBatch` pattern (drop triggers, one transaction, batched SQL operations, rebuild indexes once at the end).

### Trade-offs explicitly accepted

| Concern | Decision |
|---|---|
| Atomicity on apply failure | The whole phase rolls back (0 matches saved). Acceptable because the apply itself is fast (~1–2 s target). User can re-run. |
| Pause/cancel during apply | Not possible — apply is a single transaction. Acceptable because the apply is the fast part; responsiveness stays at chunk boundary during lookup. |
| Memory (10 000+ `_PendingTmMatch`) | Negligible in Dart. No concern. |
| Trigger drop/recreate in one phase | Wrapped in `try/finally`, same pattern as `importBatch`. No new risk. |

## Components

### 1. `TranslationVersionBatchMixin.upsertBatchOptimized` (new)

New method in `lib/repositories/mixins/translation_version_batch_mixin.dart`, modeled on `importBatch` but self-contained for the TM flow (callers do not provide existence maps).

Signature:

```dart
Future<Result<({int inserted, int updated, List<String> effectiveVersionIds}), TWMTDatabaseException>>
    upsertBatchOptimized({
  required List<TranslationVersion> entities,
  void Function(int current, int total, String message)? onProgress,
});
```

`effectiveVersionIds[i]` is the real persisted id of `entities[i]` — the entity's own `id` when inserted, or the pre-existing row's id when updated. Callers need this because they can't know ahead of time which path each entity takes. Fixes a latent defect in the current `_applyTmMatchesBatch`, which records history against the generated id even when the row was actually updated (real id is the existing one).

Algorithm (single outer `executeTransaction`):

1. **Batch existence query.** Build `(unit_id, project_language_id)` pairs, issue one `SELECT id, unit_id, project_language_id, created_at FROM translation_versions WHERE unit_id IN (…) AND project_language_id IN (…)`. Materialize into a lookup map keyed by `"$unitId:$projectLanguageId"`.
2. **Trigger strategy.** If `entities.length > 50`, drop `trg_update_project_language_progress`, `trg_translation_versions_fts_update`, `trg_update_cache_on_version_change`. Mirrors `importBatch` threshold.
3. **Batched writes.** Iterate `entities` in chunks of 500; for each chunk call `txn.batch()`, issue `update` (existing) or `insert` (new) per entity, `commit(noResult: true)` at chunk boundary. All chunks share the outer transaction.
4. **Rebuild indexes (if triggers were dropped).** Issue the same bulk SQL that `importBatch` does:
   - `DELETE FROM translation_versions_fts WHERE version_id IN (SELECT id …)` per 500-unit chunk.
   - `INSERT INTO translation_versions_fts(…) SELECT … WHERE tv.unit_id IN (…) AND tv.project_language_id = ?` per 500-unit chunk.
   - `UPDATE translation_view_cache SET … FROM translation_versions tv WHERE …` per 500-unit chunk.
   - Single `UPDATE project_languages SET progress_percent = (…)` recalculation at the end.
5. **Recreate triggers** in `finally` with the exact DDL already in `importBatch`.

Important: the `project_language_id` rebuild SQL assumes all entities share the same `projectLanguageId`. In the TM flow this is always true (one TranslationContext per batch). Assert this precondition at the top of the method.

### 2. `TmLookupHandler._applyTmMatchesBatch` (refactor)

`lib/services/translation/handlers/tm_lookup_handler.dart`.

- Replace the inner `for (final pending in matches) { await _versionRepository.upsertWithTransaction(txn, version); }` loop with a single `await _versionRepository.upsertBatchOptimized(entities: versions, onProgress: ...)`.
- Build the history entries list from the pairing of input matches and `effectiveVersionIds` returned by `upsertBatchOptimized`, so each history row references the real persisted version id (see note on the repository method above). Single call to `recordChangesBatch`.
- Keep `entryUsageCounts` accumulation unchanged.

### 3. `TmLookupHandler.performLookup` (refactor)

Same file. Change the shape of the exact phase:

- Keep the lookup chunk loop (reads in parallel), but **do not call `_applyTmMatchesBatch` per chunk**. Instead accumulate into `final allExactMatches = <_PendingTmMatch>[]`.
- After the lookup loop completes, call `_applyTmMatchesBatch(allExactMatches, context)` exactly once for the exact phase.
- Same transformation for the fuzzy phase: collect all `≥95%` auto-accepts into `allFuzzyMatches`, apply once at the end of the fuzzy loop.
- `exactMatchedUnitIds` / `fuzzyMatchedUnitIds` are populated from the accumulated list after the single apply succeeds.

Change `_maxConcurrentLookups` from `15` to `50`.

### 4. `HistoryService.recordChangesBatch` (new)

New method on the history service, takes a typed list:

```dart
class HistoryChangeEntry {
  final String versionId;
  final String translatedText;
  final String status;
  final String changedBy;
  final String changeReason;
  const HistoryChangeEntry({...});
}

Future<Result<void, TWMTDatabaseException>> recordChangesBatch(
  List<HistoryChangeEntry> entries,
);
```

Implementation: single `executeTransaction`, one `txn.batch()` with `batch.insert` per entry, one `commit(noResult: true)`. Failure path mirrors the existing per-entry behavior (log warning, non-critical — the translation itself is already persisted).

## Data flow

```
units (per chunk of 50)
    │
    ├── Future.wait(findExactMatch) in parallel
    │
    ▼
List<_PendingTmMatch> (accumulated across all chunks, held in memory)
    │
    ▼ once per phase
_applyTmMatchesBatch(allMatches, context)
    │
    ├── upsertBatchOptimized(versions) ──► one transaction,
    │                                         triggers off if >50,
    │                                         bulk FTS/cache/progress rebuild
    │
    └── recordChangesBatch(historyEntries) ──► one transaction
    │
    ▼
entryUsageCounts accumulated, returned for the existing deferred
incrementUsageCountBatch call at end of performLookup (unchanged)
```

## Error handling

- `upsertBatchOptimized` wraps DROP/CREATE trigger DDL in `try/finally` (identical to `importBatch`). Guarantees trigger state is restored even on failure.
- If the apply transaction fails, the whole phase rolls back (exact matches or fuzzy matches for that phase are not persisted). Exception propagates to `performLookup`, which surfaces it to the orchestrator. User can re-run.
- `recordChangesBatch` failures stay non-critical: log a warning, do not abort the phase. History is best-effort, as today.
- Pause/cancel: checked at each lookup chunk boundary (unchanged semantics at the user-visible level, just rarer checks because chunks are bigger — 50 vs 15). No check during the bulk apply.

## Progress reporting

Lookup phase messages unchanged in content, just update every 50 units instead of every 15:

> `Exact TM lookup: X% (i/N units, M matches found)…`

Apply phase: single coarse progression using `upsertBatchOptimized`'s `onProgress` callback:

> `Applying N exact TM matches — saving…`
> `Applying N exact TM matches — rebuilding search index…`
> `Applying N exact TM matches — updating project progress…`

Same structure for the fuzzy auto-accept apply.

## Testing

### Unit — `upsertBatchOptimized`

- Empty list → returns `(inserted: 0, updated: 0)`, no transaction issued.
- 1 entity (below trigger-drop threshold) → triggers stay active, single insert works.
- 100 entities (crosses threshold) → triggers dropped and recreated, FTS/cache/progress correct at end.
- 5000 entities (crosses chunk boundary of 500) → all chunks committed, final state correct.
- Mix of new + existing entities → both update and insert paths exercised in one call.
- Precondition: all `entities.projectLanguageId` equal — assert (test with violation → clear error).

### Unit — `recordChangesBatch`

- Empty list → no-op.
- 10 entries → single batch insert visible.
- 5000 entries → completes without OOM and in one transaction.

### Integration — `TmLookupHandler.performLookup`

- Project with 1000 source units, TM pre-populated so 800 match exactly → after run: 800 `TranslationVersion` rows created, 800 history entries, `project_languages.progress_percent` correct, FTS searchable, `exactMatchedUnitIds` returned with the 800 ids.
- Project where 200 of the 800 matched units already have a `TranslationVersion` → verify UPDATE path (IDs and `created_at` preserved) and INSERT path both execute correctly in the same call.
- Fuzzy auto-accept: 500 units with 90–98% fuzzy matches, threshold 95% → only ≥95% are applied in bulk; others left for the next phase.
- Regression: single-unit TM apply still works end-to-end.

### Benchmark (manual, local)

Synthetic project with 5000 exact matches, measured before/after.
Target: apply phase <2 s (from ~15 s current extrapolation). Recorded in PR description.

## Files touched

- `lib/repositories/mixins/translation_version_batch_mixin.dart` — add `upsertBatchOptimized`.
- `lib/services/translation/handlers/tm_lookup_handler.dart` — refactor `performLookup` (collect-then-apply) and `_applyTmMatchesBatch` (use bulk methods). Change `_maxConcurrentLookups` 15 → 50.
- `lib/services/history/history_service.dart` (and its interface) — add `recordChangesBatch` and `HistoryChangeEntry` type.
- Existing callers of `upsertWithTransaction` outside the TM flow remain untouched; the method is kept for now.

## Rollout

Single PR. No feature flag — behavior is equivalent, performance-only change. Covered by the new unit + integration tests. Benchmark result included in PR description.
