# TM Bulk Apply Optimization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring TM apply phase for 10 000 matches from minutes to single-digit seconds by switching from per-chunk-of-15 upserts to one bulk optimized write per phase (exact, fuzzy), using the same trigger-drop / bulk-rebuild pattern already in `TranslationVersionBatchMixin.importBatch`.

**Architecture:** Per match type: collect all matches into memory during parallel lookup (chunks of 50), then apply them in a single transaction that drops per-row triggers, batches INSERT/UPDATE through `txn.batch()`, rebuilds FTS index / `translation_view_cache` / `project_languages.progress_percent` in set-based SQL at the end, and re-creates triggers in `finally`. History recording is moved to a single batched insert per phase.

**Tech Stack:** Dart 3, Flutter, `sqflite_common_ffi` (WAL + NORMAL sync + 64 MB cache), mocktail for unit tests, in-memory SQLite with real migrations via `TestDatabase.openMigrated()` for integration tests.

**Spec:** `docs/superpowers/specs/2026-04-24-tm-bulk-apply-optimization-design.md`

---

## Task 1: Add `upsertBatchOptimized` to `TranslationVersionBatchMixin`

**Files:**
- Modify: `lib/repositories/mixins/translation_version_batch_mixin.dart`
- Create: `test/unit/repositories/mixins/translation_version_batch_mixin_upsert_optimized_test.dart`

- [ ] **Step 1.1: Write the failing test — empty list short-circuits**

Create `test/unit/repositories/mixins/translation_version_batch_mixin_upsert_optimized_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../../../helpers/test_database.dart';

void main() {
  late Database db;
  late TranslationVersionRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = TranslationVersionRepository();
  });

  tearDown(() => TestDatabase.close(db));

  group('upsertBatchOptimized', () {
    test('returns zero counts and no-op for empty list', () async {
      final result = await repo.upsertBatchOptimized(entities: []);
      expect(result.isOk, isTrue);
      final counts = result.unwrap();
      expect(counts.inserted, 0);
      expect(counts.updated, 0);
      expect(counts.effectiveVersionIds, isEmpty);
    });
  });
}
```

- [ ] **Step 1.2: Run the test to confirm failure**

Run: `flutter test test/unit/repositories/mixins/translation_version_batch_mixin_upsert_optimized_test.dart`
Expected: FAIL with `The method 'upsertBatchOptimized' isn't defined for the class 'TranslationVersionRepository'`.

- [ ] **Step 1.3: Add method signature and empty-list short-circuit**

Open `lib/repositories/mixins/translation_version_batch_mixin.dart`. After the existing `upsertBatch` method (around line 136), add the new method. First, add its signature and the empty-list case only:

```dart
  /// Upsert translation versions with trigger-disable optimization for large batches.
  ///
  /// Designed for the TM apply flow where thousands of matches must be
  /// persisted quickly. All entities must share the same [projectLanguageId]
  /// (the FTS / cache / progress rebuild is scoped to that language).
  ///
  /// Returns counts of inserted vs updated rows plus [effectiveVersionIds]
  /// aligned by index with [entities]: each entry is the entity's own id when
  /// the row was inserted, or the pre-existing row's id when it was updated.
  /// Callers that need to reference the persisted row (e.g. for history)
  /// should use these ids, not the ids on the input entities.
  Future<Result<({int inserted, int updated, List<String> effectiveVersionIds}),
      TWMTDatabaseException>> upsertBatchOptimized({
    required List<TranslationVersion> entities,
    void Function(int current, int total, String message)? onProgress,
  }) async {
    if (entities.isEmpty) {
      return Ok((inserted: 0, updated: 0, effectiveVersionIds: <String>[]));
    }
    // Precondition: one projectLanguageId per call (scoped rebuild).
    final projectLanguageId = entities.first.projectLanguageId;
    assert(
      entities.every((e) => e.projectLanguageId == projectLanguageId),
      'upsertBatchOptimized requires all entities to share the same projectLanguageId',
    );
    throw UnimplementedError('filled in next step');
  }
```

- [ ] **Step 1.4: Run the empty-list test — expect PASS**

Run: `flutter test test/unit/repositories/mixins/translation_version_batch_mixin_upsert_optimized_test.dart`
Expected: PASS (empty case short-circuits before the `UnimplementedError`).

- [ ] **Step 1.5: Write the next failing test — inserts-only, below trigger threshold**

Append to the same test file inside `group('upsertBatchOptimized', () { ... })`:

```dart
    test('inserts new rows and returns their own ids when below trigger threshold',
        () async {
      // 10 entities < 50 → triggers stay active.
      final now = DateTime.now().millisecondsSinceEpoch;
      final entities = List.generate(10, (i) {
        return TranslationVersion(
          id: 'v-$i',
          unitId: 'u-$i',
          projectLanguageId: 'pl-1',
          translatedText: 'text $i',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        );
      });

      final result = await repo.upsertBatchOptimized(entities: entities);
      expect(result.isOk, isTrue);
      final counts = result.unwrap();
      expect(counts.inserted, 10);
      expect(counts.updated, 0);
      expect(counts.effectiveVersionIds,
          equals(List.generate(10, (i) => 'v-$i')));

      // Verify rows persisted.
      final rows = await db.query('translation_versions',
          where: 'project_language_id = ?', whereArgs: ['pl-1']);
      expect(rows, hasLength(10));
    });
```

Add the imports at the top of the test file:

```dart
import 'package:twmt/models/domain/translation_version.dart';
```

- [ ] **Step 1.6: Run test — expect FAIL with UnimplementedError**

Run: `flutter test test/unit/repositories/mixins/translation_version_batch_mixin_upsert_optimized_test.dart`
Expected: FAIL with `UnimplementedError: filled in next step`.

- [ ] **Step 1.7: Implement the full method body**

Replace the `throw UnimplementedError(...)` in `upsertBatchOptimized` with the full body:

```dart
    return executeTransaction((txn) async {
      final total = entities.length;
      onProgress?.call(0, total, 'Preparing bulk apply...');

      // Step 1: Batch existence query to distinguish INSERT vs UPDATE.
      final unitIds = entities.map((e) => e.unitId).toSet().toList();
      // Chunk the IN (...) list to stay clear of SQLite's default parameter cap.
      const lookupChunkSize = 500;
      final existingLookup = <String, ({String id, int createdAt})>{};
      for (var i = 0; i < unitIds.length; i += lookupChunkSize) {
        final chunk = unitIds.skip(i).take(lookupChunkSize).toList();
        final placeholders = List.filled(chunk.length, '?').join(',');
        final maps = await txn.rawQuery('''
          SELECT id, unit_id, created_at
          FROM $tableName
          WHERE unit_id IN ($placeholders)
            AND project_language_id = ?
        ''', [...chunk, projectLanguageId]);
        for (final row in maps) {
          existingLookup[row['unit_id'] as String] = (
            id: row['id'] as String,
            createdAt: row['created_at'] as int,
          );
        }
      }

      final disableTriggers = entities.length > 50;
      if (disableTriggers) {
        onProgress?.call(0, total, 'Optimizing for bulk write...');
        await txn.execute('DROP TRIGGER IF EXISTS trg_update_project_language_progress');
        await txn.execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_update');
        await txn.execute('DROP TRIGGER IF EXISTS trg_update_cache_on_version_change');
      }

      int inserted = 0;
      int updated = 0;
      final effectiveIds = <String>[];

      try {
        // Step 2: Batched writes, sharing the outer transaction.
        const writeChunkSize = 500;
        for (var i = 0; i < entities.length; i += writeChunkSize) {
          final chunkEnd = (i + writeChunkSize).clamp(0, entities.length);
          final chunk = entities.sublist(i, chunkEnd);
          onProgress?.call(i, total, 'Saving translations...');

          final batch = txn.batch();
          for (final entity in chunk) {
            final existing = existingLookup[entity.unitId];
            if (existing != null) {
              // UPDATE: preserve existing id and created_at.
              final map = toMap(entity);
              map['created_at'] = existing.createdAt;
              map.remove('id');
              batch.update(
                tableName,
                map,
                where: 'id = ?',
                whereArgs: [existing.id],
              );
              effectiveIds.add(existing.id);
              updated++;
            } else {
              final map = toMap(entity);
              batch.insert(
                tableName,
                map,
                conflictAlgorithm: ConflictAlgorithm.abort,
              );
              effectiveIds.add(entity.id);
              inserted++;
            }
          }
          await batch.commit(noResult: true);
        }

        if (disableTriggers) {
          // Step 3: Rebuild FTS / cache / progress in set-based SQL.
          final now = DateTime.now().millisecondsSinceEpoch;
          onProgress?.call(total, total, 'Rebuilding search index...');

          const rebuildChunkSize = 500;
          for (var i = 0; i < unitIds.length; i += rebuildChunkSize) {
            final chunk = unitIds.skip(i).take(rebuildChunkSize).toList();
            final placeholders = List.filled(chunk.length, '?').join(',');
            await txn.rawDelete('''
              DELETE FROM translation_versions_fts
              WHERE version_id IN (
                SELECT id FROM translation_versions
                WHERE unit_id IN ($placeholders) AND project_language_id = ?
              )
            ''', [...chunk, projectLanguageId]);
          }
          for (var i = 0; i < unitIds.length; i += rebuildChunkSize) {
            final chunk = unitIds.skip(i).take(rebuildChunkSize).toList();
            final placeholders = List.filled(chunk.length, '?').join(',');
            await txn.rawInsert('''
              INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
              SELECT tv.translated_text, tv.validation_issues, tv.id
              FROM translation_versions tv
              WHERE tv.unit_id IN ($placeholders)
                AND tv.project_language_id = ?
                AND tv.translated_text IS NOT NULL
                AND tv.translated_text != ''
            ''', [...chunk, projectLanguageId]);
          }

          onProgress?.call(total, total, 'Updating cache...');
          for (var i = 0; i < unitIds.length; i += rebuildChunkSize) {
            final chunk = unitIds.skip(i).take(rebuildChunkSize).toList();
            final placeholders = List.filled(chunk.length, '?').join(',');
            await txn.rawUpdate('''
              UPDATE translation_view_cache
              SET translated_text = tv.translated_text,
                  status = tv.status,
                  is_manually_edited = tv.is_manually_edited,
                  version_id = tv.id,
                  version_updated_at = tv.updated_at
              FROM translation_versions tv
              WHERE translation_view_cache.unit_id = tv.unit_id
                AND translation_view_cache.project_language_id = tv.project_language_id
                AND tv.unit_id IN ($placeholders)
                AND tv.project_language_id = ?
            ''', [...chunk, projectLanguageId]);
          }

          onProgress?.call(total, total, 'Updating project progress...');
          await txn.rawUpdate('''
            UPDATE project_languages
            SET progress_percent = (
              SELECT
                CAST(COUNT(CASE WHEN tv.status IN ('approved', 'reviewed', 'translated') THEN 1 END) AS REAL) * 100.0 /
                NULLIF(COUNT(*), 0)
              FROM translation_versions tv
              INNER JOIN translation_units tu ON tv.unit_id = tu.id
              WHERE tv.project_language_id = project_languages.id
                AND tu.is_obsolete = 0
            ),
            updated_at = ?
            WHERE id = ?
          ''', [now, projectLanguageId]);
        }
      } finally {
        if (disableTriggers) {
          await txn.execute('''
            CREATE TRIGGER trg_update_project_language_progress
            AFTER UPDATE ON translation_versions
            WHEN NEW.status != OLD.status
            BEGIN
              UPDATE project_languages
              SET progress_percent = (
                SELECT
                  CAST(COUNT(CASE WHEN tv.status IN ('approved', 'reviewed', 'translated') THEN 1 END) AS REAL) * 100.0 /
                  NULLIF(COUNT(*), 0)
                FROM translation_versions tv
                INNER JOIN translation_units tu ON tv.unit_id = tu.id
                WHERE tv.project_language_id = NEW.project_language_id
                  AND tu.is_obsolete = 0
              ),
              updated_at = strftime('%s', 'now')
              WHERE id = NEW.project_language_id;
            END
          ''');

          await txn.execute('''
            CREATE TRIGGER trg_translation_versions_fts_update
            AFTER UPDATE OF translated_text, validation_issues ON translation_versions
            BEGIN
              DELETE FROM translation_versions_fts WHERE version_id = old.id;
              INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
              SELECT new.translated_text, new.validation_issues, new.id
              WHERE new.translated_text IS NOT NULL;
            END
          ''');

          await txn.execute('''
            CREATE TRIGGER trg_update_cache_on_version_change
            AFTER UPDATE ON translation_versions
            BEGIN
              UPDATE translation_view_cache
              SET translated_text = new.translated_text,
                  status = new.status,
                  confidence_score = NULL,
                  is_manually_edited = new.is_manually_edited,
                  version_id = new.id,
                  version_updated_at = new.updated_at
              WHERE unit_id = new.unit_id
                AND project_language_id = new.project_language_id;
            END
          ''');
        }
      }

      return (inserted: inserted, updated: updated, effectiveVersionIds: effectiveIds);
    });
```

- [ ] **Step 1.8: Run the inserts-only test — expect PASS**

Run: `flutter test test/unit/repositories/mixins/translation_version_batch_mixin_upsert_optimized_test.dart`
Expected: PASS. Both `empty list` and `inserts new rows` green.

- [ ] **Step 1.9: Add test — crosses trigger threshold (100 entities)**

Append to the group:

```dart
    test('inserts correctly when crossing trigger threshold (100 entities)',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final entities = List.generate(100, (i) {
        return TranslationVersion(
          id: 'v-$i',
          unitId: 'u-$i',
          projectLanguageId: 'pl-1',
          translatedText: 'text $i',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        );
      });

      final result = await repo.upsertBatchOptimized(entities: entities);
      expect(result.unwrap().inserted, 100);

      // Verify triggers were recreated after the call.
      final triggers = await db.rawQuery('''
        SELECT name FROM sqlite_master
        WHERE type = 'trigger'
          AND name IN (
            'trg_update_project_language_progress',
            'trg_translation_versions_fts_update',
            'trg_update_cache_on_version_change'
          )
      ''');
      expect(triggers, hasLength(3),
          reason: 'all three triggers must be recreated');

      // Verify FTS index was manually rebuilt.
      final ftsCount = await db.rawQuery(
          "SELECT COUNT(*) as c FROM translation_versions_fts");
      expect(ftsCount.first['c'], 100);
    });
```

- [ ] **Step 1.10: Run test — expect PASS**

Run: `flutter test test/unit/repositories/mixins/translation_version_batch_mixin_upsert_optimized_test.dart`
Expected: PASS for all three.

- [ ] **Step 1.11: Add test — updates-only path preserves existing ids and created_at**

Append:

```dart
    test('updates existing rows with preserved ids and created_at', () async {
      // Pre-seed two rows.
      await db.insert('translation_versions', {
        'id': 'existing-1',
        'unit_id': 'u-1',
        'project_language_id': 'pl-1',
        'translated_text': 'old',
        'status': 'translated',
        'translation_source': 'manual',
        'created_at': 1000,
        'updated_at': 1000,
      });
      await db.insert('translation_versions', {
        'id': 'existing-2',
        'unit_id': 'u-2',
        'project_language_id': 'pl-1',
        'translated_text': 'old',
        'status': 'translated',
        'translation_source': 'manual',
        'created_at': 2000,
        'updated_at': 2000,
      });

      final now = DateTime.now().millisecondsSinceEpoch;
      final entities = [
        TranslationVersion(
          id: 'new-1',  // Ignored: will use 'existing-1' because u-1 exists.
          unitId: 'u-1',
          projectLanguageId: 'pl-1',
          translatedText: 'fresh',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        ),
        TranslationVersion(
          id: 'new-2',
          unitId: 'u-2',
          projectLanguageId: 'pl-1',
          translatedText: 'fresh-2',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final result = await repo.upsertBatchOptimized(entities: entities);
      final counts = result.unwrap();
      expect(counts.inserted, 0);
      expect(counts.updated, 2);
      expect(counts.effectiveVersionIds,
          equals(['existing-1', 'existing-2']),
          reason: 'must return pre-existing ids, not the input entity ids');

      final rows = await db.query('translation_versions',
          where: 'unit_id IN (?, ?)',
          whereArgs: ['u-1', 'u-2'],
          orderBy: 'id ASC');
      expect(rows, hasLength(2));
      expect(rows[0]['id'], 'existing-1');
      expect(rows[0]['translated_text'], 'fresh');
      expect(rows[0]['created_at'], 1000, reason: 'created_at preserved');
      expect(rows[1]['id'], 'existing-2');
      expect(rows[1]['created_at'], 2000);
    });
```

- [ ] **Step 1.12: Run tests — expect PASS**

Run: `flutter test test/unit/repositories/mixins/translation_version_batch_mixin_upsert_optimized_test.dart`
Expected: all four tests PASS.

- [ ] **Step 1.13: Add test — mixed insert + update in one call**

Append:

```dart
    test('mixed insert + update yields correct counts and effectiveVersionIds',
        () async {
      await db.insert('translation_versions', {
        'id': 'pre-1',
        'unit_id': 'u-1',
        'project_language_id': 'pl-1',
        'translated_text': 'old',
        'status': 'translated',
        'translation_source': 'manual',
        'created_at': 1000,
        'updated_at': 1000,
      });

      final now = DateTime.now().millisecondsSinceEpoch;
      final entities = [
        TranslationVersion(
          id: 'ignored-1',
          unitId: 'u-1', // will UPDATE existing → effective id = 'pre-1'
          projectLanguageId: 'pl-1',
          translatedText: 'new-1',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        ),
        TranslationVersion(
          id: 'inserted-2',
          unitId: 'u-2', // will INSERT
          projectLanguageId: 'pl-1',
          translatedText: 'new-2',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final result = await repo.upsertBatchOptimized(entities: entities);
      final counts = result.unwrap();
      expect(counts.inserted, 1);
      expect(counts.updated, 1);
      expect(counts.effectiveVersionIds, equals(['pre-1', 'inserted-2']));
    });
```

- [ ] **Step 1.14: Run tests — expect PASS**

Run: `flutter test test/unit/repositories/mixins/translation_version_batch_mixin_upsert_optimized_test.dart`
Expected: all five tests PASS.

- [ ] **Step 1.15: Add test — project_languages.progress_percent recalculated after bulk write**

Append:

```dart
    test('recalculates project_languages.progress_percent after bulk write',
        () async {
      // Seed minimal project_languages and translation_units so the
      // aggregation has something to look at.
      await db.insert('project_languages', {
        'id': 'pl-1',
        'project_id': 'proj-1',
        'language_code': 'fr',
        'progress_percent': 0.0,
        'created_at': 0,
        'updated_at': 0,
      });
      for (var i = 0; i < 100; i++) {
        await db.insert('translation_units', {
          'id': 'u-$i',
          'project_id': 'proj-1',
          'key': 'k-$i',
          'source_text': 'src',
          'is_obsolete': 0,
          'created_at': 0,
          'updated_at': 0,
        });
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final entities = List.generate(60, (i) {
        return TranslationVersion(
          id: 'v-$i',
          unitId: 'u-$i',
          projectLanguageId: 'pl-1',
          translatedText: 't-$i',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        );
      });

      await repo.upsertBatchOptimized(entities: entities);

      final plRow = await db.query('project_languages',
          where: 'id = ?', whereArgs: ['pl-1'], limit: 1);
      // 60 translated out of 100 non-obsolete units → 60%.
      expect(plRow.first['progress_percent'], closeTo(60.0, 0.001));
    });
```

- [ ] **Step 1.16: Run tests — expect PASS**

Run: `flutter test test/unit/repositories/mixins/translation_version_batch_mixin_upsert_optimized_test.dart`
Expected: all six tests PASS.

- [ ] **Step 1.17: Commit**

```bash
git add lib/repositories/mixins/translation_version_batch_mixin.dart \
        test/unit/repositories/mixins/translation_version_batch_mixin_upsert_optimized_test.dart
git commit -m "feat(repo): add upsertBatchOptimized for TM bulk apply

Cousin of importBatch tailored for the TM flow: builds the existence
map internally (callers don't know which units are already translated),
returns effective version ids aligned with input entities so callers
can reference the persisted row id even on the update path. Triggers
are dropped above 50 entities; FTS, view cache and project progress
are rebuilt in set-based SQL before triggers are recreated."
```

---

## Task 2: Add `recordChangesBatch` and `HistoryChangeEntry` to history service

**Files:**
- Create: `lib/models/history/history_change_entry.dart`
- Modify: `lib/services/history/i_history_service.dart`
- Modify: `lib/services/history/history_service_impl.dart`
- Modify: `lib/repositories/translation_version_history_repository.dart` (add `insertBatch`)
- Create: `test/unit/services/history/history_service_record_changes_batch_test.dart`

- [ ] **Step 2.1: Create the `HistoryChangeEntry` value type**

Create `lib/models/history/history_change_entry.dart`:

```dart
/// Input payload for a single history entry in a batch record.
///
/// Used by [IHistoryService.recordChangesBatch] to keep the method signature
/// stable while bundling many entries into one transaction.
class HistoryChangeEntry {
  final String versionId;
  final String translatedText;
  final String status;
  final String changedBy;
  final String? changeReason;

  const HistoryChangeEntry({
    required this.versionId,
    required this.translatedText,
    required this.status,
    required this.changedBy,
    this.changeReason,
  });
}
```

- [ ] **Step 2.2: Add `insertBatch` to the history repository**

Open `lib/repositories/translation_version_history_repository.dart`. After the existing `insert` method (around line 73), add:

```dart
  /// Insert many history entries in a single transaction using a batched
  /// commit. Used by the TM apply flow to avoid per-row round trips.
  Future<Result<void, TWMTDatabaseException>> insertBatch(
      List<TranslationVersionHistory> entities) async {
    if (entities.isEmpty) {
      return const Ok(null);
    }
    return executeTransaction((txn) async {
      final batch = txn.batch();
      for (final entity in entities) {
        batch.insert(
          tableName,
          toMap(entity),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      await batch.commit(noResult: true);
    });
  }
```

(If the class does not already expose `executeTransaction`, inspect `BaseRepository` — the other batch mixins use it the same way. If not available, use `database.transaction((txn) async { ... })` directly.)

- [ ] **Step 2.3: Declare `recordChangesBatch` on `IHistoryService`**

Open `lib/services/history/i_history_service.dart`. Add the import at the top:

```dart
import '../../models/history/history_change_entry.dart';
```

Then add the method inside the abstract class (after `recordChange`):

```dart
  /// Record many history entries in a single transaction.
  ///
  /// Used by high-volume write flows (e.g. TM batch apply) to avoid per-row
  /// DB round trips. Each entry becomes one row in `translation_version_history`.
  ///
  /// History recording is best-effort: a failure here MUST NOT be treated as
  /// a failure of the underlying edit. Callers should log and move on.
  Future<Result<void, TWMTDatabaseException>> recordChangesBatch(
    List<HistoryChangeEntry> entries,
  );
```

- [ ] **Step 2.4: Write the failing test**

Create `test/unit/services/history/history_service_record_changes_batch_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/history/history_change_entry.dart';
import 'package:twmt/repositories/translation_version_history_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/history/history_service_impl.dart';

import '../../../helpers/test_database.dart';

void main() {
  late Database db;
  late HistoryServiceImpl service;
  late TranslationVersionHistoryRepository historyRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    historyRepo = TranslationVersionHistoryRepository();
    service = HistoryServiceImpl(
      historyRepository: historyRepo,
      versionRepository: TranslationVersionRepository(),
    );
  });

  tearDown(() => TestDatabase.close(db));

  group('recordChangesBatch', () {
    test('returns Ok and writes zero rows for empty list', () async {
      final result = await service.recordChangesBatch([]);
      expect(result.isOk, isTrue);
      final rows = await db.query('translation_version_history');
      expect(rows, isEmpty);
    });

    test('writes one row per entry and returns Ok', () async {
      final entries = List.generate(
        50,
        (i) => HistoryChangeEntry(
          versionId: 'v-$i',
          translatedText: 't-$i',
          status: 'translated',
          changedBy: 'tm_exact',
          changeReason: 'TM exact match (100% similarity)',
        ),
      );

      final result = await service.recordChangesBatch(entries);
      expect(result.isOk, isTrue);

      final rows = await db.query('translation_version_history',
          orderBy: 'version_id ASC');
      expect(rows, hasLength(50));
      expect(rows.first['changed_by'], 'tm_exact');
      expect(rows.first['change_reason'], contains('TM exact match'));
    });
  });
}
```

- [ ] **Step 2.5: Run the test to confirm failure**

Run: `flutter test test/unit/services/history/history_service_record_changes_batch_test.dart`
Expected: FAIL with `The method 'recordChangesBatch' isn't defined for the class 'HistoryServiceImpl'`.

- [ ] **Step 2.6: Implement `recordChangesBatch` in `HistoryServiceImpl`**

Open `lib/services/history/history_service_impl.dart`. Add the import at the top:

```dart
import '../../models/history/history_change_entry.dart';
```

Inside the class, next to `recordChange`, add:

```dart
  @override
  Future<Result<void, TWMTDatabaseException>> recordChangesBatch(
    List<HistoryChangeEntry> entries,
  ) async {
    if (entries.isEmpty) {
      return const Ok(null);
    }
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final rows = entries.map((e) {
        return TranslationVersionHistory(
          id: _uuid.v4(),
          versionId: e.versionId,
          translatedText: e.translatedText,
          status: _parseStatus(e.status),
          changedBy: e.changedBy,
          changeReason: e.changeReason,
          createdAt: now,
        );
      }).toList();
      return await _historyRepository.insertBatch(rows);
    } catch (e) {
      return Err(TWMTDatabaseException('Failed to batch-record history: $e'));
    }
  }
```

- [ ] **Step 2.7: Run tests — expect PASS**

Run: `flutter test test/unit/services/history/history_service_record_changes_batch_test.dart`
Expected: both tests PASS.

- [ ] **Step 2.8: Commit**

```bash
git add lib/models/history/history_change_entry.dart \
        lib/services/history/i_history_service.dart \
        lib/services/history/history_service_impl.dart \
        lib/repositories/translation_version_history_repository.dart \
        test/unit/services/history/history_service_record_changes_batch_test.dart
git commit -m "feat(history): add recordChangesBatch for bulk history writes

Introduces HistoryChangeEntry value type, a repository-level insertBatch
for translation_version_history, and a service method that records many
entries in a single transaction. Used by the TM apply flow so a 10k
match batch becomes one batched insert instead of 10k sequential calls."
```

---

## Task 3: Refactor `TmLookupHandler` to collect-then-apply

**Files:**
- Modify: `lib/services/translation/handlers/tm_lookup_handler.dart`
- Modify: `test/unit/services/translation/handlers/tm_lookup_handler_test.dart`

- [ ] **Step 3.1: Read the current handler test to see the existing mock surface**

Open `test/unit/services/translation/handlers/tm_lookup_handler_test.dart`. Note that it currently stubs `versionRepository.upsertWithTransaction(any(), any())` and captures each persisted version. After the refactor, the handler will instead call `versionRepository.upsertBatchOptimized(...)` once per phase, and `historyService.recordChangesBatch(any())` once per phase. We will update the stubs to match.

- [ ] **Step 3.2: Bump `_maxConcurrentLookups` and add new imports**

Open `lib/services/translation/handlers/tm_lookup_handler.dart`. Change the constant and add the import:

```dart
// near existing imports
import '../../../models/history/history_change_entry.dart';
```

```dart
  /// Maximum concurrent TM lookups for READ operations (queries).
  /// These are safe to parallelize as they don't modify data.
  static const int _maxConcurrentLookups = 50;
```

- [ ] **Step 3.3: Refactor `performLookup` to collect-then-apply for the exact phase**

In `performLookup`, replace the body of the exact-match loop (currently lines ~80‑145) so that each chunk only **collects** matches; the apply happens once after the loop. Replace the existing exact block up to and including the fuzzy-phase transition with:

```dart
    // === EXACT LOOKUP PHASE (collect only) ===
    final allExactMatches = <_PendingTmMatch>[];
    for (var i = 0; i < units.length; i += _maxConcurrentLookups) {
      await checkPauseOrCancel(batchId);

      final chunk = units.skip(i).take(_maxConcurrentLookups).toList();
      final progressPct = ((i / units.length) * 100).round();
      progress = progress.copyWith(
        phaseDetail:
            'Exact TM lookup: $progressPct% ($i/${units.length} units, ${allExactMatches.length} matches)...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      if (i % 100 == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      final lookupResults = await Future.wait(
        chunk.map((unit) => _findExactMatch(unit, context)),
      );
      for (var j = 0; j < chunk.length; j++) {
        final result = lookupResults[j];
        if (result != null) {
          allExactMatches.add(_PendingTmMatch(unit: chunk[j], match: result));
        }
      }

      if (i % 500 == 0 && i > 0) {
        _logger.debug('TM exact lookup progress', {
          'batchId': batchId,
          'processed': i,
          'total': units.length,
          'matches': allExactMatches.length,
        });
      }
    }

    // === EXACT APPLY PHASE (single bulk write) ===
    final exactMatchedUnitIds = <String>{};
    if (allExactMatches.isNotEmpty) {
      progress = progress.copyWith(
        phaseDetail: 'Applying ${allExactMatches.length} exact TM matches...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      final applyCounts = await _applyTmMatchesBatch(allExactMatches, context);
      for (final pending in allExactMatches) {
        exactMatchedUnitIds.add(pending.unit.id);
      }
      skippedCount += allExactMatches.length;
      processedCount += allExactMatches.length;
      for (final entry in applyCounts.entries) {
        allEntryUsageCounts.update(entry.key, (v) => v + entry.value,
            ifAbsent: () => entry.value);
      }
    }
```

- [ ] **Step 3.4: Refactor the fuzzy phase to the same shape**

Still in `performLookup`, replace the fuzzy chunk loop so that the apply happens once after the fuzzy loop. The block starting `for (var i = 0; i < unitsForFuzzyFiltered.length; i += _maxConcurrentLookups)` becomes:

```dart
    // === FUZZY LOOKUP PHASE (collect only) ===
    final allFuzzyMatches = <_PendingTmMatch>[];
    for (var i = 0; i < unitsForFuzzyFiltered.length; i += _maxConcurrentLookups) {
      await checkPauseOrCancel(batchId);

      final chunk =
          unitsForFuzzyFiltered.skip(i).take(_maxConcurrentLookups).toList();
      final progressPct =
          ((i / unitsForFuzzyFiltered.length) * 100).round();
      progress = progress.copyWith(
        phaseDetail:
            'Fuzzy TM lookup (≥85%): $progressPct% ($i/${unitsForFuzzyFiltered.length} units, ${allFuzzyMatches.length} matches)...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      if (i % 100 == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      final lookupResults = await Future.wait(
        chunk.map((unit) => _findFuzzyMatch(unit, context)),
      );
      for (var j = 0; j < chunk.length; j++) {
        final result = lookupResults[j];
        if (result != null &&
            result.similarityScore >= AppConstants.autoAcceptTmThreshold) {
          allFuzzyMatches.add(_PendingTmMatch(unit: chunk[j], match: result));
        }
      }
    }

    // === FUZZY APPLY PHASE (single bulk write) ===
    final fuzzyMatchedUnitIds = <String>{};
    var fuzzyMatchCount = 0;
    if (allFuzzyMatches.isNotEmpty) {
      progress = progress.copyWith(
        phaseDetail:
            'Auto-accepting ${allFuzzyMatches.length} high-confidence fuzzy matches (≥95%)...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      final applyCounts = await _applyTmMatchesBatch(allFuzzyMatches, context);
      for (final pending in allFuzzyMatches) {
        fuzzyMatchedUnitIds.add(pending.unit.id);
      }
      fuzzyMatchCount = allFuzzyMatches.length;
      skippedCount += allFuzzyMatches.length;
      processedCount += allFuzzyMatches.length;
      for (final entry in applyCounts.entries) {
        allEntryUsageCounts.update(entry.key, (v) => v + entry.value,
            ifAbsent: () => entry.value);
      }
    }
```

Preserve any existing post-phase code that increments usage counts via `incrementUsageCountBatch` and returns the `(progress, matchedIds)` tuple — that code stays untouched.

- [ ] **Step 3.5: Rewrite `_applyTmMatchesBatch` to use the new repository / service methods**

Replace the body of `_applyTmMatchesBatch` entirely:

```dart
  /// Apply a collected set of TM matches in a single optimized bulk write.
  /// Returns a map of entry IDs → applied count, for deferred usage increment.
  Future<Map<String, int>> _applyTmMatchesBatch(
    List<_PendingTmMatch> matches,
    TranslationContext context,
  ) async {
    if (matches.isEmpty) return {};

    final now = DateTime.now().millisecondsSinceEpoch;

    // Build TranslationVersion entities aligned by index with `matches`.
    final versions = <TranslationVersion>[];
    for (final pending in matches) {
      final translationSource = pending.match.matchType == TmMatchType.exact
          ? TranslationSource.tmExact
          : TranslationSource.tmFuzzy;
      final normalizedText =
          TranslationTextUtils.normalizeTranslation(pending.match.targetText);
      versions.add(TranslationVersion(
        id: _generateId(),
        unitId: pending.unit.id,
        projectLanguageId: context.projectLanguageId,
        translatedText: normalizedText,
        status: TranslationVersionStatus.translated,
        translationSource: translationSource,
        createdAt: now,
        updatedAt: now,
      ));
    }

    // Single bulk write.
    final upsertResult =
        await _versionRepository.upsertBatchOptimized(entities: versions);
    if (upsertResult.isErr) {
      throw upsertResult.unwrapErr();
    }
    final effectiveIds = upsertResult.unwrap().effectiveVersionIds;

    // Build history entries keyed off the REAL persisted ids.
    final historyEntries = <HistoryChangeEntry>[];
    for (var i = 0; i < matches.length; i++) {
      final pending = matches[i];
      final matchType =
          pending.match.matchType == TmMatchType.exact ? 'exact' : 'fuzzy';
      final similarity = (pending.match.similarityScore * 100).round();
      historyEntries.add(HistoryChangeEntry(
        versionId: effectiveIds[i],
        translatedText: versions[i].translatedText ?? '',
        status: TranslationVersionStatus.translated.name,
        changedBy: 'tm_$matchType',
        changeReason: 'TM $matchType match ($similarity% similarity)',
      ));
    }
    final historyResult =
        await _historyService.recordChangesBatch(historyEntries);
    if (historyResult.isErr) {
      // Non-critical: keep current behaviour, just log.
      _logger.warning('Failed to batch-record TM history (non-critical)', {
        'count': historyEntries.length,
        'error': historyResult.unwrapErr(),
      });
    }

    // Accumulate usage counts per TM entry.
    final entryUsageCounts = <String, int>{};
    for (final pending in matches) {
      entryUsageCounts.update(
        pending.match.entryId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return entryUsageCounts;
  }
```

- [ ] **Step 3.6: Update existing unit tests — swap mocked methods**

Open `test/unit/services/translation/handlers/tm_lookup_handler_test.dart`. In the `setUp` block, remove the stub for `upsertWithTransaction` and the `transactionManager.executeTransaction` stub that wraps it, and replace with stubs for the new methods. Locate this block:

```dart
    when(() => versionRepository.upsertWithTransaction(any(), any()))
        .thenAnswer((inv) async {
      persistedVersions.add(inv.positionalArguments[1] as TranslationVersion);
    });

    when(() => transactionManager.executeTransaction<bool>(any()))
        .thenAnswer((inv) async {
      final action =
          inv.positionalArguments[0] as Future<bool> Function(Transaction);
      final result = await action(_FakeTransaction());
      return Ok(result);
    });
```

Replace it with:

```dart
    when(() => versionRepository.upsertBatchOptimized(
          entities: any(named: 'entities'),
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((inv) async {
      final entities =
          inv.namedArguments[#entities] as List<TranslationVersion>;
      persistedVersions.addAll(entities);
      return Ok((
        inserted: entities.length,
        updated: 0,
        effectiveVersionIds: entities.map((e) => e.id).toList(),
      ));
    });

    when(() => historyService.recordChangesBatch(any()))
        .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));
```

Also remove the now-unused `recordChange` default stub — search for `historyService.recordChange` in `setUp` and delete it (the per-call `recordChange` path is no longer used by the handler). Replace the `registerFallbackValue` calls at the top of `main()` to include:

```dart
    registerFallbackValue(<TranslationVersion>[]);
    registerFallbackValue(<HistoryChangeEntry>[]);
```

And add the import at the top of the test file:

```dart
import 'package:twmt/models/history/history_change_entry.dart';
```

- [ ] **Step 3.7: Update the history-recording assertion test**

Search the test file for the test that asserts on `historyService.recordChange(...)` per match (something like "records history for every persisted match"). Replace its verification block with a check on the batched call:

```dart
      // Exactly one batched call, containing one entry per persisted match.
      final captured = verify(
        () => historyService.recordChangesBatch(captureAny()),
      ).captured.single as List<HistoryChangeEntry>;
      expect(captured, hasLength(2));
      expect(
        captured.map((e) => e.changedBy).toSet(),
        equals({'tm_exact'}),
      );
```

Adjust the match on `changedBy`/counts to what each specific test asserts.

- [ ] **Step 3.8: Run all handler tests — expect PASS**

Run: `flutter test test/unit/services/translation/handlers/tm_lookup_handler_test.dart`
Expected: all tests PASS.

- [ ] **Step 3.9: Run full test suite to catch unintended fallout**

Run: `flutter test`
Expected: no new failures. Any failure must be investigated; if it's a pre-existing flake, note it, otherwise fix before committing.

- [ ] **Step 3.10: Commit**

```bash
git add lib/services/translation/handlers/tm_lookup_handler.dart \
        test/unit/services/translation/handlers/tm_lookup_handler_test.dart
git commit -m "perf(tm): collect all matches per phase, apply in one bulk write

Replaces the per-chunk-of-15 apply loop with a collect-then-apply
pattern: each phase (exact, fuzzy) accumulates pending matches during
parallel lookup, then persists them in a single upsertBatchOptimized
call and a single recordChangesBatch call. Reuses the trigger-drop
pattern via the new repository method, which avoids the O(N^2)
aggregation in trg_update_project_language_progress firing per row.

Also raises _maxConcurrentLookups from 15 to 50 since reads are
hash/index-based and dominate in parallelism."
```

---

## Task 4: Integration-level verification on a migrated in-memory DB

**Files:**
- Create: `test/integration/translation/tm_bulk_apply_integration_test.dart`

This task builds an end-to-end test that exercises `_applyTmMatchesBatch` indirectly through the actual repository on a real migrated schema — the unit tests use mocks and the isolated mixin tests skip the handler. This closes the loop.

- [ ] **Step 4.1: Write the integration test**

Create `test/integration/translation/tm_bulk_apply_integration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../../helpers/test_database.dart';

/// End-to-end verification that the bulk apply path produces a consistent
/// schema state: rows persisted, FTS index populated, view cache updated,
/// project_languages.progress_percent recomputed.
void main() {
  late Database db;
  late TranslationVersionRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = TranslationVersionRepository();

    await db.insert('project_languages', {
      'id': 'pl-int',
      'project_id': 'proj-int',
      'language_code': 'fr',
      'progress_percent': 0.0,
      'created_at': 0,
      'updated_at': 0,
    });
    for (var i = 0; i < 1000; i++) {
      await db.insert('translation_units', {
        'id': 'u-$i',
        'project_id': 'proj-int',
        'key': 'k-$i',
        'source_text': 'source $i',
        'is_obsolete': 0,
        'created_at': 0,
        'updated_at': 0,
      });
    }
  });

  tearDown(() => TestDatabase.close(db));

  test('bulk-apply 1000 TM matches leaves the schema fully consistent',
      () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entities = List.generate(1000, (i) {
      return TranslationVersion(
        id: 'v-$i',
        unitId: 'u-$i',
        projectLanguageId: 'pl-int',
        translatedText: 'bonjour $i',
        status: TranslationVersionStatus.translated,
        translationSource: TranslationSource.tmExact,
        createdAt: now,
        updatedAt: now,
      );
    });

    final res = await repo.upsertBatchOptimized(entities: entities);
    expect(res.isOk, isTrue);
    expect(res.unwrap().inserted, 1000);

    // translation_versions populated.
    final versionsCount = (await db.rawQuery(
        "SELECT COUNT(*) AS c FROM translation_versions WHERE project_language_id = ?",
        ['pl-int'])).first['c'] as int;
    expect(versionsCount, 1000);

    // FTS index populated (one entry per non-empty translated_text).
    final ftsCount = (await db.rawQuery(
        "SELECT COUNT(*) AS c FROM translation_versions_fts")).first['c'] as int;
    expect(ftsCount, 1000);

    // Progress = 100% (all 1000 units translated).
    final pl = await db.query('project_languages',
        where: 'id = ?', whereArgs: ['pl-int'], limit: 1);
    expect(pl.first['progress_percent'], closeTo(100.0, 0.001));

    // Triggers restored.
    final triggers = await db.rawQuery('''
      SELECT name FROM sqlite_master
      WHERE type = 'trigger'
        AND name IN (
          'trg_update_project_language_progress',
          'trg_translation_versions_fts_update',
          'trg_update_cache_on_version_change'
        )
    ''');
    expect(triggers, hasLength(3));
  });
}
```

- [ ] **Step 4.2: Run the integration test**

Run: `flutter test test/integration/translation/tm_bulk_apply_integration_test.dart`
Expected: PASS.

- [ ] **Step 4.3: Commit**

```bash
git add test/integration/translation/tm_bulk_apply_integration_test.dart
git commit -m "test(tm): integration test for bulk apply on migrated schema

Verifies that 1000 TM matches through upsertBatchOptimized leave the
schema consistent end-to-end: versions persisted, FTS index populated,
project_languages.progress_percent recomputed, all three per-row
triggers restored after the optimized path finishes."
```

---

## Task 5: Manual benchmark and PR description

- [ ] **Step 5.1: Build a benchmark scratch script**

Create `tool/bench/tm_bulk_apply_bench.dart` (gitignored, not committed — a throwaway for this PR):

```dart
// Run with: dart run tool/bench/tm_bulk_apply_bench.dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../../test/helpers/test_database.dart';

Future<void> main() async {
  final db = await TestDatabase.openMigrated();
  final repo = TranslationVersionRepository();

  await db.insert('project_languages', {
    'id': 'pl', 'project_id': 'p', 'language_code': 'fr',
    'progress_percent': 0.0, 'created_at': 0, 'updated_at': 0,
  });
  const n = 5000;
  for (var i = 0; i < n; i++) {
    await db.insert('translation_units', {
      'id': 'u-$i', 'project_id': 'p', 'key': 'k-$i',
      'source_text': 'src $i', 'is_obsolete': 0,
      'created_at': 0, 'updated_at': 0,
    });
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  final entities = List.generate(n, (i) => TranslationVersion(
    id: 'v-$i', unitId: 'u-$i', projectLanguageId: 'pl',
    translatedText: 't $i',
    status: TranslationVersionStatus.translated,
    translationSource: TranslationSource.tmExact,
    createdAt: now, updatedAt: now,
  ));

  final sw = Stopwatch()..start();
  await repo.upsertBatchOptimized(entities: entities);
  sw.stop();
  print('upsertBatchOptimized $n rows: ${sw.elapsedMilliseconds} ms');
}
```

- [ ] **Step 5.2: Run the benchmark**

Run: `dart run tool/bench/tm_bulk_apply_bench.dart`
Record the elapsed milliseconds for 5000 rows.
Target: < 2000 ms. If substantially higher, revisit (profile with `flutter pub global run devtools` or log where time is spent).

- [ ] **Step 5.3: Delete the scratch file and write the PR description**

Delete `tool/bench/tm_bulk_apply_bench.dart`. Capture the benchmark number for the PR description. Write the PR description using this template:

```
## What
Move TM apply phase from per-chunk-of-15 upsert loop to one bulk
optimized write per phase (exact, fuzzy).

## Why
With 10 000 TM matches, the old code fired ~20k sequential DB ops
and the per-row progress trigger ran a full aggregation each time,
making the phase O(N^2). Observed: 33s elapsed mid-run, extrapolating
to several minutes total on a real project.

## How
- New repository method `upsertBatchOptimized` mirrors `importBatch`:
  drops triggers above 50 entities, batches writes, rebuilds FTS /
  view cache / progress in set-based SQL, re-creates triggers in
  `finally`. Returns effective version ids so callers can reference
  the persisted row id (fixes a latent defect in the previous flow
  which attached history to generated ids even on the UPDATE path).
- New history service method `recordChangesBatch` for one-shot history
  writes.
- `TmLookupHandler.performLookup` now collects all matches per phase
  during parallel lookup and applies them in a single bulk call.
- `_maxConcurrentLookups` raised 15 → 50 (reads are hash/index-based).

## Benchmark
5000 TM matches bulk-applied on an in-memory migrated DB:
- Before (extrapolated from 33s @ 10k rows): ~15s
- After: <benchmark result> ms
```

---

## Self-Review — Coverage Check

| Spec section | Task covering it |
|---|---|
| `upsertBatchOptimized` signature + internal SELECT + effective ids | Task 1 (steps 1.3, 1.7, 1.11, 1.13) |
| Trigger drop/recreate above 50, set-based rebuild | Task 1 (steps 1.7, 1.9) |
| `recordChangesBatch` + `HistoryChangeEntry` | Task 2 |
| Refactor `_applyTmMatchesBatch` to call bulk methods | Task 3 (step 3.5) |
| Refactor `performLookup` to collect-then-apply per phase | Task 3 (steps 3.3, 3.4) |
| Bump `_maxConcurrentLookups` to 50 | Task 3 (step 3.2) |
| End-to-end schema consistency on migrated DB | Task 4 |
| Benchmark target < 2s for 5000 matches | Task 5 |
| Error handling (trigger `try/finally`, history non-critical) | Task 1 (step 1.7), Task 3 (step 3.5) |
| Progress messages during apply | Task 3 (steps 3.3, 3.4) — "Applying N…" and the `onProgress` hook wired through `upsertBatchOptimized` |

All spec sections have at least one task. No placeholders remain.
