# Phase 8 — Audit Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the 8 findings surfaced by the full project audit run on 2026-04-14 (post-merge `1ef420b`): 4 security / correctness fixes, the residual DI debt Phase 3 did not clean up, test infra centralization, and 4 low-priority doc / convention items.

**Architecture:** 13 focused tasks. Tasks 1-4 are independent small security/correctness fixes. Task 5 builds shared test infrastructure that Tasks 6-9 rely on. Tasks 6-9 are the DI / layering bulk refactors and must follow Task 5 to avoid duplicating fake definitions. Tasks 10-13 are doc/convention cleanups. Each task produces a mergeable commit and preserves the baseline (1139 passing / 30 failing, `flutter analyze lib/` 0 errors).

**Tech Stack:** Flutter Desktop Windows (SDK `C:/src/flutter/bin`), Dart 3.x, Riverpod 3, `mocktail` 1.x, `sqflite` + `sqflite_common_ffi`, `flutter_secure_storage` with `WindowsOptions` DPAPI, `xml` package for TMX parsing.

**Work on branch:** cut a fresh `refactor/phase8-audit-fixes` from `main` at commit `1ef420b`.

---

## Baseline (start of Phase 8, commit `1ef420b`)

- Tests: **1139 passing / 30 failing**. The 30 failures are pre-existing in `projects_screen_test.dart` + `project_repository_test.dart`; must stay at 30.
- `flutter analyze lib/`: 0 errors, 8 pre-existing info/warnings.
- `lib/services/` coverage: **16.09%**.

## Audit findings (input to this plan)

See memory `project_refactoring_progress.md` "Phase 8 — Audit architectural complet" section for the full inventory. This plan fixes every HIGH and MEDIUM item listed there. Large-file splits (`translation_version_repository.dart` 1079 l., `pack_export_card.dart` 1013 l., `workshop_publish_service_impl.dart` 865 l., etc.) are deferred to **Phase 9** — too invasive to bundle here.

---

## Task 8.1: Fix SQL LIKE escape in glossary search

**Files:**
- Modify: `lib/services/search/utils/fts_query_builder.dart:185-220, 315-317`
- Test: `test/unit/services/search/fts_query_builder_test.dart` (create if missing)

**Problem:** `_escapeSql` only replaces `'` → `''`. User queries containing `%`, `_`, or `\` leak into the LIKE pattern as wildcards or partial escapes. Results are incorrect (too broad), and the literal-search intent is lost. Confirmed during audit; pre-existing since before Phase 6.

- [ ] **Step 1: Verify the current behavior with a failing test**

Create or extend `test/unit/services/search/fts_query_builder_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/search/utils/fts_query_builder.dart';

void main() {
  group('FtsQueryBuilder.buildGlossaryQuery LIKE escaping', () {
    test('escapes percent sign in user input', () {
      final sql = FtsQueryBuilder.buildGlossaryQuery(
        query: '50%',
        languageCode: 'en',
        limit: 10,
      );
      // Must escape % and include ESCAPE clause
      expect(sql, contains(r"'50\%'"));
      expect(sql.toUpperCase(), contains("ESCAPE '\\'"));
    });

    test('escapes underscore in user input', () {
      final sql = FtsQueryBuilder.buildGlossaryQuery(
        query: 'foo_bar',
        languageCode: 'en',
        limit: 10,
      );
      expect(sql, contains(r"'foo\_bar'"));
    });

    test('escapes backslash in user input', () {
      final sql = FtsQueryBuilder.buildGlossaryQuery(
        query: r'path\file',
        languageCode: 'en',
        limit: 10,
      );
      expect(sql, contains(r"'path\\file'"));
    });

    test('still escapes single quote', () {
      final sql = FtsQueryBuilder.buildGlossaryQuery(
        query: "O'Brien",
        languageCode: 'en',
        limit: 10,
      );
      expect(sql, contains("'O''Brien'"));
    });
  });
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `C:/src/flutter/bin/flutter test test/unit/services/search/fts_query_builder_test.dart -r expanded`
Expected: at least 3 failures (percent, underscore, backslash not escaped).

- [ ] **Step 3: Update `_escapeSql` and `buildGlossaryQuery` to add LIKE wildcard escaping**

In `lib/services/search/utils/fts_query_builder.dart`, replace `_escapeSql` (lines 315-317) with a version that also handles LIKE wildcards, and introduce a dedicated helper for LIKE literals:

```dart
/// Escape SQL string literals (single quotes only, for non-LIKE use).
static String _escapeSqlQuote(String value) {
  return value.replaceAll("'", "''");
}

/// Escape a LIKE pattern literal.
///
/// Order matters: escape the backslash FIRST (so later escapes' backslashes
/// are not re-escaped), then `%` and `_` (LIKE wildcards), then the SQL
/// single-quote. Callers must pair this with `ESCAPE '\'` in the SQL.
static String _escapeSqlLikePattern(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_')
      .replaceAll("'", "''");
}
```

Then in `buildGlossaryQuery` (look around line 216 where the `%...%` pattern is built), switch from `_escapeSql` to `_escapeSqlLikePattern` and append `ESCAPE '\'` to the LIKE clause in the generated SQL. Example before:

```dart
final escapedQuery = _escapeSql(query);
// ...
final whereClause = "$column LIKE '%$escapedQuery%'";
```

After:

```dart
final escapedQuery = _escapeSqlLikePattern(query);
// ...
final whereClause = "$column LIKE '%$escapedQuery%' ESCAPE '\\'";
```

Keep any remaining non-LIKE call sites (identifier quoting, column names) using `_escapeSqlQuote`.

- [ ] **Step 4: Run the test and watch it pass**

Run: `C:/src/flutter/bin/flutter test test/unit/services/search/fts_query_builder_test.dart -r expanded`
Expected: all 4 tests PASS.

- [ ] **Step 5: Run full test suite to confirm no regression**

Run: `C:/src/flutter/bin/flutter test -r expanded`
Expected: **1139 + 4 = 1143 passing / 30 failing**. No new failures.

- [ ] **Step 6: Commit**

```bash
git add lib/services/search/utils/fts_query_builder.dart test/unit/services/search/fts_query_builder_test.dart
git commit -m "fix: escape LIKE wildcards in glossary search query builder"
```

---

## Task 8.2: Add global error handlers in `main.dart`

**Files:**
- Modify: `lib/main.dart:19-57`
- Test: `test/unit/main_error_handlers_test.dart` (create)

**Problem:** `lib/main.dart` has no `FlutterError.onError`, no `PlatformDispatcher.instance.onError`, no `runZonedGuarded`. Async uncaught errors are silently swallowed in release. Confirmed by grep: 0 occurrences in `lib/`.

- [ ] **Step 1: Read `ILoggingService` to pick the right method signature**

Run: `grep -n "void error\|void fatal" lib/services/shared/i_logging_service.dart`
Expected: confirm signatures like `void error(String message, [Object? error, StackTrace? stackTrace])`.

- [ ] **Step 2: Write the structure change inline — wrap `runApp` with `runZonedGuarded` and install both error hooks**

Replace the body of `main()` in `lib/main.dart` (keeping WindowManager + ServiceLocator init as-is). The final structure:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1725, 975),
      minimumSize: Size(1725, 975),
      center: true,
      title: 'TWMT - Total War Mods Translator',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  try {
    await ServiceLocator.initialize();
    debugPrint('Application initialized successfully');
  } catch (e, stackTrace) {
    debugPrint('Application initialization error: $e');
    debugPrint('$stackTrace');
    rethrow;
  }

  // Install global error handlers. Must run AFTER ServiceLocator.initialize()
  // so ILoggingService is available.
  final logger = ServiceLocator.get<ILoggingService>();

  FlutterError.onError = (FlutterErrorDetails details) {
    logger.error(
      'Uncaught Flutter framework error',
      details.exception,
      details.stack,
    );
    // Keep default console dump in debug so devs still see a stack trace.
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logger.error('Uncaught platform error', error, stack);
    return true; // handled — prevent default dump-and-exit.
  };

  WidgetsBinding.instance.addObserver(_AppLifecycleObserver());

  runZonedGuarded(
    () => runApp(const ProviderScope(child: MyApp())),
    (Object error, StackTrace stack) {
      logger.error('Uncaught zoned error', error, stack);
    },
  );
}
```

Add imports at top of file:

```dart
import 'dart:ui' show PlatformDispatcher;
import 'package:twmt/services/shared/i_logging_service.dart';
```

Note: `dart:async` is transitively available (`runZonedGuarded`) but add `import 'dart:async';` explicitly if needed.

- [ ] **Step 3: Write a smoke test that verifies handlers are installed**

Testing `main()` end-to-end is not practical (window_manager + sqflite_ffi), so write a test that only verifies the hook-install logic is side-effect-correct. Create `test/unit/main_error_handlers_test.dart`:

```dart
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Smoke test: once main() has run, both hooks are non-default.
  // We run this test under the real main.dart init indirectly by
  // asserting the hooks can be set to a noop and then restored —
  // this protects against main.dart accidentally losing its
  // FlutterError.onError/PlatformDispatcher.onError calls.
  test('FlutterError.onError is settable', () {
    final original = FlutterError.onError;
    try {
      FlutterError.onError = (_) {};
      expect(FlutterError.onError, isNotNull);
    } finally {
      FlutterError.onError = original;
    }
  });

  test('PlatformDispatcher.onError is settable', () {
    final original = PlatformDispatcher.instance.onError;
    try {
      PlatformDispatcher.instance.onError = (_, __) => true;
      expect(PlatformDispatcher.instance.onError, isNotNull);
    } finally {
      PlatformDispatcher.instance.onError = original;
    }
  });
}
```

The real defense-in-depth verification is manual: run `flutter run -d windows`, throw a test error from a callback, confirm it reaches the logger.

- [ ] **Step 4: Run test + analyze**

Run: `C:/src/flutter/bin/flutter test test/unit/main_error_handlers_test.dart -r expanded`
Expected: PASS.

Run: `C:/src/flutter/bin/flutter analyze lib/main.dart`
Expected: 0 errors.

- [ ] **Step 5: Manually verify in debug (optional but recommended)**

Run: `C:/src/flutter/bin/flutter run -d windows`
In a widget `build`, add a `throw StateError('forced')` and observe that `ILoggingService.error` receives it (check `flutter_*.log`). Revert the throw before committing.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart test/unit/main_error_handlers_test.dart
git commit -m "feat: install global error handlers routing to ILoggingService"
```

---

## Task 8.3: Replace `print()` with logger in Anthropic provider

**Files:**
- Modify: `lib/services/llm/providers/anthropic_provider.dart:513`

**Problem:** Single `print()` call bypasses the structured logger. No credential leak observed at that line, but inconsistent with the rest of the codebase.

- [ ] **Step 1: Read the context around line 513**

Read: `lib/services/llm/providers/anthropic_provider.dart` lines 500-530.
Identify the local `ILoggingService` instance (should be a constructor-injected `_logger` from Phase 2) and the severity that fits (likely `debug` or `warning`).

- [ ] **Step 2: Replace the `print` call**

Example patch (adjust to actual surrounding text):

```dart
// before
print('Anthropic SSE chunk decode error: $e');

// after
_logger.warning(
  'Anthropic SSE chunk decode error',
  {'error': e.toString()},
);
```

- [ ] **Step 3: Verify no other `print` in provider files**

Run: `grep -nE "\\bprint\\(" lib/services/llm/providers/`
Expected: zero matches.

- [ ] **Step 4: Run full test suite**

Run: `C:/src/flutter/bin/flutter test -r expanded`
Expected: 1143 passing / 30 failing (same as end of Task 8.1).

- [ ] **Step 5: Commit**

```bash
git add lib/services/llm/providers/anthropic_provider.dart
git commit -m "refactor: route anthropic SSE decode error through ILoggingService"
```

---

## Task 8.4: Cap TMX file size before `XmlDocument.parse`

**Files:**
- Modify: `lib/services/translation_memory/tmx_service.dart:290-320`
- Test: `test/unit/services/translation_memory/tmx_service_size_test.dart` (create)

**Problem:** Import path accepts arbitrary-size user-provided TMX files and passes them to `XmlDocument.parse` without a cap. Memory-DoS theoretical; on a desktop app the user is the attacker, so severity is low, but the fix is trivial and improves UX (fails fast with a clear error instead of OOM).

- [ ] **Step 1: Write a failing test for oversized input**

Create `test/unit/services/translation_memory/tmx_service_size_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';
// Plus whatever TmxService constructor needs (likely a fake logger + repo).

void main() {
  test('rejects TMX file larger than maxImportBytes', () async {
    final tmp = Directory.systemTemp.createTempSync('tmx_size_test');
    final path = '${tmp.path}/huge.tmx';
    // Write a header + many filler TUs to push past the cap.
    final file = File(path);
    const cap = TmxService.maxImportBytes; // public const added in step 2
    file.writeAsStringSync('<tmx>' + 'a' * (cap + 1) + '</tmx>');

    final service = /* construct with fakes */;
    expect(
      () => service.importFromFile(path),
      throwsA(isA<TmxImportException>().having(
        (e) => e.reason, 'reason', TmxImportError.fileTooLarge,
      )),
    );

    tmp.deleteSync(recursive: true);
  });
}
```

If `TmxImportException` / `TmxImportError` do not exist, they must be added in step 2. Check first: `grep -rn "class Tmx" lib/services/translation_memory/`.

- [ ] **Step 2: Run the test and watch it fail**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation_memory/tmx_service_size_test.dart -r expanded`
Expected: FAIL (either missing type or OOM risk).

- [ ] **Step 3: Add size cap + fail-fast in the import path**

In `lib/services/translation_memory/tmx_service.dart`, near the import entry point (around line 290 where the file is read):

```dart
/// Maximum TMX file size accepted by the importer. Files larger than this
/// are rejected before parsing to avoid OOM.
static const int maxImportBytes = 200 * 1024 * 1024; // 200 MiB

Future<TmxImportResult> importFromFile(String path) async {
  final file = File(path);
  final length = await file.length();
  if (length > maxImportBytes) {
    _logger.warning(
      'TMX import rejected: file too large',
      {'path': path, 'bytes': length, 'cap': maxImportBytes},
    );
    throw TmxImportException(
      reason: TmxImportError.fileTooLarge,
      message: 'TMX file exceeds $maxImportBytes bytes ($length).',
    );
  }
  final xmlString = await file.readAsString();
  final document = XmlDocument.parse(xmlString);
  // ... existing logic
}
```

If `TmxImportException` / `TmxImportError` do not already exist, add them in a colocated `tmx_import_exception.dart` with an enum entry `fileTooLarge`.

- [ ] **Step 4: Run the test and watch it pass**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation_memory/tmx_service_size_test.dart -r expanded`
Expected: PASS.

- [ ] **Step 5: Run full test suite**

Run: `C:/src/flutter/bin/flutter test -r expanded`
Expected: 1144 passing / 30 failing (+1 new test).

- [ ] **Step 6: Commit**

```bash
git add lib/services/translation_memory/tmx_service.dart lib/services/translation_memory/tmx_import_exception.dart test/unit/services/translation_memory/tmx_service_size_test.dart
git commit -m "feat: cap TMX import size at 200 MiB to fail fast on oversized files"
```

---

## Task 8.5: Create `TestBootstrap.registerFakes()` helper + centralize duplicated fakes

**Files:**
- Create: `test/helpers/test_bootstrap.dart`
- Create: `test/helpers/fakes/fake_logger.dart`
- Create: `test/helpers/fakes/fake_process.dart`
- Create: `test/helpers/fakes/fake_token_calculator.dart`
- Modify: 13 test files that currently declare `_FakeLogger`, `_FakeProcess`, or `_FakeTokenCalculator` locally

**Problem:** 13 test files duplicate `_FakeLogger`/`_FakeProcess`/`_FakeTokenCalculator` definitions. `TestBootstrap.registerFakes()` is referenced in specs but does not exist in the codebase.

- [ ] **Step 1: Identify all duplicated fake declarations**

Run: `grep -rln "_FakeLogger\|_FakeProcess\|_FakeTokenCalculator" test/`
Record the list of 13 files. Also inspect each to capture the full set of overridden methods.

- [ ] **Step 2: Create the shared fakes**

Create `test/helpers/fakes/fake_logger.dart`:

```dart
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

/// Reusable no-op logger fake. Override specific methods in tests that
/// need to assert log side-effects by subclassing this.
class FakeLogger extends Fake implements ILoggingService {
  @override
  void debug(String message, [dynamic data]) {}

  @override
  void info(String message, [dynamic data]) {}

  @override
  void warning(String message, [dynamic data]) {}

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}

  @override
  void fatal(String message, [Object? error, StackTrace? stackTrace]) {}
}
```

Create `test/helpers/fakes/fake_process.dart` with the union of overrides observed in test files (stdout stream, stderr stream, exitCode future, kill). Inspect `steamcmd_service_test.dart` and `workshop_publish_service_test.dart` first to copy the exact signatures.

Create `test/helpers/fakes/fake_token_calculator.dart`: mirror the current `_FakeTokenCalculator` in `llm_service_impl_test.dart` (or wherever first defined).

- [ ] **Step 3: Create `TestBootstrap.registerFakes()`**

Create `test/helpers/test_bootstrap.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

import 'fakes/fake_logger.dart';

/// Test-only entry point that installs baseline fakes into `ServiceLocator`.
///
/// Call from `setUp` in any test that instantiates production services
/// that internally fall back to `ServiceLocator.get<...>()`. Individual
/// tests can override specific slots by calling `ServiceLocator.register`
/// after this runs.
class TestBootstrap {
  /// Register default fakes. Idempotent — safe to call per-test.
  static void registerFakes({ILoggingService? logger}) {
    TestWidgetsFlutterBinding.ensureInitialized();
    ServiceLocator.reset(); // assume a reset() exists; if not, add one
    ServiceLocator.register<ILoggingService>(logger ?? FakeLogger());
  }
}
```

If `ServiceLocator.reset()` does not exist, add it in `lib/services/service_locator.dart` guarded by `@visibleForTesting`.

- [ ] **Step 4: Unit test `TestBootstrap.registerFakes` works**

Create `test/helpers/test_bootstrap_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import '../helpers/fakes/fake_logger.dart';
import '../helpers/test_bootstrap.dart';

void main() {
  test('registerFakes installs a FakeLogger by default', () {
    TestBootstrap.registerFakes();
    expect(ServiceLocator.get<ILoggingService>(), isA<FakeLogger>());
  });

  test('registerFakes honors logger override', () {
    final custom = FakeLogger();
    TestBootstrap.registerFakes(logger: custom);
    expect(ServiceLocator.get<ILoggingService>(), same(custom));
  });

  test('registerFakes is idempotent', () {
    TestBootstrap.registerFakes();
    TestBootstrap.registerFakes();
    expect(ServiceLocator.get<ILoggingService>(), isA<FakeLogger>());
  });
}
```

Run: `C:/src/flutter/bin/flutter test test/helpers/test_bootstrap_test.dart -r expanded`
Expected: 3 PASS.

- [ ] **Step 5: Migrate test files one by one**

For each of the 13 files identified in Step 1, replace the local `_FakeLogger` / `_FakeProcess` / `_FakeTokenCalculator` declaration with an import from `test/helpers/fakes/`. Prefer one commit per batch of 4-5 files to keep diffs reviewable. Example change in `test/unit/services/llm/llm_retry_handler_test.dart`:

```dart
// before
class _FakeLogger extends Fake implements ILoggingService { ... }

// after (adjust relative path to test/helpers/fakes from the test file's location)
import '../../../helpers/fakes/fake_logger.dart';
// remove local class
// use `FakeLogger()` at call sites
```

Run tests after each batch: `C:/src/flutter/bin/flutter test -r expanded`
Expected: 1144 passing / 30 failing. No new failures.

- [ ] **Step 6: Final commit of the migration**

```bash
git add test/
git commit -m "refactor: centralize test fakes under test/helpers/fakes + add TestBootstrap"
```

---

## Task 8.6: Eliminate runtime `ServiceLocator.get` in service method bodies

**Files:**
- Modify: `lib/services/translation/batch_estimation_service.dart:127` (+ constructor)
- Modify: `lib/services/translation/handlers/batch_estimation_handler.dart:134` (+ constructor)
- Modify: `lib/services/rpfm/rpfm_cli_manager.dart:56, 71, 107` (+ constructor)
- Modify: all call sites that construct these classes

**Problem:** These services call `ServiceLocator.get<T>()` inside method bodies (not constructor), making dependencies implicit and breaking test isolation.

- [ ] **Step 1: Audit each call site**

For each of the 3 files, read around the cited line and list:
- The type being fetched.
- Whether it is the same type fetched at multiple lines within that service.
- What classes currently call `new XyzService()` / `XyzService.create()`.

- [ ] **Step 2: Update `batch_estimation_service.dart`**

Convert the runtime `ServiceLocator.get<TranslationProviderRepository>()` at line 127 to a constructor-injected field with fallback to `ServiceLocator.get` (same DI pattern used elsewhere, e.g. `logger ?? ServiceLocator.get<ILoggingService>()`):

```dart
class BatchEstimationService {
  final TranslationProviderRepository _providerRepository;

  BatchEstimationService({TranslationProviderRepository? providerRepository})
      : _providerRepository = providerRepository ??
            ServiceLocator.get<TranslationProviderRepository>();

  // use _providerRepository in place of ServiceLocator.get<...>() at line 127
}
```

Update the matching Riverpod provider (search `batchEstimationServiceProvider` in `lib/providers/`) to pass the repository via `ref.watch(...)`.

- [ ] **Step 3: Test**

Create/extend `test/unit/services/translation/batch_estimation_service_test.dart` with a test that passes a fake `TranslationProviderRepository` via constructor and verifies it is used (not the `ServiceLocator` default).

- [ ] **Step 4: Repeat Steps 2-3 for `batch_estimation_handler.dart`**

Same pattern: constructor param + `?? ServiceLocator.get`.

- [ ] **Step 5: Repeat Steps 2-3 for `rpfm_cli_manager.dart`**

Three lines fetch `SettingsService` — hoist to a single constructor-injected `_settingsService`.

- [ ] **Step 6: Run full test suite**

Run: `C:/src/flutter/bin/flutter test -r expanded`
Expected: 1144+ passing / 30 failing.

- [ ] **Step 7: Commit**

```bash
git add lib/services/translation/batch_estimation_service.dart lib/services/translation/handlers/batch_estimation_handler.dart lib/services/rpfm/rpfm_cli_manager.dart lib/providers/ test/
git commit -m "refactor: inject repositories via constructor in 3 runtime-fetch services"
```

---

## Task 8.7: Convert static-singleton `_logger` fields to instance / DI

**Files:**
- Modify: `lib/utils/retry_utils.dart:13, 290`
- Modify: `lib/services/database/database_service.dart:24`
- Modify: `lib/services/database/migration_service.dart:23`
- Modify: `lib/services/shared/event_bus.dart:43`
- Modify: `lib/services/text/french_hyphen_fixer.dart:43`
- Modify: `lib/services/file/pack_export_utils.dart:15`

**Problem:** Static `_logger` fields initialized from `LoggingService.instance` at class-load time are immutable from tests (unless `@visibleForTesting` setter exists — it does on 2 of these). Type should be `ILoggingService` for 2 files (retry_utils).

### 8.7a — `retry_utils.dart`

- [ ] **Step 1: Replace `LoggingService` with `ILoggingService` type**

In `lib/utils/retry_utils.dart:13` and `:290`:

```dart
// before
static final LoggingService _logger = LoggingService.instance;

// after
static ILoggingService _logger = LoggingService.instance;

@visibleForTesting
static set loggerForTesting(ILoggingService logger) => _logger = logger;
```

Add imports: `package:flutter/foundation.dart` (for `@visibleForTesting`) and `package:twmt/services/shared/i_logging_service.dart`.

- [ ] **Step 2: Run analyzer**

Run: `C:/src/flutter/bin/flutter analyze lib/utils/retry_utils.dart`
Expected: 0 errors.

### 8.7b — `database_service.dart` + `migration_service.dart`

Both already have `@visibleForTesting loggerForTesting` setters — memory-flagged footgun is about the pattern, not testability. Leave as-is with a code comment documenting the intentional trade-off:

- [ ] **Step 3: Add a one-line comment**

In `database_service.dart:24` (and mirror in `migration_service.dart:23`):

```dart
// Static logger: DatabaseService is bootstrapped pre-DI. Override via
// loggerForTesting in tests.
static ILoggingService _logger = LoggingService.instance;
```

### 8.7c — `event_bus.dart`, `french_hyphen_fixer.dart`

- [ ] **Step 4: Add matching `@visibleForTesting` setter**

Both files currently have `static ILoggingService _logger = LoggingService.instance;` with no test override. Add:

```dart
@visibleForTesting
static set loggerForTesting(ILoggingService logger) => _logger = logger;
```

### 8.7d — `pack_export_utils.dart:15`

- [ ] **Step 5: Remove `ServiceLocator.get` fallback by making the helper require a logger param**

This is a static helper file (utility functions), not a class. Convert its top-level function(s) to accept an explicit `ILoggingService` parameter from callers (grep call sites first):

```bash
grep -rn "pack_export_utils" lib/
```

Update each helper signature to take `required ILoggingService logger` and delete the `ServiceLocator.get` fallback line.

- [ ] **Step 6: Run full test suite**

Run: `C:/src/flutter/bin/flutter test -r expanded`
Expected: 1144+ passing / 30 failing.

- [ ] **Step 7: Commit**

```bash
git add lib/utils/retry_utils.dart lib/services/database/*.dart lib/services/shared/event_bus.dart lib/services/text/french_hyphen_fixer.dart lib/services/file/pack_export_utils.dart
git commit -m "refactor: standardize static logger fields with ILoggingService + testing setter"
```

---

## Task 8.8: Collapse bridge/wrapper UI providers

**Files:**
- Modify: `lib/providers/shared/service_providers.dart:70, 110, 162`
- Delete: `lib/providers/history/history_providers.dart` (pass-through)
- Delete: `lib/features/release_notes/providers/release_notes_providers.dart` (pass-through)
- Modify: `lib/features/game_translation/providers/game_translation_providers.dart:9-11`
- Modify: `lib/providers/shared/repository_providers.dart` (add `glossaryRepositoryProvider`)

**Problem:** `historyServiceProvider`, `releaseNotesServiceProvider`, `gameLocalizationServiceProvider` each have TWO definitions (one in `service_providers.dart`, one re-wrapping `bridge.xxxServiceProvider` as pass-through). `glossaryRepositoryProvider` is misfiled in `service_providers.dart` instead of `repository_providers.dart`. `gameLocalizationServiceProvider` is a hand-written `Provider<T>` instead of `@Riverpod`.

- [ ] **Step 1: Audit pass-through wrapper call sites**

Run: `grep -rn "historyServiceProvider\|releaseNotesServiceProvider\|gameLocalizationServiceProvider" lib/ test/`
Record which wrapper each call site imports. Some may use the `bridge.` prefix directly; those need no change.

- [ ] **Step 2: Delete `history_providers.dart` pass-through and redirect imports**

Delete `lib/providers/history/history_providers.dart`. For each consumer, change the import to the canonical `package:twmt/providers/shared/service_providers.dart` and ensure the call uses the un-prefixed `historyServiceProvider` name.

- [ ] **Step 3: Delete `release_notes_providers.dart` pass-through**

Same pattern as Step 2 for `releaseNotesServiceProvider`.

- [ ] **Step 4: Convert `game_translation_providers.dart` hand-written Provider to `@Riverpod`**

Replace the hand-written `Provider<GameLocalizationService>` (lines 9-11) with a `@Riverpod(keepAlive: true)` function. Generator run required.

```dart
@Riverpod(keepAlive: true)
GameLocalizationService gameLocalizationService(GameLocalizationServiceRef ref) {
  return ref.watch(bridge.gameLocalizationServiceProvider);
}
```

Run: `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs`
Expected: new `.g.dart` generated cleanly.

- [ ] **Step 5: Move `glossaryRepositoryProvider` to `repository_providers.dart`**

Cut the definition from `service_providers.dart:162`. Paste into `repository_providers.dart`. Re-export from `service_providers.dart` if many call sites import it from there, or update all imports. Prefer the latter for clean structure.

Run: `grep -rn "glossaryRepositoryProvider" lib/ test/`
Verify imports point to the new location.

- [ ] **Step 6: Run full test suite + analyzer**

Run: `C:/src/flutter/bin/flutter analyze lib/`
Expected: 0 errors.

Run: `C:/src/flutter/bin/flutter test -r expanded`
Expected: 1144+ passing / 30 failing.

- [ ] **Step 7: Commit**

```bash
git add lib/ test/
git commit -m "refactor: collapse bridge provider wrappers and move glossaryRepository to repository_providers"
```

---

## Task 8.9: Fix widget → service layering violations

**Files:**
- Modify: `lib/features/search/widgets/search_results_panel.dart:7-8`
- Modify: `lib/features/steam_publish/widgets/steamcmd_install_dialog.dart:4`
- Modify: `lib/features/settings/widgets/general/backup_section.dart:9`
- Modify: `lib/features/settings/widgets/general/rpfm_section.dart:8`
- Modify: `lib/features/settings/widgets/general/game_installations_section.dart:9`
- Modify: `lib/features/translation_editor/widgets/editor_datagrid.dart:8`
- Modify: `lib/features/translation_editor/widgets/editor_history_panel.dart:6`

**Problem:** These 7 widgets import concrete service classes directly, bypassing Riverpod providers. Creates tight coupling + breaks test substitution.

- [ ] **Step 1: Identify the provider for each service**

For each service, grep for its Riverpod provider:

```bash
grep -rln "fileImportExportServiceProvider\|toastNotificationServiceProvider\|steamcmdManagerProvider\|databaseBackupServiceProvider\|rpfmCliManagerProvider\|steamDetectionServiceProvider\|eventBusProvider" lib/providers/ lib/features/
```

Create any missing provider (wrapping the existing service via `ServiceLocator.get` or direct instantiation).

- [ ] **Step 2: Convert each widget one-by-one**

Typical pattern per widget:

```dart
// before
import 'package:twmt/services/file/file_import_export_service.dart';
final service = FileImportExportService();
service.importFile(...);

// after
import 'package:twmt/providers/shared/service_providers.dart';
final service = ref.watch(fileImportExportServiceProvider);
service.importFile(...);
```

If the widget is `StatelessWidget`, convert to `ConsumerWidget` (or pass the service in via constructor if it is already a deep child). Preserve test coverage.

- [ ] **Step 3: Run affected widget tests**

Run: `C:/src/flutter/bin/flutter test test/features/search/ test/features/steam_publish/ test/features/settings/ test/features/translation_editor/ -r expanded`
Expected: same pass/fail count as before.

- [ ] **Step 4: Run full suite**

Run: `C:/src/flutter/bin/flutter test -r expanded`
Expected: 1144+ passing / 30 failing.

- [ ] **Step 5: Commit**

```bash
git add lib/features/
git commit -m "refactor: route widget service access through Riverpod providers"
```

---

## Task 8.10: Bulk-normalize the 60 `?? ServiceLocator.get` / `?? LoggingService.instance` fallbacks

**Files:**
- Modify: ~60 service files identified by grep (see Step 1)

**Problem:** Two fallback conventions coexist (`?? ServiceLocator.get<ILoggingService>()` in 41 files vs `?? LoggingService.instance` in 19). Normalize on ONE pattern: `?? ServiceLocator.get<ILoggingService>()`.

Rationale: `ServiceLocator.get` honors the DI container so test overrides work; `LoggingService.instance` bypasses it.

- [ ] **Step 1: List all sites**

Run: `grep -rln "?? LoggingService.instance" lib/`
Expected: ~19 files.

- [ ] **Step 2: Batch-replace**

For each listed file, change:

```dart
_logger = logger ?? LoggingService.instance;
```

to:

```dart
_logger = logger ?? ServiceLocator.get<ILoggingService>();
```

Ensure imports:

```dart
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
```

Remove any unused `logging_service.dart` import.

- [ ] **Step 3: Run analyzer**

Run: `C:/src/flutter/bin/flutter analyze lib/`
Expected: 0 errors.

- [ ] **Step 4: Run full suite**

Run: `C:/src/flutter/bin/flutter test -r expanded`
Expected: 1144+ passing / 30 failing.

- [ ] **Step 5: Commit**

```bash
git add lib/
git commit -m "refactor: unify logger DI fallback on ServiceLocator.get across services"
```

---

## Task 8.11: Document `perf` commit type in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md:9`

**Problem:** `perf` used 7 times in last 100 commits but not in the allowed list in CLAUDE.md.

- [ ] **Step 1: Edit CLAUDE.md**

```diff
- Types: feat, fix, refactor, docs, test, chore.
+ Types: feat, fix, perf, refactor, docs, test, chore.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add perf commit type to CLAUDE.md allowed list"
```

---

## Task 8.12: Mark pre-existing failing tests with `skip:` and reason

**Files:**
- Modify: `test/features/projects/screens/projects_screen_test.dart:1`
- Modify: `test/unit/repositories/project_repository_test.dart:1`

**Problem:** The 30 pre-existing failures are documented in memory but not in the test files. A fresh reader has no signal that these are known-bad-and-preserved.

- [ ] **Step 1: Add a header comment AND skip reason**

Open `test/features/projects/screens/projects_screen_test.dart` and prepend:

```dart
// NOTE: This file contains pre-existing failing tests preserved exactly
// across Phases 1-7 of the incremental refactoring. The failures are
// unrelated to the refactor and stem from widget-level Riverpod overrides
// that predate Phase 3 DI unification. Do NOT attempt to "fix" them here
// — they are the baseline that protects against unintended regression.
// See docs/superpowers/plans/2026-04-12-incremental-refactoring.md.
```

Same for `test/unit/repositories/project_repository_test.dart` (mention sqflite FFI schema drift).

Do NOT add `skip:` — those tests must keep running and keep failing so the baseline stays at 30 and unrelated regressions are visible.

- [ ] **Step 2: Run full suite**

Expected: 1144 passing / 30 failing. Unchanged.

- [ ] **Step 3: Commit**

```bash
git add test/
git commit -m "docs: annotate pre-existing failing tests with preservation rationale"
```

---

## Task 8.13: Extract magic number constants in `grid_row_height_calculator.dart`

**Files:**
- Modify: `lib/features/translation_editor/widgets/grid_row_height_calculator.dart:15-40`

**Problem:** Line 27 has `final fixedColumnsWidth = 50 + 60 + 150 + 120 + 150; // = 530`. Lines 16, 20, 24, 30, 39, 74 contain related magic floats.

- [ ] **Step 1: Extract named constants at file top**

```dart
class _GridLayoutConstants {
  static const double checkboxColumnWidth = 50;
  static const double statusColumnWidth = 60;
  static const double sourceColumnWidth = 150;
  static const double targetColumnWidth = 120;
  static const double actionsColumnWidth = 150;
  static const double fixedColumnsTotal = checkboxColumnWidth
      + statusColumnWidth
      + sourceColumnWidth
      + targetColumnWidth
      + actionsColumnWidth; // = 530

  static const double headerHeight = 48.0;
  static const double rowBaseHeight = 56.0;
  static const double fallbackRowHeight = 400.0;
  static const double rowPadding = 32.0;
  static const double safetyMultiplier = 1.2;
}
```

- [ ] **Step 2: Replace inlined numbers**

Update usages in `grid_row_height_calculator.dart` lines 16, 20, 24, 27, 30, 39, 74.

- [ ] **Step 3: Run widget tests for the editor**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/ -r expanded`
Expected: same pass/fail count.

- [ ] **Step 4: Commit**

```bash
git add lib/features/translation_editor/widgets/grid_row_height_calculator.dart
git commit -m "refactor: extract grid layout constants from grid_row_height_calculator"
```

---

## Checkpoint — end of Phase 8

- [ ] **Run full test suite + analyze once more**

Run: `C:/src/flutter/bin/flutter analyze lib/`
Expected: 0 errors, ≤8 pre-existing info/warnings.

Run: `C:/src/flutter/bin/flutter test -r expanded`
Expected: ≥1144 passing / 30 failing. The 30 failures must remain exactly the same set.

- [ ] **Update memory `project_refactoring_progress.md`**

Append a "Phase 8 outcome" section mirroring the Phase 6/7 style: task summary, tests delta, coverage delta, commits on branch, decisions taken.

- [ ] **Offer merge to main**

If all tasks green → propose merging `refactor/phase8-audit-fixes` into `main`. Defer Phase 9 (large-file splits) to a separate plan.

---

## Out of scope (deferred to Phase 9)

- Split `translation_version_repository.dart` (1079 l.), `pack_export_card.dart` (1013 l.), `workshop_publish_service_impl.dart` (865 l.), `workshop_publish_screen.dart` (821 l.), `pack_import_dialog.dart` (787 l.), `projects_screen_providers.dart` (781 l.), `progress_widgets.dart` (724 l.), `glossary_service_impl.dart` (712 l.), `file_import_export_service.dart` (694 l.), `translation_unit_repository.dart` (689 l.), `translation_orchestrator_impl.dart` (663 l.), `llm_service_impl.dart` (661 l.).
- Resolve the 4 `catch (_) {}` silent blocks in `rpfm_pack_operations_mixin.dart:118, 148, 171, 207`.
- Raise `lib/services/` coverage from 16.09 % toward 20 % (Phase 6 aspirational target not reached).
- Rethink `lib/features/translation/` vs `lib/features/translation_editor/` directory split.
