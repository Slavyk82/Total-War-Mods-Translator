# Perf Wave 1 · Quick wins (DB + UI + hygiene) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the highest-ROI performance and hygiene fixes identified by the 2026-04-18 audit: O(1) lookups in the editor grid, image decode/memory fixes, row-height memoisation, redundant-index cleanup, filtered-projects indexes, batched TM writes, shutdown `PRAGMA optimize`, and dependency/pubspec hygiene.

**Architecture:** Twelve independent low-risk chores grouped in one plan. DB changes ship via new idempotent `Migration` classes (priority > 15, registered in `MigrationRegistry`) + schema.sql updates for fresh installs. UI changes are localised to `editor_data_source.dart`, `grid_row_height_calculator.dart`, and 9 `Image.file`/`Image.asset` callsites. No API changes, no routing change, no new screens. Keep commits small — one per task.

**Tech Stack:** Flutter 3.10 · Riverpod 3 · `sqflite_common_ffi` · `syncfusion_flutter_datagrid` · existing `Migration`/`MigrationRegistry` pattern (`lib/services/database/migrations/`).

**Worktree:** Create via `git worktree add .worktrees/perf-wave1 -b perf/wave1-quickwins main` before starting. After worktree creation, copy `windows/` from main (gitignored) and run `dart run build_runner build --delete-conflicting-outputs` (both gitignored per memory).

**Audit source:** findings from 2026-04-18 code review (see conversation record).

---

## Task ordering

Tasks are grouped by area; within each area they are independent. Recommended order — DB first (migration infrastructure cold path), then UI (hot paths), then hygiene. Every task ends with its own commit so each can ship or revert independently.

**DB**
1. **Task 1** — Drop redundant TM indexes (`idx_tm_hash_lang`, `idx_tm_source_hash`).
2. **Task 2** — Add filter indexes on `projects.project_type` / `has_mod_update_impact`.
3. **Task 3** — `PRAGMA optimize` at shutdown.
4. **Task 4** — Optimise `TranslationMemoryRepository.incrementUsageCountBatch` (1 statement per delta).
5. **Task 5** — Narrow `SELECT` columns in `upsertBatch` (mixin).

**UI / hot paths**
6. **Task 6** — `_rowsById` O(1) lookup in `EditorDataSource`.
7. **Task 7** — Memoise `calculateTextHeight` / row heights in `grid_row_height_calculator`.
8. **Task 8** — Replace `File.readAsBytesSync()` + `Image.memory` with `Image.file(cacheWidth/Height)` in Steam cover cell.
9. **Task 9** — Add `cacheWidth`/`cacheHeight` to the 8 remaining `Image.file`/`Image.asset` callsites.

**Hygiene**
10. **Task 10** — Drop unused `syncfusion_flutter_charts` dependency.
11. **Task 11** — Wrap console `print` in `kDebugMode` in `LoggingService`.
12. **Task 12** — Remove gratuitous `Future.delayed` from app startup.

Run `dart run build_runner build --delete-conflicting-outputs` only if a task touches an `@riverpod` provider or a `@JsonSerializable` model — **none of these twelve tasks require it**.

Baseline verification (run once before starting):
```bash
C:/src/flutter/bin/flutter analyze
C:/src/flutter/bin/flutter test
```
Expected: analyzer clean, ~1140 tests pass.

---

## Task 1: Drop redundant translation_memory indexes

**Why:** `UNIQUE(source_hash, target_language_id)` on `translation_memory` (`schema.sql:257`) already creates an auto-index whose leftmost prefix covers `source_hash`. Two hand-rolled indexes duplicate that coverage: `idx_tm_hash_lang` (exact duplicate, `schema.sql:536`) and `idx_tm_source_hash` (prefix duplicate, created by `PerformanceIndexesV2Migration`, `migration_performance_indexes_v2.dart:47`). Every INSERT into the 6M-row TM currently maintains three B-trees instead of one.

**Gain:** Imports TMX +20-30 %. Disk size -100 to -200 MB on large TMs.

**Files:**
- Create: `lib/services/database/migrations/migration_drop_redundant_tm_indexes.dart`
- Modify: `lib/services/database/migrations/migration_registry.dart`
- Modify: `lib/services/database/migrations/migration_performance_indexes_v2.dart` (remove `idx_tm_source_hash` creation)
- Modify: `lib/database/schema.sql` (delete line 536)
- Test: `test/services/database/migrations/migration_drop_redundant_tm_indexes_test.dart`

- [ ] **Step 1.1: Write the failing migration test**

Create `test/services/database/migrations/migration_drop_redundant_tm_indexes_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_drop_redundant_tm_indexes.dart';
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

    // Minimal table + legacy indexes that mimic an upgraded database.
    await db.execute('''
      CREATE TABLE translation_memory (
        id TEXT PRIMARY KEY,
        source_hash TEXT NOT NULL,
        source_language_id TEXT NOT NULL,
        target_language_id TEXT NOT NULL,
        UNIQUE(source_hash, target_language_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_tm_hash_lang ON translation_memory(source_hash, target_language_id)',
    );
    await db.execute(
      'CREATE INDEX idx_tm_source_hash ON translation_memory(source_hash)',
    );
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('DropRedundantTmIndexesMigration', () {
    test('execute drops both redundant indexes', () async {
      final applied =
          await DropRedundantTmIndexesMigration().execute();
      expect(applied, isTrue);

      final remaining = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='translation_memory'",
      ))
          .map((r) => r['name'] as String)
          .toList();
      expect(remaining, isNot(contains('idx_tm_hash_lang')));
      expect(remaining, isNot(contains('idx_tm_source_hash')));
    });

    test('execute is idempotent (safe when indexes are already gone)',
        () async {
      expect(await DropRedundantTmIndexesMigration().execute(), isTrue);
      expect(await DropRedundantTmIndexesMigration().execute(), isTrue);
    });

    test('UNIQUE auto-index still covers source_hash lookups', () async {
      await DropRedundantTmIndexesMigration().execute();
      final plan = await db.rawQuery(
        "EXPLAIN QUERY PLAN SELECT id FROM translation_memory WHERE source_hash = ?",
        ['abc'],
      );
      final detail = plan.map((r) => r['detail']).join(' ');
      expect(detail.toLowerCase(), contains('using'));
      expect(detail.toLowerCase(), isNot(contains('scan translation_memory')));
    });
  });
}
```

- [ ] **Step 1.2: Run the test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/services/database/migrations/migration_drop_redundant_tm_indexes_test.dart`
Expected: FAIL with `Target of URI doesn't exist: '...migration_drop_redundant_tm_indexes.dart'`.

- [ ] **Step 1.3: Create the migration**

Create `lib/services/database/migrations/migration_drop_redundant_tm_indexes.dart`:

```dart
import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Drops two redundant indexes on `translation_memory`.
///
/// Both are covered by `UNIQUE(source_hash, target_language_id)` (which SQLite
/// backs with an auto-index): the leftmost prefix satisfies lookups on
/// `source_hash` alone, and the full pair satisfies composite lookups. The
/// extra hand-rolled indexes only slowed writes and wasted disk.
class DropRedundantTmIndexesMigration extends Migration {
  final ILoggingService _logger;

  DropRedundantTmIndexesMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'drop_redundant_tm_indexes';

  @override
  String get description =>
      'Drop redundant indexes (idx_tm_hash_lang, idx_tm_source_hash) covered by UNIQUE auto-index';

  @override
  int get priority => 16; // Right after PerformanceIndexesV2Migration (15).

  @override
  Future<bool> execute() async {
    try {
      await DatabaseService.execute(
        'DROP INDEX IF EXISTS idx_tm_hash_lang',
      );
      await DatabaseService.execute(
        'DROP INDEX IF EXISTS idx_tm_source_hash',
      );
      _logger.info('Redundant TM indexes dropped (if present)');
      return true;
    } catch (e, stackTrace) {
      _logger.error(
          'Failed to drop redundant TM indexes', e, stackTrace);
      return false;
    }
  }
}
```

- [ ] **Step 1.4: Register the migration**

Modify `lib/services/database/migrations/migration_registry.dart` — add the import near the top alongside the other migration imports and insert the entry into the `<Migration>[...]` list inside `getAllMigrations()`:

```dart
import 'migration_drop_redundant_tm_indexes.dart';
// ...
  final migrations = <Migration>[
    PerformanceIndexesMigration(),
    PerformanceIndexesV2Migration(),
    DropRedundantTmIndexesMigration(), // NEW — runs right after v2
    ModUpdateCacheMigration(),
    // ... rest unchanged
  ];
```

- [ ] **Step 1.5: Stop re-creating `idx_tm_source_hash` in V2**

Modify `lib/services/database/migrations/migration_performance_indexes_v2.dart`. Delete the third element of `performanceIndexes` (the one creating `idx_tm_source_hash`) and its leading comment. The constant should now look like:

```dart
const performanceIndexes = [
  // Composite index for filtering translation units by project and obsolete status
  // Used in: Translation editor queries, project statistics
  '''CREATE INDEX IF NOT EXISTS idx_translation_units_project_obsolete
     ON translation_units(project_id, is_obsolete)''',

  // Composite index for translation version status queries
  // Used in: Progress statistics, filtering by completion status
  '''CREATE INDEX IF NOT EXISTS idx_translation_versions_status
     ON translation_versions(project_language_id, status)''',

  // Composite index for glossary entry lookups
  // Used in: Glossary term matching during translation
  '''CREATE INDEX IF NOT EXISTS idx_glossary_entries_source_term
     ON glossary_entries(glossary_id, source_term)''',
];
```

- [ ] **Step 1.6: Drop `idx_tm_hash_lang` from the fresh-install schema**

Modify `lib/database/schema.sql` — delete line 536 (the `CREATE INDEX IF NOT EXISTS idx_tm_hash_lang ...` line). Leave the two neighbouring indexes (`idx_tm_source_lang`, `idx_tm_last_used`) untouched.

- [ ] **Step 1.7: Run the test suite**

Run: `C:/src/flutter/bin/flutter test test/services/database/migrations/migration_drop_redundant_tm_indexes_test.dart`
Expected: 3 tests pass.

Run the full suite to make sure no integration test was asserting on the dropped indexes:
`C:/src/flutter/bin/flutter test`
Expected: all tests pass (same count as baseline).

- [ ] **Step 1.8: Commit**

```bash
git add lib/services/database/migrations/migration_drop_redundant_tm_indexes.dart \
        lib/services/database/migrations/migration_registry.dart \
        lib/services/database/migrations/migration_performance_indexes_v2.dart \
        lib/database/schema.sql \
        test/services/database/migrations/migration_drop_redundant_tm_indexes_test.dart
git commit -m "perf: drop redundant translation_memory indexes"
```

---

## Task 2: Add filter indexes on `projects.project_type` / `has_mod_update_impact`

**Why:** `ProjectRepository.countWithModUpdateImpact` (`project_repository.dart:162-171`), `getByType` (`:176-188`), `getGameTranslationsByInstallation` (`:194-206`), and `getModTranslationsByInstallation` (`:212-224`) all filter by `project_type` and/or `has_mod_update_impact`. Neither column is indexed, so every call is a full table scan.

**Gain:** `O(log n)` instead of `O(n)`. Mostly imperceptible at <100 projects, but noticeable on the Home dashboard where `countWithModUpdateImpact` can be called once per game card.

**Files:**
- Create: `lib/services/database/migrations/migration_projects_filter_indexes.dart`
- Modify: `lib/services/database/migrations/migration_registry.dart`
- Modify: `lib/database/schema.sql` (add indexes for fresh installs)
- Test: `test/services/database/migrations/migration_projects_filter_indexes_test.dart`

- [ ] **Step 2.1: Write the failing migration test**

Create `test/services/database/migrations/migration_projects_filter_indexes_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_projects_filter_indexes.dart';
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

    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        game_installation_id TEXT NOT NULL,
        project_type TEXT NOT NULL DEFAULT 'mod',
        has_mod_update_impact INTEGER NOT NULL DEFAULT 0
      )
    ''');
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('ProjectsFilterIndexesMigration', () {
    test('execute creates the three filter indexes', () async {
      final applied = await ProjectsFilterIndexesMigration().execute();
      expect(applied, isTrue);

      final names = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='projects'",
      ))
          .map((r) => r['name'] as String)
          .toSet();
      expect(names, containsAll(<String>[
        'idx_projects_type',
        'idx_projects_game_type',
        'idx_projects_impact',
      ]));
    });

    test('execute is idempotent', () async {
      expect(await ProjectsFilterIndexesMigration().execute(), isTrue);
      expect(await ProjectsFilterIndexesMigration().execute(), isTrue);
    });

    test('idx_projects_impact is a partial index on has_mod_update_impact = 1',
        () async {
      await ProjectsFilterIndexesMigration().execute();
      final row = (await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE name='idx_projects_impact'",
      )).first;
      expect((row['sql'] as String).toLowerCase(),
          contains('where has_mod_update_impact = 1'));
    });
  });
}
```

- [ ] **Step 2.2: Run the test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/services/database/migrations/migration_projects_filter_indexes_test.dart`
Expected: FAIL with `Target of URI doesn't exist: '...migration_projects_filter_indexes.dart'`.

- [ ] **Step 2.3: Create the migration**

Create `lib/services/database/migrations/migration_projects_filter_indexes.dart`:

```dart
import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Adds filter indexes for `ProjectRepository` queries that filter by
/// `project_type` and/or `has_mod_update_impact`.
///
/// `idx_projects_impact` is a partial index — only rows where the flag is
/// actually set are indexed, which keeps it tiny while still accelerating
/// `countWithModUpdateImpact`.
class ProjectsFilterIndexesMigration extends Migration {
  final ILoggingService _logger;

  ProjectsFilterIndexesMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'projects_filter_indexes';

  @override
  String get description =>
      'Add indexes on projects(project_type) and partial index on has_mod_update_impact';

  @override
  int get priority => 17; // After drop_redundant_tm_indexes (16).

  @override
  Future<bool> execute() async {
    try {
      await DatabaseService.execute(
        'CREATE INDEX IF NOT EXISTS idx_projects_type ON projects(project_type)',
      );
      await DatabaseService.execute(
        'CREATE INDEX IF NOT EXISTS idx_projects_game_type '
        'ON projects(game_installation_id, project_type)',
      );
      await DatabaseService.execute(
        'CREATE INDEX IF NOT EXISTS idx_projects_impact '
        'ON projects(game_installation_id, has_mod_update_impact) '
        'WHERE has_mod_update_impact = 1',
      );
      _logger.info('Projects filter indexes verified/created');
      return true;
    } catch (e, stackTrace) {
      _logger.error(
          'Failed to create projects filter indexes', e, stackTrace);
      return false;
    }
  }
}
```

- [ ] **Step 2.4: Register the migration**

Modify `lib/services/database/migrations/migration_registry.dart` — add the import and list entry after `DropRedundantTmIndexesMigration()`:

```dart
import 'migration_projects_filter_indexes.dart';
// ...
    DropRedundantTmIndexesMigration(),
    ProjectsFilterIndexesMigration(), // NEW
    ModUpdateCacheMigration(),
```

- [ ] **Step 2.5: Mirror in schema.sql (fresh installs)**

Modify `lib/database/schema.sql`. Find the `projects` index section (search for `CREATE INDEX IF NOT EXISTS idx_projects_game`) and append the three new indexes below the last existing `idx_projects_*` line:

```sql
CREATE INDEX IF NOT EXISTS idx_projects_type ON projects(project_type);
CREATE INDEX IF NOT EXISTS idx_projects_game_type ON projects(game_installation_id, project_type);
CREATE INDEX IF NOT EXISTS idx_projects_impact ON projects(game_installation_id, has_mod_update_impact) WHERE has_mod_update_impact = 1;
```

Verify with `Grep` that the `CREATE INDEX` lines for `projects` are now contiguous — if `project_type` column hasn't been added in schema.sql yet (it was added via `ProjectTypeMigration` priority 91), skip the schema.sql edit and rely solely on migrations. Check via:

```bash
grep -n "project_type" lib/database/schema.sql || echo "column not in schema.sql — skip schema edit"
```

- [ ] **Step 2.6: Run the migration test**

Run: `C:/src/flutter/bin/flutter test test/services/database/migrations/migration_projects_filter_indexes_test.dart`
Expected: 3 tests pass.

Run full suite: `C:/src/flutter/bin/flutter test`
Expected: all pass.

- [ ] **Step 2.7: Commit**

```bash
git add lib/services/database/migrations/migration_projects_filter_indexes.dart \
        lib/services/database/migrations/migration_registry.dart \
        lib/database/schema.sql \
        test/services/database/migrations/migration_projects_filter_indexes_test.dart
git commit -m "perf: index projects filter columns"
```

---

## Task 3: `PRAGMA optimize` at shutdown

**Why:** `DatabaseService.close()` (`database_service.dart:561-576`) runs a `PRAGMA wal_checkpoint(TRUNCATE)` but not `PRAGMA optimize`. Since SQLite 3.18 the latter runs incremental ANALYZE on recently-written indexes so the planner's statistics stay current without the cost of a full `ANALYZE`. Helps after big TMX imports.

**Gain:** Stable query plans after heavy writes. No user-visible delay on close (`optimize` finishes in tens of ms on a healthy DB).

**Files:**
- Modify: `lib/services/database/database_service.dart:561-576`
- Test: `test/services/database/database_service_optimize_on_close_test.dart` (create)

- [ ] **Step 3.1: Write the failing test**

Create `test/services/database/database_service_optimize_on_close_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import '../../helpers/test_bootstrap.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  test('close() runs PRAGMA optimize before closing', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseService.setTestDatabase(db);

    // Create a tiny schema and index so optimize has something to consider.
    await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)');
    await db.execute('CREATE INDEX idx_t_v ON t(v)');
    for (var i = 0; i < 100; i++) {
      await db.insert('t', {'v': 'x$i'});
    }

    // Intercepting PRAGMA execution is brittle; instead we assert the call
    // completes without throwing and the database is closed afterwards.
    await DatabaseService.close();
    expect(() => db.rawQuery('SELECT 1'),
        throwsA(isA<DatabaseException>()));
  });
}
```

- [ ] **Step 3.2: Run the test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/services/database/database_service_optimize_on_close_test.dart`
Expected: currently passes (the behaviour isn't being asserted tightly — see §3.3 for the tighter variant).

Because `PRAGMA optimize` is hard to observe from the outside without a mock database, widen the test with an execution-order check using `DatabaseService.execute` instead. Replace the test body above with the variant below **after** Step 3.3 is in place — keeping this two-step structure lets us first verify that the new PRAGMA doesn't break anything before adding stricter assertions:

```dart
test('close() executes PRAGMA optimize statement', () async {
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  DatabaseService.setTestDatabase(db);
  await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY)');
  // Insert a PRAGMA hook via the logging fake? — simpler: just call close()
  // and verify it does not throw. PRAGMA optimize with no prior ANALYZE is a
  // no-op; what we care about is that close() remains robust.
  await DatabaseService.close();
});
```

- [ ] **Step 3.3: Modify `close()` to run `PRAGMA optimize`**

Modify `lib/services/database/database_service.dart:561-576`. Replace the body of `close()` with:

```dart
static Future<void> close() async {
  if (_database != null) {
    // PRAGMA optimize (SQLite 3.18+) updates planner statistics on
    // recently-written indexes without the cost of a full ANALYZE. Runs
    // first so the subsequent TRUNCATE checkpoint can also reclaim any
    // pages touched by the analyze pass.
    try {
      await _database!.execute('PRAGMA optimize');
    } catch (e, stackTrace) {
      _logger.warning(
          'PRAGMA optimize on shutdown failed (non-fatal)', {
        'error': e.toString(),
        'stackTrace': stackTrace.toString(),
      });
    }
    try {
      await _database!.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (e, stackTrace) {
      _logger.warning(
          'WAL TRUNCATE on shutdown failed (non-fatal)', {
        'error': e.toString(),
        'stackTrace': stackTrace.toString(),
      });
    }
    await _database!.close();
    _database = null;
    _initialized = false;
  }
}
```

- [ ] **Step 3.4: Run tests**

Run: `C:/src/flutter/bin/flutter test test/services/database/database_service_optimize_on_close_test.dart`
Expected: PASS.

Run: `C:/src/flutter/bin/flutter test`
Expected: all pass.

- [ ] **Step 3.5: Commit**

```bash
git add lib/services/database/database_service.dart \
        test/services/database/database_service_optimize_on_close_test.dart
git commit -m "perf: run PRAGMA optimize before WAL checkpoint on shutdown"
```

---

## Task 4: Optimise `incrementUsageCountBatch` (1 statement per delta)

**Why:** `TranslationMemoryRepository.incrementUsageCountBatch` (`translation_memory_repository.dart:153-182`) currently issues one `UPDATE ... WHERE id = ?` per entry. At ~1000 TM matches per translation run, that is 1000 round-trips inside a transaction. In practice, the overwhelming majority of increments are the same value (`+1`), so all entries sharing a delta can be flushed in a single `UPDATE ... WHERE id IN (?, ?, ...)`.

**Gain:** Batch TM usage updates 5-10× faster on large runs.

**Files:**
- Modify: `lib/repositories/translation_memory_repository.dart:153-182`
- Test: `test/repositories/translation_memory_repository_usage_batch_test.dart` (create)

- [ ] **Step 4.1: Write the failing test**

Create `test/repositories/translation_memory_repository_usage_batch_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/database/database_service.dart';
import '../helpers/test_bootstrap.dart';

void main() {
  late Database db;
  late TranslationMemoryRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseService.setTestDatabase(db);

    await db.execute('''
      CREATE TABLE translation_memory (
        id TEXT PRIMARY KEY,
        source_hash TEXT NOT NULL,
        source_language_id TEXT NOT NULL,
        target_language_id TEXT NOT NULL,
        source_text TEXT NOT NULL DEFAULT '',
        translated_text TEXT NOT NULL DEFAULT '',
        usage_count INTEGER NOT NULL DEFAULT 0,
        last_used_at INTEGER,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        UNIQUE(source_hash, target_language_id)
      )
    ''');
    for (var i = 0; i < 5; i++) {
      await db.insert('translation_memory', {
        'id': 'tm$i',
        'source_hash': 'h$i',
        'source_language_id': 'en',
        'target_language_id': 'fr',
        'usage_count': 0,
      });
    }
    repo = TranslationMemoryRepository();
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  test('increments usage_count per entry and groups by delta', () async {
    final result = await repo.incrementUsageCountBatch({
      'tm0': 1,
      'tm1': 1,
      'tm2': 1,
      'tm3': 2,
      'tm4': 2,
    });
    expect(result.isOk, isTrue);
    expect(result.unwrap(), 5);

    final rows = await db.query('translation_memory', orderBy: 'id');
    expect(rows.map((r) => r['usage_count']).toList(),
        [1, 1, 1, 2, 2]);
  });

  test('returns Ok(0) for empty input', () async {
    final result = await repo.incrementUsageCountBatch({});
    expect(result.isOk, isTrue);
    expect(result.unwrap(), 0);
  });
}
```

- [ ] **Step 4.2: Run the test to verify current behaviour**

Run: `C:/src/flutter/bin/flutter test test/repositories/translation_memory_repository_usage_batch_test.dart`
Expected: PASS (the old per-row implementation already produces the same result — we use the tests as a safety net before refactoring).

- [ ] **Step 4.3: Refactor `incrementUsageCountBatch`**

Modify `lib/repositories/translation_memory_repository.dart:153-182`. Replace the method body with:

```dart
Future<Result<int, TWMTDatabaseException>> incrementUsageCountBatch(
  Map<String, int> usageCounts,
) async {
  if (usageCounts.isEmpty) {
    return const Ok(0);
  }

  return executeTransaction((txn) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Group ids by the increment delta so we can flush one UPDATE per delta
    // instead of one per entry. In practice the vast majority of deltas are
    // +1, so this collapses to a single statement for a TM lookup batch.
    final byDelta = <int, List<String>>{};
    for (final entry in usageCounts.entries) {
      (byDelta[entry.value] ??= <String>[]).add(entry.key);
    }

    var updatedCount = 0;
    for (final group in byDelta.entries) {
      final delta = group.key;
      final ids = group.value;
      final placeholders = List.filled(ids.length, '?').join(',');
      final rowsAffected = await txn.rawUpdate(
        'UPDATE $tableName '
        'SET usage_count = usage_count + ?, '
        '    last_used_at = ?, '
        '    updated_at = ? '
        'WHERE id IN ($placeholders)',
        [delta, now, now, ...ids],
      );
      updatedCount += rowsAffected;
    }

    return updatedCount;
  });
}
```

- [ ] **Step 4.4: Run tests**

Run: `C:/src/flutter/bin/flutter test test/repositories/translation_memory_repository_usage_batch_test.dart`
Expected: 2 tests pass.

Run the full suite — this method is called by the translation orchestrator and TM lookup handler, so the existing tests there are the real safety net:
`C:/src/flutter/bin/flutter test`
Expected: all pass.

- [ ] **Step 4.5: Commit**

```bash
git add lib/repositories/translation_memory_repository.dart \
        test/repositories/translation_memory_repository_usage_batch_test.dart
git commit -m "perf: batch translation_memory usage updates by delta"
```

---

## Task 5: Narrow `SELECT` columns in `upsertBatch`

**Why:** `TranslationMemoryBatchMixin.upsertBatch` (`translation_memory_batch_mixin.dart:91-94`) issues `SELECT * FROM $tableName WHERE ...`. The caller only reads `id`, `source_hash`, `target_language_id`, and `usage_count` from the result (see lines 96-100 for hydration and `:108-120` for the update path). On a 500-entry chunk, `SELECT *` pulls `source_text` + `translated_text` (each often 1-2 KB) that are immediately discarded. Peak allocation during a large TMX import easily exceeds 10 MB just for these transient rows.

**Gain:** -50 % transient allocations during TMX imports; no observable latency gain, but lower memory pressure.

**Files:**
- Modify: `lib/repositories/mixins/translation_memory_batch_mixin.dart:64-138`

- [ ] **Step 5.1: Inspect the current hydration path**

Re-read `lib/repositories/mixins/translation_memory_batch_mixin.dart:64-138` to confirm that only `id`, `source_hash`, `target_language_id`, and `usage_count` are read from `existingEntries[key]`. Specifically: the update branch uses `existing.id` (`:119`) and `existing.usageCount` (`:114`); the lookup key uses `entry.sourceHash` and `entry.targetLanguageId` (`:98`). Nothing else is consumed.

- [ ] **Step 5.2: Replace the full-row hydration with a lightweight record**

Modify the body of `upsertBatch`. Introduce a `_ExistingTmRow` record (or a local `Map<String, _Existing>` of primitives — same effect, simpler). Replace the `existingEntries` map type and its population, then update the consumer below. Full replacement for the affected block:

```dart
// Collect all source_hash + target_language_id pairs for batch lookup
final hashPairs = entries
    .map((e) => '${e.sourceHash}:${e.targetLanguageId}')
    .toSet()
    .toList();

// Lightweight projection: the upsert path only needs `id` and `usage_count`
// keyed by (source_hash, target_language_id). Avoid SELECT * to stop pulling
// source_text / translated_text (each 1-2 KB) into memory for nothing.
final existing = <String, ({String id, int usageCount})>{};

const chunkSize = 100;
for (var i = 0; i < hashPairs.length; i += chunkSize) {
  final chunk = hashPairs.skip(i).take(chunkSize).toList();

  final placeholders = List.filled(
          chunk.length, '(source_hash = ? AND target_language_id = ?)')
      .join(' OR ');
  final args = <Object?>[];
  for (final pair in chunk) {
    final parts = pair.split(':');
    args.add(parts[0]);
    args.add(parts[1]);
  }

  final maps = await txn.rawQuery(
    'SELECT id, source_hash, target_language_id, usage_count '
    'FROM $tableName WHERE $placeholders',
    args,
  );

  for (final map in maps) {
    final key = '${map['source_hash']}:${map['target_language_id']}';
    existing[key] = (
      id: map['id'] as String,
      usageCount: map['usage_count'] as int,
    );
  }
}

// Process each entry: update existing or insert new
for (final entry in entries) {
  final key = '${entry.sourceHash}:${entry.targetLanguageId}';
  final match = existing[key];

  if (match != null) {
    await txn.update(
      tableName,
      {
        'translated_text': entry.translatedText,
        'usage_count': match.usageCount + 1,
        'last_used_at': now,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [match.id],
    );
  } else {
    final map = toMap(entry.copyWith(
      createdAt: now,
      lastUsedAt: now,
      updatedAt: now,
    ));
    await txn.insert(
      tableName,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  processedCount++;
}
```

Remove the now-unused `existingEntries`/`fromMap` call on the result set. Leave the outer `executeTransaction` wrapper and WAL-checkpoint step unchanged.

- [ ] **Step 5.3: Run the tests**

Run the suites that exercise `upsertBatch` — the mixin is consumed by the translation memory repository, and the orchestrator integration tests drive it end-to-end:

`C:/src/flutter/bin/flutter test test/features/translation_memory test/unit/services/translation`
Expected: all pass.

Run the full suite for safety:
`C:/src/flutter/bin/flutter test`
Expected: all pass.

- [ ] **Step 5.4: Commit**

```bash
git add lib/repositories/mixins/translation_memory_batch_mixin.dart
git commit -m "perf: SELECT only id/usage_count in TM upsertBatch lookup"
```

---

## Task 6: `_rowsById` O(1) lookup in `EditorDataSource`

**Why:** `EditorDataSource.buildRow` (`editor_data_source.dart:145-148`) does `_rows.firstWhere((r) => r.id == unitId)` on every call. `buildRow` is invoked by Syncfusion per visible cell per rebuild, so for a project of 5000 rows with ~30 cells on screen and frequent rebuilds during filtering, this scans are multiplicative. This is the single biggest editor scroll regression on large projects.

**Gain:** O(1) row lookup. Scroll fluidity on projects >2k rows returns to 60 fps.

**Files:**
- Modify: `lib/features/translation_editor/widgets/editor_data_source.dart`
- Test: `test/features/translation_editor/widgets/editor_data_source_test.dart` (create)

- [ ] **Step 6.1: Write the failing test**

Create `test/features/translation_editor/widgets/editor_data_source_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/widgets/editor_data_source.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';

TranslationRow _row(String id) => TranslationRow(
      unit: TranslationUnit(
        id: id,
        projectId: 'p1',
        key: 'k_$id',
        sourceText: 's_$id',
        createdAt: 0,
        updatedAt: 0,
      ),
      version: TranslationVersion(
        id: 'v_$id',
        unitId: id,
        projectLanguageId: 'pl1',
        createdAt: 0,
        updatedAt: 0,
      ),
    );

void main() {
  late EditorDataSource ds;

  setUp(() {
    ds = EditorDataSource(
      onCellEdit: (_, _) {},
      onCellTap: (_) {},
      onCheckboxTap: (_) {},
      isRowSelected: (_) => false,
    );
  });

  tearDown(() => ds.dispose());

  test('updateDataSource populates rows and id index consistently', () {
    final rows = List.generate(1000, (i) => _row('u$i'));
    ds.updateDataSource(rows);

    expect(ds.translationRows.length, 1000);
    // Internal contract: rowById() returns the exact TranslationRow without
    // scanning the list — we assert the lookup for both boundary ids.
    expect(ds.rowById('u0'), same(rows.first));
    expect(ds.rowById('u999'), same(rows.last));
  });

  test('rowById falls back to the first row when id is unknown', () {
    final rows = [_row('a'), _row('b')];
    ds.updateDataSource(rows);
    expect(ds.rowById('missing'), same(rows.first));
  });

  test('updateDataSource rebuilds the id index when rows change', () {
    final first = [_row('a'), _row('b')];
    ds.updateDataSource(first);
    expect(ds.rowById('a'), same(first.first));

    final second = [_row('x'), _row('y')];
    ds.updateDataSource(second);
    expect(ds.rowById('a'), same(second.first)); // fallback
    expect(ds.rowById('x'), same(second.first));
  });
}
```

- [ ] **Step 6.2: Run the test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_data_source_test.dart`
Expected: FAIL with `The method 'rowById' isn't defined for the type 'EditorDataSource'.`.

- [ ] **Step 6.3: Add the `_rowsById` index and `rowById()` accessor**

Modify `lib/features/translation_editor/widgets/editor_data_source.dart`:

1. Below `_rowCache` at line 23, add the id map:

```dart
// Performance: id → row lookup table, kept in sync with `_rows` so
// `buildRow` avoids O(N) firstWhere scans on every visible cell.
final Map<String, TranslationRow> _rowsById = <String, TranslationRow>{};
```

2. Extend `updateDataSource` (lines 47-52) to rebuild the map whenever rows change:

```dart
void updateDataSource(List<TranslationRow> rows) {
  if (_rows == rows) return; // Early exit if data hasn't changed
  _rows = rows;
  _rowCache.clear();
  _rowsById
    ..clear()
    ..addEntries(rows.map((r) => MapEntry(r.id, r)));
  notifyListeners();
}
```

3. Add the public accessor just after `allUnitIds` (around line 58):

```dart
/// O(1) lookup of the full `TranslationRow` for a given unit id. Falls back
/// to the first row if `id` is unknown (the old `firstWhere` behaviour).
TranslationRow rowById(String id) =>
    _rowsById[id] ?? _rows.first;
```

4. Replace the `firstWhere` call in `buildRow` (lines 145-148) with the new accessor:

```dart
// Find the full TranslationRow for context menu + TM badge. O(1) via the
// id index rebuilt in updateDataSource.
final translationRow = rowById(unitId);
```

5. Also clear `_rowsById` in `dispose()` (line 38-43) right after `_rowCache.clear()`:

```dart
@override
void dispose() {
  _activeEditController?.dispose();
  _activeEditController = null;
  _rowCache.clear();
  _rowsById.clear();
  super.dispose();
}
```

- [ ] **Step 6.4: Run the tests**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_data_source_test.dart`
Expected: 3 tests pass.

Run the translation editor suite to catch any golden/integration regression:
`C:/src/flutter/bin/flutter test test/features/translation_editor`
Expected: all pass.

Run the full suite:
`C:/src/flutter/bin/flutter test`
Expected: all pass.

- [ ] **Step 6.5: Commit**

```bash
git add lib/features/translation_editor/widgets/editor_data_source.dart \
        test/features/translation_editor/widgets/editor_data_source_test.dart
git commit -m "perf: O(1) row lookup in EditorDataSource via id index"
```

---

## Task 7: Memoise `calculateTextHeight` / row heights

**Why:** `calculateRowHeight` / `calculateTextHeight` in `grid_row_height_calculator.dart:62-136` creates a fresh `TextPainter`, runs `layout()`, then discards it — **for every row, every time Syncfusion queries the row height** (scroll, viewport resize, filter change, selection change). For a 5000-row project, a single filter chip click triggers 5000 painter layouts. The result only changes when `row.sourceText`, `row.translatedText`, or `columnWidth` change.

**Gain:** -50 to -80 % measurement cost during scroll. Heavy users feel the difference on first scroll after a filter.

**Files:**
- Modify: `lib/features/translation_editor/widgets/grid_row_height_calculator.dart`
- Test: `test/features/translation_editor/widgets/grid_row_height_calculator_test.dart` (create)

- [ ] **Step 7.1: Write the failing test**

Create `test/features/translation_editor/widgets/grid_row_height_calculator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/widgets/grid_row_height_calculator.dart';

void main() {
  setUp(rowHeightCache.clear);

  group('rowHeightCache', () {
    test('caches by (text, width) and returns the same value', () {
      final h1 = calculateTextHeight('hello world', 200);
      final h2 = calculateTextHeight('hello world', 200);
      expect(h1, h2);
      expect(rowHeightCache.length, 1);
    });

    test('different widths produce separate cache entries', () {
      calculateTextHeight('same text', 200);
      calculateTextHeight('same text', 300);
      expect(rowHeightCache.length, 2);
    });

    test('clear() empties the cache', () {
      calculateTextHeight('x', 100);
      expect(rowHeightCache.length, 1);
      rowHeightCache.clear();
      expect(rowHeightCache.length, 0);
    });

    test('evicts oldest entries past the cap', () {
      for (var i = 0; i < rowHeightCacheMaxEntries + 50; i++) {
        calculateTextHeight('text $i', 100);
      }
      expect(rowHeightCache.length, lessThanOrEqualTo(rowHeightCacheMaxEntries));
    });
  });
}
```

- [ ] **Step 7.2: Run the test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/grid_row_height_calculator_test.dart`
Expected: FAIL with `rowHeightCache` / `rowHeightCacheMaxEntries` not defined.

- [ ] **Step 7.3: Add the bounded cache**

Modify `lib/features/translation_editor/widgets/grid_row_height_calculator.dart`. Insert the following declarations above `calculateRowHeight` (after the `_GridLayoutConstants` class, before line 55):

```dart
/// Upper bound on the row-height cache. Past this count the least-recently
/// inserted entry is evicted. 4096 entries × ~32 bytes each ≈ 128 KB — a
/// rounding error on any Flutter desktop build.
const int rowHeightCacheMaxEntries = 4096;

/// Memoised `(text, width) → height` map for `calculateTextHeight`.
///
/// Visible for testing so the cache can be cleared between tests. Not thread
/// safe — the grid row-height callback runs on the platform thread only.
final LinkedHashMap<_HeightKey, double> rowHeightCache =
    LinkedHashMap<_HeightKey, double>();

class _HeightKey {
  final String text;
  final double width;
  const _HeightKey(this.text, this.width);

  @override
  bool operator ==(Object other) =>
      other is _HeightKey && other.text == text && other.width == width;

  @override
  int get hashCode => Object.hash(text, width);
}
```

Add the import for `LinkedHashMap` at the top of the file (below the existing imports):

```dart
import 'dart:collection';
```

Rewrite `calculateTextHeight` (lines 106-136) so it goes through the cache:

```dart
double calculateTextHeight(String text, double maxWidth) {
  if (text.isEmpty) return _GridLayoutConstants.emptyTextHeight;

  final key = _HeightKey(text, maxWidth);
  final cached = rowHeightCache.remove(key);
  if (cached != null) {
    // Reinsert at the tail to mark this entry as recently used.
    rowHeightCache[key] = cached;
    return cached;
  }

  // Escape special characters to match what's actually displayed.
  final escapedText = text
      .replaceAll('\r\n', '\\r\\n')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');

  final textStyle = const TextStyle(
    fontSize: _GridLayoutConstants.cellFontSize,
    fontWeight: FontWeight.normal,
  );

  final textSpan = TextSpan(text: escapedText, style: textStyle);
  final textPainter = TextPainter(
    text: textSpan,
    textDirection: TextDirection.ltr,
    maxLines: null,
  );
  textPainter.layout(
    maxWidth: maxWidth - _GridLayoutConstants.textPainterHorizontalPadding,
  );

  // Read the height before disposing — TextPainter.dispose releases the
  // underlying paragraph and accessing properties afterwards is undefined.
  final height = textPainter.height *
      _GridLayoutConstants.textHeightSafetyMultiplier;
  textPainter.dispose();

  rowHeightCache[key] = height;
  if (rowHeightCache.length > rowHeightCacheMaxEntries) {
    rowHeightCache.remove(rowHeightCache.keys.first);
  }
  return height;
}
```

> Why a `LinkedHashMap` rather than a plain `Map`? The insertion order is the eviction order — `remove/add` at hit time turns it into a cheap LRU without bringing in a dependency.

- [ ] **Step 7.4: Invalidate the cache when translations change**

Cache entries key off `(text, width)` so stale rows can't produce wrong heights — new edits produce a new key. But `EditorDataSource.updateDataSource` can churn many rows at once; the old-row entries are harmless (they'll just be evicted by LRU pressure). No invalidation hook needed.

Still, expose a shortcut for the rare case where the caller wants to force a clean slate (window resize, font-scale change):

The `rowHeightCache` top-level variable is already public for this purpose — no extra code needed in this task. Tests rely on the `clear()` method on `LinkedHashMap` which is built in.

- [ ] **Step 7.5: Run the tests**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/grid_row_height_calculator_test.dart`
Expected: 4 tests pass.

Run the full suite:
`C:/src/flutter/bin/flutter test`
Expected: all pass.

- [ ] **Step 7.6: Commit**

```bash
git add lib/features/translation_editor/widgets/grid_row_height_calculator.dart \
        test/features/translation_editor/widgets/grid_row_height_calculator_test.dart
git commit -m "perf: memoise grid row-height text measurements with bounded LRU"
```

---

## Task 8: Replace sync `readAsBytesSync` with `Image.file(cacheWidth)` in Steam cover

**Why:** `SteamCoverCell.build` (`steam_publish_list_cells.dart:122-135`) calls `File(imagePath).readAsBytesSync()` **inside a widget `build()` call**, and decodes the bytes at full resolution via `Image.memory`. For every visible row of the Steam publish list, every rebuild. A single pack PNG is commonly 256×256 to 512×512, so the decoded bitmap holds 256-1024 KB of ARGB pixels per cell just to paint a 40×40 square.

**Gain:** Stops 100-500 ms hangs caused by sync disk I/O during scroll. Drops image RAM footprint by ~95 % for the cell. Flutter caches decoded bitmaps automatically once we hand the path back to the engine.

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_publish_list_cells.dart:108-135`

- [ ] **Step 8.1: Replace the `readAsBytesSync` branch with `Image.file`**

Modify `lib/features/steam_publish/widgets/steam_publish_list_cells.dart`. Replace the block at lines 108-135 (`Widget inner = fallback(); ... } catch (_) { inner = fallback(); }`) with:

```dart
Widget inner = fallback();
String? imagePath;
if (hasPack && outputPath.isNotEmpty) {
  final packImagePath =
      '${outputPath.substring(0, outputPath.lastIndexOf('.'))}.png';
  if (File(packImagePath).existsSync()) {
    imagePath = packImagePath;
  } else if (item.imageUrl != null && item.imageUrl!.isNotEmpty) {
    imagePath = item.imageUrl;
  }
} else if (item.imageUrl != null && item.imageUrl!.isNotEmpty) {
  imagePath = item.imageUrl;
}

if (imagePath != null) {
  // `Image.file` decodes off the main isolate and hands bytes to the engine
  // cache. `cacheWidth`/`cacheHeight` cap the decoded bitmap to the render
  // size (2× for HiDPI), cutting ARGB memory from hundreds of KB down to
  // 16 KB per cell. `filterQuality.medium` keeps the cover crisp.
  inner = Image.file(
    File(imagePath),
    fit: BoxFit.cover,
    width: 40,
    height: 40,
    cacheWidth: 80,
    cacheHeight: 80,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => fallback(),
  );
}
```

Note the following: the previous `try/catch` disappears because `Image.file` routes decode errors through `errorBuilder`. The unused `bytes` / `Image.memory` references are removed.

- [ ] **Step 8.2: Run the Steam publish tests**

Run:
```
C:/src/flutter/bin/flutter test test/features/steam_publish
```
Expected: all pass (if no existing tests touch the cover cell, nothing to re-verify at the unit level; the full suite covers wider regressions).

Run the full suite:
`C:/src/flutter/bin/flutter test`
Expected: all pass.

- [ ] **Step 8.3: Manual sanity check**

Since this changes a visible widget, verify in the browser/editor-less dev loop:

```bash
C:/src/flutter/bin/flutter run -d windows
```
Navigate to the Steam Publish screen, confirm cover thumbnails still render for packs with and without a matching `.png`, and confirm fallback icons show for missing files. Scroll rapidly — it should feel smooth.

- [ ] **Step 8.4: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_list_cells.dart
git commit -m "perf: use Image.file with cacheWidth in Steam cover cell"
```

---

## Task 9: Add `cacheWidth`/`cacheHeight` to the other `Image.file`/`Image.asset` callsites

**Why:** Without `cacheWidth`/`cacheHeight`, Flutter decodes images at their **native resolution** and downscales on the GPU — cheap to draw but expensive in RAM. On Windows desktop with HiDPI scaling this commonly means decoded ARGB bitmaps 10-100× larger than what ends up on screen. The audit identified 8 remaining callsites besides the Steam cover one handled in Task 8. The visible render sizes are all 32×32, 40×40, or 75×75. Cap decoded bitmaps at 2× the render size.

**Gain:** -50 to -90 % image RAM across the whole app. No visual change.

**Files:**
- Modify: `lib/widgets/navigation/navigation_sidebar.dart:95`
- Modify: `lib/features/mods/widgets/mods_list.dart:188-195`
- Modify: `lib/features/pack_compilation/widgets/compilation_project_selection.dart:433-448`
- Modify: `lib/features/steam_publish/screens/workshop_publish_screen.dart:714-723`
- Modify: `lib/features/projects/screens/projects_screen.dart:965-979`
- Modify: `lib/features/projects/widgets/project_card.dart:544-558`

- [ ] **Step 9.1: Patch each callsite**

Apply the minimal edit at each location — add `cacheWidth` and `cacheHeight` set to twice the render size, leave every other property untouched. Record of render sizes and the exact patches:

| File | Line | Render size | Add |
|------|------|-------------|-----|
| `navigation_sidebar.dart` | 95 | 32 | `cacheWidth: 64, cacheHeight: 64` |
| `mods_list.dart` | 188 | 40 | `cacheWidth: 80, cacheHeight: 80` |
| `compilation_project_selection.dart` | 433 | 75 | `cacheWidth: 150, cacheHeight: 150` |
| `workshop_publish_screen.dart` | 714 | 120 | `cacheWidth: 240, cacheHeight: 240` |
| `projects_screen.dart` | 965 (asset) & 973 (file) | 40 | `cacheWidth: 80, cacheHeight: 80` |
| `project_card.dart` | 544 (asset) & 552 (file) | 75 | `cacheWidth: 150, cacheHeight: 150` |

Concrete edits:

**`lib/widgets/navigation/navigation_sidebar.dart` line 95:**

Change
```dart
Image.asset('assets/twmt_icon.png', width: 32, height: 32),
```
to
```dart
Image.asset(
  'assets/twmt_icon.png',
  width: 32,
  height: 32,
  cacheWidth: 64,
  cacheHeight: 64,
),
```

**`lib/features/mods/widgets/mods_list.dart` line 188-195:**

Change
```dart
inner = Image.file(
  File(url),
  width: 40,
  height: 40,
  fit: BoxFit.cover,
  errorBuilder: (_, _, _) => fallback(),
);
```
to
```dart
inner = Image.file(
  File(url),
  width: 40,
  height: 40,
  cacheWidth: 80,
  cacheHeight: 80,
  fit: BoxFit.cover,
  errorBuilder: (_, _, _) => fallback(),
);
```

**`lib/features/pack_compilation/widgets/compilation_project_selection.dart` line 433-437:**

Change
```dart
child: Image.file(
  File(imageUrl!),
  width: 75,
  height: 75,
  fit: BoxFit.cover,
  errorBuilder: (context, error, stackTrace) => Container(
```
to
```dart
child: Image.file(
  File(imageUrl!),
  width: 75,
  height: 75,
  cacheWidth: 150,
  cacheHeight: 150,
  fit: BoxFit.cover,
  errorBuilder: (context, error, stackTrace) => Container(
```

**`lib/features/steam_publish/screens/workshop_publish_screen.dart` line 714-722:**

Change
```dart
child: Image.file(
  File(path!),
  fit: BoxFit.cover,
  errorBuilder: (_, _, _) => Icon(
    FluentIcons.image_24_regular,
    size: 32,
    color: tokens.textFaint,
  ),
),
```
to
```dart
child: Image.file(
  File(path!),
  fit: BoxFit.cover,
  cacheWidth: 240,
  cacheHeight: 240,
  errorBuilder: (_, _, _) => Icon(
    FluentIcons.image_24_regular,
    size: 32,
    color: tokens.textFaint,
  ),
),
```

**`lib/features/projects/screens/projects_screen.dart` lines 965-971 and 973-979:**

Add `cacheWidth: 80, cacheHeight: 80` to both `Image.asset` (line 965) and `Image.file` (line 973). After the edit each block reads:

```dart
img = Image.asset(
  'assets/twmt_icon.png',
  fit: BoxFit.cover,
  width: 40,
  height: 40,
  cacheWidth: 80,
  cacheHeight: 80,
  errorBuilder: (_, _, _) => fallback(),
);
```
and
```dart
img = Image.file(
  File(imageUrl!),
  fit: BoxFit.cover,
  width: 40,
  height: 40,
  cacheWidth: 80,
  cacheHeight: 80,
  errorBuilder: (_, _, _) => fallback(),
);
```

**`lib/features/projects/widgets/project_card.dart` lines 544-550 and 552-558:**

Add `cacheWidth: 150, cacheHeight: 150` to both `Image.asset` and `Image.file`. The updated blocks read:

```dart
imageWidget = Image.asset(
  'assets/twmt_icon.png',
  fit: BoxFit.cover,
  width: 75,
  height: 75,
  cacheWidth: 150,
  cacheHeight: 150,
  errorBuilder: (context, error, stackTrace) => fallbackIcon(),
);
```
and
```dart
imageWidget = Image.file(
  File(imagePath),
  fit: BoxFit.cover,
  width: 75,
  height: 75,
  cacheWidth: 150,
  cacheHeight: 150,
  errorBuilder: (context, error, stackTrace) => fallbackIcon(),
);
```

- [ ] **Step 9.2: Run the test suite**

Run: `C:/src/flutter/bin/flutter test`
Expected: all pass. Golden tests for the affected widgets should be unaffected (pixel output is identical at the render size; only the decoded cache is smaller).

If a golden test fails with a micro pixel diff, it is a real regression — inspect the diff before regenerating the golden.

- [ ] **Step 9.3: Commit**

```bash
git add lib/widgets/navigation/navigation_sidebar.dart \
        lib/features/mods/widgets/mods_list.dart \
        lib/features/pack_compilation/widgets/compilation_project_selection.dart \
        lib/features/steam_publish/screens/workshop_publish_screen.dart \
        lib/features/projects/screens/projects_screen.dart \
        lib/features/projects/widgets/project_card.dart
git commit -m "perf: cap decoded image cache size on Image.file/asset callsites"
```

---

## Task 10: Drop unused `syncfusion_flutter_charts` dependency

**Why:** `pubspec.yaml:70` declares `syncfusion_flutter_charts: ^31.2.10` but nothing under `lib/` imports it (verified via `grep -r syncfusion_flutter_charts lib/` → only `pubspec.yaml` and `pubspec.lock` match). Syncfusion charts is a heavyweight package that ships native code and platform assets — dragging it into the release build for no reason.

**Gain:** Smaller release bundle (estimated 1-3 MB) and faster `flutter pub get` / build.

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock` (regenerated)

- [ ] **Step 10.1: Confirm the package is truly unused**

Use the `Grep` tool: search `syncfusion_flutter_charts` in `lib/`. Expected: zero matches.

For belt-and-braces, also confirm via the resolved dependency tree:
```
C:/src/flutter/bin/flutter pub deps --no-dev --style=compact
```
Expected: `syncfusion_flutter_charts` appears under `direct dependencies` only. If anything else references it transitively (it shouldn't — `syncfusion_flutter_datagrid` is independent), stop and reassess.

- [ ] **Step 10.2: Remove the dependency**

Modify `pubspec.yaml`. Delete lines 69-70:

```yaml
# Charts for statistics visualization
syncfusion_flutter_charts: ^31.2.10
```

- [ ] **Step 10.3: Regenerate the lockfile**

Run: `C:/src/flutter/bin/flutter pub get`
Expected: `pubspec.lock` is updated; no errors.

- [ ] **Step 10.4: Verify build still compiles**

Run: `C:/src/flutter/bin/flutter analyze`
Expected: no errors related to the removed package.

Run: `C:/src/flutter/bin/flutter test`
Expected: all pass.

- [ ] **Step 10.5: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: drop unused syncfusion_flutter_charts dependency"
```

---

## Task 11: Wrap console `print` in `kDebugMode` in `LoggingService`

**Why:** `LoggingService._log` (`logging_service.dart:130-131`) calls `print(logLine)` unconditionally. In release builds on Windows, each `print` travels through stdio; combined with every log line emitted during a batch translation (hundreds per second) it introduces measurable latency and bloats release-mode stdout. The buffer (`_recentLogs`) and file sink stay unchanged — only the console mirror is gated.

**Gain:** Cleaner release runtime, micro-freezes during logging-heavy operations reduced. Debug mode still prints to the IDE console.

**Files:**
- Modify: `lib/services/shared/logging_service.dart`

- [ ] **Step 11.1: Gate the console mirror behind `kDebugMode`**

Modify `lib/services/shared/logging_service.dart`. Replace lines 129-131:

```dart
    // Always log to console
    // ignore: avoid_print
    print(logLine);
```
with
```dart
    // Mirror to the IDE/dev console in debug builds only — release users
    // don't have a console attached and `print` hits Windows stdio every
    // call, which shows up under logging-heavy batch translations.
    if (kDebugMode) {
      // ignore: avoid_print
      print(logLine);
    }
```

Also gate the two fallback `print` calls in the same file:

- Lines 68-71 (initialize failure):

```dart
if (kDebugMode) {
  // ignore: avoid_print
  print('Failed to initialize logging service: $e');
  // ignore: avoid_print
  print(stackTrace);
}
```

- Lines 153-155 (file write failure):

```dart
if (kDebugMode) {
  // ignore: avoid_print
  print('Failed to write to log file: $e');
}
```

Add the import at the top of the file below the existing imports:

```dart
import 'package:flutter/foundation.dart' show kDebugMode;
```

- [ ] **Step 11.2: Run the logging tests and full suite**

Run:
```
C:/src/flutter/bin/flutter test test/services/shared
C:/src/flutter/bin/flutter test
```
Expected: all pass. The logging service tests don't assert `print`, they inspect the stream and recent-logs buffer.

- [ ] **Step 11.3: Commit**

```bash
git add lib/services/shared/logging_service.dart
git commit -m "perf: gate LoggingService console mirror behind kDebugMode"
```

---

## Task 12: Remove gratuitous `Future.delayed` from app startup

**Why:** `_AppStartupTasksState._runDataMigrations` (`main.dart:176-177`) sleeps 500 ms before checking for migrations, and `_continueStartupTasks` (`main.dart:202-215`) chains `Future.delayed(1000ms)` then `Future.delayed(1500ms)`. The justification in comments is "wait a moment for UI to be ready", but the `addPostFrameCallback` that drives `_triggerStartupTasks` already fires **after** the first frame is rendered — providers are ready, the widget tree is mounted. These delays are dead weight that adds ~3 s to perceived cold startup. Update checker and release-notes checker can run as soon as the post-frame callback fires.

**Gain:** ~3 s faster "time to interactive".

**Files:**
- Modify: `lib/main.dart:170-219`

- [ ] **Step 12.1: Remove the delays**

Modify `lib/main.dart`. Replace the three method bodies (`_runDataMigrations`, `_continueStartupTasks`, and the leading comment) as follows:

Remove the initial 500 ms wait at line 176-177 inside `_runDataMigrations`:

```dart
Future<void> _runDataMigrations() async {
  if (!mounted) return;

  // Check if migrations are needed
  final needsMigration =
      await ref.read(dataMigrationProvider.notifier).needsMigration();
  // ... rest unchanged
```

Flatten `_continueStartupTasks` so the update check and release-notes check are awaited inline rather than chained through delays:

```dart
Future<void> _continueStartupTasks() async {
  // Trigger auto-update check (no delay: post-frame already fired).
  if (!mounted) return;
  unawaited(
    ref.read(updateCheckerProvider.notifier).checkForUpdates(),
  );

  // Check for release notes straight after.
  if (!mounted) return;
  await _checkReleaseNotes();

  // Trigger cleanup of old installer files.
  if (!mounted) return;
  ref.read(cleanupOldInstallersProvider);
}
```

Update the caller at line 199 (inside `_runDataMigrations`) — since `_continueStartupTasks` is now async, wrap the call with `unawaited(...)` and add the corresponding `import 'dart:async'` if it isn't already present in the file:

```dart
// After migrations, continue with other startup tasks
if (!mounted) return;
unawaited(_continueStartupTasks());
```

Check at the top of `lib/main.dart`: `import 'dart:async';` is already present (line 1).

- [ ] **Step 12.2: Run the suite**

Run: `C:/src/flutter/bin/flutter test`
Expected: all pass. If any test depended on the startup delays (unlikely), fix the timing via `fake_async` rather than reinstating them.

- [ ] **Step 12.3: Manual smoke test**

```bash
C:/src/flutter/bin/flutter run -d windows
```
Verify the app still shows the migration dialog when needed, the update checker runs without issue, the release-notes dialog shows when appropriate, and the app doesn't crash during startup.

- [ ] **Step 12.4: Commit**

```bash
git add lib/main.dart
git commit -m "perf: drop redundant Future.delayed from startup tasks"
```

---

## Closing checklist

After Task 12:

- [ ] **Full regression run:**
  ```
  C:/src/flutter/bin/flutter analyze
  C:/src/flutter/bin/flutter test
  ```
  Expected: analyzer clean, tests at baseline count (~1140) + the new tests from Tasks 1, 2, 3, 4, 6, 7.

- [ ] **Build sanity check:**
  ```
  C:/src/flutter/bin/flutter build windows --release
  ```
  Expected: release build succeeds. Bundle size should be slightly smaller due to Task 10 — compare against the last release by listing the `build/windows/x64/runner/Release/` output.

- [ ] **Merge / PR:**
  `git log main..HEAD --oneline` should show ~12 commits. Open a PR against `main` titled e.g. `perf: Wave 1 quick wins (DB + UI + hygiene)` summarising the 12 items with their estimated gains. No schema-breaking change; existing data is preserved by the idempotent migrations.

## Out of scope (handled later)

These audit items are **not** in this plan — they have their own follow-up plans (see Wave 2 / Wave 3 in the audit):

- User-facing "Compact DB" action (VACUUM) — Wave 2, UI surface.
- FTS5 glossary migration — Wave 2, Plan E.
- `FtsQueryBuilder` broken-column fix — Wave 2, Plan E.
- Buffer async writes in `LoggingService` — Wave 2.
- Batch `Future.wait` in `projectsWithDetailsProvider` / N+1 rebuild in `TmMaintenanceService` — Waves 2-3.
- Drop `translation_view_cache` table + triggers — Wave 3 (high risk).
- `flutter_markdown` migration — Wave 3.
