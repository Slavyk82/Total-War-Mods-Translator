# ValidationIssuesJsonMigration Post-RunApp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the legacy `validation_issues` JSON rewrite out of the pre-`runApp` schema migration chain into the post-`runApp` `DataMigration` flow with progress UI, and optimize the rewrite by dropping cascading triggers inside a transaction so the work runs in seconds instead of minutes.

**Architecture:** Extract the rewrite logic into a new data-migration service (`ValidationIssuesJsonDataMigration`) called from the existing `DataMigration` Riverpod provider (a new step, positioned before TM rebuild). The service drops 3 cascading triggers inside a single transaction, rewrites legacy payloads via keyset-paginated UPDATEs, recreates triggers from DDL constants, commits, then attempts an FTS rebuild (best-effort) before writing a marker row in `_migration_markers`.

**Tech Stack:** Dart 3 / Flutter 3, `sqflite_common_ffi` (Windows SQLite backend), Riverpod (with code generation for providers), `flutter_test`, in-memory SQLite for tests.

---

## File Structure

- **Create**: `lib/services/database/data_migrations/validation_issues_json_data_migration.dart` — service class invoked from the provider.
- **Create**: `test/services/database/data_migrations/validation_issues_json_data_migration_test.dart` — unit tests.
- **Modify**: `lib/providers/data_migration_provider.dart` — add validation_issues step at position 1, update `needsMigration()`.
- **Modify**: `lib/services/database/migrations/migration_registry.dart` — remove the entry + import.
- **Delete**: `lib/services/database/migrations/migration_validation_issues_json.dart`.

---

## Task 1: New service skeleton + `isApplied()` logic

**Goal:** Create the service file with constructor, id, marker-table check and the legacy-shape fallback scan (same two-phase logic as the current migration). Verify with unit tests on an in-memory DB.

**Files:**
- Create: `lib/services/database/data_migrations/validation_issues_json_data_migration.dart`
- Create: `test/services/database/data_migrations/validation_issues_json_data_migration_test.dart`

- [ ] **Step 1.1: Write the failing tests**

Create `test/services/database/data_migrations/validation_issues_json_data_migration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/data_migrations/validation_issues_json_data_migration.dart';
import '../../../helpers/test_bootstrap.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseService.setTestDatabase(db);
    // Minimal table — the service uses only these columns.
    await db.execute('''
      CREATE TABLE translation_versions (
        id TEXT PRIMARY KEY,
        translated_text TEXT,
        validation_issues TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('ValidationIssuesJsonDataMigration.isApplied', () {
    test('returns false on empty DB with no marker (nothing to migrate)', () async {
      // No rows, no marker => fallback scan finds nothing => writes marker => applied.
      final migration = ValidationIssuesJsonDataMigration();
      expect(await migration.isApplied(), isTrue);
      final markers = await db.rawQuery(
          "SELECT 1 FROM _migration_markers WHERE id = 'validation_issues_json'");
      expect(markers, isNotEmpty);
    });

    test('returns true if marker is already present', () async {
      await db.execute('''
        CREATE TABLE _migration_markers (
          id TEXT PRIMARY KEY,
          applied_at INTEGER NOT NULL
        )
      ''');
      await db.insert('_migration_markers',
          {'id': 'validation_issues_json', 'applied_at': 1});
      expect(await ValidationIssuesJsonDataMigration().isApplied(), isTrue);
    });

    test('returns false when a legacy-shaped row exists', () async {
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '[legacy message]',
        'updated_at': 0,
      });
      expect(await ValidationIssuesJsonDataMigration().isApplied(), isFalse);
    });

    test('returns true (and writes marker) when all rows are already JSON', () async {
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '["msg1"]',
        'updated_at': 0,
      });
      final migration = ValidationIssuesJsonDataMigration();
      expect(await migration.isApplied(), isTrue);
      final markers = await db.rawQuery(
          "SELECT 1 FROM _migration_markers WHERE id = 'validation_issues_json'");
      expect(markers, isNotEmpty);
    });
  });
}
```

- [ ] **Step 1.2: Run tests — expect compile failure (service does not exist yet)**

Run:
```bash
/c/src/flutter/bin/flutter test test/services/database/data_migrations/validation_issues_json_data_migration_test.dart
```

Expected: compile error `Target of URI doesn't exist ... validation_issues_json_data_migration.dart`.

- [ ] **Step 1.3: Create the service file**

Create `lib/services/database/data_migrations/validation_issues_json_data_migration.dart`:

```dart
import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';

/// Post-`runApp` data migration that rewrites legacy `validation_issues`
/// payloads (Dart `List.toString()` / `Map.toString()` output) as proper
/// JSON arrays. Invoked from `DataMigration.runMigrations()`.
///
/// Ported from the pre-`runApp` `ValidationIssuesJsonMigration` to run with
/// a progress dialog and to drop cascading triggers during the rewrite for
/// orders-of-magnitude speedup on large databases.
class ValidationIssuesJsonDataMigration {
  final ILoggingService _logger;

  ValidationIssuesJsonDataMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  /// Stable identifier — reused from the old migration so existing markers
  /// in already-migrated databases short-circuit `isApplied()` on the first
  /// call.
  static const String id = 'validation_issues_json';

  static const String _markerTable = '_migration_markers';

  /// Fast-path applicability check.
  ///
  /// Order of checks:
  /// 1. Marker row present => applied.
  /// 2. No legacy-shaped row remaining => write marker and return applied.
  /// 3. Otherwise => not applied; caller should invoke `execute`.
  Future<bool> isApplied() async {
    await _ensureMarkerTable();
    final marker = await DatabaseService.database.rawQuery(
      'SELECT 1 FROM $_markerTable WHERE id = ? LIMIT 1',
      [id],
    );
    if (marker.isNotEmpty) return true;

    final legacy = await DatabaseService.database.rawQuery('''
      SELECT 1 FROM translation_versions
      WHERE validation_issues IS NOT NULL
        AND TRIM(validation_issues) <> ''
        AND validation_issues NOT LIKE '["%'
        AND validation_issues NOT LIKE '[]'
        AND validation_issues NOT LIKE '[{"%'
      LIMIT 1
    ''');
    if (legacy.isEmpty) {
      await _writeMarker();
      return true;
    }
    return false;
  }

  Future<void> _ensureMarkerTable() async {
    await DatabaseService.database.execute('''
      CREATE TABLE IF NOT EXISTS $_markerTable (
        id TEXT PRIMARY KEY,
        applied_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _writeMarker() async {
    await _ensureMarkerTable();
    await DatabaseService.database.insert(
      _markerTable,
      {'id': id, 'applied_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
```

- [ ] **Step 1.4: Run tests — expect all four in the group to pass**

Run:
```bash
/c/src/flutter/bin/flutter test test/services/database/data_migrations/validation_issues_json_data_migration_test.dart
```

Expected: 4 passed.

- [ ] **Step 1.5: Commit**

```bash
git add lib/services/database/data_migrations/validation_issues_json_data_migration.dart \
        test/services/database/data_migrations/validation_issues_json_data_migration_test.dart
git commit -m "feat: scaffold post-runApp validation_issues data migration"
```

---

## Task 2: Rewrite loop with trigger drop/recreate inside a transaction

**Goal:** Add `execute(onProgress)` that drops the three cascading triggers, rewrites legacy rows in keyset-paginated batches, and recreates the triggers — all in one transaction. No FTS rebuild, no marker write yet (Task 3).

**Files:**
- Modify: `lib/services/database/data_migrations/validation_issues_json_data_migration.dart`
- Modify: `test/services/database/data_migrations/validation_issues_json_data_migration_test.dart`

- [ ] **Step 2.1: Write the failing tests**

Append to the test file, inside `main()`, after the existing group:

```dart
  group('ValidationIssuesJsonDataMigration.execute — rewrite semantics', () {
    // Minimal schema that triggers reference. We create the 3 cascading
    // triggers before calling execute so we can assert they are restored.
    Future<void> _createCascadingContext() async {
      await db.execute('''
        CREATE TABLE translation_view_cache (
          unit_id TEXT,
          project_language_id TEXT,
          translated_text TEXT,
          status TEXT,
          confidence_score REAL,
          is_manually_edited INTEGER,
          version_id TEXT,
          version_updated_at INTEGER
        )
      ''');
      // Column set must mirror schema.sql's translation_versions enough for
      // the triggers to compile. Add the ones the triggers reference.
      await db.execute(
          'ALTER TABLE translation_versions ADD COLUMN unit_id TEXT');
      await db.execute(
          'ALTER TABLE translation_versions ADD COLUMN project_language_id TEXT');
      await db.execute(
          'ALTER TABLE translation_versions ADD COLUMN status TEXT');
      await db.execute(
          'ALTER TABLE translation_versions ADD COLUMN is_manually_edited INTEGER');
      // FTS virtual table (contentless, matches schema.sql:624-629).
      await db.execute('''
        CREATE VIRTUAL TABLE translation_versions_fts USING fts5(
          translated_text, validation_issues, version_id UNINDEXED, content=''
        )
      ''');
      // The 3 triggers the migration will drop.
      await db.execute('''
        CREATE TRIGGER trg_translation_versions_fts_update
        AFTER UPDATE OF translated_text, validation_issues ON translation_versions
        BEGIN
          DELETE FROM translation_versions_fts WHERE version_id = old.id;
          INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
          SELECT new.translated_text, new.validation_issues, new.id
          WHERE new.translated_text IS NOT NULL;
        END
      ''');
      await db.execute('''
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
      await db.execute('''
        CREATE TRIGGER trg_translation_versions_updated_at
        AFTER UPDATE ON translation_versions
        WHEN NEW.updated_at = OLD.updated_at
        BEGIN
          UPDATE translation_versions SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
        END
      ''');
    }

    test('rewrites legacy List.toString shape to JSON array', () async {
      await _createCascadingContext();
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '[msg A, msg B]',
        'updated_at': 0,
      });

      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (_, __) {},
      );

      final row = (await db.rawQuery(
          'SELECT validation_issues FROM translation_versions WHERE id = ?',
          ['v1'])).single;
      expect(jsonDecode(row['validation_issues'] as String), ['msg A', 'msg B']);
    });

    test('leaves already-JSON rows untouched', () async {
      await _createCascadingContext();
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '["already"]',
        'updated_at': 0,
      });

      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (_, __) {},
      );

      final row = (await db.rawQuery(
          'SELECT validation_issues FROM translation_versions WHERE id = ?',
          ['v1'])).single;
      expect(row['validation_issues'], '["already"]');
    });

    test('emits monotonic progress with stable total', () async {
      await _createCascadingContext();
      for (var i = 0; i < 5; i++) {
        await db.insert('translation_versions', {
          'id': 'v$i',
          'translated_text': 'hello',
          'validation_issues': '[legacy $i]',
          'updated_at': 0,
        });
      }

      final samples = <List<int>>[];
      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (p, t) => samples.add([p, t]),
      );

      expect(samples, isNotEmpty);
      expect(samples.last[0], 5);
      expect(samples.every((s) => s[1] == 5), isTrue);
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i][0], greaterThanOrEqualTo(samples[i - 1][0]));
      }
    });

    test('triggers are restored after successful run', () async {
      await _createCascadingContext();
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '[legacy]',
        'updated_at': 0,
      });

      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (_, __) {},
      );

      final triggers = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='trigger' ORDER BY name");
      final names = triggers.map((r) => r['name']).toList();
      expect(names, containsAll([
        'trg_translation_versions_fts_update',
        'trg_update_cache_on_version_change',
        'trg_translation_versions_updated_at',
      ]));
    });

    test('rewrites Map.toString payload (real-world legacy shape)', () async {
      // Observed in production logs: older code called `.toString()` on a
      // List<Map>, producing this exact unparseable shape. The heuristic
      // split on ", " fragments the message; we accept that for idempotence
      // and data preservation. Assertion is that the result is valid JSON.
      await _createCascadingContext();
      const legacy =
          '[{type: ValidationIssueType.lengthDifference, severity: ValidationSeverity.warning, autoFixable: false, autoFixValue: null}]';
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': legacy,
        'updated_at': 0,
      });

      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (_, __) {},
      );

      final raw = (await db.rawQuery(
          'SELECT validation_issues FROM translation_versions WHERE id = ?',
          ['v1'])).single['validation_issues'] as String;
      final parsed = jsonDecode(raw);
      expect(parsed, isA<List>());
      expect((parsed as List).every((e) => e is String), isTrue);
    });

    test('second execute is a no-op on already-migrated data', () async {
      await _createCascadingContext();
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '[legacy]',
        'updated_at': 0,
      });

      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (_, __) {},
      );
      final afterFirst = (await db.rawQuery(
          'SELECT validation_issues FROM translation_versions WHERE id = ?',
          ['v1'])).single['validation_issues'];

      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (_, __) {},
      );
      final afterSecond = (await db.rawQuery(
          'SELECT validation_issues FROM translation_versions WHERE id = ?',
          ['v1'])).single['validation_issues'];

      expect(afterSecond, afterFirst);
      // Already-JSON rows take the skip branch — no rewriting happens.
    });
  });
```

Also add this import at the top of the test file if not already present:

```dart
import 'dart:convert';
```

- [ ] **Step 2.2: Run tests — expect failures (method does not exist)**

Run:
```bash
/c/src/flutter/bin/flutter test test/services/database/data_migrations/validation_issues_json_data_migration_test.dart
```

Expected: new tests fail with "The method 'execute' isn't defined" or similar.

- [ ] **Step 2.3: Implement `execute()`**

Append to `lib/services/database/data_migrations/validation_issues_json_data_migration.dart`, inside the class (keep the existing members, add below them):

```dart
  /// Page size for the keyset-paginated rewrite loop. Chosen to give the
  /// progress callback ~frequent updates on a 30k-row database without
  /// incurring per-statement transaction overhead.
  static const int _batchSize = 500;

  /// Rewrite legacy payloads and restore triggers inside a single
  /// transaction. FTS rebuild and marker write are the caller's
  /// responsibility (see [executeAndFinalize]).
  Future<void> execute({
    required void Function(int processed, int total) onProgress,
  }) async {
    final db = DatabaseService.database;

    final totalRow = await db.rawQuery('''
      SELECT COUNT(*) AS cnt FROM translation_versions
      WHERE validation_issues IS NOT NULL
        AND TRIM(validation_issues) <> ''
    ''');
    final total = (totalRow.first['cnt'] as int?) ?? 0;
    if (total == 0) {
      _logger.debug('validation_issues: no candidate rows');
      onProgress(0, 0);
      return;
    }

    _logger.info('validation_issues: rewriting $total rows');

    await db.transaction((txn) async {
      for (final name in _triggerDdl.keys) {
        await txn.execute('DROP TRIGGER IF EXISTS $name');
      }

      String? cursor;
      var processed = 0;
      var splitOnCommaSamples = 0;

      while (true) {
        final whereCursor = cursor == null ? '' : 'AND id > ?';
        final args = cursor == null ? <Object?>[] : <Object?>[cursor];

        final rows = await txn.rawQuery('''
          SELECT id, validation_issues FROM translation_versions
          WHERE validation_issues IS NOT NULL
            AND TRIM(validation_issues) <> ''
            $whereCursor
          ORDER BY id
          LIMIT $_batchSize
        ''', args);

        if (rows.isEmpty) break;

        for (final row in rows) {
          final rowId = row['id'] as String;
          final raw = row['validation_issues'] as String;

          if (!_isAlreadyJson(raw)) {
            final decoded = _parseDartListToString(raw);
            if (decoded != null) {
              if (raw.contains(', ') && splitOnCommaSamples < 5) {
                splitOnCommaSamples++;
                _logger.debug(
                  'validation_issues row contained `, ` — messages may have '
                  'been split by the heuristic parser',
                  {'id': rowId, 'raw': raw},
                );
              }
              await txn.update(
                'translation_versions',
                {'validation_issues': jsonEncode(decoded)},
                where: 'id = ?',
                whereArgs: [rowId],
              );
            } else {
              _logger.warning(
                'Could not parse validation_issues; leaving as-is',
                {'id': rowId},
              );
            }
          }
          cursor = rowId;
        }

        processed += rows.length;
        onProgress(processed, total);
      }

      for (final entry in _triggerDdl.entries) {
        await txn.execute(entry.value);
      }
    });
  }

  /// DDL for the 3 triggers the rewrite drops. Copied verbatim from
  /// `schema.sql` (lines 729-737, 791-803, 877-882) minus the
  /// `IF NOT EXISTS` clause, which would silently suppress recreation
  /// failures. Trailing semicolon is omitted — SQLite's execute wraps
  /// a single statement.
  static const Map<String, String> _triggerDdl = {
    'trg_translation_versions_fts_update': '''
CREATE TRIGGER trg_translation_versions_fts_update
AFTER UPDATE OF translated_text, validation_issues ON translation_versions
BEGIN
    DELETE FROM translation_versions_fts WHERE version_id = old.id;
    INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
    SELECT new.translated_text, new.validation_issues, new.id
    WHERE new.translated_text IS NOT NULL;
END
''',
    'trg_update_cache_on_version_change': '''
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
''',
    'trg_translation_versions_updated_at': '''
CREATE TRIGGER trg_translation_versions_updated_at
AFTER UPDATE ON translation_versions
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE translation_versions SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END
''',
  };

  bool _isAlreadyJson(String raw) {
    final trimmed = raw.trimLeft();
    if (!trimmed.startsWith('[')) return false;
    try {
      return jsonDecode(raw) is List;
    } catch (_) {
      return false;
    }
  }

  /// Best-effort conversion of `List.toString()` / `Map.toString()` output
  /// into a list of string messages. Prefers a real `jsonDecode` when the
  /// payload happens to be valid JSON with non-string elements; falls back
  /// to splitting on `, ` — the exact separator `List.toString()` uses.
  /// Returns null only when the shape is unrecognizable (missing brackets).
  List<String>? _parseDartListToString(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // Fall through to heuristic split.
    }

    final inner = trimmed.substring(1, trimmed.length - 1).trim();
    if (inner.isEmpty) return <String>[];
    return inner.split(', ').map((s) => s.trim()).toList();
  }
```

- [ ] **Step 2.4: Run tests — expect all pass**

Run:
```bash
/c/src/flutter/bin/flutter test test/services/database/data_migrations/validation_issues_json_data_migration_test.dart
```

Expected: 10 passed (4 from Task 1 + 6 new).

- [ ] **Step 2.5: Commit**

```bash
git add lib/services/database/data_migrations/validation_issues_json_data_migration.dart \
        test/services/database/data_migrations/validation_issues_json_data_migration_test.dart
git commit -m "feat: rewrite legacy validation_issues via triggerless transaction"
```

---

## Task 3: FTS rebuild (best-effort) and marker write

**Goal:** Wrap the existing `execute` into a higher-level entry point that, after the transaction commits, attempts an FTS rebuild (catching and logging errors — contentless FTS5 rebuild may be unsupported) and then writes the marker row. This is what the Riverpod provider will call.

**Files:**
- Modify: `lib/services/database/data_migrations/validation_issues_json_data_migration.dart`
- Modify: `test/services/database/data_migrations/validation_issues_json_data_migration_test.dart`

- [ ] **Step 3.1: Write the failing tests**

Append to `main()` in the test file:

```dart
  group('ValidationIssuesJsonDataMigration.run — end-to-end', () {
    test('marker is written after successful run', () async {
      // No cascading context needed: `run` is only responsible for
      // delegating to execute + FTS rebuild + marker; in this test the
      // DB has no candidate rows, so the loop is a no-op.
      await ValidationIssuesJsonDataMigration().run(
        onProgress: (_, __) {},
      );
      final markers = await db.rawQuery(
          "SELECT 1 FROM _migration_markers WHERE id = 'validation_issues_json'");
      expect(markers, isNotEmpty);
    });

    test('marker still written when FTS rebuild fails', () async {
      // No FTS table exists — rebuild command will raise. Assert run
      // completes and writes the marker anyway.
      await ValidationIssuesJsonDataMigration().run(
        onProgress: (_, __) {},
      );
      final markers = await db.rawQuery(
          "SELECT 1 FROM _migration_markers WHERE id = 'validation_issues_json'");
      expect(markers, isNotEmpty);
    });
  });
```

- [ ] **Step 3.2: Run tests — expect failures (method does not exist)**

Run:
```bash
/c/src/flutter/bin/flutter test test/services/database/data_migrations/validation_issues_json_data_migration_test.dart
```

Expected: new tests fail with "The method 'run' isn't defined".

- [ ] **Step 3.3: Implement `run()`**

Append to the service class (below `execute`, above `_triggerDdl`):

```dart
  /// Top-level entry point: performs the rewrite transaction, then attempts
  /// an FTS5 rebuild (best-effort — contentless FTS5 rebuild is not always
  /// supported; stale FTS is tolerable since the field is advisory), and
  /// finally writes the marker. The marker is the last write: if any step
  /// above throws, the marker is not written and the next startup re-runs
  /// the migration.
  Future<void> run({
    required void Function(int processed, int total) onProgress,
  }) async {
    await execute(onProgress: onProgress);
    try {
      await DatabaseService.database.execute(
        "INSERT INTO translation_versions_fts(translation_versions_fts) VALUES('rebuild')",
      );
    } catch (e) {
      _logger.warning(
        'validation_issues: FTS rebuild skipped (non-fatal)',
        {'error': e.toString()},
      );
    }
    await _writeMarker();
    _logger.info('validation_issues: migration finished');
  }
```

- [ ] **Step 3.4: Run tests — expect all pass**

Run:
```bash
/c/src/flutter/bin/flutter test test/services/database/data_migrations/validation_issues_json_data_migration_test.dart
```

Expected: 12 passed.

- [ ] **Step 3.5: Commit**

```bash
git add lib/services/database/data_migrations/validation_issues_json_data_migration.dart \
        test/services/database/data_migrations/validation_issues_json_data_migration_test.dart
git commit -m "feat: add validation_issues top-level run with marker and FTS rebuild"
```

---

## Task 4: Wire into `DataMigration` Riverpod provider as step 1

**Goal:** Make the `DataMigration` provider consider the new migration in `needsMigration()` and run it first in `runMigrations()`. The existing `DataMigrationDialog` will pick up the state automatically via `state.currentStep` and `state.progressMessage`.

**Files:**
- Modify: `lib/providers/data_migration_provider.dart`

- [ ] **Step 4.1: Update `needsMigration()`**

Replace the body of `needsMigration()` (currently at `lib/providers/data_migration_provider.dart:69-74`) with:

```dart
  /// Check if any migrations are needed
  Future<bool> needsMigration() async {
    final prefs = await SharedPreferences.getInstance();
    final rebuildDone = prefs.getBool(_tmRebuildKey) ?? false;
    final hashMigrationDone = prefs.getBool(_tmHashMigrationKey) ?? false;
    final validationIssuesApplied =
        await ValidationIssuesJsonDataMigration().isApplied();
    return !rebuildDone || !hashMigrationDone || !validationIssuesApplied;
  }
```

Add the import near the other service imports at the top of the file:

```dart
import '../services/database/data_migrations/validation_issues_json_data_migration.dart';
```

- [ ] **Step 4.2: Insert step 1 in `runMigrations()`**

Inside `runMigrations()` (starts at `data_migration_provider.dart:77`), insert a new block **before** the existing "Step 1: TM Rebuild" block. Locate the line `final tmService = ref.read(translationMemoryServiceProvider);` inside the `try {` block — insert the new block immediately after it:

```dart
      // Step 1: validation_issues JSON rewrite (fast; drops triggers)
      final validationMigration = ValidationIssuesJsonDataMigration();
      if (!await validationMigration.isApplied()) {
        _logging.info('Running validation_issues JSON rewrite');
        state = state.copyWith(
          currentStep: 'Upgrading validation data...',
          progressMessage: 'Preparing...',
          currentProgress: 0,
          totalProgress: 0,
        );
        await validationMigration.run(
          onProgress: (processed, total) {
            state = state.copyWith(
              progressMessage: total == 0
                  ? 'No rows to migrate'
                  : '$processed / $total entries',
              currentProgress: processed,
              totalProgress: total,
            );
          },
        );
      }
```

Also rename the two existing step comments / log lines from "Step 1 / Step 2" to "Step 2 / Step 3" for clarity:

- `// Step 1: TM Rebuild ...` → `// Step 2: TM Rebuild ...`
- `// Step 2: TM Hash Migration ...` → `// Step 3: TM Hash Migration ...`

Do not change the step titles shown to users (`Rebuilding Translation Memory...`, `Migrating Translation Memory hashes...`) — those are user-visible and do not include a number.

- [ ] **Step 4.3: Regenerate provider code (if needed)**

This file uses `riverpod_annotation` and has a generated `.g.dart` companion. Re-run the generator:

```bash
/c/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs
```

Expected: clean run, no errors. If `data_migration_provider.g.dart` is unchanged, no new commit content will be produced — that's fine; the new class member is not a provider annotation.

- [ ] **Step 4.4: Run the existing provider tests, if any**

```bash
/c/src/flutter/bin/flutter test test/providers 2>&1 | tail -30
```

Expected: all existing tests still pass.

- [ ] **Step 4.5: Commit**

```bash
git add lib/providers/data_migration_provider.dart \
        lib/providers/data_migration_provider.g.dart
git commit -m "feat: run validation_issues data migration as step 1 of DataMigration"
```

---

## Task 5: Remove the old pre-runApp migration

**Goal:** Delete `ValidationIssuesJsonMigration` from the `MigrationRegistry` (so it no longer runs before `runApp`), remove the now-dead file, and drop any dead test.

**Files:**
- Modify: `lib/services/database/migrations/migration_registry.dart`
- Delete: `lib/services/database/migrations/migration_validation_issues_json.dart`

- [ ] **Step 5.1: Remove the import from the registry**

In `lib/services/database/migrations/migration_registry.dart`, delete this line (currently line 23):

```dart
import 'migration_validation_issues_json.dart';
```

- [ ] **Step 5.2: Remove the registry entry**

In the same file, inside `getAllMigrations()` (starting at line 37), delete the entry:

```dart
      ValidationIssuesJsonMigration(),
```

- [ ] **Step 5.3: Delete the old migration file**

```bash
rm lib/services/database/migrations/migration_validation_issues_json.dart
```

There is no existing test file for it (`find test -name 'migration_validation_issues*'` returns none as of this plan).

- [ ] **Step 5.4: Verify static analysis**

```bash
/c/src/flutter/bin/flutter analyze lib test 2>&1 | tail -30
```

Expected: no errors referencing `ValidationIssuesJsonMigration` or `migration_validation_issues_json.dart`.

- [ ] **Step 5.5: Run the full test suite**

```bash
/c/src/flutter/bin/flutter test 2>&1 | tail -20
```

Expected: all tests pass. No test references the deleted class.

- [ ] **Step 5.6: Commit**

```bash
git add lib/services/database/migrations/migration_registry.dart
git rm lib/services/database/migrations/migration_validation_issues_json.dart
git commit -m "refactor: remove pre-runApp validation_issues migration entry"
```

---

## Task 6: Manual acceptance on the real old DB

**Goal:** Verify on the imported problem database that (a) the first frame renders within 1–2 seconds, (b) the `DataMigrationDialog` appears, (c) the validation_issues step completes in seconds (not minutes), (d) subsequent launches do not show the dialog.

- [ ] **Step 6.1: Back up the test DB**

On the Windows host (adjust path if yours differs):

```powershell
Copy-Item "C:\Users\jmp\AppData\Roaming\com.github.slavyk82\twmt\twmt.db" `
         "C:\Users\jmp\AppData\Roaming\com.github.slavyk82\twmt\twmt.db.bak-preval"
```

- [ ] **Step 6.2: Launch the app**

```bash
/c/src/flutter/bin/flutter run -d windows
```

Expected in the console log:
- First frame painted within a second or two after `Application initialized successfully`.
- Log lines from `DataMigration`: `Running validation_issues JSON rewrite`, progress entries, `validation_issues: migration finished`.
- Total wall-clock time for step 1 under 15 seconds on a 33 324-row DB (target: under 10 s).

Expected on screen:
- A modal dialog titled "Database Update" with step label "Upgrading validation data..." and a progress bar advancing from 0 to 100%.
- Dialog auto-closes when step 1 finishes, then shows step 2 ("Rebuilding Translation Memory..."), then step 3.

- [ ] **Step 6.3: Quit the app and re-launch**

Expected: no dialog, no migration log lines — the app lands on its main UI immediately.

- [ ] **Step 6.4: Verify the marker row**

Query the DB with any SQLite browser (or via the app's logs if you add a debug call):

```sql
SELECT id, applied_at FROM _migration_markers WHERE id = 'validation_issues_json';
```

Expected: one row with a recent epoch-ms timestamp.

- [ ] **Step 6.5: Spot-check a rewritten row**

```sql
SELECT validation_issues FROM translation_versions
WHERE validation_issues NOT LIKE '["%'
  AND validation_issues NOT LIKE '[]'
  AND validation_issues NOT LIKE '[{"%'
  AND validation_issues IS NOT NULL
  AND TRIM(validation_issues) <> '';
```

Expected: empty result — no legacy-shaped rows left.

- [ ] **Step 6.6: If anything unexpected, restore the backup**

```powershell
Copy-Item "C:\Users\jmp\AppData\Roaming\com.github.slavyk82\twmt\twmt.db.bak-preval" `
         "C:\Users\jmp\AppData\Roaming\com.github.slavyk82\twmt\twmt.db" -Force
```

---

## Notes for the implementer

- **Flutter CLI path.** Per `CLAUDE.md`, Flutter SDK lives at `C:/src/flutter/bin`. From a WSL/bash prompt that's `/c/src/flutter/bin/flutter`; from PowerShell it's `C:\src\flutter\bin\flutter`.
- **Build_runner.** Before running the app, CLAUDE.md mandates `dart run build_runner build --delete-conflicting-outputs`. Step 4.3 performs this once.
- **Transactions and DDL in sqflite_common_ffi.** DDL (DROP/CREATE TRIGGER) inside `db.transaction(...)` is supported and atomic. If `execute()` throws, rollback restores the dropped triggers — no `try/finally` is needed in Dart.
- **Contentless FTS5 rebuild.** `INSERT INTO fts(fts) VALUES('rebuild')` may not be supported on `content=''` FTS5 tables. The `run` method catches and logs this at warning. Stale FTS is acceptable since `validation_issues` is advisory.
- **Why keyset, not OFFSET.** Keyset pagination (`WHERE id > ? ORDER BY id`) is O(N) over the whole scan. OFFSET N on a WHERE-filtered result re-walks N rows per page and is O(N²).
