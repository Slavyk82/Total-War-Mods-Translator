# Untranslated IDs filter alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `TranslationVersionRepository.getUntranslatedIds` and `filterUntranslatedIds` honour the same status-and-skip predicate as `getLanguageStatistics.pendingCount`, so the `Translate All` / `Translate Selected` confirmation popups agree with the sidebar subtitle on the number of units to enqueue.

**Architecture:** Rename the existing `_excludeSkipUnitsCondition` getter on `TranslationVersionStatisticsMixin` to public (`excludeSkipUnitsCondition`). Both `getUntranslatedIds` and `filterUntranslatedIds` are rewritten to (1) filter by `tv.status IN ('pending', 'translating')`, (2) filter by `tu.is_obsolete = 0`, (3) apply `excludeSkipUnitsCondition` (HIDDEN prefix + fully-bracketed + user skip texts). `filterUntranslatedIds` gains an `INNER JOIN translation_units tu`. Two new repository tests land next to the existing `translation_version_repository_rescan_test.dart`.

**Tech Stack:** Flutter desktop, sqflite in-memory DB for tests (`TestDatabase.openMigrated()`), existing `TranslationSkipFilter` fallback defaults (`placeholder`, `dummy`).

**Reference spec:** `docs/superpowers/specs/2026-04-20-untranslated-ids-skip-and-status-filters-design.md`

**Files touched:**

- Modify: `lib/repositories/mixins/translation_version_statistics_mixin.dart` — rename `_excludeSkipUnitsCondition` to `excludeSkipUnitsCondition` and update the four in-file call sites.
- Modify: `lib/repositories/translation_version_repository.dart` — rewrite the SQL bodies of `getUntranslatedIds` (starts ~line 221) and `filterUntranslatedIds` (starts ~line 247). Update the doc comments to list the new exclusion rules.
- Create: `test/unit/repositories/translation_version_repository_untranslated_filter_test.dart` — two test groups covering the positive and negative cases of both methods.

No schema change, no code-gen, no provider change.

---

## Task 1: Expose the shared skip predicate (one commit)

Rename `_excludeSkipUnitsCondition` to `excludeSkipUnitsCondition` so it's callable from the repository in a different Dart library.

**Files:**
- Modify: `lib/repositories/mixins/translation_version_statistics_mixin.dart`

- [ ] **Step 1: Rename the getter**

Around line 31 of `translation_version_statistics_mixin.dart`:

```dart
  String get _excludeSkipUnitsCondition {
```

becomes:

```dart
  String get excludeSkipUnitsCondition {
```

The body (returning the multi-line SQL string) is untouched.

- [ ] **Step 2: Update the four in-file call sites**

Same file, replace every occurrence of `$_excludeSkipUnitsCondition` with `$excludeSkipUnitsCondition`. Today they live around lines 130, 153, 264, and 308. Confirm via:

```
C:/src/flutter/bin/flutter test test/unit/repositories/translation_version_repository_rescan_test.dart
```

(This test file exercises the mixin indirectly via `countLegacyValidationRows` / `getLegacyValidationPage` and will fail to compile if any reference is stale.)

- [ ] **Step 3: Run the full test suite to confirm the rename is mechanical**

```
C:/src/flutter/bin/flutter test
```

Expected: unchanged pass count. Nothing semantic moved.

- [ ] **Step 4: Commit**

```bash
git add lib/repositories/mixins/translation_version_statistics_mixin.dart
git commit -m "refactor: expose excludeSkipUnitsCondition on statistics mixin"
```

---

## Task 2: Red — failing tests for the new filter behaviour

New file. TDD: the two test groups fail against the current implementation because it still returns bracket-only and status-inconsistent rows.

**Files:**
- Create: `test/unit/repositories/translation_version_repository_untranslated_filter_test.dart`

- [ ] **Step 1: Create the test file**

Write the full file below. It follows the exact pattern of the sibling file `translation_version_repository_rescan_test.dart` (open migrated in-memory DB, raw `db.insert` seeding, tear-down close).

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late TranslationVersionRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// Seed a unit + its translation_version row in a single call.
  Future<void> seed({
    required String unitId,
    required String sourceText,
    required String projectLanguageId,
    required String status,
    String? translatedText,
    int isObsolete = 0,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.insert('translation_units', {
      'id': unitId,
      'project_id': 'proj-1',
      'key': 'k-$unitId',
      'source_text': sourceText,
      'is_obsolete': isObsolete,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('translation_versions', {
      'id': '$unitId-v',
      'unit_id': unitId,
      'project_language_id': projectLanguageId,
      'translated_text': translatedText,
      'status': status,
      'created_at': now,
      'updated_at': now,
    });
  }

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = TranslationVersionRepository();

    // Rows that must be RETURNED by the two queries:
    await seed(
      unitId: 'u-pending',
      sourceText: 'normal source',
      projectLanguageId: 'pl-1',
      status: 'pending',
      translatedText: '',
    );
    await seed(
      unitId: 'u-translating',
      sourceText: 'normal source 2',
      projectLanguageId: 'pl-1',
      status: 'translating',
      translatedText: null,
    );

    // Rows that must be EXCLUDED:
    await seed(
      unitId: 'u-translated-with-text',
      sourceText: 'normal source 3',
      projectLanguageId: 'pl-1',
      status: 'translated',
      translatedText: 'done',
    );
    await seed(
      unitId: 'u-translated-empty',
      sourceText: 'normal source 4',
      projectLanguageId: 'pl-1',
      status: 'translated', // Status/text inconsistency.
      translatedText: '',
    );
    await seed(
      unitId: 'u-needs-review',
      sourceText: 'normal source 5',
      projectLanguageId: 'pl-1',
      status: 'needs_review',
      translatedText: 'needs review text',
    );
    await seed(
      unitId: 'u-hidden',
      sourceText: '[HIDDEN] ui key',
      projectLanguageId: 'pl-1',
      status: 'pending',
      translatedText: '',
    );
    await seed(
      unitId: 'u-bracketed',
      sourceText: '[ok]',
      projectLanguageId: 'pl-1',
      status: 'pending',
      translatedText: '',
    );
    await seed(
      unitId: 'u-skip-text',
      // Matches `TranslationSkipFilter`'s fallback default `placeholder`.
      sourceText: 'placeholder',
      projectLanguageId: 'pl-1',
      status: 'pending',
      translatedText: '',
    );
    await seed(
      unitId: 'u-obsolete',
      sourceText: 'normal source 6',
      projectLanguageId: 'pl-1',
      status: 'pending',
      translatedText: '',
      isObsolete: 1,
    );
    await seed(
      unitId: 'u-wrong-lang',
      sourceText: 'normal source 7',
      projectLanguageId: 'pl-OTHER',
      status: 'pending',
      translatedText: '',
    );
  });

  tearDown(() => TestDatabase.close(db));

  group('getUntranslatedIds', () {
    test('returns only pending and translating rows that pass the skip filter',
        () async {
      final result = await repo.getUntranslatedIds(projectLanguageId: 'pl-1');
      final ids = result.unwrap().toSet();

      expect(ids, {'u-pending', 'u-translating'});
    });
  });

  group('filterUntranslatedIds', () {
    test('mirrors getUntranslatedIds when the input covers every seeded unit',
        () async {
      final inputIds = [
        'u-pending',
        'u-translating',
        'u-translated-with-text',
        'u-translated-empty',
        'u-needs-review',
        'u-hidden',
        'u-bracketed',
        'u-skip-text',
        'u-obsolete',
        'u-wrong-lang',
      ];

      final result = await repo.filterUntranslatedIds(
        ids: inputIds,
        projectLanguageId: 'pl-1',
      );
      final ids = result.unwrap().toSet();

      expect(ids, {'u-pending', 'u-translating'});
    });

    test('returns empty list when the input list is empty', () async {
      final result = await repo.filterUntranslatedIds(
        ids: const [],
        projectLanguageId: 'pl-1',
      );
      expect(result.unwrap(), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the new file and confirm the main assertions fail**

```
C:/src/flutter/bin/flutter test test/unit/repositories/translation_version_repository_untranslated_filter_test.dart
```

Expected failures (today's behaviour returns too many rows):

- `getUntranslatedIds` group: fails because the returned set includes `u-translated-empty`, `u-bracketed`, `u-skip-text` (and possibly `u-needs-review` / `u-translated-with-text` depending on text state) in addition to the expected two.
- `filterUntranslatedIds` first test: same over-count.
- `filterUntranslatedIds` empty-input test: PASSES (the `ids.isEmpty → Ok([])` short-circuit already exists).

At least the two positive-case tests MUST fail before proceeding. Do NOT commit yet.

---

## Task 3: Green — rewrite both SQL bodies (one commit)

Apply the new predicates to the repository methods.

**Files:**
- Modify: `lib/repositories/translation_version_repository.dart`

- [ ] **Step 1: Rewrite `getUntranslatedIds`**

Find the existing method starting around line 221 and replace the whole method body (including the doc comment) with:

```dart
  /// Get all untranslated unit IDs for a specific project language.
  ///
  /// Returns only units that are actionable for bulk translation: status
  /// in (`pending`, `translating`), not obsolete, and whose source text
  /// passes [excludeSkipUnitsCondition] (HIDDEN prefix, fully-bracketed
  /// placeholders, and user-configurable skip texts). Matches the
  /// predicate used by `getLanguageStatistics.pendingCount` so the UI
  /// count and the batch count agree.
  Future<Result<List<String>, TWMTDatabaseException>> getUntranslatedIds({
    required String projectLanguageId,
  }) async {
    return executeQuery(() async {
      final maps = await database.rawQuery(
        '''
        SELECT tu.id
        FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tv.project_language_id = ?
          AND tv.status IN ('pending', 'translating')
          AND tu.is_obsolete = 0
          AND $excludeSkipUnitsCondition
        ORDER BY tu.key
        ''',
        [projectLanguageId],
      );

      return maps.map((map) => map['id'] as String).toList();
    });
  }
```

- [ ] **Step 2: Rewrite `filterUntranslatedIds`**

Find the method starting around line 247 and replace the whole method body (including the doc comment) with:

```dart
  /// Filter a list of IDs to only include actionable untranslated units.
  ///
  /// Applies the same predicate as [getUntranslatedIds] (status
  /// pending/translating, not obsolete, source text passes
  /// [excludeSkipUnitsCondition]) but constrains the result to the
  /// supplied [ids]. Requires [projectLanguageId] to scope the query to a
  /// single project language.
  Future<Result<List<String>, TWMTDatabaseException>> filterUntranslatedIds({
    required List<String> ids,
    required String projectLanguageId,
  }) async {
    if (ids.isEmpty) {
      return Ok([]);
    }

    return executeQuery(() async {
      final placeholders = List.filled(ids.length, '?').join(',');

      final maps = await database.rawQuery(
        '''
        SELECT tu.id
        FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.id IN ($placeholders)
          AND tv.project_language_id = ?
          AND tv.status IN ('pending', 'translating')
          AND tu.is_obsolete = 0
          AND $excludeSkipUnitsCondition
        ''',
        [...ids, projectLanguageId],
      );

      return maps.map((map) => map['id'] as String).toList();
    });
  }
```

Note the column alias change in the final `map[...]` call: we now select `tu.id` (key `id`), not the bare `unit_id` column. The returned list's content is unchanged (each row's unit id), but the map key changed.

- [ ] **Step 3: Run the new test file — must be fully green**

```
C:/src/flutter/bin/flutter test test/unit/repositories/translation_version_repository_untranslated_filter_test.dart
```

Expected: all 3 tests pass (2 positive-case groups + the empty-input test).

- [ ] **Step 4: Run the full suite to confirm no regression**

```
C:/src/flutter/bin/flutter test
```

Expected: previous pass count + 3 new tests. If any unrelated test fails, STOP and investigate — do not patch around it. The widget tests that go through `TranslationBatchHelper.getUntranslatedUnitIds` / `filterUntranslatedUnits` stub at the helper layer and should be unaffected; anything else failing points at a deeper coupling worth surfacing.

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/translation_version_repository.dart test/unit/repositories/translation_version_repository_untranslated_filter_test.dart
git commit -m "fix: align untranslated-ids queries with pending-count semantics"
```

---

## Task 4: Manual smoke check

- [ ] **Step 1: Launch the app**

```
C:/src/flutter/bin/flutter run -d windows
```

- [ ] **Step 2: Open the same project/language that showed the 20 vs 1612 gap**

Click `Translate all`. Confirm:
- The confirmation dialog now says `Translate 20 untranslated units?` (same number as the sidebar subtitle).
- After confirming, the batch screen enqueues 20 units.
- Selecting a range of rows that contains a mix of bracket-only and normal units and clicking the sidebar's `Translate selection`: the dialog's `X untranslated units (Y already translated)` figure honours the skip filter — the bracket-only rows count as "already translated" from the dialog's perspective.

- [ ] **Step 3: Report result**

If the counts match end-to-end, the fix is done. If the batch visibly skips units the user expected to see translated, flag it — the follow-up is `reanalyzeAllStatuses`, not another tweak to the filter.
