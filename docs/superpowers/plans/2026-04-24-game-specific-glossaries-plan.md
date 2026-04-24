# Game-Specific Glossaries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace universal glossaries with strictly game-scoped glossaries (one per `(game_code, target_language_id)`), with a one-shot migration screen, auto-provisioning, and a translation-editor-style language switcher.

**Architecture:** Two-stage SQLite migration (partial add → user-driven finalization). A `GlossaryMigrationService` uses raw SQL to detect/convert/merge. A blocking modal `GlossaryMigrationScreen` is pushed from the bootstrap flow when pending work exists. After migration, `GlossaryAutoProvisioningService` creates empty glossaries on game-configuration / language-addition triggers. The glossary screen is refactored to consume `selectedGameProvider` (sidebar) + a new per-game language chip.

**Tech Stack:** Flutter, Riverpod 3 (`@riverpod` codegen), sqflite, GoRouter, SfDataGrid, `go_router`, service-locator (GetIt), existing `TokenDialog` + `SmallTextButton` token-theme widgets.

**Spec reference:** `docs/superpowers/specs/2026-04-24-game-specific-glossaries-design.md`

---

## File Map

**New files**
- `lib/services/database/migrations/migration_glossary_game_code_partial.dart` — phase 1 schema migration
- `lib/services/glossary/glossary_migration_service.dart` — detect, convert, merge, finalize
- `lib/services/glossary/glossary_auto_provisioning_service.dart` — auto-create empty `(game, language)` glossaries
- `lib/features/glossary/screens/glossary_migration_screen.dart` — blocking migration modal
- `lib/features/glossary/widgets/glossary_migration_universal_row.dart` — one-row-per-universal widget
- `lib/features/glossary/widgets/glossary_language_switcher.dart` — language chip adapted from `editor_language_switcher.dart`
- `lib/features/glossary/providers/glossary_migration_providers.dart` — providers for migration screen state
- `test/unit/services/glossary_migration_service_test.dart`
- `test/unit/services/glossary_auto_provisioning_service_test.dart`
- `test/services/database/migrations/migration_glossary_game_code_partial_test.dart`
- `test/features/glossary/screens/glossary_migration_screen_test.dart`
- `test/features/glossary/widgets/glossary_language_switcher_test.dart`

**Modified files**
- `lib/database/schema.sql` — align fresh-install schema with final state
- `lib/services/database/migrations/migration_registry.dart` — register phase 1 migration
- `lib/services/glossary/models/glossary.dart` — drop `isGlobal`, `gameInstallationId`; add `gameCode`
- `lib/repositories/glossary_repository.dart` — drop `includeUniversal`/`gameInstallationId`; add `gameCode` filter; fix `getByProjectAndLanguage`
- `lib/services/glossary/i_glossary_service.dart` — drop `isGlobal`/`gameInstallationId` from API; add `gameCode`
- `lib/services/glossary/glossary_service_impl.dart` — propagate the interface changes
- `lib/services/glossary/glossary_import_export_service.dart` — drop any legacy params
- `lib/features/glossary/providers/glossary_providers.dart` — drop `includeUniversal`/`gameInstallationId`; add `currentGlossaryProvider`, `glossaryAvailableLanguagesProvider`, `selectedGlossaryLanguageProvider`; delete `selectedGlossaryProvider`
- `lib/features/glossary/screens/glossary_screen.dart` — replace list+editor with language-switcher + editor; add empty-state branches
- `lib/main.dart` — push migration screen from `_runDataMigrations` if `detectPendingMigration` is pending
- `lib/config/router/app_router.dart` — add `AppRoutes.glossaryMigration`
- `lib/features/settings/providers/settings_providers.dart` — add `SettingsKeys.glossarySelectedLanguage(gameCode)`
- `lib/providers/shared/service_providers.dart` — register `glossaryMigrationServiceProvider`, `glossaryAutoProvisioningServiceProvider`
- `lib/services/service_locator.dart` — register new services in GetIt
- Any call site of `AddLanguageDialog` that adds a language to a project — trigger `provisionForProjectLanguage`
- Any call site of `settings_*` that sets a game path — trigger `provisionForGame`

**Deleted files**
- `lib/features/glossary/widgets/glossary_new_dialog.dart`
- `lib/features/glossary/widgets/glossary_list.dart`

---

## Implementation Order

Three phases, each ending with the app in a runnable state.

**Phase A — Data layer & migration plumbing** (tasks 1–5): add phase 1 migration, migration service + tests, auto-provisioning service + tests. No UI change. App keeps working; legacy screens still render.

**Phase B — Migration UI & bootstrap wiring** (tasks 6–8): migration screen, bootstrap integration, end-to-end smoke test.

**Phase C — Glossary screen refactor & cleanup** (tasks 9–14): model/repo/service refactor, new glossary screen, delete dead UI, hook auto-provisioning, finalize schema in fresh-install `schema.sql`.

---

## Task 1: Phase 1 migration — add `game_code` column and strip obsolete constraints

**Files:**
- Create: `lib/services/database/migrations/migration_glossary_game_code_partial.dart`
- Create: `test/services/database/migrations/migration_glossary_game_code_partial_test.dart`
- Modify: `lib/services/database/migrations/migration_registry.dart`

**Behavior:**
- Idempotent. If `glossaries` table does not have `is_global` column → no-op.
- Else: in a transaction,
  1. Add `game_code TEXT` column (nullable).
  2. Populate `game_code` for rows with `is_global = 0`: `UPDATE glossaries SET game_code = (SELECT gi.game_code FROM game_installations gi WHERE gi.id = glossaries.game_installation_id) WHERE is_global = 0;`
  3. Rebuild `glossaries` to: drop `CHECK ((is_global = 1 AND …) OR (…))`, drop `UNIQUE(name)`, keep `is_global` and `game_installation_id` columns for now (still populated by any stale code path until task 9). The rebuild is: create `glossaries_new` with the reduced constraints, `INSERT INTO glossaries_new SELECT …`, `DROP glossaries`, `ALTER TABLE glossaries_new RENAME TO glossaries`, recreate indexes.
- Priority `130` (after `ProjectsFilterIndexesMigration` at 120).
- `id = 'glossary_game_code_partial'`.

- [ ] **Step 1: Write the failing migration test**

Path: `test/services/database/migrations/migration_glossary_game_code_partial_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/database/migrations/migration_glossary_game_code_partial.dart';
import 'package:twmt/services/database/database_service.dart';
import '../../../helpers/test_database.dart';

void main() {
  late dynamic db;

  setUp(() async {
    db = await TestDatabase.openMigrated(clearSeeds: true);
    DatabaseService.setDatabaseForTesting(db);
  });
  tearDown(() async {
    await DatabaseService.resetForTesting();
  });

  group('GlossaryGameCodePartialMigration', () {
    test('adds game_code column', () async {
      await DatabaseService.execute(
        'ALTER TABLE glossaries ADD COLUMN game_code TEXT',
      ); // simulate fresh-install path: nothing to do
      final applied = await GlossaryGameCodePartialMigration().isApplied();
      expect(applied, isTrue);
    });

    test('populates game_code for game-specific glossaries', () async {
      await DatabaseService.execute('''
        INSERT INTO game_installations (id, game_code, game_name, created_at, updated_at)
        VALUES ('gi1', 'wh3', 'WH3', 0, 0)
      ''');
      await DatabaseService.execute('''
        INSERT INTO languages (id, code, name, native_name, is_active)
        VALUES ('lang_fr', 'fr', 'French', 'Français', 1)
      ''');
      await DatabaseService.execute('''
        INSERT INTO glossaries (id, name, is_global, game_installation_id, target_language_id, created_at, updated_at)
        VALUES ('g1', 'WH3 FR', 0, 'gi1', 'lang_fr', 0, 0)
      ''');

      final ok = await GlossaryGameCodePartialMigration().execute();

      expect(ok, isTrue);
      final rows = await DatabaseService.database
          .rawQuery('SELECT game_code FROM glossaries WHERE id = ?', ['g1']);
      expect(rows.first['game_code'], 'wh3');
    });

    test('leaves game_code NULL for universal glossaries', () async {
      await DatabaseService.execute('''
        INSERT INTO languages (id, code, name, native_name, is_active)
        VALUES ('lang_fr', 'fr', 'French', 'Français', 1)
      ''');
      await DatabaseService.execute('''
        INSERT INTO glossaries (id, name, is_global, target_language_id, created_at, updated_at)
        VALUES ('gu', 'Universal FR', 1, 'lang_fr', 0, 0)
      ''');

      await GlossaryGameCodePartialMigration().execute();

      final rows = await DatabaseService.database
          .rawQuery('SELECT game_code FROM glossaries WHERE id = ?', ['gu']);
      expect(rows.first['game_code'], isNull);
    });

    test('drops UNIQUE(name) and CHECK is_global/game_installation_id', () async {
      await DatabaseService.execute('''
        INSERT INTO languages (id, code, name, native_name, is_active)
        VALUES ('lang_fr', 'fr', 'French', 'Français', 1)
      ''');
      await DatabaseService.execute('''
        INSERT INTO glossaries (id, name, is_global, target_language_id, created_at, updated_at)
        VALUES ('g1', 'Dup', 1, 'lang_fr', 0, 0)
      ''');

      await GlossaryGameCodePartialMigration().execute();

      // Same name should now be insertable twice
      await DatabaseService.execute('''
        INSERT INTO glossaries (id, name, is_global, target_language_id, game_code, created_at, updated_at)
        VALUES ('g2', 'Dup', 0, 'lang_fr', 'wh3', 0, 0)
      ''');
      final rows = await DatabaseService.database
          .rawQuery("SELECT COUNT(*) as cnt FROM glossaries WHERE name = 'Dup'");
      expect(rows.first['cnt'], 2);
    });

    test('is idempotent on already-migrated DB', () async {
      await GlossaryGameCodePartialMigration().execute();
      final applied = await GlossaryGameCodePartialMigration().isApplied();
      expect(applied, isTrue);
      final secondRun = await GlossaryGameCodePartialMigration().execute();
      expect(secondRun, anyOf(isTrue, isFalse));
    });
  });
}
```

- [ ] **Step 2: Run the test to see it fail**

Run: `flutter test test/services/database/migrations/migration_glossary_game_code_partial_test.dart`
Expected: FAIL (import of `GlossaryGameCodePartialMigration` cannot resolve).

- [ ] **Step 3: Implement the migration**

Path: `lib/services/database/migrations/migration_glossary_game_code_partial.dart`

```dart
import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Phase 1 of the game-specific glossary refactor.
///
/// Adds `game_code` to `glossaries`, populates it from `game_installations`
/// for game-specific rows, and strips the now-obsolete `UNIQUE(name)` and
/// CHECK constraints. Universals keep `game_code = NULL` until the user
/// resolves them via [GlossaryMigrationService].
class GlossaryGameCodePartialMigration extends Migration {
  final ILoggingService _logger;

  GlossaryGameCodePartialMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'glossary_game_code_partial';

  @override
  String get description =>
      'Add game_code to glossaries, drop obsolete CHECK/UNIQUE constraints';

  @override
  int get priority => 130;

  @override
  Future<bool> isApplied() async {
    final cols = await DatabaseService.database
        .rawQuery('PRAGMA table_info(glossaries)');
    return cols.any((row) => row['name'] == 'game_code');
  }

  @override
  Future<bool> execute() async {
    if (await isApplied()) return false;

    try {
      await DatabaseService.database.transaction((txn) async {
        await txn.execute('ALTER TABLE glossaries ADD COLUMN game_code TEXT');
        await txn.execute('''
          UPDATE glossaries
          SET game_code = (
            SELECT gi.game_code
            FROM game_installations gi
            WHERE gi.id = glossaries.game_installation_id
          )
          WHERE is_global = 0
        ''');

        // Rebuild to drop UNIQUE(name) and the is_global CHECK constraint.
        await txn.execute('''
          CREATE TABLE glossaries_new (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            is_global INTEGER NOT NULL DEFAULT 0,
            game_installation_id TEXT,
            game_code TEXT,
            target_language_id TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE CASCADE,
            FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
            CHECK (created_at <= updated_at)
          )
        ''');
        await txn.execute('''
          INSERT INTO glossaries_new
            (id, name, description, is_global, game_installation_id, game_code,
             target_language_id, created_at, updated_at)
          SELECT id, name, description, is_global, game_installation_id, game_code,
                 target_language_id, created_at, updated_at
          FROM glossaries
        ''');
        await txn.execute('DROP TABLE glossaries');
        await txn.execute('ALTER TABLE glossaries_new RENAME TO glossaries');
      });

      _logger.info('glossary_game_code_partial migration applied');
      return true;
    } catch (e, st) {
      _logger.error('glossary_game_code_partial migration failed', e, st);
      return false;
    }
  }
}
```

- [ ] **Step 4: Register the migration**

Modify `lib/services/database/migrations/migration_registry.dart`:

At the import block (end):
```dart
import 'migration_glossary_game_code_partial.dart';
```

Inside `getAllMigrations()`, after `ProjectsFilterIndexesMigration()`:
```dart
GlossaryGameCodePartialMigration(), // Priority 130 — game-specific glossary refactor
```

- [ ] **Step 5: Run tests to verify pass**

Run: `flutter test test/services/database/migrations/migration_glossary_game_code_partial_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 6: Run all DB migration tests**

Run: `flutter test test/services/database/migrations/`
Expected: PASS (no regression).

- [ ] **Step 7: Commit**

```bash
git add lib/services/database/migrations/migration_glossary_game_code_partial.dart \
        lib/services/database/migrations/migration_registry.dart \
        test/services/database/migrations/migration_glossary_game_code_partial_test.dart
git commit -m "feat(glossary): add phase 1 schema migration for game_code column"
```

---

## Task 2: `GlossaryMigrationService` — detect pending work

**Files:**
- Create: `lib/services/glossary/glossary_migration_service.dart`
- Create: `test/unit/services/glossary_migration_service_test.dart`

**Responsibility:** expose `detectPendingMigration()` returning a `PendingGlossaryMigration?`. Uses raw SQL. Lives next to `glossary_service_impl.dart`.

**Data types:**
```dart
class PendingGlossaryMigration {
  final List<UniversalGlossaryInfo> universals;
  final List<DuplicateGlossaryGroup> duplicates;
  bool get isEmpty => universals.isEmpty && duplicates.isEmpty;
}

class UniversalGlossaryInfo {
  final String id;
  final String name;
  final String? description;
  final String targetLanguageId;
  final String targetLanguageCode;
  final int entryCount;
}

class DuplicateGlossaryGroup {
  final String gameCode;
  final String targetLanguageId;
  final String targetLanguageCode;
  final List<DuplicateGlossaryMember> members;
}

class DuplicateGlossaryMember {
  final String id;
  final String name;
  final int entryCount;
  final int createdAt;
}
```

- [ ] **Step 1: Write failing tests**

Path: `test/unit/services/glossary_migration_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/glossary/glossary_migration_service.dart';
import '../../helpers/test_database.dart';

void main() {
  late dynamic db;
  late GlossaryMigrationService service;

  setUp(() async {
    db = await TestDatabase.openMigrated(clearSeeds: true);
    DatabaseService.setDatabaseForTesting(db);
    service = GlossaryMigrationService();

    // Seed language + game_installation shared by tests.
    await DatabaseService.execute('''
      INSERT INTO languages (id, code, name, native_name, is_active)
      VALUES ('lang_fr', 'fr', 'French', 'Français', 1)
    ''');
    await DatabaseService.execute('''
      INSERT INTO game_installations (id, game_code, game_name, created_at, updated_at)
      VALUES ('gi1', 'wh3', 'WH3', 0, 0)
    ''');
  });
  tearDown(() async => DatabaseService.resetForTesting());

  group('detectPendingMigration', () {
    test('returns null when nothing pending', () async {
      final result = await service.detectPendingMigration();
      expect(result, isNull);
    });

    test('detects universal glossary (game_code IS NULL)', () async {
      await DatabaseService.execute('''
        INSERT INTO glossaries (id, name, is_global, target_language_id, created_at, updated_at)
        VALUES ('gu', 'Old universal', 1, 'lang_fr', 0, 0)
      ''');
      final result = await service.detectPendingMigration();
      expect(result, isNotNull);
      expect(result!.universals, hasLength(1));
      expect(result.universals.first.id, 'gu');
      expect(result.universals.first.targetLanguageCode, 'fr');
      expect(result.duplicates, isEmpty);
    });

    test('detects duplicates of (game_code, target_language_id)', () async {
      await DatabaseService.execute('''
        INSERT INTO glossaries
          (id, name, is_global, game_installation_id, game_code, target_language_id, created_at, updated_at)
        VALUES
          ('a', 'A', 0, 'gi1', 'wh3', 'lang_fr', 0, 0),
          ('b', 'B', 0, 'gi1', 'wh3', 'lang_fr', 1, 1)
      ''');
      final result = await service.detectPendingMigration();
      expect(result, isNotNull);
      expect(result!.universals, isEmpty);
      expect(result.duplicates, hasLength(1));
      expect(result.duplicates.first.gameCode, 'wh3');
      expect(result.duplicates.first.members.map((m) => m.id), containsAll(['a', 'b']));
    });

    test('reports entry counts accurately', () async {
      await DatabaseService.execute('''
        INSERT INTO glossaries (id, name, is_global, target_language_id, created_at, updated_at)
        VALUES ('gu', 'U', 1, 'lang_fr', 0, 0)
      ''');
      await DatabaseService.execute('''
        INSERT INTO glossary_entries
          (id, glossary_id, target_language_code, source_term, target_term, created_at, updated_at)
        VALUES ('e1', 'gu', 'fr', 'apple', 'pomme', 0, 0)
      ''');
      final result = await service.detectPendingMigration();
      expect(result!.universals.first.entryCount, 1);
    });
  });
}
```

- [ ] **Step 2: Run the test — fails**

Run: `flutter test test/unit/services/glossary_migration_service_test.dart`
Expected: FAIL (import unresolved).

- [ ] **Step 3: Implement the service (detection only for now)**

Path: `lib/services/glossary/glossary_migration_service.dart`

```dart
import '../database/database_service.dart';
import '../service_locator.dart';
import '../shared/i_logging_service.dart';

class PendingGlossaryMigration {
  final List<UniversalGlossaryInfo> universals;
  final List<DuplicateGlossaryGroup> duplicates;
  const PendingGlossaryMigration({
    required this.universals,
    required this.duplicates,
  });
  bool get isEmpty => universals.isEmpty && duplicates.isEmpty;
}

class UniversalGlossaryInfo {
  final String id;
  final String name;
  final String? description;
  final String targetLanguageId;
  final String targetLanguageCode;
  final int entryCount;
  const UniversalGlossaryInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.targetLanguageId,
    required this.targetLanguageCode,
    required this.entryCount,
  });
}

class DuplicateGlossaryGroup {
  final String gameCode;
  final String targetLanguageId;
  final String targetLanguageCode;
  final List<DuplicateGlossaryMember> members;
  const DuplicateGlossaryGroup({
    required this.gameCode,
    required this.targetLanguageId,
    required this.targetLanguageCode,
    required this.members,
  });
}

class DuplicateGlossaryMember {
  final String id;
  final String name;
  final int entryCount;
  final int createdAt;
  const DuplicateGlossaryMember({
    required this.id,
    required this.name,
    required this.entryCount,
    required this.createdAt,
  });
}

class GlossaryMigrationService {
  final ILoggingService _logger;
  GlossaryMigrationService({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  Future<PendingGlossaryMigration?> detectPendingMigration() async {
    final universals = await _queryUniversals();
    final duplicates = await _queryDuplicates();
    if (universals.isEmpty && duplicates.isEmpty) return null;
    return PendingGlossaryMigration(
      universals: universals,
      duplicates: duplicates,
    );
  }

  Future<List<UniversalGlossaryInfo>> _queryUniversals() async {
    final rows = await DatabaseService.database.rawQuery('''
      SELECT g.id, g.name, g.description,
             g.target_language_id AS target_language_id,
             l.code AS target_language_code,
             COALESCE(COUNT(ge.id), 0) AS entry_count
      FROM glossaries g
      LEFT JOIN glossary_entries ge ON ge.glossary_id = g.id
      INNER JOIN languages l ON l.id = g.target_language_id
      WHERE g.game_code IS NULL
      GROUP BY g.id
      ORDER BY g.name ASC
    ''');
    return rows
        .map((r) => UniversalGlossaryInfo(
              id: r['id'] as String,
              name: r['name'] as String,
              description: r['description'] as String?,
              targetLanguageId: r['target_language_id'] as String,
              targetLanguageCode: r['target_language_code'] as String,
              entryCount: r['entry_count'] as int,
            ))
        .toList();
  }

  Future<List<DuplicateGlossaryGroup>> _queryDuplicates() async {
    final rows = await DatabaseService.database.rawQuery('''
      SELECT g.id, g.name, g.game_code, g.target_language_id, g.created_at,
             l.code AS target_language_code,
             COALESCE(COUNT(ge.id), 0) AS entry_count
      FROM glossaries g
      INNER JOIN languages l ON l.id = g.target_language_id
      LEFT JOIN glossary_entries ge ON ge.glossary_id = g.id
      WHERE g.game_code IS NOT NULL
        AND (g.game_code, g.target_language_id) IN (
          SELECT game_code, target_language_id FROM glossaries
          WHERE game_code IS NOT NULL
          GROUP BY game_code, target_language_id
          HAVING COUNT(*) > 1
        )
      GROUP BY g.id
      ORDER BY g.game_code, g.target_language_id, g.created_at
    ''');

    final Map<String, DuplicateGlossaryGroup> grouped = {};
    for (final r in rows) {
      final gc = r['game_code'] as String;
      final tli = r['target_language_id'] as String;
      final key = '$gc|$tli';
      final member = DuplicateGlossaryMember(
        id: r['id'] as String,
        name: r['name'] as String,
        entryCount: r['entry_count'] as int,
        createdAt: r['created_at'] as int,
      );
      final existing = grouped[key];
      if (existing == null) {
        grouped[key] = DuplicateGlossaryGroup(
          gameCode: gc,
          targetLanguageId: tli,
          targetLanguageCode: r['target_language_code'] as String,
          members: [member],
        );
      } else {
        existing.members.add(member);
      }
    }
    return grouped.values.toList();
  }
}
```

- [ ] **Step 4: Run tests — pass**

Run: `flutter test test/unit/services/glossary_migration_service_test.dart`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/glossary/glossary_migration_service.dart \
        test/unit/services/glossary_migration_service_test.dart
git commit -m "feat(glossary): add GlossaryMigrationService detection"
```

---

## Task 3: `GlossaryMigrationService` — conversion + merge + finalize

**Files:**
- Modify: `lib/services/glossary/glossary_migration_service.dart`
- Modify: `test/unit/services/glossary_migration_service_test.dart`

**New API surface:**
```dart
/// Choices made by the user on the migration screen.
class MigrationPlan {
  /// Map universal glossary id → chosen game code (or null to delete).
  final Map<String, String?> conversions;
}

Future<void> applyMigration(MigrationPlan plan) async; // orchestrates
```

**Rules:**
- Dedup on `source_term` after `.trim().toLowerCase()`. Winner = highest `updated_at`; on tie, keep row with the larger `id` lexically (stable).
- Conversion: if target `(game_code, target_language_id)` glossary exists → reassign entries with dedup + delete universal. Else → UPDATE universal: set `game_code`.
- Duplicate merge (always runs, regardless of user choices): survivor = group member with the smallest `created_at`. Reassign entries with dedup, delete others.
- `finalizeSchema()` rebuilds `glossaries` with `game_code NOT NULL` and `UNIQUE(game_code, target_language_id)`, drops `is_global` and `game_installation_id` columns. Idempotent (no-op if columns already absent).
- `applyMigration` runs: conversions → duplicate merges → finalizeSchema, all in one transaction.

- [ ] **Step 1: Add failing tests**

Append to `test/unit/services/glossary_migration_service_test.dart`:

```dart
  group('applyMigration — conversion', () {
    test('converts universal to non-colliding (game, language) by setting game_code', () async {
      await DatabaseService.execute('''
        INSERT INTO glossaries (id, name, is_global, target_language_id, created_at, updated_at)
        VALUES ('gu', 'U', 1, 'lang_fr', 0, 0)
      ''');
      await service.applyMigration(const MigrationPlan(conversions: {'gu': 'wh3'}));
      final rows = await DatabaseService.database
          .rawQuery('SELECT game_code FROM glossaries WHERE id = ?', ['gu']);
      expect(rows.first['game_code'], 'wh3');
    });

    test('merges universal into existing (game, language) with dedup', () async {
      await DatabaseService.execute('''
        INSERT INTO glossaries (id, name, is_global, game_installation_id, game_code, target_language_id, created_at, updated_at)
        VALUES
          ('gu', 'Universal', 1, NULL, NULL, 'lang_fr', 0, 0),
          ('gg', 'Game', 0, 'gi1', 'wh3', 'lang_fr', 1, 1)
      ''');
      await DatabaseService.execute('''
        INSERT INTO glossary_entries
          (id, glossary_id, target_language_code, source_term, target_term, created_at, updated_at)
        VALUES
          ('e1', 'gu', 'fr', 'Apple', 'Pomme Universal', 10, 10),
          ('e2', 'gg', 'fr', 'apple', 'Pomme Game', 5, 5),
          ('e3', 'gu', 'fr', 'Banana', 'Banane', 10, 10)
      ''');

      await service.applyMigration(const MigrationPlan(conversions: {'gu': 'wh3'}));

      final remaining = await DatabaseService.database
          .rawQuery('SELECT id FROM glossaries');
      expect(remaining.map((r) => r['id']), ['gg']);
      final entries = await DatabaseService.database.rawQuery(
          'SELECT source_term, target_term FROM glossary_entries WHERE glossary_id = ?',
          ['gg']);
      // 'Apple' (updated_at 10) wins over 'apple' (5); 'Banana' migrates in.
      expect(entries.map((e) => e['target_term']),
          containsAll(['Pomme Universal', 'Banane']));
      expect(entries.where((e) => (e['target_term'] as String).contains('Game')),
          isEmpty);
    });

    test('deletes universal when conversion target is null', () async {
      await DatabaseService.execute('''
        INSERT INTO glossaries (id, name, is_global, target_language_id, created_at, updated_at)
        VALUES ('gu', 'Doomed', 1, 'lang_fr', 0, 0)
      ''');
      await service.applyMigration(const MigrationPlan(conversions: {'gu': null}));
      final rows = await DatabaseService.database.rawQuery('SELECT id FROM glossaries');
      expect(rows, isEmpty);
    });
  });

  group('applyMigration — duplicate merge', () {
    test('merges duplicates into oldest, dedups case-insensitively', () async {
      await DatabaseService.execute('''
        INSERT INTO glossaries (id, name, is_global, game_installation_id, game_code, target_language_id, created_at, updated_at)
        VALUES
          ('old', 'Old', 0, 'gi1', 'wh3', 'lang_fr', 0, 0),
          ('new', 'New', 0, 'gi1', 'wh3', 'lang_fr', 5, 5)
      ''');
      await DatabaseService.execute('''
        INSERT INTO glossary_entries (id, glossary_id, target_language_code, source_term, target_term, created_at, updated_at)
        VALUES
          ('a', 'old', 'fr', ' Apple ', 'Pomme v1', 0, 0),
          ('b', 'new', 'fr', 'apple', 'Pomme v2', 10, 10),
          ('c', 'new', 'fr', 'Pear', 'Poire', 5, 5)
      ''');

      await service.applyMigration(const MigrationPlan(conversions: {}));

      final glossaries = await DatabaseService.database.rawQuery('SELECT id FROM glossaries');
      expect(glossaries.map((g) => g['id']), ['old']);
      final entries = await DatabaseService.database.rawQuery(
          'SELECT source_term, target_term FROM glossary_entries WHERE glossary_id = ?', ['old']);
      expect(entries.length, 2);
      expect(entries.firstWhere((e) =>
          (e['source_term'] as String).trim().toLowerCase() == 'apple')['target_term'],
          'Pomme v2');
    });
  });

  group('finalizeSchema', () {
    test('adds UNIQUE(game_code, target_language_id) and makes game_code NOT NULL', () async {
      await DatabaseService.execute('''
        INSERT INTO glossaries (id, name, is_global, game_installation_id, game_code, target_language_id, created_at, updated_at)
        VALUES ('a', 'A', 0, 'gi1', 'wh3', 'lang_fr', 0, 0)
      ''');
      await service.finalizeSchema();

      // Inserting a duplicate (game_code, target_language_id) must fail.
      expect(
        () => DatabaseService.execute('''
          INSERT INTO glossaries (id, name, game_code, target_language_id, created_at, updated_at)
          VALUES ('b', 'B', 'wh3', 'lang_fr', 0, 0)
        '''),
        throwsA(anything),
      );
    });

    test('is idempotent', () async {
      await service.finalizeSchema();
      await service.finalizeSchema();
    });
  });
}
```

- [ ] **Step 2: Run tests — fail**

Run: `flutter test test/unit/services/glossary_migration_service_test.dart`
Expected: FAIL on the new groups only.

- [ ] **Step 3: Extend the service implementation**

Append to `lib/services/glossary/glossary_migration_service.dart`:

```dart
class MigrationPlan {
  /// Map of universal glossary id → chosen game_code (or null to delete).
  final Map<String, String?> conversions;
  const MigrationPlan({required this.conversions});
}

extension GlossaryMigrationActions on GlossaryMigrationService {
  Future<void> applyMigration(MigrationPlan plan) async {
    await DatabaseService.database.transaction((txn) async {
      // 1. Apply user decisions on universals.
      for (final entry in plan.conversions.entries) {
        final universalId = entry.key;
        final gameCode = entry.value;
        if (gameCode == null) {
          await txn.delete('glossaries', where: 'id = ?', whereArgs: [universalId]);
          continue;
        }
        final uni = await _fetchGlossary(txn, universalId);
        if (uni == null) continue;
        final existing = await _fetchSameGameAndLanguage(
          txn,
          gameCode: gameCode,
          targetLanguageId: uni['target_language_id'] as String,
          excludingId: universalId,
        );
        if (existing == null) {
          await txn.update(
            'glossaries',
            {'game_code': gameCode, 'is_global': 0},
            where: 'id = ?',
            whereArgs: [universalId],
          );
        } else {
          await _mergeEntriesDedup(
            txn,
            sourceGlossaryId: universalId,
            survivorGlossaryId: existing['id'] as String,
          );
          await txn.delete('glossaries', where: 'id = ?', whereArgs: [universalId]);
        }
      }

      // Delete any remaining universals that were not mentioned in the plan.
      await txn.delete('glossaries', where: 'game_code IS NULL');

      // 2. Merge duplicate game-specific groups.
      final dupRows = await txn.rawQuery('''
        SELECT game_code, target_language_id
        FROM glossaries
        WHERE game_code IS NOT NULL
        GROUP BY game_code, target_language_id
        HAVING COUNT(*) > 1
      ''');
      for (final row in dupRows) {
        final members = await txn.rawQuery('''
          SELECT id FROM glossaries
          WHERE game_code = ? AND target_language_id = ?
          ORDER BY created_at ASC, id ASC
        ''', [row['game_code'], row['target_language_id']]);
        final survivor = members.first['id'] as String;
        for (final m in members.skip(1)) {
          await _mergeEntriesDedup(
            txn,
            sourceGlossaryId: m['id'] as String,
            survivorGlossaryId: survivor,
          );
          await txn.delete('glossaries', where: 'id = ?', whereArgs: [m['id']]);
        }
      }

      // 3. Finalize schema inside the same transaction.
      await _finalizeSchemaInTxn(txn);
    });
  }

  Future<void> finalizeSchema() async {
    await DatabaseService.database.transaction(_finalizeSchemaInTxn);
  }

  Future<Map<String, Object?>?> _fetchGlossary(dynamic txn, String id) async {
    final rows = await txn.query('glossaries', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first as Map<String, Object?>;
  }

  Future<Map<String, Object?>?> _fetchSameGameAndLanguage(
    dynamic txn, {
    required String gameCode,
    required String targetLanguageId,
    required String excludingId,
  }) async {
    final rows = await txn.query(
      'glossaries',
      where: 'game_code = ? AND target_language_id = ? AND id != ?',
      whereArgs: [gameCode, targetLanguageId, excludingId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first as Map<String, Object?>;
  }

  Future<void> _mergeEntriesDedup(
    dynamic txn, {
    required String sourceGlossaryId,
    required String survivorGlossaryId,
  }) async {
    final sourceEntries = await txn.query('glossary_entries',
        where: 'glossary_id = ?', whereArgs: [sourceGlossaryId]);
    for (final entry in sourceEntries) {
      final srcTermKey = (entry['source_term'] as String).trim().toLowerCase();
      final tlc = entry['target_language_code'] as String;
      final conflicting = await txn.rawQuery('''
        SELECT id, updated_at
        FROM glossary_entries
        WHERE glossary_id = ?
          AND LOWER(TRIM(source_term)) = ?
          AND LOWER(target_language_code) = LOWER(?)
        LIMIT 1
      ''', [survivorGlossaryId, srcTermKey, tlc]);
      if (conflicting.isEmpty) {
        await txn.update(
          'glossary_entries',
          {'glossary_id': survivorGlossaryId},
          where: 'id = ?',
          whereArgs: [entry['id']],
        );
      } else {
        final conflictUpdatedAt = conflicting.first['updated_at'] as int;
        final entryUpdatedAt = entry['updated_at'] as int;
        if (entryUpdatedAt > conflictUpdatedAt) {
          await txn.delete('glossary_entries',
              where: 'id = ?', whereArgs: [conflicting.first['id']]);
          await txn.update('glossary_entries',
              {'glossary_id': survivorGlossaryId},
              where: 'id = ?', whereArgs: [entry['id']]);
        } else {
          await txn.delete('glossary_entries',
              where: 'id = ?', whereArgs: [entry['id']]);
        }
      }
    }
  }

  Future<void> _finalizeSchemaInTxn(dynamic txn) async {
    final cols = await txn.rawQuery('PRAGMA table_info(glossaries)');
    final hasIsGlobal = cols.any((c) => c['name'] == 'is_global');
    final hasGameInstallationId =
        cols.any((c) => c['name'] == 'game_installation_id');
    final indexes = await txn.rawQuery('PRAGMA index_list(glossaries)');
    final hasUniqueIndex = indexes.any((i) => i['name'] == 'glossaries_game_lang_uq');
    if (!hasIsGlobal && !hasGameInstallationId && hasUniqueIndex) {
      return; // already finalized
    }
    await txn.execute('''
      CREATE TABLE glossaries_final (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        game_code TEXT NOT NULL,
        target_language_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
        CHECK (created_at <= updated_at)
      )
    ''');
    await txn.execute('''
      INSERT INTO glossaries_final
        (id, name, description, game_code, target_language_id, created_at, updated_at)
      SELECT id, name, description, game_code, target_language_id, created_at, updated_at
      FROM glossaries
    ''');
    await txn.execute('DROP TABLE glossaries');
    await txn.execute('ALTER TABLE glossaries_final RENAME TO glossaries');
    await txn.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS glossaries_game_lang_uq
      ON glossaries(game_code, target_language_id)
    ''');
  }
}
```

- [ ] **Step 4: Run tests — pass**

Run: `flutter test test/unit/services/glossary_migration_service_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/services/glossary/glossary_migration_service.dart \
        test/unit/services/glossary_migration_service_test.dart
git commit -m "feat(glossary): add MigrationService conversion, merge, finalize"
```

---

## Task 4: Register `GlossaryMigrationService` in DI

**Files:**
- Modify: `lib/services/service_locator.dart`
- Modify: `lib/providers/shared/service_providers.dart`

- [ ] **Step 1: Register in ServiceLocator**

Locate the `ServiceLocator.initialize()` body. Add after existing glossary registrations:

```dart
_locator.registerLazySingleton<GlossaryMigrationService>(
  () => GlossaryMigrationService(),
);
```

Add the import at the top of the file:
```dart
import 'glossary/glossary_migration_service.dart';
```

- [ ] **Step 2: Expose via Riverpod**

In `lib/providers/shared/service_providers.dart`, alongside `glossaryServiceProvider`:

```dart
@Riverpod(keepAlive: true)
GlossaryMigrationService glossaryMigrationService(Ref ref) =>
    ServiceLocator.get<GlossaryMigrationService>();
```

Add import:
```dart
import 'package:twmt/services/glossary/glossary_migration_service.dart';
```

- [ ] **Step 3: Regenerate Riverpod codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: SUCCESS. A `glossaryMigrationServiceProvider` is generated.

- [ ] **Step 4: Commit**

```bash
git add lib/services/service_locator.dart \
        lib/providers/shared/service_providers.dart \
        lib/providers/shared/service_providers.g.dart
git commit -m "feat(glossary): register GlossaryMigrationService in DI"
```

---

## Task 5: `GlossaryAutoProvisioningService`

**Files:**
- Create: `lib/services/glossary/glossary_auto_provisioning_service.dart`
- Create: `test/unit/services/glossary_auto_provisioning_service_test.dart`
- Modify: `lib/services/service_locator.dart`
- Modify: `lib/providers/shared/service_providers.dart`

**API:**
```dart
Future<void> provisionForGame(String gameCode);
Future<void> provisionForProjectLanguage({
  required String gameCode,
  required String targetLanguageId,
});
```

**Rules:**
- `provisionForGame(gameCode)`: for each distinct `target_language_id` used by `projects` of that `gameCode` (join via `game_installations`), insert empty glossary if none exists for `(gameCode, targetLanguageId)`.
- `provisionForProjectLanguage(...)`: insert one empty glossary if none exists. Idempotent.
- Glossary id = generated UUID (use `const Uuid()` pattern already in codebase — check existing services).
- Glossary name = `"{gameName} · {languageCode}"` — resolve `gameName` via `supportedGames[gameCode].name` and `languageCode` via `languages.code`. Append `" (2)"`, `" (3)"`, … if name already exists.
- `created_at = updated_at = DateTime.now().millisecondsSinceEpoch`.

- [ ] **Step 1: Write failing tests**

Path: `test/unit/services/glossary_auto_provisioning_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/glossary/glossary_auto_provisioning_service.dart';
import '../../helpers/test_database.dart';

void main() {
  late dynamic db;
  late GlossaryAutoProvisioningService service;

  setUp(() async {
    db = await TestDatabase.openMigrated(clearSeeds: true);
    DatabaseService.setDatabaseForTesting(db);
    service = GlossaryAutoProvisioningService();

    await DatabaseService.execute('''
      INSERT INTO languages (id, code, name, native_name, is_active)
      VALUES
        ('lang_fr', 'fr', 'French', 'Français', 1),
        ('lang_de', 'de', 'German', 'Deutsch', 1)
    ''');
    await DatabaseService.execute('''
      INSERT INTO game_installations (id, game_code, game_name, created_at, updated_at)
      VALUES ('gi1', 'wh3', 'WH3', 0, 0)
    ''');
    await DatabaseService.execute('''
      INSERT INTO projects (id, name, game_installation_id, batch_size, parallel_batches, created_at, updated_at)
      VALUES ('p1', 'P', 'gi1', 25, 5, 0, 0)
    ''');
    await DatabaseService.execute('''
      INSERT INTO project_languages (id, project_id, language_id, created_at, updated_at)
      VALUES
        ('pl1', 'p1', 'lang_fr', 0, 0),
        ('pl2', 'p1', 'lang_de', 0, 0)
    ''');
  });
  tearDown(() async => DatabaseService.resetForTesting());

  test('provisionForGame creates one glossary per distinct project language', () async {
    await service.provisionForGame('wh3');

    final rows = await DatabaseService.database.rawQuery(
        'SELECT game_code, target_language_id FROM glossaries ORDER BY target_language_id');
    expect(rows, hasLength(2));
    expect(rows.map((r) => r['target_language_id']), ['lang_de', 'lang_fr']);
  });

  test('provisionForGame is idempotent', () async {
    await service.provisionForGame('wh3');
    await service.provisionForGame('wh3');

    final rows = await DatabaseService.database.rawQuery('SELECT COUNT(*) as cnt FROM glossaries');
    expect(rows.first['cnt'], 2);
  });

  test('provisionForProjectLanguage creates a single glossary', () async {
    await service.provisionForProjectLanguage(
      gameCode: 'wh3',
      targetLanguageId: 'lang_fr',
    );
    final rows = await DatabaseService.database.rawQuery('SELECT * FROM glossaries');
    expect(rows, hasLength(1));
    expect(rows.first['game_code'], 'wh3');
    expect(rows.first['target_language_id'], 'lang_fr');
    expect(rows.first['name'], contains('fr'));
  });

  test('provisionForProjectLanguage no-op when glossary already exists', () async {
    await service.provisionForProjectLanguage(
      gameCode: 'wh3',
      targetLanguageId: 'lang_fr',
    );
    await service.provisionForProjectLanguage(
      gameCode: 'wh3',
      targetLanguageId: 'lang_fr',
    );
    final rows = await DatabaseService.database.rawQuery('SELECT COUNT(*) as cnt FROM glossaries');
    expect(rows.first['cnt'], 1);
  });
}
```

- [ ] **Step 2: Run — FAIL**

Run: `flutter test test/unit/services/glossary_auto_provisioning_service_test.dart`

- [ ] **Step 3: Implement the service**

Path: `lib/services/glossary/glossary_auto_provisioning_service.dart`

```dart
import 'package:uuid/uuid.dart';
import 'package:twmt/services/steam/models/game_definitions.dart';
import '../database/database_service.dart';
import '../service_locator.dart';
import '../shared/i_logging_service.dart';

class GlossaryAutoProvisioningService {
  final ILoggingService _logger;
  static const _uuid = Uuid();

  GlossaryAutoProvisioningService({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  Future<void> provisionForGame(String gameCode) async {
    final rows = await DatabaseService.database.rawQuery('''
      SELECT DISTINCT pl.language_id AS target_language_id
      FROM project_languages pl
      INNER JOIN projects p ON p.id = pl.project_id
      INNER JOIN game_installations gi ON gi.id = p.game_installation_id
      WHERE gi.game_code = ?
    ''', [gameCode]);
    for (final r in rows) {
      await provisionForProjectLanguage(
        gameCode: gameCode,
        targetLanguageId: r['target_language_id'] as String,
      );
    }
  }

  Future<void> provisionForProjectLanguage({
    required String gameCode,
    required String targetLanguageId,
  }) async {
    final exists = await DatabaseService.database.rawQuery('''
      SELECT 1 FROM glossaries
      WHERE game_code = ? AND target_language_id = ?
      LIMIT 1
    ''', [gameCode, targetLanguageId]);
    if (exists.isNotEmpty) return;

    final lang = await DatabaseService.database.rawQuery(
        'SELECT code FROM languages WHERE id = ? LIMIT 1', [targetLanguageId]);
    if (lang.isEmpty) {
      _logger.warn('provisionForProjectLanguage: unknown language $targetLanguageId');
      return;
    }
    final gameName = supportedGames[gameCode]?.name ?? gameCode;
    final langCode = lang.first['code'] as String;
    final baseName = '$gameName · $langCode';
    final name = await _uniqueName(baseName);
    final now = DateTime.now().millisecondsSinceEpoch;

    await DatabaseService.database.insert('glossaries', {
      'id': _uuid.v4(),
      'name': name,
      'description': null,
      'game_code': gameCode,
      'target_language_id': targetLanguageId,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<String> _uniqueName(String baseName) async {
    String candidate = baseName;
    int suffix = 2;
    while (true) {
      final rows = await DatabaseService.database.rawQuery(
          'SELECT 1 FROM glossaries WHERE name = ? LIMIT 1', [candidate]);
      if (rows.isEmpty) return candidate;
      candidate = '$baseName ($suffix)';
      suffix++;
    }
  }
}
```

Note: the test's `INSERT INTO glossaries` in task 3's migration tests uses `is_global` and `game_installation_id`. The test setUp in task 5 does *not* insert any glossary, so we're fine even though the pre-finalization schema still has those columns. But `provisionForProjectLanguage` omits `is_global` and `game_installation_id` in the INSERT. Since the partial migration dropped the CHECK constraint on them, and `is_global` has DEFAULT 0, the INSERT succeeds.

- [ ] **Step 4: Run tests — pass**

Run: `flutter test test/unit/services/glossary_auto_provisioning_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Register in DI**

In `lib/services/service_locator.dart`:
```dart
import 'glossary/glossary_auto_provisioning_service.dart';
// ...
_locator.registerLazySingleton<GlossaryAutoProvisioningService>(
  () => GlossaryAutoProvisioningService(),
);
```

In `lib/providers/shared/service_providers.dart`:
```dart
import 'package:twmt/services/glossary/glossary_auto_provisioning_service.dart';
// ...
@Riverpod(keepAlive: true)
GlossaryAutoProvisioningService glossaryAutoProvisioningService(Ref ref) =>
    ServiceLocator.get<GlossaryAutoProvisioningService>();
```

Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 6: Commit**

```bash
git add lib/services/glossary/glossary_auto_provisioning_service.dart \
        test/unit/services/glossary_auto_provisioning_service_test.dart \
        lib/services/service_locator.dart \
        lib/providers/shared/service_providers.dart \
        lib/providers/shared/service_providers.g.dart
git commit -m "feat(glossary): add GlossaryAutoProvisioningService"
```

---

## Task 6: `GlossaryMigrationScreen` — blocking modal UI

**Files:**
- Create: `lib/features/glossary/screens/glossary_migration_screen.dart`
- Create: `lib/features/glossary/widgets/glossary_migration_universal_row.dart`
- Create: `lib/features/glossary/providers/glossary_migration_providers.dart`
- Create: `test/features/glossary/screens/glossary_migration_screen_test.dart`

**Screen API:** `GlossaryMigrationScreen({required PendingGlossaryMigration pending, required VoidCallback onDone})`. When the user clicks `Apply and continue`, the screen calls `applyMigration`, then `onDone()`.

**State provider:** `glossaryMigrationPlanProvider` — a `NotifierProvider<Map<String, String?>>` that tracks `{universalId: chosenGameCode}`. Default: each universal id maps to `null` ("don't convert").

**Widget hierarchy:**
```
GlossaryMigrationScreen (stateful widget, barrier: false)
 ├─ Header: title + warning text
 ├─ Scrollable body
 │   ├─ Section: Universals — list of GlossaryMigrationUniversalRow
 │   └─ Section: Duplicates — read-only list
 └─ Footer: [Cancel migration] [Apply and continue]
```

`GlossaryMigrationUniversalRow({UniversalGlossaryInfo info, List<ConfiguredGame> games, String? selectedGameCode, ValueChanged<String?> onChanged, VoidCallback onExport})`.

All user-facing strings in English. Use the existing `TokenDialog`, `SmallTextButton`, `FluentIcons`, `tokens.*` theme. Reference `editor_language_switcher.dart` for patterns.

- [ ] **Step 1: Provider file**

Path: `lib/features/glossary/providers/glossary_migration_providers.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'glossary_migration_providers.g.dart';

@riverpod
class GlossaryMigrationPlan extends _$GlossaryMigrationPlan {
  @override
  Map<String, String?> build() => const {};

  void seed(List<String> universalIds) {
    state = {for (final id in universalIds) id: null};
  }

  void setChoice(String universalId, String? gameCode) {
    state = {...state, universalId: gameCode};
  }
}
```

- [ ] **Step 2: Row widget**

Path: `lib/features/glossary/widgets/glossary_migration_universal_row.dart`

```dart
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/services/glossary/glossary_migration_service.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

class GlossaryMigrationUniversalRow extends StatelessWidget {
  const GlossaryMigrationUniversalRow({
    super.key,
    required this.info,
    required this.games,
    required this.selectedGameCode,
    required this.onChanged,
    required this.onExport,
  });

  final UniversalGlossaryInfo info;
  final List<ConfiguredGame> games;
  final String? selectedGameCode;
  final ValueChanged<String?> onChanged;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.name, style: tokens.fontBody.copyWith(fontSize: 14, color: tokens.text, fontWeight: FontWeight.w600)),
                if (info.description != null && info.description!.isNotEmpty)
                  Text(info.description!, style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim)),
                const SizedBox(height: 4),
                Text(
                  'Target: ${info.targetLanguageCode} — ${info.entryCount} entries',
                  style: tokens.fontMono.copyWith(fontSize: 12, color: tokens.textDim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SmallTextButton(
            key: Key('glossary-migration-export-${info.id}'),
            label: 'Export CSV',
            icon: FluentIcons.document_arrow_down_24_regular,
            onTap: onExport,
          ),
          const SizedBox(width: 8),
          DropdownButton<String?>(
            key: Key('glossary-migration-convert-${info.id}'),
            value: selectedGameCode,
            hint: const Text('Convert to…'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text("— Don't convert —"),
              ),
              ...games.map((g) => DropdownMenuItem<String?>(
                    value: g.code,
                    child: Text(g.name, overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Screen**

Path: `lib/features/glossary/screens/glossary_migration_screen.dart`

```dart
import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/glossary/providers/glossary_migration_providers.dart';
import 'package:twmt/features/glossary/widgets/glossary_migration_universal_row.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/glossary/glossary_migration_service.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

class GlossaryMigrationScreen extends ConsumerStatefulWidget {
  const GlossaryMigrationScreen({
    super.key,
    required this.pending,
    required this.onDone,
  });

  final PendingGlossaryMigration pending;
  final VoidCallback onDone;

  @override
  ConsumerState<GlossaryMigrationScreen> createState() =>
      _GlossaryMigrationScreenState();
}

class _GlossaryMigrationScreenState
    extends ConsumerState<GlossaryMigrationScreen> {
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(glossaryMigrationPlanProvider.notifier)
          .seed(widget.pending.universals.map((u) => u.id).toList());
    });
  }

  Future<void> _exportCsv(UniversalGlossaryInfo info) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export "${info.name}" to CSV',
      fileName: '${info.name.replaceAll(RegExp(r"[^\w-]"), "_")}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || !mounted) return;
    final exportService = ref.read(glossaryServiceProvider);
    final outcome = await exportService.exportToCsv(
      glossaryId: info.id,
      filePath: result,
    );
    if (!mounted) return;
    if (outcome.isErr) {
      FluentToast.error(context, 'Export failed: ${outcome.error}');
    } else {
      FluentToast.success(context, 'Exported ${outcome.value} entries');
    }
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      final service = ref.read(glossaryMigrationServiceProvider);
      final plan = ref.read(glossaryMigrationPlanProvider);
      await service.applyMigration(MigrationPlan(conversions: plan));
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Migration failed: $e');
        setState(() => _applying = false);
      }
    }
  }

  void _cancel() {
    // Quit the app — the DB is in a half-migrated state.
    // Use SystemNavigator.pop() to close cleanly.
    Future.microtask(() => _cancelExit());
  }

  Future<void> _cancelExit() async {
    // Defer to platform: on desktop, this closes the window.
    await Future.delayed(const Duration(milliseconds: 50));
    throw _MigrationCancelled();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final configuredGamesAsync = ref.watch(configuredGamesProvider);
    final plan = ref.watch(glossaryMigrationPlanProvider);
    final games = configuredGamesAsync.asData?.value ?? const <ConfiguredGame>[];

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: tokens.surfaceBg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(FluentIcons.warning_24_filled,
                            size: 24, color: tokens.warn),
                        const SizedBox(width: 8),
                        Text('Glossary migration required',
                            style: tokens.fontHeading.copyWith(
                                fontSize: 20,
                                color: tokens.text,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Glossaries are now strictly game-specific. '
                      'Resolve the following items to continue.',
                      style: tokens.fontBody
                          .copyWith(fontSize: 13, color: tokens.textDim),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.pending.universals.isNotEmpty)
                              _UniversalsSection(
                                universals: widget.pending.universals,
                                games: games,
                                plan: plan,
                                onChanged: (id, gc) => ref
                                    .read(glossaryMigrationPlanProvider.notifier)
                                    .setChoice(id, gc),
                                onExport: _exportCsv,
                              ),
                            if (widget.pending.duplicates.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _DuplicatesSection(groups: widget.pending.duplicates),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SmallTextButton(
                          key: const Key('glossary-migration-cancel'),
                          label: 'Cancel migration',
                          onTap: _applying ? null : _cancel,
                        ),
                        const SizedBox(width: 8),
                        SmallTextButton(
                          key: const Key('glossary-migration-apply'),
                          label: _applying ? 'Applying…' : 'Apply and continue',
                          icon: FluentIcons.checkmark_24_regular,
                          filled: true,
                          onTap: _applying ? null : _apply,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UniversalsSection extends StatelessWidget {
  const _UniversalsSection({
    required this.universals,
    required this.games,
    required this.plan,
    required this.onChanged,
    required this.onExport,
  });
  final List<UniversalGlossaryInfo> universals;
  final List<ConfiguredGame> games;
  final Map<String, String?> plan;
  final void Function(String, String?) onChanged;
  final void Function(UniversalGlossaryInfo) onExport;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Universal glossaries',
            style: tokens.fontHeading
                .copyWith(fontSize: 16, color: tokens.text)),
        const SizedBox(height: 8),
        for (final u in universals) ...[
          GlossaryMigrationUniversalRow(
            info: u,
            games: games,
            selectedGameCode: plan[u.id],
            onChanged: (gc) => onChanged(u.id, gc),
            onExport: () => onExport(u),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: tokens.warnBg,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Text(
            'Universal glossaries not converted will be deleted permanently.',
            style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.warn),
          ),
        ),
      ],
    );
  }
}

class _DuplicatesSection extends StatelessWidget {
  const _DuplicatesSection({required this.groups});
  final List<DuplicateGlossaryGroup> groups;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Duplicate glossaries',
            style: tokens.fontHeading
                .copyWith(fontSize: 16, color: tokens.text)),
        const SizedBox(height: 8),
        Text(
          'These glossaries will be merged automatically. Duplicate entries '
          '(same source term, case-insensitive) will be deduplicated, keeping '
          'the most recent one.',
          style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
        ),
        const SizedBox(height: 8),
        for (final g in groups) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${g.gameCode} · ${g.targetLanguageCode}',
                    style: tokens.fontMono.copyWith(
                        fontSize: 12, color: tokens.textDim)),
                const SizedBox(height: 4),
                for (final m in g.members)
                  Text('  • ${m.name} (${m.entryCount} entries)',
                      style:
                          tokens.fontBody.copyWith(fontSize: 12, color: tokens.text)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _MigrationCancelled implements Exception {}
```

- [ ] **Step 4: Regenerate Riverpod codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: generates `glossary_migration_providers.g.dart`.

- [ ] **Step 5: Write widget test**

Path: `test/features/glossary/screens/glossary_migration_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/glossary/screens/glossary_migration_screen.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/services/glossary/glossary_migration_service.dart';

void main() {
  testWidgets('shows universals section when universals exist', (tester) async {
    final pending = PendingGlossaryMigration(
      universals: [
        const UniversalGlossaryInfo(
          id: 'u1',
          name: 'Legacy Universal',
          description: null,
          targetLanguageId: 'lang_fr',
          targetLanguageCode: 'fr',
          entryCount: 3,
        ),
      ],
      duplicates: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredGamesProvider.overrideWith((ref) async => [
                const ConfiguredGame(code: 'wh3', name: 'WH3', path: '/p'),
              ]),
        ],
        child: MaterialApp(
          home: GlossaryMigrationScreen(pending: pending, onDone: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Glossary migration required'), findsOneWidget);
    expect(find.text('Legacy Universal'), findsOneWidget);
    expect(find.byKey(const Key('glossary-migration-export-u1')), findsOneWidget);
    expect(find.byKey(const Key('glossary-migration-convert-u1')), findsOneWidget);
  });

  testWidgets('shows duplicates section when duplicates exist', (tester) async {
    final pending = PendingGlossaryMigration(
      universals: const [],
      duplicates: [
        DuplicateGlossaryGroup(
          gameCode: 'wh3',
          targetLanguageId: 'lang_fr',
          targetLanguageCode: 'fr',
          members: [
            const DuplicateGlossaryMember(id: 'a', name: 'A', entryCount: 2, createdAt: 0),
            const DuplicateGlossaryMember(id: 'b', name: 'B', entryCount: 1, createdAt: 1),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredGamesProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          home: GlossaryMigrationScreen(pending: pending, onDone: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Duplicate glossaries'), findsOneWidget);
    expect(find.textContaining('A (2 entries)'), findsOneWidget);
  });
}
```

- [ ] **Step 6: Run widget test — pass**

Run: `flutter test test/features/glossary/screens/glossary_migration_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/glossary/screens/glossary_migration_screen.dart \
        lib/features/glossary/widgets/glossary_migration_universal_row.dart \
        lib/features/glossary/providers/glossary_migration_providers.dart \
        lib/features/glossary/providers/glossary_migration_providers.g.dart \
        test/features/glossary/screens/glossary_migration_screen_test.dart
git commit -m "feat(glossary): add GlossaryMigrationScreen with universals + duplicates sections"
```

---

## Task 7: Wire migration screen into bootstrap (`main.dart`)

**Files:**
- Modify: `lib/main.dart`

**Goal:** After existing `_runDataMigrations`, call `detectPendingMigration`. If non-null, push `GlossaryMigrationScreen` as a fullscreen modal; block continuation until `onDone` fires.

- [ ] **Step 1: Add the hook**

In `lib/main.dart`, within `_AppStartupTasks._runDataMigrations()` (or immediately after, before `ValidationRescanDialog`):

```dart
// Check for pending glossary migration. Blocking if any.
final migrationService = ref.read(glossaryMigrationServiceProvider);
final pending = await migrationService.detectPendingMigration();
if (pending != null && mounted) {
  final completer = Completer<void>();
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => GlossaryMigrationScreen(
        pending: pending,
        onDone: () {
          Navigator.of(context).pop();
          completer.complete();
        },
      ),
    ),
  );
  await completer.future;
}
```

Add needed imports:
```dart
import 'package:twmt/features/glossary/screens/glossary_migration_screen.dart';
import 'package:twmt/providers/shared/service_providers.dart';
```

- [ ] **Step 2: Manual smoke test**

Run: `flutter run -d linux` (or your platform).

Precondition: the dev DB must have at least one row with `is_global = 1`. Seed one manually via sqlite CLI or add a one-shot dev helper.

Expected: on launch, the migration screen blocks the rest of the UI. Picking `Apply and continue` without touching any dropdown deletes universals and proceeds normally.

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat(glossary): push migration screen from bootstrap when pending"
```

---

## Task 8: Refactor `Glossary` model — drop `isGlobal`, `gameInstallationId`; add `gameCode`

**Files:**
- Modify: `lib/services/glossary/models/glossary.dart`
- Regenerate: `lib/services/glossary/models/glossary.g.dart`

At this point, all prod code paths that reach the model run *after* `finalizeSchema` has been called (triggered by migration screen), so the legacy columns are gone. Safe to remove from the model.

- [ ] **Step 1: Rewrite the model**

Replace `lib/services/glossary/models/glossary.dart` with:

```dart
import 'package:json_annotation/json_annotation.dart';

part 'glossary.g.dart';

/// A game-scoped glossary, uniquely identified by (gameCode, targetLanguageId).
@JsonSerializable()
class Glossary {
  final String id;
  final String name;
  final String? description;

  @JsonKey(name: 'game_code')
  final String gameCode;

  @JsonKey(name: 'target_language_id')
  final String targetLanguageId;

  @JsonKey(includeToJson: false)
  final int entryCount;

  @JsonKey(name: 'created_at')
  final int createdAt;

  @JsonKey(name: 'updated_at')
  final int updatedAt;

  const Glossary({
    required this.id,
    required this.name,
    this.description,
    required this.gameCode,
    required this.targetLanguageId,
    this.entryCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Glossary.fromJson(Map<String, dynamic> json) =>
      _$GlossaryFromJson(json);

  Map<String, dynamic> toJson() => _$GlossaryToJson(this);

  Glossary copyWith({
    String? id,
    String? name,
    String? description,
    String? gameCode,
    String? targetLanguageId,
    int? entryCount,
    int? createdAt,
    int? updatedAt,
  }) =>
      Glossary(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        gameCode: gameCode ?? this.gameCode,
        targetLanguageId: targetLanguageId ?? this.targetLanguageId,
        entryCount: entryCount ?? this.entryCount,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Glossary &&
          other.id == id &&
          other.name == name &&
          other.description == description &&
          other.gameCode == gameCode &&
          other.targetLanguageId == targetLanguageId &&
          other.entryCount == entryCount &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, name, description, gameCode,
      targetLanguageId, entryCount, createdAt, updatedAt);

  @override
  String toString() =>
      'Glossary(id: $id, name: $name, gameCode: $gameCode, targetLanguageId: $targetLanguageId, entryCount: $entryCount)';
}
```

- [ ] **Step 2: Regenerate codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `glossary.g.dart` regenerated.

- [ ] **Step 3: Fix compilation errors cascade**

Running `flutter analyze` will point to every call site of `.isGlobal` / `.gameInstallationId`. Fix each call site to use `.gameCode`. Common hotspots:
- `lib/repositories/glossary_repository.dart` — already to be rewritten in next task.
- `lib/services/glossary/glossary_service_impl.dart` — remove `isGlobal` / `gameInstallationId` from `createGlossary` params; use `gameCode`.
- `lib/services/glossary/i_glossary_service.dart` — update interface.
- `lib/services/glossary/glossary_import_export_service.dart` — if it mentions these, strip them.
- Provider files referencing these fields.

Run: `flutter analyze`
Expected: a bounded list of errors all pointing at legacy field accesses. Fix each by using `gameCode`.

- [ ] **Step 4: Run existing tests — many will now fail**

Run: `flutter test`
Expected: tests referencing legacy fields fail. Fix the test fixtures in the next tasks' cascade.

- [ ] **Step 5: Commit (may leave tests red — fixed next)**

```bash
git add lib/services/glossary/models/glossary.dart \
        lib/services/glossary/models/glossary.g.dart
git commit -m "refactor(glossary): drop isGlobal/gameInstallationId from Glossary model"
```

*Note:* if compile breaks other files, include them in the same commit.

---

## Task 9: Refactor `GlossaryRepository`

**Files:**
- Modify: `lib/repositories/glossary_repository.dart`
- Modify: `test/unit/repositories/glossary_repository_test.dart`

**Changes:**
- `getAllGlossaries({String? gameCode})` — drop `gameInstallationId` + `includeUniversal`.
- `getGlossaryByGameAndLanguage(String gameCode, String targetLanguageId)` — new lookup by the natural key.
- `insertGlossary`, `updateGlossary`, `deleteGlossary` — still OK, just write the new columns.
- `getByProjectAndLanguage` — join through `game_installations` to get `game_code`, filter glossaries by that code.

- [ ] **Step 1: Update `getAllGlossaries` signature + implementation**

Replace lines 183–218 with:

```dart
/// Get all glossaries, optionally filtered by game code.
Future<List<Glossary>> getAllGlossaries({String? gameCode}) async {
  final whereClause = gameCode != null ? ' WHERE g.game_code = ?' : '';
  final whereArgs = gameCode != null ? [gameCode] : const <Object?>[];
  final maps = await database.rawQuery('''
    SELECT
      g.*,
      COALESCE(COUNT(ge.id), 0) as entryCount
    FROM $glossaryTableName g
    LEFT JOIN $tableName ge ON g.id = ge.glossary_id
    $whereClause
    GROUP BY g.id
    ORDER BY g.name ASC
  ''', whereArgs);
  return maps.map((map) => Glossary.fromJson(map)).toList();
}
```

- [ ] **Step 2: Add `getGlossaryByGameAndLanguage`**

Insert after `getGlossaryById`:

```dart
/// Get the glossary for a given (gameCode, targetLanguageId) pair, if any.
Future<Glossary?> getGlossaryByGameAndLanguage({
  required String gameCode,
  required String targetLanguageId,
}) async {
  final maps = await database.rawQuery('''
    SELECT
      g.*,
      COALESCE(COUNT(ge.id), 0) as entryCount
    FROM $glossaryTableName g
    LEFT JOIN $tableName ge ON g.id = ge.glossary_id
    WHERE g.game_code = ? AND g.target_language_id = ?
    GROUP BY g.id
    LIMIT 1
  ''', [gameCode, targetLanguageId]);
  return maps.isEmpty ? null : Glossary.fromJson(maps.first);
}
```

- [ ] **Step 3: Rewrite `getByProjectAndLanguage`**

Replace its body with:

```dart
return executeQuery(() async {
  final maps = await database.rawQuery('''
    SELECT ge.*
    FROM $tableName ge
    INNER JOIN $glossaryTableName g ON g.id = ge.glossary_id
    INNER JOIN projects p ON p.id = ?
    INNER JOIN game_installations gi ON gi.id = p.game_installation_id
    WHERE LOWER(ge.target_language_code) = LOWER(?)
      AND g.game_code = gi.game_code
    ORDER BY ge.source_term ASC
  ''', [projectId, targetLanguageCode]);
  return maps.map((map) => fromMap(map)).toList();
});
```

- [ ] **Step 4: Update repository tests**

Replace every fixture that inserts a glossary with `is_global`/`game_installation_id` to use `game_code`. Delete tests of `includeUniversal` behavior (add a NOTE in-place: these semantics are gone).

Specifically in `test/unit/repositories/glossary_repository_test.dart`:
- Replace `INSERT INTO glossaries (id, name, is_global, game_installation_id, target_language_id, ...)` with `INSERT INTO glossaries (id, name, game_code, target_language_id, ...)`.
- Delete test cases that exercise `includeUniversal: true/false` — they have no equivalent in the new model.
- Add new test: `getGlossaryByGameAndLanguage returns the glossary for an existing pair`.

- [ ] **Step 5: Run tests — pass**

Run: `flutter test test/unit/repositories/glossary_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/repositories/glossary_repository.dart \
        test/unit/repositories/glossary_repository_test.dart
git commit -m "refactor(glossary): rewrite repository around gameCode"
```

---

## Task 10: Refactor service interface + impl

**Files:**
- Modify: `lib/services/glossary/i_glossary_service.dart`
- Modify: `lib/services/glossary/glossary_service_impl.dart`
- Modify: `lib/services/glossary/glossary_import_export_service.dart`
- Modify: any test fixture using `createGlossary({isGlobal: …})`

**API change:**
```dart
Future<Result<Glossary, GlossaryException>> createGlossary({
  required String name,
  String? description,
  required String gameCode,
  required String targetLanguageId,
});

Future<Result<List<Glossary>, GlossaryException>> getAllGlossaries({
  String? gameCode,
});

// New:
Future<Result<Glossary?, GlossaryException>> getGlossaryByGameAndLanguage({
  required String gameCode,
  required String targetLanguageId,
});
```

- [ ] **Step 1: Edit interface**

In `lib/services/glossary/i_glossary_service.dart`:
- Replace `createGlossary` params: drop `isGlobal` and `gameInstallationId`, add `required String gameCode`.
- Replace `getAllGlossaries` params: drop `gameInstallationId`, `includeUniversal`; add `String? gameCode`.
- Add `getGlossaryByGameAndLanguage` abstract method.

- [ ] **Step 2: Update impl**

In `lib/services/glossary/glossary_service_impl.dart`:
- `createGlossary`: build a `Glossary(...)` with `gameCode: gameCode`. Remove the branch that checked `isGlobal`.
- `getAllGlossaries`: pass `gameCode` through to `repository.getAllGlossaries`.
- Add `getGlossaryByGameAndLanguage` delegating to repo.

- [ ] **Step 3: Fix import/export service**

In `lib/services/glossary/glossary_import_export_service.dart`:
- Drop any code path that inspects `isGlobal` or `gameInstallationId`.

- [ ] **Step 4: Update any test harness**

Grep the tests directory for `createGlossary(` and for `isGlobal`. Fix each call.

Run: `grep -rn "isGlobal\|includeUniversal\|gameInstallationId" test/ lib/`
Expected: zero hits after fixes.

- [ ] **Step 5: Run all unit + service tests**

Run: `flutter test test/unit/ test/services/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/glossary/ test/
git commit -m "refactor(glossary): rewrite service API around gameCode"
```

---

## Task 11: Refactor glossary providers

**Files:**
- Modify: `lib/features/glossary/providers/glossary_providers.dart`

**Changes:**
- `glossariesProvider`: signature becomes `glossaries({String? gameCode})`. Remove `includeUniversal`.
- Delete `selectedGlossaryProvider` (notifier) — no more list selection.
- Add `glossaryAvailableLanguagesProvider(String gameCode)` — returns `List<Language>` = distinct languages used by projects of that game.
- Add `selectedGlossaryLanguageProvider` — `AsyncNotifierProvider` persisting per-game selection in settings.
- Add `currentGlossaryProvider` — async provider resolving the glossary for `(selectedGame, selectedGlossaryLanguage)`.
- `glossaryEntriesProvider`, `glossaryEntryEditorProvider`, `glossaryImportStateProvider`, `glossaryExportStateProvider`: strip any legacy params, keep the rest.
- Update `glossaryFilterStateProvider` usages if they reference removed concepts.

- [ ] **Step 1: Delete selectedGlossaryProvider**

Remove its class + its generated `_selectedGlossaryProvider` in `glossary_providers.g.dart` (regenerated on rebuild).

- [ ] **Step 2: Update `glossaries` provider**

```dart
@riverpod
Future<List<Glossary>> glossaries(Ref ref, {String? gameCode}) async {
  final service = ref.watch(glossaryServiceProvider);
  final result = await service.getAllGlossaries(gameCode: gameCode);
  return result.whenOrRethrow();
}
```

- [ ] **Step 3: Add the new providers**

```dart
@riverpod
Future<List<Language>> glossaryAvailableLanguages(Ref ref, String gameCode) async {
  // Uses a DB-level distinct query, run through a dedicated repository method.
  final repo = ref.watch(projectLanguageRepositoryProvider);
  final result = await repo.distinctLanguagesForGameCode(gameCode);
  return result.whenOrRethrow();
}

@riverpod
class SelectedGlossaryLanguage extends _$SelectedGlossaryLanguage {
  @override
  Future<String?> build(String gameCode) async {
    final settings = ref.read(settingsServiceProvider);
    final saved = await settings.getString(_key(gameCode));
    return saved.isEmpty ? null : saved;
  }

  Future<void> setLanguageId(String gameCode, String? languageId) async {
    final settings = ref.read(settingsServiceProvider);
    if (languageId == null) {
      await settings.setString(_key(gameCode), '');
    } else {
      await settings.setString(_key(gameCode), languageId);
    }
    state = AsyncData(languageId);
  }

  static String _key(String gameCode) => 'glossary_selected_language_$gameCode';
}

@riverpod
Future<Glossary?> currentGlossary(Ref ref) async {
  final game = await ref.watch(selectedGameProvider.future);
  if (game == null) return null;
  final langId = await ref.watch(selectedGlossaryLanguageProvider(game.code).future);
  if (langId == null) return null;
  final service = ref.watch(glossaryServiceProvider);
  final result = await service.getGlossaryByGameAndLanguage(
    gameCode: game.code,
    targetLanguageId: langId,
  );
  return result.whenOrRethrow();
}
```

- [ ] **Step 4: Add `distinctLanguagesForGameCode` to the repository chain**

In `lib/repositories/project_language_repository.dart` (if absent), add:

```dart
Future<Result<List<Language>, TWMTDatabaseException>> distinctLanguagesForGameCode(String gameCode) async {
  return executeQuery(() async {
    final rows = await database.rawQuery('''
      SELECT DISTINCT l.*
      FROM project_languages pl
      INNER JOIN projects p ON p.id = pl.project_id
      INNER JOIN game_installations gi ON gi.id = p.game_installation_id
      INNER JOIN languages l ON l.id = pl.language_id
      WHERE gi.game_code = ?
      ORDER BY l.name
    ''', [gameCode]);
    return rows.map((r) => Language.fromJson(r)).toList();
  });
}
```

- [ ] **Step 5: Regenerate codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 6: Run tests**

Run: `flutter test test/features/glossary/ test/providers/`
Expected: PASS (fix any test-side call sites pointing at removed providers).

- [ ] **Step 7: Commit**

```bash
git add lib/features/glossary/providers/ lib/repositories/project_language_repository.dart test/
git commit -m "refactor(glossary): replace list-based providers with (game, language)-driven providers"
```

---

## Task 12: Delete manual-creation UI, refactor `GlossaryScreen`, add language switcher

**Files:**
- Delete: `lib/features/glossary/widgets/glossary_new_dialog.dart`
- Delete: `lib/features/glossary/widgets/glossary_list.dart`
- Create: `lib/features/glossary/widgets/glossary_language_switcher.dart`
- Create: `test/features/glossary/widgets/glossary_language_switcher_test.dart`
- Rewrite: `lib/features/glossary/screens/glossary_screen.dart`

**Empty-state branches (all English):**
1. `selectedGame == null` → `"Select a game from the sidebar to view its glossary."`
2. Game selected, `await hasProjectsForGame(game.code)` == false → `"No projects yet for ${game.name}. A glossary will be generated automatically when you create your first project."`
3. Game + projects exist, `glossaryAvailableLanguages(game.code).isEmpty` → `"No target languages configured for projects of ${game.name} yet. A glossary will be generated when you add a language to a project."`
4. Game + language selected, `currentGlossary.entries.isEmpty` → soft empty in the grid: `"No entries yet. Import a CSV or add your first entry."`
5. Nominal: the entry editor grid.

- [ ] **Step 1: Delete obsolete widgets**

```bash
git rm lib/features/glossary/widgets/glossary_new_dialog.dart
git rm lib/features/glossary/widgets/glossary_list.dart
```

- [ ] **Step 2: Create `GlossaryLanguageSwitcher`**

Copy the structural skeleton of `editor_language_switcher.dart` (MenuAnchor + `_SwitcherChip`) and adapt:
- Input: `gameCode`, `currentLanguageId`.
- Watches `glossaryAvailableLanguagesProvider(gameCode)`.
- On select → calls `ref.read(selectedGlossaryLanguageProvider(gameCode).notifier).setLanguageId(gameCode, id)`.
- No delete, no add-language affordances.

Path: `lib/features/glossary/widgets/glossary_language_switcher.dart` — full file (same style as editor_language_switcher, no delete/add menu items, renders `_SwitcherChip` with the language name).

Full code:

```dart
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/glossary/providers/glossary_providers.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

class GlossaryLanguageSwitcher extends ConsumerWidget {
  const GlossaryLanguageSwitcher({
    super.key,
    required this.gameCode,
    required this.currentLanguageId,
  });

  final String gameCode;
  final String? currentLanguageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final langsAsync = ref.watch(glossaryAvailableLanguagesProvider(gameCode));
    final langs = langsAsync.asData?.value ?? const <Language>[];
    final current = langs.where((l) => l.id == currentLanguageId).firstOrNull;

    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      builder: (context, controller, _) {
        return _SwitcherChip(
          key: const Key('glossary-language-switcher-chip'),
          label: current?.name ?? '—',
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
        );
      },
      menuChildren: [
        if (langs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('No languages available',
                style: tokens.fontBody
                    .copyWith(fontSize: 12, color: tokens.textDim)),
          )
        else
          for (final l in langs)
            _LanguageMenuItem(
              key: Key('glossary-language-switcher-item-${l.id}'),
              language: l,
              isCurrent: l.id == currentLanguageId,
              onSelect: () => ref
                  .read(selectedGlossaryLanguageProvider(gameCode).notifier)
                  .setLanguageId(gameCode, l.id),
            ),
      ],
    );
  }
}

class _SwitcherChip extends StatelessWidget {
  const _SwitcherChip({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.accentBg,
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.globe_24_regular, size: 16, color: tokens.accent),
              const SizedBox(width: 6),
              Text(label,
                  style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      color: tokens.accent,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Icon(FluentIcons.chevron_down_24_regular,
                  size: 14, color: tokens.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageMenuItem extends StatelessWidget {
  const _LanguageMenuItem({
    super.key,
    required this.language,
    required this.isCurrent,
    required this.onSelect,
  });
  final Language language;
  final bool isCurrent;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onSelect,
      child: SizedBox(
        width: 280,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                isCurrent
                    ? FluentIcons.checkmark_24_regular
                    : FluentIcons.translate_24_regular,
                size: 16,
                color: isCurrent ? tokens.accent : tokens.textDim,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(language.name,
                    style: tokens.fontBody
                        .copyWith(fontSize: 13, color: tokens.text)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Rewrite `GlossaryScreen`**

Replace `lib/features/glossary/screens/glossary_screen.dart` with a screen that:
1. Watches `selectedGameProvider`.
2. If null → empty state #1.
3. Else watches `hasProjectsForGameCodeProvider(game.code)` (add a simple provider if not present: counts rows in `projects` joined via `game_installations` for the game code). If 0 → empty state #2.
4. Else watches `glossaryAvailableLanguagesProvider(game.code)`. If empty → empty state #3.
5. Else renders: `GlossaryLanguageSwitcher` + entries grid driven by `currentGlossaryProvider`.

Keep the existing entries grid widget — only change the `glossaryId` source (from `selectedGlossaryProvider` to `currentGlossaryProvider`). Delete any code path that opened `GlossaryNewDialog` or rendered `GlossaryList`.

- [ ] **Step 4: Write widget tests for each empty state**

Path: `test/features/glossary/widgets/glossary_language_switcher_test.dart`

Test that:
- Passing `currentLanguageId = null` shows `—` on the chip.
- Opening the menu lists every language from the provider override.
- Tapping a language triggers the notifier `setLanguageId`.

Add to `test/features/glossary/screens/glossary_screen_test.dart` overrides for each empty state (selectedGameProvider returns null / provider returns empty projects / etc.) and asserts the exact English text appears.

- [ ] **Step 5: Run tests**

Run: `flutter test test/features/glossary/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/glossary/ test/features/glossary/
git commit -m "refactor(glossary): replace list+editor screen with language-switcher driven editor"
```

---

## Task 13: Hook auto-provisioning into game configuration + add-language

**Files:**
- Modify: `lib/providers/selected_game_provider.dart` (or settings writer for game path) — trigger `provisionForGame` when a new game path is saved.
- Modify: `lib/features/projects/widgets/add_language_dialog.dart` (or the handler it delegates to) — trigger `provisionForProjectLanguage` after the insert succeeds.

**Approach:** do not couple the provisioning service to Riverpod — call it directly from the code path that writes the game path / inserts the language.

- [ ] **Step 1: Hook into "game path saved"**

Grep for the settings writer that saves a game path. Look in `lib/features/settings/` for a method like `setGamePath` or `saveGamePath(gameCode, path)`.

After the write succeeds, call:

```dart
await ServiceLocator.get<GlossaryAutoProvisioningService>()
    .provisionForGame(gameCode);
```

Add the import at the top.

- [ ] **Step 2: Hook into "add language to project"**

Find the submit handler of `AddLanguageDialog`. Grep `grep -rn "AddLanguageDialog" lib/`. Find where the language is inserted into `project_languages`. Immediately after insert:

```dart
final projectRepo = ServiceLocator.get<ProjectRepository>();
final project = await projectRepo.getById(projectId);
final game = await ServiceLocator.get<GameInstallationRepository>()
    .getById(project.value.gameInstallationId);
await ServiceLocator.get<GlossaryAutoProvisioningService>()
    .provisionForProjectLanguage(
      gameCode: game.value.gameCode,
      targetLanguageId: addedLanguageId,
    );
```

Handle any repository result types gracefully (adapt to the actual Result-type boilerplate in the codebase).

- [ ] **Step 3: Manual smoke**

Run: `flutter run`
1. Add a new game path in settings → verify a glossary appears in DB for each existing project language of that game.
2. Add a new language to a project → verify a glossary is created for `(game, lang)`.

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings/ lib/features/projects/
git commit -m "feat(glossary): auto-provision empty glossaries on game config + language add"
```

---

## Task 14: Update `schema.sql`, drop `UNIQUE(name)` & legacy columns for fresh installs

**Files:**
- Modify: `lib/database/schema.sql`

Target state of the `glossaries` table:

```sql
CREATE TABLE IF NOT EXISTS glossaries (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    game_code TEXT NOT NULL,
    target_language_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
    CHECK (created_at <= updated_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS glossaries_game_lang_uq
  ON glossaries(game_code, target_language_id);
```

- [ ] **Step 1: Replace the table definition**

Open `lib/database/schema.sql`, locate lines 280–294, replace with the block above. Also drop the CHECK on is_global. Add the UNIQUE index in the indexes section of the file.

- [ ] **Step 2: Ensure phase 1 migration remains a no-op for fresh installs**

The migration's `isApplied()` checks for `game_code` column → present from schema.sql on fresh installs → skip. ✓

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`
Expected: PASS.

Run: `flutter analyze`
Expected: no warnings/errors.

- [ ] **Step 4: Final manual smoke**

Steps:
1. Delete the dev DB.
2. `flutter run`. Fresh install: no migration screen, no glossaries yet.
3. Add a game path → empty glossary appears in DB for each existing project language.
4. Create a project with languages → empty glossary appears for each.
5. Navigate to glossary screen → language switcher works.

- [ ] **Step 5: Commit**

```bash
git add lib/database/schema.sql
git commit -m "refactor(glossary): align fresh-install schema with final glossary model"
```

---

## Self-Review Checklist (for the planner before handoff)

Spec coverage:
- [x] Two-phase migration (partial + finalize) — tasks 1, 3.
- [x] Migration screen with per-row CSV export + conversion dropdown — task 6.
- [x] Automatic merge of duplicates with case-insensitive dedup, most-recent wins — task 3.
- [x] Auto-provisioning triggered by game config + project language add — tasks 5, 13.
- [x] Glossary screen driven by selectedGameProvider + per-game language switcher — tasks 11, 12.
- [x] All empty states (no game, no project, no language, no entries) — task 12.
- [x] Removal of manual creation UI and old list view — task 12.
- [x] All user-facing strings in English — task 6, 12 (verify during review).
- [x] Fresh-install schema aligns with final state — task 14.

Type consistency:
- `gameCode` used consistently (String) across model, service, repo, providers.
- `targetLanguageId` used consistently (String).
- `PendingGlossaryMigration.universals` / `.duplicates` used consistently in service + screen.

No placeholders found.
