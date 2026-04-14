# TWMT Incremental Refactoring Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the technical debt identified in the 2026-04-12 audit (DB performance ceilings, hybrid DI, god files in the editor, zero tests on critical services) through incremental refactoring — without a full rewrite. The app must remain fully functional after every task.

**Architecture:** Five cumulative phases, each producing a mergeable, shippable state. Phase 1 delivers immediate perf gains with near-zero risk. Phase 2 unblocks testability. Phase 3 unifies DI. Phase 4 fragments the editor god files. Phase 5 adds tests on critical services (only possible after Phase 2 unlocks injectable logging). TDD is used where applicable; pure-refactor tasks rely on pre-existing tests acting as guardrails.

**Tech Stack:** Flutter Desktop Windows (SDK 3.10), Dart 3.x, Riverpod 3.0.3 with `riverpod_annotation` (code-gen), `sqflite_common_ffi` 2.4.0, GoRouter 14, Freezed via `json_serializable`, `get_it` 9 (being phased out in Phase 3), `mocktail` 1 for tests.

**Build commands reminder:**
- Generate code: `dart run build_runner build --delete-conflicting-outputs`
- Run app (debug): `flutter run -d windows`
- Run tests: `flutter test`
- Flutter SDK path: `C:/src/flutter/bin`

---

## File Structure Overview

### Phase 1 — DB performance (files touched)
- Modify: `lib/config/database_config.dart` (lines 122-141 — pragma config)
- Modify: `lib/repositories/mixins/translation_memory_batch_mixin.dart` (wire checkpoint)
- Modify: `lib/services/translation_memory/tm_search_service.dart` (lines 146-198 — remove in-memory fallback)
- Modify: `lib/services/translation_memory/tm_import_export_service.dart` (lines ~100-120 — stream export)
- Create: `test/unit/config/database_config_test.dart`
- Create: `test/unit/services/translation_memory/tm_search_service_test.dart`

### Phase 2 — Logging injectable (files touched)
- Create: `lib/services/shared/i_logging_service.dart` (new interface)
- Modify: `lib/services/shared/logging_service.dart` (implement interface, remove singleton pattern gradually)
- Modify: `lib/services/locators/core_service_locator.dart` (register as ILoggingService)
- Create: `lib/providers/shared/logging_providers.dart` (Riverpod provider)
- Create: `test/helpers/mock_logging_service.dart` (shared mock)
- Modify: ~141 sites using `LoggingService.instance` across `lib/services/**` and `lib/repositories/**` (migrated in 3 batches)

### Phase 3 — DI unification (files touched)
- Modify: `lib/providers/shared/repository_providers.dart` (replace manual wrappers with @riverpod)
- Create: `lib/providers/shared/repository_providers.g.dart` (generated)
- Modify: `lib/features/glossary/**` and other features using `ServiceLocator.get` directly (migrate to ref.watch)
- Modify: `lib/services/service_locator.dart` (keep, but shrink surface — keep only non-Riverpod-friendly services like DB init)

### Phase 4 — Editor fragmentation (files touched)
- Modify: `lib/features/translation_editor/providers/editor_providers.dart` (split into 3-4 focused notifiers)
- Create: `lib/features/translation_editor/providers/editor_filter_notifier.dart`
- Create: `lib/features/translation_editor/providers/editor_selection_notifier.dart`
- Create: `lib/features/translation_editor/providers/grid_data_notifier.dart`
- Modify: `lib/features/translation_editor/widgets/editor_datagrid.dart` (split into grid frame + cell renderer + toolbar)
- Create: `lib/features/translation_editor/widgets/editor_grid_frame.dart`
- Create: `lib/features/translation_editor/widgets/editor_cell_renderer.dart`
- Create: `lib/features/translation_editor/widgets/editor_toolbar.dart`

### Phase 5 — Critical service tests (files touched)
- Create: `test/unit/services/translation_memory/tm_search_service_test.dart` (extended)
- Create: `test/unit/services/steam/workshop_publish_service_test.dart`
- Create: `test/unit/services/translation/translation_orchestration_service_test.dart`
- Create: `test/unit/services/llm/llm_provider_test.dart`

---

## PHASE 1 — Database Performance (~2-3 days)

**Goal of this phase:** Eliminate the known DB performance cliffs (small cache, missing mmap, in-memory fallback that OOMs at 10M+ rows) without changing schema or data model. App must be shippable after each commit.

### Task 1.1: Add benchmark of current pragma settings (baseline measurement)

**Files:**
- Create: `docs/benchmarks/database_benchmark.md` (notes file, not a test)

- [ ] **Step 1: Run the app on a realistic DB and record three numbers.**

Open app in debug mode with current DB (`flutter run -d windows`). Open the Translation Memory screen, trigger a TM search on a common term (e.g., "cost"). Record in `docs/benchmarks/database_benchmark.md`:

```markdown
# DB Performance Baseline — 2026-04-12

## Before Phase 1 pragma changes
- cache_size: -2000 (2 MB)
- mmap_size: not set (default 0)
- TM row count: <fill in from TM screen stats>
- TM FTS5 search on common term "cost": <ms from logs>
- App memory after opening 10 recent projects: <MB from Task Manager>
- App startup to first editable project: <seconds>
```

- [ ] **Step 2: Commit the baseline.**

```bash
mkdir -p docs/benchmarks
git add docs/benchmarks/database_benchmark.md
git commit -m "docs: record DB performance baseline before Phase 1 refactoring"
```

### Task 1.2: Increase SQLite cache_size and add mmap_size

**Files:**
- Modify: `lib/config/database_config.dart` lines 122-141
- Create: `test/unit/config/database_config_test.dart`

- [ ] **Step 1: Write the failing test for pragma values.**

Create `test/unit/config/database_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/config/database_config.dart';

void main() {
  group('DatabaseConfig.getPragmaStatements', () {
    test('uses 64 MB cache_size for 6M+ row scalability', () {
      final pragmas = DatabaseConfig.getPragmaStatements();
      expect(
        pragmas.any((p) => p.contains('cache_size = -64000')),
        true,
        reason: 'cache_size should be -64000 (64 MB) for TM workloads',
      );
    });

    test('enables mmap_size of 256 MB for kernel-level page cache', () {
      final pragmas = DatabaseConfig.getPragmaStatements();
      expect(
        pragmas.any((p) => p.contains('mmap_size = 268435456')),
        true,
        reason: 'mmap_size should be 256 MB (268435456 bytes)',
      );
    });

    test('still includes WAL journal mode and foreign keys', () {
      final pragmas = DatabaseConfig.getPragmaStatements();
      expect(pragmas, contains('PRAGMA journal_mode = WAL'));
      expect(pragmas, contains('PRAGMA foreign_keys = ON'));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `C:/src/flutter/bin/flutter test test/unit/config/database_config_test.dart`
Expected: FAIL — "cache_size should be -64000" and "mmap_size should be 256 MB"

- [ ] **Step 3: Update the pragma statements.**

In `lib/config/database_config.dart`, replace the `connectionConfig` map (lines 122-129) and `getPragmaStatements()` method (lines 132-141) with:

```dart
  /// Database connection configuration
  static const Map<String, dynamic> connectionConfig = {
    'journal_mode': 'WAL',
    'foreign_keys': true,
    'synchronous': 'NORMAL',
    'temp_store': 'MEMORY',
    'cache_size': -64000, // 64 MB cache (tuned for 6M+ TM rows)
    'mmap_size': 268435456, // 256 MB memory-mapped I/O (kernel page cache)
    'busy_timeout': 30000,
  };

  /// Get database connection configuration as PRAGMA statements
  static List<String> getPragmaStatements() {
    return [
      'PRAGMA foreign_keys = ON',
      'PRAGMA journal_mode = WAL',
      'PRAGMA synchronous = NORMAL',
      'PRAGMA temp_store = MEMORY',
      'PRAGMA cache_size = -64000',
      'PRAGMA mmap_size = 268435456',
      'PRAGMA busy_timeout = 30000',
    ];
  }
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `C:/src/flutter/bin/flutter test test/unit/config/database_config_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Manual smoke test.**

Run: `C:/src/flutter/bin/flutter run -d windows`
Open the app, navigate to the TM screen, do a search. Verify no errors in the console and the search still returns results. Record new FTS5 search latency in `docs/benchmarks/database_benchmark.md` under an "After Task 1.2" section.

- [ ] **Step 6: Commit.**

```bash
git add lib/config/database_config.dart test/unit/config/database_config_test.dart docs/benchmarks/database_benchmark.md
git commit -m "perf: raise SQLite cache_size to 64MB and enable 256MB mmap"
```

### Task 1.3: Wire automatic WAL checkpoint into TM batch writes

**Files:**
- Modify: `lib/repositories/mixins/translation_memory_batch_mixin.dart`

- [ ] **Step 1: Read the current batch mixin to find the insertion entry point.**

Read `lib/repositories/mixins/translation_memory_batch_mixin.dart` in full. Identify the method that performs `upsertBatch` (should be near line 52 per audit). Locate the point right after the transaction commits successfully.

- [ ] **Step 2: Add the checkpoint call after successful batch commit.**

At the end of the `upsertBatch` method (or equivalent bulk write entry point), after the transaction returns its count but before the method returns, add:

```dart
    // Opportunistic WAL checkpoint to prevent unbounded WAL file growth
    // during long batch imports. 1 MB threshold keeps the WAL small without
    // checkpointing after every trivial batch.
    await DatabaseService.checkpointIfNeeded(thresholdBytes: 1048576);
```

Add the import at the top of the file if not already present:

```dart
import '../../services/database/database_service.dart';
```

- [ ] **Step 3: Run existing tests to ensure no regression.**

Run: `C:/src/flutter/bin/flutter test test/unit/repositories/`
Expected: all repository tests still pass (or same pass/fail state as before).

- [ ] **Step 4: Manual smoke test — import a real project.**

Run the app, import a `.pack` file large enough to trigger a batch TM write (a Total War localisation file with a few thousand strings). Check logs (Settings → Terminal) for `WAL checkpoint completed` messages. Verify the file `%APPDATA%\com.github.slavyk82\twmt\twmt.db-wal` stays below ~5 MB during and after the import.

- [ ] **Step 5: Commit.**

```bash
git add lib/repositories/mixins/translation_memory_batch_mixin.dart
git commit -m "perf: checkpoint WAL after TM batch writes to cap growth"
```

### Task 1.4: Replace in-memory TM search fallback with streamed LIKE query

**Files:**
- Modify: `lib/services/translation_memory/tm_search_service.dart` lines 129-198
- Modify: `lib/repositories/translation_memory_repository.dart` (add `searchByLike` method)
- Create: `test/unit/services/translation_memory/tm_search_service_test.dart`

- [ ] **Step 1: Write a failing test verifying no getAll() fallback happens.**

Create `test/unit/services/translation_memory/tm_search_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/tm_search_service.dart';

class _MockRepo extends Mock implements TranslationMemoryRepository {}
class _FakeLogger extends Fake implements LoggingService {
  @override void debug(String m, [dynamic d]) {}
  @override void warning(String m, [dynamic d]) {}
  @override void info(String m, [dynamic d]) {}
  @override void error(String m, [dynamic e, StackTrace? s]) {}
}

void main() {
  late _MockRepo repo;
  late _FakeLogger logger;
  late TmSearchService service;

  setUp(() {
    repo = _MockRepo();
    logger = _FakeLogger();
    service = TmSearchService(repository: repo, logger: logger);
  });

  group('TmSearchService.searchEntries — FTS5 failure path', () {
    test('falls back to LIKE query, never to getAll() in-memory scan', () async {
      // Arrange: FTS5 search returns an error
      when(() => repo.searchFts5(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => Err(TWMTDatabaseException('FTS5 down')));

      when(() => repo.searchByLike(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const Ok([]));

      // Act
      final result = await service.searchEntries(searchText: 'hello');

      // Assert: getAll() must NOT have been called (OOM hazard at 6M rows)
      verifyNever(() => repo.getAll());
      verify(() => repo.searchByLike(
            searchText: 'hello',
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).called(1);
      expect(result.isOk, true);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation_memory/tm_search_service_test.dart`
Expected: FAIL — `repo.searchByLike` does not exist yet, and `getAll()` is still called.

- [ ] **Step 3: Add `searchByLike` method to the repository.**

In `lib/repositories/translation_memory_repository.dart`, add this method inside the class (below `getAll()`):

```dart
  /// LIKE-based fallback search used when FTS5 is unavailable.
  ///
  /// Uses indexed columns with bounded LIMIT — streaming, not in-memory scan.
  /// Not as fast as FTS5 BM25 but O(n) with early termination via LIMIT,
  /// not O(n) with full table load into RAM.
  Future<Result<List<TranslationMemoryEntry>, TWMTDatabaseException>>
      searchByLike({
    required String searchText,
    required String searchScope,
    String? targetLanguageId,
    int limit = 50,
  }) async {
    return executeQuery(() async {
      final pattern = '%${searchText.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      final whereClauses = <String>[];
      final args = <Object?>[];

      if (searchScope == 'source' || searchScope == 'both') {
        whereClauses.add('source_text LIKE ? ESCAPE ?');
        args.addAll([pattern, r'\']);
      }
      if (searchScope == 'target' || searchScope == 'both') {
        whereClauses.add('translated_text LIKE ? ESCAPE ?');
        args.addAll([pattern, r'\']);
      }

      var where = '(${whereClauses.join(' OR ')})';
      if (targetLanguageId != null) {
        where = '$where AND target_language_id = ?';
        args.add(targetLanguageId);
      }

      final maps = await database.query(
        tableName,
        where: where,
        whereArgs: args,
        orderBy: 'usage_count DESC',
        limit: limit,
      );

      return maps.map(fromMap).toList();
    });
  }
```

- [ ] **Step 4: Replace the in-memory fallback with the LIKE call.**

In `lib/services/translation_memory/tm_search_service.dart`, replace the body of `_searchEntriesInMemory` (lines 150-198) with a delegation to the repository's LIKE search, and rename the method for clarity:

Replace lines 129-198 (the entire block from `return _searchEntriesInMemory(` through the closing brace of `_searchEntriesInMemory`) with:

```dart
      return _searchEntriesWithLike(
        searchText: searchText,
        searchIn: searchIn,
        targetLanguageId: targetLanguageId,
        limit: limit,
      );
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error searching entries: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Bounded LIKE fallback when FTS5 fails.
  ///
  /// Streams from the DB with LIMIT instead of loading all rows into RAM.
  /// Safe at 6M+ rows.
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>>
      _searchEntriesWithLike({
    required String searchText,
    required TmSearchScope searchIn,
    String? targetLanguageId,
    required int limit,
  }) async {
    try {
      final searchScope = switch (searchIn) {
        TmSearchScope.source => 'source',
        TmSearchScope.target => 'target',
        TmSearchScope.both => 'both',
      };

      final result = await _repository.searchByLike(
        searchText: searchText,
        searchScope: searchScope,
        targetLanguageId: targetLanguageId,
        limit: limit,
      );

      if (result.isErr) {
        return Err(
          TmServiceException(
            'LIKE fallback failed: ${result.error}',
            error: result.error,
          ),
        );
      }
      return Ok(result.value);
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error in LIKE fallback: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
```

- [ ] **Step 5: Run the test to verify it passes.**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation_memory/tm_search_service_test.dart`
Expected: PASS (1 test)

- [ ] **Step 6: Run full test suite to check for regressions.**

Run: `C:/src/flutter/bin/flutter test`
Expected: all tests pass (or match pre-change pass count).

- [ ] **Step 7: Commit.**

```bash
git add lib/repositories/translation_memory_repository.dart lib/services/translation_memory/tm_search_service.dart test/unit/services/translation_memory/tm_search_service_test.dart
git commit -m "perf: replace in-memory TM search fallback with streamed LIKE query"
```

### Task 1.5: Stream the TM export instead of loading everything into RAM

**Files:**
- Modify: `lib/services/translation_memory/tm_import_export_service.dart` (around line 100-120)
- Modify: `lib/repositories/translation_memory_repository.dart` (add cursor-style pagination helper)

- [ ] **Step 1: Read the current export implementation.**

Read `lib/services/translation_memory/tm_import_export_service.dart` around lines 90-130 to locate the `getAll()` call used for export. Identify the output format (TMX, JSON, CSV).

- [ ] **Step 2: Add a paginated reader to the repository.**

In `lib/repositories/translation_memory_repository.dart`, add a method that returns entries in chunks:

```dart
  /// Stream TM entries in fixed-size pages. Caller is responsible for writing
  /// each chunk to disk before requesting the next page — this avoids loading
  /// the full TM into RAM (500+ MB at 6M rows).
  Future<Result<List<TranslationMemoryEntry>, TWMTDatabaseException>>
      getPage({
    required int offset,
    required int pageSize,
    String? targetLanguageId,
  }) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: targetLanguageId != null ? 'target_language_id = ?' : null,
        whereArgs: targetLanguageId != null ? [targetLanguageId] : null,
        orderBy: 'id ASC',
        limit: pageSize,
        offset: offset,
      );
      return maps.map(fromMap).toList();
    });
  }
```

- [ ] **Step 3: Refactor the export to use page-based streaming.**

In `lib/services/translation_memory/tm_import_export_service.dart`, replace the `await _repository.getAll()` call in the export method with a loop that pages through results and writes to the output file incrementally. The exact shape depends on the current code; the pattern is:

```dart
    const pageSize = 5000;
    int offset = 0;
    int totalExported = 0;

    while (true) {
      final pageResult = await _repository.getPage(
        offset: offset,
        pageSize: pageSize,
        targetLanguageId: targetLanguageId,
      );
      if (pageResult.isErr) {
        return Err(/* wrap the error in the service-level exception */);
      }
      final page = pageResult.value;
      if (page.isEmpty) break;

      await _writeChunkToOutput(page, sink); // existing serialization logic, called per-chunk
      totalExported += page.length;
      offset += pageSize;
    }
```

Where `_writeChunkToOutput` is extracted from the existing full-list serialization: take the loop body that iterates over the `getAll()` result and wrap it in a method that accepts a chunk and the output sink.

- [ ] **Step 4: Manual smoke test — export the full TM.**

Run the app. Navigate to TM → Export. Export all entries. Verify:
- The file is created and valid (open in a text editor, check the format is intact).
- Memory usage during export stays well below the size of the full TM (Task Manager → Memory column should show incremental growth capped, not a spike to 500+ MB).
- The row count in the exported file matches the TM stats.

- [ ] **Step 5: Commit.**

```bash
git add lib/repositories/translation_memory_repository.dart lib/services/translation_memory/tm_import_export_service.dart
git commit -m "perf: stream TM export in 5k chunks to avoid loading full TM in RAM"
```

### Phase 1 completion checkpoint

- [ ] **App manually tested:** Open the app, run a TM search, import a project, export TM. Everything works.
- [ ] **All tests pass:** `C:/src/flutter/bin/flutter test` returns zero failures.
- [ ] **Record post-Phase-1 benchmark:** Add an "After Phase 1" section to `docs/benchmarks/database_benchmark.md` with the three numbers from Task 1.1.

---

## PHASE 2 — Logging injectable (~3-5 days)

**Goal of this phase:** Replace the 141 uses of `LoggingService.instance` (a static singleton that blocks testability of every service that uses it) with an injectable `ILoggingService`. This is a prerequisite for Phase 5 (testing critical services).

### Task 2.1: Extract the ILoggingService interface

**Files:**
- Create: `lib/services/shared/i_logging_service.dart`
- Modify: `lib/services/shared/logging_service.dart`

- [ ] **Step 1: Write a failing test that expects the interface to exist.**

Create `test/unit/services/shared/i_logging_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/shared/logging_service.dart';

void main() {
  test('LoggingService implements ILoggingService', () {
    final svc = LoggingService.instance;
    expect(svc, isA<ILoggingService>());
  });

  test('ILoggingService exposes the four log levels', () {
    final svc = LoggingService.instance as ILoggingService;
    // Should not throw — just check call sites compile and don't crash
    svc.debug('test');
    svc.info('test');
    svc.warning('test');
    svc.error('test');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `C:/src/flutter/bin/flutter test test/unit/services/shared/i_logging_service_test.dart`
Expected: FAIL — `ILoggingService` does not exist yet.

- [ ] **Step 3: Create the interface file.**

Create `lib/services/shared/i_logging_service.dart`:

```dart
/// Abstraction for the logging service.
///
/// Allows injection via Riverpod / GetIt and substitution with a mock or
/// no-op implementation in tests. The concrete [LoggingService] implements
/// this interface.
abstract class ILoggingService {
  void debug(String message, [dynamic data]);
  void info(String message, [dynamic data]);
  void warning(String message, [dynamic data]);
  void error(String message, [dynamic error, StackTrace? stackTrace]);
}
```

- [ ] **Step 4: Make LoggingService implement the interface.**

In `lib/services/shared/logging_service.dart`, add the import and the `implements` clause. Change line 52 from:

```dart
class LoggingService {
```

to:

```dart
class LoggingService implements ILoggingService {
```

Add at the top:

```dart
import 'i_logging_service.dart';
```

The existing method signatures already match the interface — no other changes needed.

- [ ] **Step 5: Run the test to verify it passes.**

Run: `C:/src/flutter/bin/flutter test test/unit/services/shared/i_logging_service_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 6: Commit.**

```bash
git add lib/services/shared/i_logging_service.dart lib/services/shared/logging_service.dart test/unit/services/shared/i_logging_service_test.dart
git commit -m "refactor: extract ILoggingService interface from LoggingService"
```

### Task 2.2: Register ILoggingService in GetIt and add a Riverpod provider

**Files:**
- Modify: `lib/services/locators/core_service_locator.dart`
- Create: `lib/providers/shared/logging_providers.dart`
- Create: `test/helpers/mock_logging_service.dart`

- [ ] **Step 1: Read the current registration in CoreServiceLocator.**

Read `lib/services/locators/core_service_locator.dart`. Locate where `LoggingService` is currently registered (likely via its concrete type).

- [ ] **Step 2: Register LoggingService under the ILoggingService interface type.**

Wherever `LoggingService` is registered in `core_service_locator.dart`, change:

```dart
locator.registerSingleton<LoggingService>(LoggingService.instance);
```

to:

```dart
locator.registerSingleton<ILoggingService>(LoggingService.instance);
locator.registerSingleton<LoggingService>(LoggingService.instance); // temporary — removed in Task 2.4
```

(Registering both during the migration lets the 141 existing callers keep working until they migrate.)

Add the import at the top:

```dart
import '../shared/i_logging_service.dart';
```

- [ ] **Step 3: Create the Riverpod provider.**

Create `lib/providers/shared/logging_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/service_locator.dart';
import '../../services/shared/i_logging_service.dart';

/// Riverpod provider for the application logger.
///
/// Delegates to the ServiceLocator-registered singleton during the DI
/// migration. After Phase 3, this will become the primary access point.
final loggingServiceProvider = Provider<ILoggingService>((ref) {
  return ServiceLocator.get<ILoggingService>();
});
```

- [ ] **Step 4: Create a reusable mock for tests.**

Create `test/helpers/mock_logging_service.dart`:

```dart
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

/// Mock logger for unit and widget tests.
///
/// Example:
/// ```dart
/// final logger = MockLoggingService();
/// // Pass to system-under-test, then verify log calls:
/// verify(() => logger.error(any())).called(1);
/// ```
class MockLoggingService extends Mock implements ILoggingService {}

/// Silent no-op logger for tests that do not care about log output.
class NoopLoggingService implements ILoggingService {
  @override void debug(String message, [dynamic data]) {}
  @override void info(String message, [dynamic data]) {}
  @override void warning(String message, [dynamic data]) {}
  @override void error(String message, [dynamic error, StackTrace? stackTrace]) {}
}
```

- [ ] **Step 5: Run full test suite to check nothing broke.**

Run: `C:/src/flutter/bin/flutter test`
Expected: same pass/fail state as before Task 2.1.

- [ ] **Step 6: Commit.**

```bash
git add lib/services/locators/core_service_locator.dart lib/providers/shared/logging_providers.dart test/helpers/mock_logging_service.dart
git commit -m "refactor: register ILoggingService in GetIt and add Riverpod provider"
```

### Task 2.3: Migrate batch 1 — repositories and database services

**Files:**
- Modify: all files under `lib/repositories/**/*.dart`
- Modify: all files under `lib/services/database/*.dart`

- [ ] **Step 1: List all affected files.**

Run from the repo root:

```bash
grep -rl "LoggingService.instance" lib/repositories lib/services/database
```

Note: expect ~20-30 files in this batch.

- [ ] **Step 2: Add logger constructor parameter to each affected class.**

For each file, replace the pattern:

```dart
// BEFORE
import '../services/shared/logging_service.dart';

class FooRepository extends BaseRepository<...> {
  ...
  void someMethod() {
    LoggingService.instance.info('something');
  }
}
```

with:

```dart
// AFTER
import '../services/service_locator.dart';
import '../services/shared/i_logging_service.dart';

class FooRepository extends BaseRepository<...> {
  final ILoggingService _logger;
  FooRepository({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();
  ...
  void someMethod() {
    _logger.info('something');
  }
}
```

The `logger ?? ServiceLocator.get<...>()` default keeps the class constructible by existing callers (GetIt factory, manual instantiation) during the migration. Task 2.5 removes the default once every construction site passes a logger explicitly. Remove the now-unused `import '../services/shared/logging_service.dart';` line if no direct references to the concrete class remain.

- [ ] **Step 3: Run tests for each migrated file.**

Run: `C:/src/flutter/bin/flutter test test/unit/repositories/`
Expected: all existing repository tests still pass.

- [ ] **Step 4: Check no remaining `LoggingService.instance` calls in the batch.**

```bash
grep -rn "LoggingService.instance" lib/repositories lib/services/database
```

Expected: no matches.

- [ ] **Step 5: Commit.**

```bash
git add lib/repositories lib/services/database
git commit -m "refactor: inject ILoggingService into repositories and database services"
```

### Task 2.4: Migrate batch 2 — business services

**Files:**
- Modify: all files under `lib/services/translation`, `lib/services/translation_memory`, `lib/services/file`, `lib/services/llm`, `lib/services/validation`, `lib/services/glossary`, `lib/services/rpfm`, `lib/services/steam`, `lib/services/mods`

- [ ] **Step 1: List the affected files.**

```bash
grep -rl "LoggingService.instance" lib/services | grep -v "lib/services/shared\|lib/services/locators\|lib/services/database\|lib/services/service_locator.dart"
```

- [ ] **Step 2: Apply the same constructor-injection pattern.**

Follow the same pattern as Task 2.3: add `ILoggingService` as a constructor parameter with a fallback to `ServiceLocator.get<ILoggingService>()`.

For services whose constructor is called from a locator file (`lib/services/locators/*.dart`), update the locator to pass the logger explicitly:

```dart
// In e.g. lib/services/locators/translation_service_locator.dart
locator.registerLazySingleton<SomeTranslationService>(
  () => SomeTranslationService(
    logger: locator<ILoggingService>(),
    // ... other deps
  ),
);
```

- [ ] **Step 3: Run full test suite.**

Run: `C:/src/flutter/bin/flutter test`
Expected: all existing tests still pass.

- [ ] **Step 4: Commit.**

```bash
git add lib/services
git commit -m "refactor: inject ILoggingService into business services"
```

### Task 2.5: Migrate batch 3 — providers, features, widgets

**Files:**
- Modify: all remaining files under `lib/providers`, `lib/features`, `lib/widgets`

- [ ] **Step 1: List the affected files.**

```bash
grep -rl "LoggingService.instance" lib/providers lib/features lib/widgets
```

- [ ] **Step 2: Migrate to the Riverpod provider.**

For providers and widgets, replace:

```dart
LoggingService.instance.info('msg');
```

with:

```dart
ref.read(loggingServiceProvider).info('msg');
```

Adding:

```dart
import '../../providers/shared/logging_providers.dart';
```

For widgets that are not ConsumerWidgets, convert them to ConsumerWidget/ConsumerStatefulWidget if they need logging, or pass the logger through the constructor.

- [ ] **Step 3: Verify no remaining `LoggingService.instance` except in the service itself.**

```bash
grep -rn "LoggingService.instance" lib/ | grep -v "lib/services/shared/logging_service.dart\|lib/services/locators/core_service_locator.dart"
```

Expected: no matches.

- [ ] **Step 4: Remove the fallback constructor defaults in services.**

Now that every construction site passes the logger explicitly, remove the `logger ?? ServiceLocator.get<ILoggingService>()` default from every service constructor modified in Tasks 2.3 and 2.4. Make `logger` required.

- [ ] **Step 5: Remove the duplicate GetIt registration.**

In `lib/services/locators/core_service_locator.dart`, remove the line:

```dart
locator.registerSingleton<LoggingService>(LoggingService.instance);
```

keeping only the `ILoggingService` registration.

- [ ] **Step 6: Run full test suite and manually smoke-test the app.**

Run: `C:/src/flutter/bin/flutter test`
Expected: all pass.

Run the app (`C:/src/flutter/bin/flutter run -d windows`). Open the Terminal panel (Settings → Terminal or equivalent) and verify log lines still appear in real time during normal interactions (opening a project, running a TM search).

- [ ] **Step 7: Commit.**

```bash
git add lib/
git commit -m "refactor: complete ILoggingService injection in providers and UI"
```

### Phase 2 completion checkpoint

- [ ] **Zero static logger calls:** `grep -rn "LoggingService.instance" lib/` returns matches only inside `logging_service.dart` and `core_service_locator.dart`.
- [ ] **All tests pass.**
- [ ] **App manually tested:** logs flow normally to the file at `%APPDATA%\...\logs\` and to the in-app terminal panel.

---

## PHASE 3 — DI Unification (~3-4 days)

**Goal of this phase:** Eliminate the `ServiceLocator.get<T>()` wrappers in `repository_providers.dart` and the direct `GetIt.instance<T>()` / `ServiceLocator.get<T>()` calls scattered in the UI. After this phase, the UI layer only uses Riverpod.

### Task 3.1: Convert repository_providers.dart to @riverpod code generation

**Files:**
- Modify: `lib/providers/shared/repository_providers.dart`
- Auto-generate: `lib/providers/shared/repository_providers.g.dart`

- [ ] **Step 1: Rewrite the file using @riverpod annotations.**

Replace the entire content of `lib/providers/shared/repository_providers.dart` with:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../models/domain/game_installation.dart';
import '../../models/domain/language.dart';
import '../../repositories/compilation_repository.dart';
import '../../repositories/game_installation_repository.dart';
import '../../repositories/language_repository.dart';
import '../../repositories/project_language_repository.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/translation_unit_repository.dart';
import '../../repositories/translation_version_repository.dart';
import '../../repositories/workshop_mod_repository.dart';
import '../../services/service_locator.dart';

part 'repository_providers.g.dart';

@Riverpod(keepAlive: true)
ProjectRepository projectRepository(ProjectRepositoryRef ref) =>
    ServiceLocator.get<ProjectRepository>();

@Riverpod(keepAlive: true)
ProjectLanguageRepository projectLanguageRepository(
        ProjectLanguageRepositoryRef ref) =>
    ServiceLocator.get<ProjectLanguageRepository>();

@Riverpod(keepAlive: true)
LanguageRepository languageRepository(LanguageRepositoryRef ref) =>
    ServiceLocator.get<LanguageRepository>();

@Riverpod(keepAlive: true)
GameInstallationRepository gameInstallationRepository(
        GameInstallationRepositoryRef ref) =>
    ServiceLocator.get<GameInstallationRepository>();

@Riverpod(keepAlive: true)
CompilationRepository compilationRepository(CompilationRepositoryRef ref) =>
    ServiceLocator.get<CompilationRepository>();

@Riverpod(keepAlive: true)
TranslationVersionRepository translationVersionRepository(
        TranslationVersionRepositoryRef ref) =>
    ServiceLocator.get<TranslationVersionRepository>();

@Riverpod(keepAlive: true)
TranslationUnitRepository translationUnitRepository(
        TranslationUnitRepositoryRef ref) =>
    ServiceLocator.get<TranslationUnitRepository>();

@Riverpod(keepAlive: true)
WorkshopModRepository workshopModRepository(WorkshopModRepositoryRef ref) =>
    ServiceLocator.get<WorkshopModRepository>();

@riverpod
Future<List<Language>> allLanguages(AllLanguagesRef ref) async {
  final langRepo = ref.watch(languageRepositoryProvider);
  final result = await langRepo.getAll();
  if (result.isErr) {
    throw Exception('Failed to load languages: ${result.unwrapErr().message}');
  }
  return result.unwrap();
}

@riverpod
Future<List<Language>> activeLanguages(ActiveLanguagesRef ref) async {
  final langRepo = ref.watch(languageRepositoryProvider);
  final result = await langRepo.getActive();
  if (result.isErr) {
    throw Exception('Failed to load languages');
  }
  return result.unwrap();
}

@riverpod
Future<List<GameInstallation>> allGameInstallations(
    AllGameInstallationsRef ref) async {
  final gameRepo = ref.watch(gameInstallationRepositoryProvider);
  final result = await gameRepo.getAll();
  if (result.isErr) {
    throw Exception('Failed to load game installations');
  }
  return result.unwrap();
}
```

- [ ] **Step 2: Generate the code.**

Run: `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs`
Expected: `repository_providers.g.dart` is regenerated without errors.

- [ ] **Step 3: Run the full test suite.**

Run: `C:/src/flutter/bin/flutter test`
Expected: all tests pass (the provider names remain the same — `projectRepositoryProvider` etc.).

- [ ] **Step 4: Manual smoke test.**

Run the app and navigate through several screens that read projects, languages, game installations. Everything should load normally.

- [ ] **Step 5: Commit.**

```bash
git add lib/providers/shared/repository_providers.dart lib/providers/shared/repository_providers.g.dart
git commit -m "refactor: migrate repository providers to @riverpod code generation"
```

### Task 3.2: Remove direct ServiceLocator / GetIt calls in the UI layer

**Files:**
- Modify: all UI files under `lib/features/` and `lib/widgets/` that still reference `ServiceLocator.get` or `GetIt.instance`

- [ ] **Step 1: List the offenders.**

```bash
grep -rn "ServiceLocator.get\|GetIt.instance" lib/features lib/widgets
```

Expected: a modest list (the audit flagged `game_translation_providers.dart` and `GlossaryScreen` specifically).

- [ ] **Step 2: Create missing Riverpod providers for each service used this way.**

For each service `XyzService` that UI code fetches via `ServiceLocator.get<XyzService>()`, add a provider to `lib/providers/shared/` in an appropriate file (e.g., `service_providers.dart`):

```dart
@Riverpod(keepAlive: true)
XyzService xyzService(XyzServiceRef ref) =>
    ServiceLocator.get<XyzService>();
```

Regenerate code: `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 3: Replace UI call sites.**

In each UI file, replace:

```dart
final svc = ServiceLocator.get<XyzService>();
```

with (inside a ConsumerWidget or ConsumerStatefulWidget):

```dart
final svc = ref.watch(xyzServiceProvider);
```

For StatefulWidgets that are not Consumer-aware, convert them to ConsumerStatefulWidget.

- [ ] **Step 4: Verify no more direct locator calls in UI.**

```bash
grep -rn "ServiceLocator.get\|GetIt.instance" lib/features lib/widgets
```

Expected: no matches.

- [ ] **Step 5: Run tests + manual smoke test.**

Run: `C:/src/flutter/bin/flutter test`
Expected: all pass.

Manually interact with the features that were migrated (Glossary screen, Game translation, etc.).

- [ ] **Step 6: Commit.**

```bash
git add lib/
git commit -m "refactor: remove direct ServiceLocator calls from UI layer"
```

### Task 3.3: Decision checkpoint — keep GetIt for infrastructure only

**Files:**
- Modify: (notes only — no code change in this task)
- Create: `docs/architecture/dependency_injection.md`

- [ ] **Step 1: Document the final DI strategy.**

Create `docs/architecture/dependency_injection.md`:

```markdown
# Dependency Injection Strategy (post-Phase-3)

## Two layers, two tools

**Infrastructure layer (GetIt via ServiceLocator):**
- DatabaseService (singleton, tied to `dart:io` lifecycle)
- Repositories (hold a DB reference, need app-wide singleton lifetime)
- Core services instantiated at app startup before Riverpod is available

**Application layer (Riverpod):**
- All UI providers (features/, widgets/)
- All business-logic orchestration that composes repositories
- Future services — new services default to Riverpod unless they must exist before the ProviderScope

## Bridge

`lib/providers/shared/repository_providers.dart` and related files expose
every ServiceLocator-registered dependency as a Riverpod provider. UI code
must never call ServiceLocator directly.

## Why keep GetIt at all?

The DB and some OS-level integrations (SteamCmdManager, RpfmService) need
deterministic initialization order at app startup, before Riverpod's
ProviderScope wraps the widget tree. GetIt handles that cleanly.
```

- [ ] **Step 2: Commit the doc.**

```bash
git add docs/architecture/dependency_injection.md
git commit -m "docs: document hybrid GetIt+Riverpod DI strategy"
```

### Phase 3 completion checkpoint

- [ ] **UI only uses Riverpod:** `grep -rn "ServiceLocator.get\|GetIt.instance" lib/features lib/widgets` returns zero.
- [ ] **All tests pass.**
- [ ] **App works end-to-end manually.**

---

## PHASE 4 — Editor fragmentation (~2-3 weeks)

**Goal of this phase:** Break `editor_providers.dart` (749 lines) and `editor_datagrid.dart` (669 lines) into focused units. This is the largest phase and carries the most regression risk because the editor is the core UX of the app.

> **Sub-plan required.** Before starting Phase 4, re-read `lib/features/translation_editor/providers/editor_providers.dart` and `lib/features/translation_editor/widgets/editor_datagrid.dart` in full. They may have evolved since the 2026-04-12 audit. Write a detailed sub-plan at `docs/superpowers/plans/2026-05-XX-editor-fragmentation.md` before touching code, using the brainstorming + writing-plans skills. The bullets below are the skeleton; the sub-plan fills in exact class boundaries and method signatures.

### Task 4.1: Baseline — characterisation tests for the editor

**Files:**
- Create: `test/features/translation_editor/editor_characterisation_test.dart`

- [ ] **Step 1: Write widget tests that capture the current observable editor behaviour.**

These are not TDD tests — they lock in current behaviour so the refactor cannot silently break it. Cover at minimum:
- Opening a project language loads rows in the grid.
- Editing a cell fires an update and reflects in the grid.
- Filtering by status narrows the displayed rows.
- Selecting multiple rows and using the toolbar action (e.g., "mark reviewed") updates them all.

Use the existing screen-level test pattern from `test/features/translation_editor/screens/translation_editor_screen_test.dart`.

- [ ] **Step 2: Run and confirm all pass on current code.**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/`

- [ ] **Step 3: Commit.**

```bash
git add test/features/translation_editor/editor_characterisation_test.dart
git commit -m "test: add characterisation tests for translation editor pre-fragmentation"
```

### Task 4.2: Extract EditorFilterNotifier

**Files:**
- Create: `lib/features/translation_editor/providers/editor_filter_notifier.dart`
- Modify: `lib/features/translation_editor/providers/editor_providers.dart`

- [ ] **Step 1: Identify the filter-related state and methods in editor_providers.dart.**

Read `editor_providers.dart`. Locate the `EditorFilter` class and every provider / notifier method that reads or mutates it.

- [ ] **Step 2: Move the filter class, its state, and its notifier into the new file.**

Create `lib/features/translation_editor/providers/editor_filter_notifier.dart` with the extracted state class and a `@riverpod class EditorFilterNotifier` that owns it. Copy the exact state fields and methods — do not refactor behaviour.

- [ ] **Step 3: Re-export from editor_providers.dart for backwards compatibility.**

At the top of `editor_providers.dart`, replace the now-moved code with:

```dart
export 'editor_filter_notifier.dart';
```

- [ ] **Step 4: Regenerate code and run characterisation tests.**

Run: `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs`
Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/`
Expected: all characterisation tests still pass.

- [ ] **Step 5: Commit.**

```bash
git add lib/features/translation_editor/providers/
git commit -m "refactor: extract EditorFilterNotifier from editor_providers"
```

### Task 4.3: Extract EditorSelectionNotifier

**Files:**
- Create: `lib/features/translation_editor/providers/editor_selection_notifier.dart`
- Modify: `lib/features/translation_editor/providers/editor_providers.dart`

- [ ] **Step 1: Identify the selection-related state and methods in editor_providers.dart.**

Read `editor_providers.dart` again. Locate the `EditorSelection` class (or equivalent) and every provider / notifier method that reads or mutates it. Typical shape: a set of selected row IDs, range-select helpers, last-selected-row tracking.

- [ ] **Step 2: Move the selection class, its state, and its notifier into the new file.**

Create `lib/features/translation_editor/providers/editor_selection_notifier.dart`. Copy the extracted state class (e.g., `EditorSelection`) and create a `@riverpod class EditorSelectionNotifier` that owns it. Copy methods verbatim — do not refactor behaviour.

- [ ] **Step 3: Re-export from editor_providers.dart.**

Remove the now-moved code from `editor_providers.dart` and add near the top:

```dart
export 'editor_selection_notifier.dart';
```

- [ ] **Step 4: Regenerate code and run characterisation tests.**

Run: `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs`
Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/`
Expected: all characterisation tests still pass.

- [ ] **Step 5: Commit.**

```bash
git add lib/features/translation_editor/providers/
git commit -m "refactor: extract EditorSelectionNotifier from editor_providers"
```

### Task 4.4: Extract GridDataNotifier

**Files:**
- Create: `lib/features/translation_editor/providers/grid_data_notifier.dart`
- Modify: `lib/features/translation_editor/providers/editor_providers.dart`

- [ ] **Step 1: Identify the grid-data state in editor_providers.dart.**

Read `editor_providers.dart`. Locate the code that materialises translation rows (joins `TranslationUnit` + `TranslationVersion` into the `TranslationRow` view model flagged by the audit), the grid's data source, and any caching of materialised rows.

- [ ] **Step 2: Move the grid data class, its state, and its notifier into the new file.**

Create `lib/features/translation_editor/providers/grid_data_notifier.dart`. Move the `TranslationRow` class out of `editor_providers.dart` into this file (the audit flagged it as being in the wrong location). Create a `@riverpod class GridDataNotifier` that owns the row materialisation. Copy methods verbatim.

- [ ] **Step 3: Re-export from editor_providers.dart.**

Remove the moved code and add near the top:

```dart
export 'grid_data_notifier.dart';
```

- [ ] **Step 4: Regenerate code and run characterisation tests.**

Run: `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs`
Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/`
Expected: all characterisation tests still pass.

- [ ] **Step 5: Commit.**

```bash
git add lib/features/translation_editor/providers/
git commit -m "refactor: extract GridDataNotifier and TranslationRow from editor_providers"
```

### Task 4.5: Split editor_datagrid.dart into three widgets

**Files:**
- Create: `lib/features/translation_editor/widgets/editor_grid_frame.dart`
- Create: `lib/features/translation_editor/widgets/editor_cell_renderer.dart`
- Create: `lib/features/translation_editor/widgets/editor_toolbar.dart`
- Modify: `lib/features/translation_editor/widgets/editor_datagrid.dart`

- [ ] **Step 1: Read editor_datagrid.dart and identify three responsibilities.**

Per the audit, the 669 lines mix: grid rendering, cell editing/cell renderers, toolbar actions, undo/redo, glossary lookup.

- [ ] **Step 2: Extract the toolbar first (lowest coupling).**

Move the toolbar widget tree (whatever Row or Ribbon holds the action buttons) into `editor_toolbar.dart` as a `ConsumerWidget`. Keep the exact public API via the parent screen.

- [ ] **Step 3: Extract the cell renderer.**

Move cell-specific build/edit logic into `editor_cell_renderer.dart`.

- [ ] **Step 4: Keep the grid frame in editor_datagrid.dart but slim it down.**

What remains in `editor_datagrid.dart` should be only the grid shell — `SfDataGrid` or equivalent setup — delegating to the new widgets.

- [ ] **Step 5: Run characterisation tests after each extraction.**

After each of the three extractions, run:
```bash
C:/src/flutter/bin/flutter test test/features/translation_editor/
```

Commit after each extraction with its own message.

### Phase 4 completion checkpoint

- [ ] **editor_providers.dart is under 250 lines** (or re-exports only).
- [ ] **editor_datagrid.dart is under 300 lines.**
- [ ] **All characterisation tests still pass.**
- [ ] **Manual smoke test:** open a project language, edit cells, filter, select, apply batch actions, use undo/redo. Everything works.

---

## PHASE 5 — Tests on critical services (~ongoing, 1-2 weeks for the core set)

**Goal of this phase:** Raise coverage of the highest-value services from zero to a working safety net. Only possible after Phase 2 (injectable logger) unblocks mocking.

### Task 5.1: TmSearchService — full test coverage

**Files:**
- Modify: `test/unit/services/translation_memory/tm_search_service_test.dart` (started in Task 1.4)

- [ ] **Step 1: Add tests for each code path.**

Expand the file created in Task 1.4 to cover:
- Empty search text returns empty list without hitting the repo.
- FTS5 success path returns the FTS5 results directly.
- FTS5 error path falls back to LIKE (already tested).
- LIKE error path returns a wrapped service exception.
- Search scope `source`, `target`, `both` each call the repo with the correct parameter.
- Language filter is threaded through to the repo.
- Unexpected exception in the service itself returns `TmServiceException` with stack trace.

- [ ] **Step 2: Commit.**

```bash
git add test/unit/services/translation_memory/tm_search_service_test.dart
git commit -m "test: full coverage for TmSearchService"
```

### Task 5.2: WorkshopPublishService — test the orchestration

**Files:**
- Create: `test/unit/services/steam/workshop_publish_service_test.dart`

- [ ] **Step 1: Mock the three collaborators — SteamCmdManager, VdfGenerator, Process.**

These were hard-coded per the audit. If they are still hard-coded, add constructor parameters with defaults first (similar to the logger migration in Phase 2), then write tests using the injected mocks.

- [ ] **Step 2: Cover at minimum:**
- Update path: given a valid Workshop ID, publishes the VDF and invokes steamcmd with expected args.
- Missing preview image path: regenerates the preview before publish.
- steamcmd failure path: returns a structured error.
- Invalid Workshop ID: fails validation before any steamcmd call.

- [ ] **Step 3: Commit.**

```bash
git add lib/services/steam/ test/unit/services/steam/
git commit -m "test: add tests for WorkshopPublishService orchestration"
```

### Task 5.3: TranslationOrchestrationService — test the translation pipeline

**Files:**
- Create: `test/unit/services/translation/translation_orchestration_service_test.dart`

- [ ] **Step 1: Mock all collaborators (repositories, TM service, LLM provider, validator).**

Cover:
- Happy path: a batch translates, goes through TM lookup, LLM fallback for misses, validation, and persists.
- Skip-filter path: entries matching skip filter bypass the LLM and are marked accordingly.
- TM hit path: entries with a direct TM hit use the TM translation without calling the LLM.
- LLM error path: errors are wrapped and do not corrupt the batch state.

- [ ] **Step 2: Commit.**

```bash
git add test/unit/services/translation/
git commit -m "test: add tests for TranslationOrchestrationService pipeline"
```

### Task 5.4: LLM provider — test request/response shape and retries

**Files:**
- Create: `test/unit/services/llm/llm_provider_test.dart`

- [ ] **Step 1: Mock the Dio client.**

Cover at minimum:
- Successful response parsing.
- Rate limit response triggers backoff and retry.
- Non-retryable error (auth failure) is returned immediately.
- Malformed response returns a structured error, not a crash.

- [ ] **Step 2: Commit.**

```bash
git add test/unit/services/llm/
git commit -m "test: add tests for LLM provider request/response handling"
```

### Phase 5 completion checkpoint

- [ ] **`flutter test --coverage` shows coverage up from ~2.3% to at least 15%** (measured against `lib/services/` only).
- [ ] **All new tests pass on CI locally.**

---

## Post-refactor summary

After all five phases:

- **DB**: Tuned pragmas, streamed export, no in-memory TM fallback. Tested to ~20M rows comfortably, headroom to 60M+ with later sharding.
- **DI**: Single Riverpod-first UI layer, GetIt kept only for infrastructure init. No more double-indirection wrappers.
- **Logger**: Fully injectable across the codebase. Tests can mock silently.
- **Editor**: Decomposed into focused notifiers and widgets, each under 300 lines. Characterisation tests prevent regressions.
- **Tests**: Critical services have a real safety net. New features can be developed TDD-style.

**Estimated total effort: 5-8 weeks** of focused refactoring work, with the app remaining shippable after every commit.

**What this plan deliberately does NOT do:**
- Rewrite the app in another stack (Flutter is not the bottleneck).
- Change the DB schema (no evidence it's the problem).
- Introduce a `use-case` / `application service` layer (can be added later if a feature genuinely needs it — YAGNI for now).
- Replace `syncfusion_flutter_datagrid` (stable enough).

**What this plan leaves open (explicit non-goals):**
- Dialog-boilerplate deduplication (minor, can wait).
- Large god-repositories outside the editor (e.g., `translation_version_repository.dart` 1079 L) — if one becomes a bottleneck, tackle it then.
- Migration off `get_it` entirely — the hybrid is a stable endpoint, not a stepping stone to pure Riverpod.
