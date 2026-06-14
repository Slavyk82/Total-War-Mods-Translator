# Published Steam IDs via `project_publication` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Steam Publish screen read and write published Workshop IDs from the `project_publication` table (keyed by project + language) instead of the empty/vestigial `projects.published_steam_id` column, with a backfill migration for legacy data.

**Architecture:** A new idempotent migration creates `project_publication` and backfills it from any legacy `projects.published_steam_id`. A new `ProjectPublication` model + repository read/write it. The `publishableItems` provider bulk-loads publication rows and resolves one id per project by target language; the three publish write paths upsert into the table.

**Tech Stack:** Flutter, Dart, sqflite_common_ffi (SQLite), Riverpod (codegen), GetIt, Result type.

**Spec:** `docs/superpowers/specs/2026-06-14-published-steam-id-project-publication-design.md`

---

## File Structure

- Create: `lib/models/domain/project_publication.dart` — plain data model (hand-written json, no codegen).
- Create: `lib/repositories/project_publication_repository.dart` — read/upsert against the table.
- Create: `lib/services/database/migrations/migration_create_project_publication.dart` — create + backfill.
- Modify: `lib/services/database/migrations/migration_registry.dart` — register migration.
- Modify: `lib/services/locators/repository_locator.dart` — register repository in GetIt.
- Modify: `lib/providers/shared/repository_providers.dart` (+ regenerate `.g.dart`) — expose Riverpod provider.
- Modify: `lib/features/steam_publish/providers/steam_publish_providers.dart` — language-resolution helpers, read path, `ProjectPublishItem` fields + `publicationLanguageCode`.
- Modify: `lib/features/steam_publish/widgets/steam_id_editing.dart` — manual-edit write path.
- Modify: `lib/features/steam_publish/providers/workshop_publish_notifier.dart` — single-publish write path (+ `languageCode` param).
- Modify: `lib/features/steam_publish/providers/batch_workshop_publish_notifier.dart` — batch write path (+ `languageCode` on `BatchPublishItemInfo`).
- Modify: `lib/features/steam_publish/screens/steam_publish_screen.dart` — pass `languageCode` when building batch items.
- Modify: `lib/features/steam_publish/screens/workshop_publish_screen.dart` — pass `languageCode` to single publish.
- Tests: one new test file per new unit (model, migration, repository, provider resolution).

**Language resolution rule (used everywhere):** prefer `'fr'` when it is among the project's target languages, else the first target language, else `'fr'`. On the read side, if no publication row matches the resolved language but rows exist, fall back to the first available row.

---

## Task 1: `ProjectPublication` model

**Files:**
- Create: `lib/models/domain/project_publication.dart`
- Test: `test/unit/models/project_publication_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/models/project_publication_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/project_publication.dart';

void main() {
  group('ProjectPublication', () {
    test('round-trips through json with snake_case keys', () {
      const pub = ProjectPublication(
        projectId: 'p1',
        languageCode: 'fr',
        steamId: '3664274763',
        publishedAt: 1777103299,
      );

      final json = pub.toJson();
      expect(json, {
        'project_id': 'p1',
        'language_code': 'fr',
        'steam_id': '3664274763',
        'published_at': 1777103299,
      });

      final parsed = ProjectPublication.fromJson(json);
      expect(parsed.projectId, 'p1');
      expect(parsed.languageCode, 'fr');
      expect(parsed.steamId, '3664274763');
      expect(parsed.publishedAt, 1777103299);
    });

    test('tolerates null steam_id and published_at', () {
      final parsed = ProjectPublication.fromJson({
        'project_id': 'p1',
        'language_code': 'de',
        'steam_id': null,
        'published_at': null,
      });
      expect(parsed.steamId, isNull);
      expect(parsed.publishedAt, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/models/project_publication_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:twmt/models/domain/project_publication.dart'`.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/models/domain/project_publication.dart

/// A published Steam Workshop item for one project translation, keyed by
/// project and target language.
///
/// Distinct from `Project.modSteamId` (the source mod being translated): this
/// is the Workshop id of the user's OWN published translation pack. Stored in
/// the `project_publication` table, one row per (project, language).
class ProjectPublication {
  final String projectId;
  final String languageCode;
  final String? steamId;
  final int? publishedAt;

  const ProjectPublication({
    required this.projectId,
    required this.languageCode,
    this.steamId,
    this.publishedAt,
  });

  factory ProjectPublication.fromJson(Map<String, dynamic> json) {
    return ProjectPublication(
      projectId: json['project_id'] as String,
      languageCode: json['language_code'] as String,
      steamId: json['steam_id'] as String?,
      publishedAt: json['published_at'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'project_id': projectId,
        'language_code': languageCode,
        'steam_id': steamId,
        'published_at': publishedAt,
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/models/project_publication_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/models/domain/project_publication.dart test/unit/models/project_publication_test.dart
git commit -m "feat(model): add ProjectPublication domain model"
```

---

## Task 2: Create-and-backfill migration

**Files:**
- Create: `lib/services/database/migrations/migration_create_project_publication.dart`
- Modify: `lib/services/database/migrations/migration_registry.dart`
- Test: `test/services/database/migrations/migration_create_project_publication_test.dart`

- [ ] **Step 1: Confirm the chosen priority is free**

Run: `grep -rn "priority => 95" lib/services/database/migrations/`
Expected: no output (95 unused). If it prints a match, use 96 (and re-check) — any value `> 93` and not already used is valid, since the backfill only needs `projects.published_steam_id` (priority 92) to exist first. Use the confirmed number wherever `95` appears below.

- [ ] **Step 2: Write the failing test**

```dart
// test/services/database/migrations/migration_create_project_publication_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_create_project_publication.dart';

import '../../../helpers/test_database.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await TestDatabase.openMigrated();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  Future<Set<String>> tables() async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    return rows.map((r) => r['name'] as String).toSet();
  }

  group('CreateProjectPublicationMigration', () {
    test('creates the table when absent', () async {
      await db.execute('DROP TABLE IF EXISTS project_publication');
      expect(await tables(), isNot(contains('project_publication')));

      await CreateProjectPublicationMigration().execute();

      expect(await tables(), contains('project_publication'));
    });

    test('backfills from legacy projects.published_steam_id, preferring fr',
        () async {
      await db.execute('DROP TABLE IF EXISTS project_publication');

      // Seed a language, a project with a legacy published id, and its link.
      await db.insert('languages', {
        'id': 'lang-fr',
        'code': 'fr',
        'name': 'French',
        'native_name': 'Français',
        'is_active': 1,
      });
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.insert('projects', {
        'id': 'proj-1',
        'name': 'Legendary Lore',
        'mod_steam_id': '2789857945',
        'game_installation_id': 'gi-1',
        'batch_size': 25,
        'parallel_batches': 3,
        'created_at': now,
        'updated_at': now,
        'project_type': 'mod',
        'published_steam_id': '3664274763',
        'published_at': 1777103299,
      });
      await db.insert('project_languages', {
        'id': 'pl-1',
        'project_id': 'proj-1',
        'language_id': 'lang-fr',
        'progress_percent': 0,
        'created_at': now,
        'updated_at': now,
      });

      await CreateProjectPublicationMigration().execute();

      final rows = await db.query('project_publication',
          where: 'project_id = ?', whereArgs: ['proj-1']);
      expect(rows, hasLength(1));
      expect(rows.first['language_code'], 'fr');
      expect(rows.first['steam_id'], '3664274763');
      expect(rows.first['published_at'], 1777103299);
    });

    test('is idempotent — running twice does not duplicate or throw',
        () async {
      await CreateProjectPublicationMigration().execute();
      await CreateProjectPublicationMigration().execute();
      // No exception; table still present.
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='project_publication'",
      );
      expect(rows, hasLength(1));
    });
  });
}
```

> Note: `TestDatabase.openMigrated()` already runs every registered migration, so `project_publication` exists at setup; each test drops it first to exercise creation/backfill from a known state. The `languages` / `project_languages` column sets above match `lib/database/schema.sql`; if an insert fails with "no column named X", open `schema.sql`, copy the required NOT NULL columns into the insert map, and re-run.

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/services/database/migrations/migration_create_project_publication_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../migration_create_project_publication.dart'`.

- [ ] **Step 4: Write the migration**

```dart
// lib/services/database/migrations/migration_create_project_publication.dart
import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Create the `project_publication` table and backfill it from the legacy
/// `projects.published_steam_id` / `published_at` columns.
///
/// Published Workshop ids for translations live per (project, language) in
/// this table — distinct from `projects.mod_steam_id` (the source mod) and
/// from the now-vestigial flat `projects.published_steam_id` column. The
/// backfill resolves each legacy id to the project's target language,
/// preferring `fr` when present, so installs that wrote ids to the flat
/// column keep their data.
class CreateProjectPublicationMigration extends Migration {
  final ILoggingService _logger;

  CreateProjectPublicationMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'create_project_publication';

  @override
  String get description =>
      'Create project_publication table and backfill from legacy '
      'projects.published_steam_id';

  @override
  int get priority => 95;

  @override
  Future<bool> isApplied() async {
    final rows = await DatabaseService.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='project_publication'",
    );
    return rows.isNotEmpty;
  }

  @override
  Future<bool> execute() async {
    try {
      await DatabaseService.execute('''
        CREATE TABLE IF NOT EXISTS project_publication (
          project_id TEXT NOT NULL,
          language_code TEXT NOT NULL,
          steam_id TEXT,
          published_at INTEGER,
          PRIMARY KEY (project_id, language_code)
        )
      ''');

      // Backfill from the legacy flat column when it still exists. INSERT OR
      // IGNORE never overwrites rows already present (e.g. DBs where the data
      // already lives in project_publication). Language is resolved to the
      // project's target language, preferring 'fr'.
      final projectCols = await DatabaseService.database
          .rawQuery('PRAGMA table_info(projects)');
      final hasLegacy =
          projectCols.any((c) => c['name'] == 'published_steam_id');
      if (hasLegacy) {
        await DatabaseService.execute('''
          INSERT OR IGNORE INTO project_publication
            (project_id, language_code, steam_id, published_at)
          SELECT
            p.id,
            COALESCE(
              (SELECT l.code
                 FROM project_languages pl
                 JOIN languages l ON l.id = pl.language_id
                WHERE pl.project_id = p.id
                ORDER BY (l.code = 'fr') DESC, pl.created_at ASC
                LIMIT 1),
              'fr'),
            p.published_steam_id,
            p.published_at
          FROM projects p
          WHERE p.published_steam_id IS NOT NULL
            AND p.published_steam_id <> ''
        ''');
      }

      _logger.info('Ensured project_publication table (with legacy backfill)');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to create project_publication', e, stackTrace);
      return false;
    }
  }
}
```

- [ ] **Step 5: Register the migration**

In `lib/services/database/migrations/migration_registry.dart`, add the import after the `migration_published_at.dart` import (line ~21):

```dart
import 'migration_create_project_publication.dart';
```

And add to the `migrations` list, immediately after `PublishedAtMigration(),` (line ~68):

```dart
      CreateProjectPublicationMigration(), // Priority 95 — table + legacy backfill
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/services/database/migrations/migration_create_project_publication_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/services/database/migrations/migration_create_project_publication.dart lib/services/database/migrations/migration_registry.dart test/services/database/migrations/migration_create_project_publication_test.dart
git commit -m "feat(db): create project_publication table with legacy backfill migration"
```

---

## Task 3: `ProjectPublicationRepository`

**Files:**
- Create: `lib/repositories/project_publication_repository.dart`
- Modify: `lib/services/locators/repository_locator.dart`
- Test: `test/unit/repositories/project_publication_repository_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/repositories/project_publication_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/project_publication_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late ProjectPublicationRepository repo;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = ProjectPublicationRepository();
    await db.delete('project_publication');
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('ProjectPublicationRepository', () {
    test('setPublication inserts then updates both fields on conflict',
        () async {
      final ins = await repo.setPublication('p1', 'fr', '111', 1000);
      expect(ins.isOk, isTrue);

      var rows = await db.query('project_publication');
      expect(rows, hasLength(1));
      expect(rows.first['steam_id'], '111');
      expect(rows.first['published_at'], 1000);

      final upd = await repo.setPublication('p1', 'fr', '222', 2000);
      expect(upd.isOk, isTrue);
      rows = await db.query('project_publication');
      expect(rows, hasLength(1)); // same PK -> updated, not duplicated
      expect(rows.first['steam_id'], '222');
      expect(rows.first['published_at'], 2000);
    });

    test('setSteamId preserves existing published_at', () async {
      await repo.setPublication('p1', 'fr', '111', 1000);

      final res = await repo.setSteamId('p1', 'fr', '999');
      expect(res.isOk, isTrue);

      final rows = await db.query('project_publication');
      expect(rows.first['steam_id'], '999');
      expect(rows.first['published_at'], 1000); // unchanged
    });

    test('getAll and getByProject return inserted rows', () async {
      await repo.setPublication('p1', 'fr', '111', 1000);
      await repo.setPublication('p2', 'de', '222', 2000);

      final all = await repo.getAll();
      expect(all.isOk, isTrue);
      expect(all.value, hasLength(2));

      final byProject = await repo.getByProject('p1');
      expect(byProject.isOk, isTrue);
      expect(byProject.value, hasLength(1));
      expect(byProject.value.first.steamId, '111');
      expect(byProject.value.first.languageCode, 'fr');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/repositories/project_publication_repository_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../project_publication_repository.dart'`.

- [ ] **Step 3: Write the repository**

```dart
// lib/repositories/project_publication_repository.dart
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/project_publication.dart';
import 'base_repository.dart';

/// Repository for `project_publication` rows — the published Workshop id of a
/// project's translation, keyed by (project_id, language_code).
class ProjectPublicationRepository
    extends BaseRepository<ProjectPublication> {
  @override
  String get tableName => 'project_publication';

  @override
  ProjectPublication fromMap(Map<String, dynamic> map) =>
      ProjectPublication.fromJson(map);

  @override
  Map<String, dynamic> toMap(ProjectPublication entity) => entity.toJson();

  @override
  Future<Result<ProjectPublication, TWMTDatabaseException>> getById(
      String id) async {
    return Err(TWMTDatabaseException(
        'getById is not supported: project_publication has a composite key'));
  }

  @override
  Future<Result<List<ProjectPublication>, TWMTDatabaseException>>
      getAll() async {
    return executeQuery(() async {
      final maps = await database.query(tableName);
      return maps.map(fromMap).toList();
    });
  }

  @override
  Future<Result<ProjectPublication, TWMTDatabaseException>> insert(
      ProjectPublication entity) async {
    return executeQuery(() async {
      await database.insert(tableName, toMap(entity));
      return entity;
    });
  }

  @override
  Future<Result<ProjectPublication, TWMTDatabaseException>> update(
      ProjectPublication entity) async {
    return setPublication(entity.projectId, entity.languageCode,
            entity.steamId ?? '', entity.publishedAt ?? 0)
        .then((r) => r.isOk
            ? Ok<ProjectPublication, TWMTDatabaseException>(entity)
            : Err<ProjectPublication, TWMTDatabaseException>(r.error));
  }

  @override
  Future<Result<void, TWMTDatabaseException>> delete(String id) async {
    return Err(TWMTDatabaseException(
        'delete(id) is not supported: project_publication has a composite key'));
  }

  /// All publication rows for one project (usually one per target language).
  Future<Result<List<ProjectPublication>, TWMTDatabaseException>> getByProject(
      String projectId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ?',
        whereArgs: [projectId],
      );
      return maps.map(fromMap).toList();
    });
  }

  /// Upsert the published Workshop id AND publish timestamp for a
  /// (project, language). Used after a successful publish.
  Future<Result<void, TWMTDatabaseException>> setPublication(
      String projectId, String languageCode, String steamId,
      int publishedAt) async {
    return executeQuery(() async {
      await database.execute('''
        INSERT INTO project_publication
          (project_id, language_code, steam_id, published_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(project_id, language_code) DO UPDATE SET
          steam_id = excluded.steam_id,
          published_at = excluded.published_at
      ''', [projectId, languageCode, steamId, publishedAt]);
    });
  }

  /// Upsert ONLY the Workshop id for a (project, language), preserving any
  /// existing publish timestamp. Used by the manual "set Workshop ID" editor,
  /// which must not stamp a publish time (that would mark the item outdated).
  Future<Result<void, TWMTDatabaseException>> setSteamId(
      String projectId, String languageCode, String steamId) async {
    return executeQuery(() async {
      await database.execute('''
        INSERT INTO project_publication
          (project_id, language_code, steam_id)
        VALUES (?, ?, ?)
        ON CONFLICT(project_id, language_code) DO UPDATE SET
          steam_id = excluded.steam_id
      ''', [projectId, languageCode, steamId]);
    });
  }
}
```

- [ ] **Step 4: Register in GetIt**

In `lib/services/locators/repository_locator.dart`, add the import near the other repository imports:

```dart
import '../../repositories/project_publication_repository.dart';
```

And register it alongside the other `registerLazySingleton<...Repository>` calls (e.g. right after the `ProjectRepository` registration around line 55):

```dart
    locator.registerLazySingleton<ProjectPublicationRepository>(
      () => ProjectPublicationRepository(),
    );
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/unit/repositories/project_publication_repository_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/repositories/project_publication_repository.dart lib/services/locators/repository_locator.dart test/unit/repositories/project_publication_repository_test.dart
git commit -m "feat(repo): add ProjectPublicationRepository with setPublication/setSteamId"
```

---

## Task 4: Riverpod provider for the repository

**Files:**
- Modify: `lib/providers/shared/repository_providers.dart`
- Regenerate: `lib/providers/shared/repository_providers.g.dart`

- [ ] **Step 1: Add the provider declaration**

In `lib/providers/shared/repository_providers.dart`, add the import next to the other repository imports:

```dart
import '../../repositories/project_publication_repository.dart';
```

And add the provider after the `projectRepository` provider (line ~19):

```dart
@Riverpod(keepAlive: true)
ProjectPublicationRepository projectPublicationRepository(Ref ref) =>
    ServiceLocator.get<ProjectPublicationRepository>();
```

- [ ] **Step 2: Regenerate codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes; `repository_providers.g.dart` now defines `projectPublicationRepositoryProvider`.

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/providers/shared/repository_providers.dart`
Expected: No issues for this file (the generated provider resolves).

- [ ] **Step 4: Commit**

```bash
git add lib/providers/shared/repository_providers.dart lib/providers/shared/repository_providers.g.dart
git commit -m "feat(providers): expose projectPublicationRepository provider"
```

---

## Task 5: Read path — resolve published id by target language

**Files:**
- Modify: `lib/features/steam_publish/providers/steam_publish_providers.dart`
- Test: `test/features/steam_publish/providers/publication_language_resolution_test.dart`

- [ ] **Step 1: Write the failing test (pure resolution helpers)**

```dart
// test/features/steam_publish/providers/publication_language_resolution_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/project_publication.dart';
import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';

void main() {
  group('resolvePublicationLanguage', () {
    test('prefers fr when present among targets', () {
      expect(resolvePublicationLanguage(['de', 'fr', 'es']), 'fr');
    });
    test('falls back to first target when no fr', () {
      expect(resolvePublicationLanguage(['de', 'es']), 'de');
    });
    test('defaults to fr when no targets', () {
      expect(resolvePublicationLanguage([]), 'fr');
    });
  });

  group('resolvePublication', () {
    final frRow = const ProjectPublication(
        projectId: 'p', languageCode: 'fr', steamId: '111', publishedAt: 5);
    final deRow = const ProjectPublication(
        projectId: 'p', languageCode: 'de', steamId: '222', publishedAt: 9);

    test('returns null when no rows', () {
      expect(resolvePublication([], ['fr']), isNull);
    });
    test('matches the resolved target language', () {
      expect(resolvePublication([deRow, frRow], ['fr'])?.steamId, '111');
    });
    test('falls back to first row when no language match', () {
      expect(resolvePublication([deRow], ['fr'])?.steamId, '222');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/steam_publish/providers/publication_language_resolution_test.dart`
Expected: FAIL — `resolvePublicationLanguage` / `resolvePublication` not defined.

- [ ] **Step 3: Add helpers + import to `steam_publish_providers.dart`**

Add the import near the top (with the other model imports):

```dart
import 'package:twmt/models/domain/project_publication.dart';
```

Add these top-level functions (e.g. just below the `import`/`part` block, before the enums):

```dart
/// Resolve which target language's published id applies to a per-project
/// publish row. `project_publication` is keyed by (project, language) but the
/// list shows one row per project. Prefer 'fr' when it is a target language,
/// else the first target language, else 'fr'.
String resolvePublicationLanguage(List<String> targetLanguages) {
  if (targetLanguages.contains('fr')) return 'fr';
  if (targetLanguages.isNotEmpty) return targetLanguages.first;
  return 'fr';
}

/// Pick the publication row for a project: the one matching the resolved
/// target language, else the first available row, else null.
ProjectPublication? resolvePublication(
    List<ProjectPublication> rows, List<String> targetLanguages) {
  if (rows.isEmpty) return null;
  final lang = resolvePublicationLanguage(targetLanguages);
  for (final row in rows) {
    if (row.languageCode == lang) return row;
  }
  return rows.first;
}
```

- [ ] **Step 4: Wire `ProjectPublishItem` to resolved values**

In `ProjectPublishItem`, add two fields and a getter, and change the two getters to use the stored values.

Replace the constructor + the `publishedSteamId` / `publishedAt` getters:

```dart
class ProjectPublishItem extends PublishableItem {
  final ExportHistory? export;
  final Project project;
  final List<String> languageCodes;

  /// Resolved from `project_publication` by target language (not the legacy
  /// `project.publishedSteamId` column, which is vestigial).
  final String? resolvedPublishedSteamId;
  final int? resolvedPublishedAt;

  ProjectPublishItem({
    required this.export,
    required this.project,
    required this.languageCodes,
    this.resolvedPublishedSteamId,
    this.resolvedPublishedAt,
  });
```

```dart
  @override
  String? get publishedSteamId => resolvedPublishedSteamId;

  @override
  int? get publishedAt => resolvedPublishedAt;
```

Add a getter (next to `languagesList`) for the language to write back to:

```dart
  /// The target language under which this project's publication id is stored.
  String get publicationLanguageCode =>
      resolvePublicationLanguage(languagesList);
```

- [ ] **Step 5: Load publication rows in `publishableItems`**

In `publishableItems`, add the repository near the other repos (after `projectLanguageRepo`):

```dart
  final projectPublicationRepo = ref.watch(projectPublicationRepositoryProvider);
```

After resolving `gameInstallationId` and before the projects loop, bulk-load and index publication rows:

```dart
  // Bulk-load published Workshop ids (keyed by project+language) once, so the
  // per-project resolution below is a map lookup, not an N+1 query.
  final publicationsByProject = <String, List<ProjectPublication>>{};
  final allPublicationsResult = await projectPublicationRepo.getAll();
  if (allPublicationsResult.isOk) {
    for (final pub in allPublicationsResult.value) {
      publicationsByProject.putIfAbsent(pub.projectId, () => []).add(pub);
    }
  }
```

In the projects loop, after `langCodes` is built and before `items.add(...)`, resolve the publication and pass it in:

```dart
      final publication = resolvePublication(
        publicationsByProject[project.id] ?? const [],
        langCodes,
      );

      items.add(ProjectPublishItem(
        export: lastExport,
        project: project,
        languageCodes: langCodes,
        resolvedPublishedSteamId: publication?.steamId,
        resolvedPublishedAt: publication?.publishedAt,
      ));
```

(Remove the old `items.add(ProjectPublishItem(export:..., project:..., languageCodes:...));` call this replaces.)

- [ ] **Step 6: Run helper test + analyze the file**

Run: `flutter test test/features/steam_publish/providers/publication_language_resolution_test.dart`
Expected: PASS (6 tests).

Run: `flutter analyze lib/features/steam_publish/providers/steam_publish_providers.dart`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/steam_publish/providers/steam_publish_providers.dart test/features/steam_publish/providers/publication_language_resolution_test.dart
git commit -m "feat(steam-publish): read published id from project_publication by target language"
```

---

## Task 6: Write path — manual edit

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_id_editing.dart`

- [ ] **Step 1: Switch the project branch to the publication repo**

In `saveWorkshopId`, replace the `ProjectPublishItem` branch body (the `getById` + `copyWith(publishedSteamId:)` + `update` block) with a `setSteamId` call:

```dart
    if (item is ProjectPublishItem) {
      final pubRepo = ref.read(projectPublicationRepositoryProvider);
      final setResult = await pubRepo.setSteamId(
        item.project.id,
        item.publicationLanguageCode,
        parsed,
      );
      if (setResult.isErr) {
        showSaveError(setResult.error.message);
        return false;
      }
    } else if (item is CompilationPublishItem) {
```

The `CompilationPublishItem` branch and the surrounding `try/catch`, the parse logic, and the `ref.invalidate(publishableItemsProvider)` call stay unchanged.

- [ ] **Step 2: Confirm the provider import resolves**

`steam_id_editing.dart` already imports `package:twmt/providers/shared/repository_providers.dart`, which now exports `projectPublicationRepositoryProvider`. No new import needed.

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/steam_publish/widgets/steam_id_editing.dart`
Expected: No issues (the now-unused `projectRepositoryProvider` reference is gone from this branch; leave other usages intact).

- [ ] **Step 4: Run the existing steam-id editing test**

Run: `flutter test test/features/steam_publish/widgets/steam_id_editing_test.dart`
Expected: PASS. If a test stubbed `projectRepositoryProvider.update`, update it to stub `projectPublicationRepositoryProvider.setSteamId` returning `Ok(null)` (mirroring the new call); show the minimal mock change and re-run.

- [ ] **Step 5: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_id_editing.dart test/features/steam_publish/widgets/steam_id_editing_test.dart
git commit -m "feat(steam-publish): persist manual Workshop ID to project_publication"
```

---

## Task 7: Write path — single publish notifier

**Files:**
- Modify: `lib/features/steam_publish/providers/workshop_publish_notifier.dart`
- Modify: `lib/features/steam_publish/screens/workshop_publish_screen.dart`

- [ ] **Step 1: Add `languageCode` to `publish(...)` and cache it**

In `WorkshopPublishNotifier`, add a cache field next to `_cachedProjectId`:

```dart
  String? _cachedLanguageCode;
```

Add the param to `publish(...)` (after `projectId`):

```dart
    String? projectId,
    String? compilationId,
    String? languageCode,
```

Cache it next to the other cached values:

```dart
    _cachedProjectId = projectId;
    _cachedCompilationId = compilationId;
    _cachedLanguageCode = languageCode;
```

- [ ] **Step 2: Write to the publication repo on success**

Replace the project save block (the `getById` + `copyWith(publishedSteamId:..., publishedAt:...)` + `update`) with:

```dart
          if (projectId != null) {
            final pubRepo = ref.read(projectPublicationRepositoryProvider);
            final setResult = await pubRepo.setPublication(
              projectId,
              languageCode ?? 'fr',
              publishResult.workshopId,
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
            );
            if (setResult.isErr) {
              saveFailure = setResult.error.message;
            }
          } else if (compilationId != null) {
```

The compilation branch stays unchanged.

- [ ] **Step 3: Pass `languageCode` through Steam Guard retry**

In `retryWithSteamGuard`, add to the `publish(...)` call:

```dart
      projectId: _cachedProjectId,
      compilationId: _cachedCompilationId,
      languageCode: _cachedLanguageCode,
```

And clear it in `_clearCachedCredentials`:

```dart
    _cachedProjectId = null;
    _cachedCompilationId = null;
    _cachedLanguageCode = null;
```

- [ ] **Step 4: Pass `languageCode` from the single publish screen**

In `workshop_publish_screen.dart` `_startPublish`, where `projectId` / `compilationId` are derived (around line 285), capture the language and pass it:

```dart
    String? projectId;
    String? compilationId;
    String? languageCode;
    if (_item is ProjectPublishItem) {
      final projectItem = _item as ProjectPublishItem;
      projectId = projectItem.project.id;
      languageCode = projectItem.publicationLanguageCode;
    } else if (_item is CompilationPublishItem) {
      compilationId = (_item as CompilationPublishItem).compilation.id;
    }

    ref.read(workshopPublishProvider.notifier).publish(
          params: params,
          username: username,
          password: password,
          steamGuardCode: steamGuardCode,
          projectId: projectId,
          compilationId: compilationId,
          languageCode: languageCode,
        );
```

- [ ] **Step 5: Analyze both files**

Run: `flutter analyze lib/features/steam_publish/providers/workshop_publish_notifier.dart lib/features/steam_publish/screens/workshop_publish_screen.dart`
Expected: No issues. (`workshop_publish_notifier.dart` already imports `repository_providers.dart`.)

- [ ] **Step 6: Run the notifier test**

Run: `flutter test test/features/steam_publish/providers/workshop_publish_notifier_test.dart`
Expected: PASS. If a test asserted on `projectRepositoryProvider.update`, switch the stub/verify to `projectPublicationRepositoryProvider.setPublication` returning `Ok(null)`; show the change and re-run.

- [ ] **Step 7: Commit**

```bash
git add lib/features/steam_publish/providers/workshop_publish_notifier.dart lib/features/steam_publish/screens/workshop_publish_screen.dart test/features/steam_publish/providers/workshop_publish_notifier_test.dart
git commit -m "feat(steam-publish): persist single-publish Workshop ID to project_publication"
```

---

## Task 8: Write path — batch publish notifier

**Files:**
- Modify: `lib/features/steam_publish/providers/batch_workshop_publish_notifier.dart`
- Modify: `lib/features/steam_publish/screens/steam_publish_screen.dart`

- [ ] **Step 1: Add `languageCode` to `BatchPublishItemInfo`**

```dart
class BatchPublishItemInfo {
  final String name;
  final WorkshopPublishParams params;
  final String? projectId;
  final String? compilationId;
  final String? languageCode;

  const BatchPublishItemInfo({
    required this.name,
    required this.params,
    this.projectId,
    this.compilationId,
    this.languageCode,
  });
}
```

- [ ] **Step 2: Write to the publication repo in `_saveWorkshopId`**

Replace the project branch (the `getById` + `copyWith(publishedSteamId:..., publishedAt:...)` + `update`) with:

```dart
    if (item.projectId != null) {
      try {
        final pubRepo = ref.read(projectPublicationRepositoryProvider);
        final setResult = await pubRepo.setPublication(
          item.projectId!,
          item.languageCode ?? 'fr',
          workshopId,
          now,
        );
        if (setResult.isErr) {
          final detail = setResult.error.message;
          logging.warning(
              'Failed to save Workshop ID for ${item.name}: $detail');
          return detail;
        }
      } catch (e) {
        logging.warning('Failed to save Workshop ID for ${item.name}: $e');
        return e.toString();
      }
    } else if (item.compilationId != null) {
```

The compilation branch and the rest of the method stay unchanged.

- [ ] **Step 3: Populate `languageCode` when building batch items**

In `steam_publish_screen.dart` `_startBatchPublish`, where `BatchPublishItemInfo(...)` is constructed (around line 310), capture the language for project items:

```dart
      String? projectId;
      String? compilationId;
      String? languageCode;
      if (item is ProjectPublishItem) {
        projectId = item.project.id;
        languageCode = item.publicationLanguageCode;
      } else if (item is CompilationPublishItem) {
        compilationId = item.compilation.id;
      }

      items.add(BatchPublishItemInfo(
        name: modName,
        params: params,
        projectId: projectId,
        compilationId: compilationId,
        languageCode: languageCode,
      ));
```

(Replace the existing `projectId`/`compilationId` derivation + `items.add(...)` block this supersedes.)

- [ ] **Step 4: Analyze both files**

Run: `flutter analyze lib/features/steam_publish/providers/batch_workshop_publish_notifier.dart lib/features/steam_publish/screens/steam_publish_screen.dart`
Expected: No issues. (`batch_workshop_publish_notifier.dart` already imports `repository_providers.dart`.)

- [ ] **Step 5: Run the batch notifier test**

Run: `flutter test test/features/steam_publish/providers/batch_workshop_publish_notifier_test.dart`
Expected: PASS. If a test asserted `projectRepositoryProvider.update`, switch to `projectPublicationRepositoryProvider.setPublication` returning `Ok(null)`; show the change and re-run.

- [ ] **Step 6: Commit**

```bash
git add lib/features/steam_publish/providers/batch_workshop_publish_notifier.dart lib/features/steam_publish/screens/steam_publish_screen.dart test/features/steam_publish/providers/batch_workshop_publish_notifier_test.dart
git commit -m "feat(steam-publish): persist batch-publish Workshop IDs to project_publication"
```

---

## Task 9: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Static analysis (whole project)**

Run: `flutter analyze`
Expected: No new issues introduced by these changes. Fix any that trace to the edits above.

- [ ] **Step 2: Run the steam_publish + db + repository + model suites**

Run: `flutter test test/features/steam_publish test/unit/repositories test/unit/models test/services/database`
Expected: PASS. Address any failures (most likely tests that stubbed the old `projectRepository` write path — migrate them to the publication repo as noted in Tasks 6–8).

- [ ] **Step 3: Full test suite**

Run: `flutter test`
Expected: PASS (modulo the known intermittent token-encoder flake noted in project memory, which is unrelated).

- [ ] **Step 4: Manual smoke (real app, real DB)**

Build/run the app, open the Steam Publish screen for TW:WH3, and confirm the published Steam IDs (e.g. Legendary Lore → `3664274763`) now display in the Steam ID column. The migration creates/leaves the table; existing `project_publication` data is read directly (no backfill needed on this DB).

- [ ] **Step 5: Final commit (if any verification fixups were made)**

```bash
git add -A
git commit -m "test(steam-publish): align publish tests with project_publication write path"
```

---

## Self-Review Notes

- **Spec coverage:** migration+backfill (Task 2), model (Task 1), repository (Task 3), provider wiring (Task 4), read-by-target-language (Task 5), three write paths (Tasks 6–8), tests (each task + Task 9), `projects.published_steam_id` left vestigial (no drop; no longer read/written for projects). All spec sections mapped.
- **Type consistency:** `setPublication(projectId, languageCode, steamId, publishedAt)` and `setSteamId(projectId, languageCode, steamId)` used identically across repo (Task 3) and all call sites (Tasks 6–8). `resolvePublicationLanguage` / `resolvePublication` / `publicationLanguageCode` names consistent across Tasks 5, 7, 8. `BatchPublishItemInfo.languageCode` and `publish(..., languageCode:)` match their call sites.
- **Compilations** untouched throughout (separate, working path).
