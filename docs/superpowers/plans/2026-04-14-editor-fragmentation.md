# Phase 4 — Editor Fragmentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. All subagents use `model: "opus"` (user is on MAX PRO). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `editor_providers.dart` (744 l.), `editor_datagrid.dart` (668 l.), and `editor_toolbar.dart` (573 l.) into focused units without changing behaviour, guarded by widget characterisation tests.

**Architecture:** Five sequential batches. Batch A adds characterisation tests as a regression net. Batches B–D perform focused file-level extractions (one batch per source file). Batch E is manual smoke + memory update. Thin bridge-wrapper providers from Phase 3 deferred debt are inlined during Batch B.

**Tech Stack:** Flutter 3.10 desktop Windows, Dart 3.x, Riverpod 3.0.3 with `riverpod_annotation` codegen, `flutter_test` + `mocktail` for widget/unit tests, `syncfusion_flutter_datagrid` for the grid, GoRouter for nav. Build command: `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs`.

**Reference spec:** [`docs/superpowers/specs/2026-04-14-editor-fragmentation-design.md`](../specs/2026-04-14-editor-fragmentation-design.md) (committed `effcc4a`) — authoritative source for file layout, per-file content, invariants, rollback strategy, and completion criteria. This plan expands the spec into executable steps; when they disagree, the spec wins and this plan should be updated.

**Conventions (carried over from Phase 3):**
- Commit messages: English, format `type: short description`, no AI attribution.
- Bridge imports default unprefixed; use `as bridge` prefix only when a local `@riverpod` wrapper collides with a bridge symbol name.
- `ref.watch` in `@riverpod` function bodies, Notifier `build()`, widget `build()`. `ref.read` in Notifier mutators, imperative handlers, async callbacks.
- Interface types drop `I` prefix in Riverpod symbol names (e.g. `ITranslationMemoryService` → `translationMemoryServiceProvider`).
- Widget tests that read a bridge provider must pass `overrides:` via `createTestableWidget` + `overrideWithValue`. Use `NoopLoggingService` from `test/helpers/mock_logging_service.dart` for silent logger fakes.

**Starting state (2026-04-14):** Branch `refactor/incremental-2026-04-12`, working tree clean except design spec committed at `effcc4a`. Baseline: 986 passing / 30 failing tests (30 pre-existing, unrelated). `flutter analyze lib/` 0 errors.

---

## File Structure

Files created / modified across all five tasks:

```
lib/features/translation_editor/providers/
  editor_providers.dart                    Modify (744 l. → ~120 l.)
  editor_row_models.dart                   Create (~140 l.)
  editor_filter_notifier.dart              Create (~60 l.)
  editor_selection_notifier.dart           Create (~70 l.)
  grid_data_providers.dart                 Create (~170 l.)
  llm_model_providers.dart                 Create (~65 l.)
  tm_suggestions_provider.dart             Create (~60 l.)
  validation_issues_provider.dart          Create (~30 l.)

lib/features/translation_editor/widgets/
  editor_datagrid.dart                     Modify (668 l. → ~420 l.)
  translation_context_builder.dart         Create (~130 l.)
  grid_row_height_calculator.dart          Create (~70 l.)
  editor_toolbar.dart                      Modify (573 l. → ~240 l.)
  editor_toolbar_model_selector.dart       Create (~95 l.)
  editor_toolbar_skip_tm.dart              Create (~105 l.)
  editor_toolbar_mod_rule.dart             Create (~85 l.)

Call sites modified (feature-internal wrapper migrations, Batch B):
  lib/features/translation_editor/screens/actions/editor_actions_base.dart
  lib/features/translation_editor/screens/actions/editor_actions_import.dart
  lib/features/translation_editor/screens/actions/editor_actions_translation.dart
  lib/features/translation_editor/widgets/editor_datagrid.dart
  lib/features/translation_editor/widgets/editor_sidebar.dart
  lib/features/translation_editor/widgets/grid_actions_handler.dart
  lib/features/translation_editor/widgets/grid_selection_handler.dart
  lib/features/translation_editor/widgets/cell_renderers/context_menu_builder.dart
  (plus any other file grep finds that imports a deleted wrapper from editor_providers.dart)

test/features/translation_editor/
  editor_characterisation_test.dart        Create (~200–300 l.)

memory/project_refactoring_progress.md     Modify (Task 5 only)
```

---

## Task 1: Characterisation tests (Batch A)

**Purpose:** Lock in observable editor behaviour before any refactor. Provides the regression net for Tasks 2–4.

**Files:**
- Create: `test/features/translation_editor/editor_characterisation_test.dart`

**Existing test pattern reference:** `test/features/translation_editor/screens/translation_editor_screen_test.dart` — use this as the scaffold for widget tests, including the `ProviderScope` + `overrideWithValue` setup and `createTestableWidget` helper. Do not duplicate code the helper already provides.

**Existing logger fake:** `test/helpers/mock_logging_service.dart` exports `NoopLoggingService`. Override `loggingServiceProvider` with it in every test that triggers a code path that logs on error.

- [ ] **Step 1: Read the existing editor screen test to match its style**

Read `test/features/translation_editor/screens/translation_editor_screen_test.dart`. Note the fixture-building helpers (project + language + units + versions seeding), the provider overrides, and the `pumpAndSettle` cadence used for async providers.

- [ ] **Step 2: Decide fixture shape**

Create a fixture helper (inline in the new test file) that builds: 1 project, 1 source language, 1 target language, 3 translation units (status mix: 1 pending / 1 translated / 1 needs_review), 3 versions joined to them. If an equivalent helper already exists in `test/features/translation_editor/screens/translation_editor_screen_test.dart`, extract it to a shared helper first (separate commit) and reuse.

- [ ] **Step 3: Write test case 1 — grid loads N rows**

Test: given 3 seeded translation units with matching versions, `translationRowsProvider(projectId, languageId)` resolves to 3 `TranslationRow` instances ordered by key ASC. Assert on the resolved value's length and `.key` ordering.

- [ ] **Step 4: Write test case 2 — status filter narrows list**

Test: after writing `editorFilterProvider.notifier.setStatusFilters({TranslationVersionStatus.translated})`, `filteredTranslationRowsProvider(projectId, languageId)` resolves to the single translated row. Clearing filters returns all 3.

- [ ] **Step 5: Write test case 3 — search query filters on key / source / translated**

Three sub-tests:
1. Set `searchQuery` matching only a unit `key` → 1 row returned.
2. Set `searchQuery` matching only a `sourceText` → 1 row returned.
3. Set `searchQuery` matching only a `translatedText` → 1 row returned.

- [ ] **Step 6: Write test case 4 — selection + mark-reviewed batch action**

Test: toggle selection on 2 out of 3 rows via `editorSelectionProvider.notifier.toggleSelection`. Then invoke the mark-reviewed action path (whichever public entry point the `editor_actions_validation.dart` action currently exposes — read it fresh). Assert both selected rows' `version.status` is `needsReview → translated` (or the equivalent reviewed state) in the repository after the action.

- [ ] **Step 7: Write test case 5 — SelectedLlmModel keepAlive**

Test: write `selectedLlmModelProvider.notifier.setModel('foo-model-id')`. Dispose the outer `ProviderScope` container and rebuild — the state must still be `'foo-model-id'`. This locks in the `@Riverpod(keepAlive: true)` annotation.

**Technical note:** `keepAlive` in Riverpod 3 is scope-bound — disposal of a `ProviderContainer` still clears its state. The testable assertion is: within the same container, after no listeners remain for one frame, the state must still be present (use `container.read(selectedLlmModelProvider)` after pumping, without auto-dispose kicking in). If this is too brittle, fall back to asserting on the provider annotation itself via static inspection of the generated file — but prefer the behavioural test.

- [ ] **Step 8: Write test case 6 — TranslationInProgress blocks navigation**

Test: set `translationInProgressProvider.notifier.setInProgress(true)`. Invoke whatever navigation guard currently reads this state (grep for consumers of `translationInProgressProvider` — likely a `GoRouter` redirect or a `PopScope`). Assert the navigation is blocked or the expected blocking signal is emitted.

- [ ] **Step 9: Run the new test file in isolation**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/editor_characterisation_test.dart`
Expected: all 6 test cases pass on the current (pre-refactor) code.

If any test fails, the test is wrong — fix it, do NOT commit failing tests. The point is to lock in **current** behaviour.

- [ ] **Step 10: Run the full editor test folder**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/`
Expected: all green, no regression in sibling tests.

- [ ] **Step 11: Run the full suite to confirm baseline maintained**

Run: `C:/src/flutter/bin/flutter test`
Expected: 986 + new cases passing, 30 pre-existing failures unchanged.

- [ ] **Step 12: Commit**

```bash
git add test/features/translation_editor/editor_characterisation_test.dart
git commit -m "test: add characterisation tests for translation editor pre-fragmentation"
```

---

## Task 2: Split editor_providers.dart (Batch B)

**Purpose:** Fragment the 744-line file into 7 focused provider files + inline Phase 3 deferred thin wrappers. Behavioural identity with verbatim copy.

**Files:**
- Create: `lib/features/translation_editor/providers/editor_row_models.dart`
- Create: `lib/features/translation_editor/providers/editor_filter_notifier.dart`
- Create: `lib/features/translation_editor/providers/editor_selection_notifier.dart`
- Create: `lib/features/translation_editor/providers/grid_data_providers.dart`
- Create: `lib/features/translation_editor/providers/llm_model_providers.dart`
- Create: `lib/features/translation_editor/providers/tm_suggestions_provider.dart`
- Create: `lib/features/translation_editor/providers/validation_issues_provider.dart`
- Modify: `lib/features/translation_editor/providers/editor_providers.dart`
- Modify: all feature-internal call sites that import a deleted thin wrapper (enumerated via grep in Step 10)

**Source of truth for class/method bodies:** the current `editor_providers.dart`. Copy verbatim — do NOT rewrite logic. The only allowed transformations are: (a) moving code to another file, (b) renaming `_parseStatus`→`parseStatus` and `_parseTranslationSource`→`parseTranslationSource` (dropping the underscore prefix to make them public across files), (c) switching `ref.watch(xxxRepositoryProvider)` calls that previously routed through a thin wrapper to watch the bridge provider directly (`shared_repo.xxxRepositoryProvider` or `shared_svc.xxxServiceProvider`).

- [ ] **Step 1: Reread editor_providers.dart in full**

Open `lib/features/translation_editor/providers/editor_providers.dart`. Confirm the line ranges for each concern match the spec's per-file content section. If the file has drifted since 2026-04-14, re-map.

- [ ] **Step 2: Create editor_row_models.dart**

File contents: `TranslationRow` class, `EditorStats` class, `TmSourceType` enum, `getTmSourceType(TranslationRow)` top-level helper, `parseStatus(String)` top-level (renamed from `_parseStatus`), `parseTranslationSource(String?)` top-level (renamed from `_parseTranslationSource`).

Imports needed:
```dart
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
```

No `@riverpod` annotations in this file — it's pure domain.

- [ ] **Step 3: Create editor_filter_notifier.dart**

File contents: `EditorFilterState` class (copy verbatim from editor_providers.dart lines ~76–108), `@riverpod class EditorFilter extends _$EditorFilter` (copy verbatim from lines ~241–267).

Imports needed:
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'editor_row_models.dart'; // for TmSourceType

part 'editor_filter_notifier.g.dart';
```

- [ ] **Step 4: Create editor_selection_notifier.dart**

File contents: `EditorSelectionState` class (lines ~120–139), `@riverpod class EditorSelection extends _$EditorSelection` (lines ~270–307).

Imports needed:
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'editor_selection_notifier.g.dart';
```

- [ ] **Step 5: Create grid_data_providers.dart**

File contents: the 3 async providers `translationRows`, `filteredTranslationRows`, `editorStats` (lines ~332–561 of the original).

**Key transformation:** replace calls to the thin wrappers with bridge calls. Specifically:
- `ref.watch(translationUnitRepositoryProvider)` → `ref.watch(shared_repo.translationUnitRepositoryProvider)`
- `ref.watch(projectLanguageRepositoryProvider)` → `ref.watch(shared_repo.projectLanguageRepositoryProvider)`
- `ref.watch(translationVersionRepositoryProvider)` → `ref.watch(shared_svc.translationVersionRepositoryProvider)`
- `ref.watch(editorFilterProvider)` → unchanged (EditorFilter stays a real notifier, not a wrapper)

Replace private `_parseStatus` / `_parseTranslationSource` call sites with public `parseStatus` / `parseTranslationSource` from `editor_row_models.dart`.

Imports needed:
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/services/translation/utils/translation_skip_filter.dart';
import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;
import 'package:twmt/providers/shared/service_providers.dart' as shared_svc;
import 'editor_row_models.dart';
import 'editor_filter_notifier.dart';

part 'grid_data_providers.g.dart';
```

- [ ] **Step 6: Create llm_model_providers.dart**

File contents: `availableLlmModels` async provider (lines ~607–630) and `@Riverpod(keepAlive: true) class SelectedLlmModel` (lines ~635–649). **Preserve `@Riverpod(keepAlive: true)` exactly** — do not downgrade to `@riverpod`.

Replace `ref.watch(llmProviderModelRepositoryProvider)` with `ref.watch(shared_svc.llmProviderModelRepositoryProvider)`. Keep `ref.read(loggingServiceProvider)` for error logging — this is a real bridge provider (not a wrapper).

Imports needed:
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/providers/shared/service_providers.dart' as shared_svc;
import 'package:twmt/providers/shared/logging_providers.dart';

part 'llm_model_providers.g.dart';
```

- [ ] **Step 7: Create tm_suggestions_provider.dart**

File contents: `tmSuggestionsForUnit` async provider (lines ~659–712).

Replace `ref.watch(translationUnitRepositoryProvider)` → `ref.watch(shared_repo.translationUnitRepositoryProvider)`. Replace `ref.watch(translationMemoryServiceProvider)` → `ref.watch(shared_svc.translationMemoryServiceProvider)`.

Imports needed:
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;
import 'package:twmt/providers/shared/service_providers.dart' as shared_svc;

part 'tm_suggestions_provider.g.dart';
```

- [ ] **Step 8: Create validation_issues_provider.dart**

File contents: `validationIssues` async provider (lines ~722–744).

Replace `ref.watch(validationServiceProvider)` → `ref.watch(shared_svc.translationValidationServiceProvider)`. Keep `ref.read(loggingServiceProvider)` for error logging.

Imports needed:
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/services/validation/models/validation_issue.dart';
import 'package:twmt/providers/shared/service_providers.dart' as shared_svc;
import 'package:twmt/providers/shared/logging_providers.dart';

part 'validation_issues_provider.g.dart';
```

- [ ] **Step 9: Rewrite editor_providers.dart**

Replace the entire file content with:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/services/history/undo_redo_manager.dart';
import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;

part 'editor_providers.g.dart';

// Re-exports: extracted provider files.
export 'editor_row_models.dart';
export 'editor_filter_notifier.dart';
export 'editor_selection_notifier.dart';
export 'grid_data_providers.dart';
export 'llm_model_providers.dart';
export 'tm_suggestions_provider.dart';
export 'validation_issues_provider.dart';

/// Global state tracking if a batch translation is in progress.
/// Used to block navigation while translation is running.
@Riverpod(keepAlive: true)
class TranslationInProgress extends _$TranslationInProgress {
  @override
  bool build() => false;

  void setInProgress(bool value) => state = value;
}

/// Provider for undo/redo manager.
/// Not a bridge wrapper — creates a fresh instance per project editor session.
@riverpod
UndoRedoManager undoRedoManager(Ref ref) {
  return UndoRedoManager();
}

/// Provider for current project (async single-record fetch).
@riverpod
Future<Project> currentProject(
  Ref ref,
  String projectId,
) async {
  final repository = ref.watch(shared_repo.projectRepositoryProvider);
  final result = await repository.getById(projectId);

  return result.when(
    ok: (project) => project,
    err: (error) => throw Exception('Failed to load project: $error'),
  );
}

/// Provider for current language (async single-record fetch).
@riverpod
Future<Language> currentLanguage(
  Ref ref,
  String languageId,
) async {
  final repository = ref.watch(shared_repo.languageRepositoryProvider);
  final result = await repository.getById(languageId);

  return result.when(
    ok: (language) => language,
    err: (error) => throw Exception('Failed to load language: $error'),
  );
}
```

**Note:** `currentProject` and `currentLanguage` previously used the now-deleted `projectRepositoryProvider` / `languageRepositoryProvider` thin wrappers — they're switched to direct bridge calls here.

- [ ] **Step 10: Enumerate feature-internal call sites that imported deleted wrappers**

Run:
```bash
grep -rn -l "translationUnitRepositoryProvider\|translationVersionRepositoryProvider\|projectLanguageRepositoryProvider\|translationMemoryServiceProvider\|searchServiceProvider\|validationServiceProvider\|translationBatchRepositoryProvider\|translationBatchUnitRepositoryProvider\|translationOrchestratorProvider\|exportOrchestratorServiceProvider\|llmProviderModelRepositoryProvider\|projectRepositoryProvider\|languageRepositoryProvider" lib/features/translation_editor/
```

For each file in the result that reads one of these providers via `ref.watch` / `ref.read`, check which file the provider is imported from. If it's from `providers/editor_providers.dart` (i.e., it was using the deleted wrapper), change the import to the bridge:

- Repository providers → add `import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;` and use `shared_repo.xxxProvider`.
- Service providers → add `import 'package:twmt/providers/shared/service_providers.dart' as shared_svc;` and use `shared_svc.xxxProvider`.

**Skip:** consumers that import the provider via the real bridge import (they're already direct).

**Special case:** `editor_datagrid.dart` currently has `import '../../../providers/shared/service_providers.dart' as shared_svc;` on line 7 — reuse that alias. For repository providers it currently uses the thin wrapper via `editor_providers.dart` (`projectLanguageRepositoryProvider`) — add the `shared_repo` import and switch.

- [ ] **Step 11: Generate code**

Run: `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs`
Expected: green, generated `.g.dart` files for all 7 new notifiers/providers + updated `editor_providers.g.dart`.

If build_runner errors (usually: missing import, typo in annotation, stale generator cache), read the error, fix the offending file, re-run.

- [ ] **Step 12: Run analyze**

Run: `C:/src/flutter/bin/flutter analyze lib/`
Expected: 0 errors. 8 pre-existing info/warnings OK.

If analyze reports a missing symbol, most likely a call site from Step 10 was missed. Grep for the symbol, fix, re-run.

- [ ] **Step 13: Run characterisation tests**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/editor_characterisation_test.dart`
Expected: all 6 tests from Task 1 still green.

If a test fails, investigate — likely a filter / selection / keepAlive semantic regression. Do NOT commit until green.

- [ ] **Step 14: Run full suite**

Run: `C:/src/flutter/bin/flutter test`
Expected: 986 + Task 1 cases passing, 30 pre-existing failures unchanged.

- [ ] **Step 15: Commit**

```bash
git add lib/features/translation_editor/providers/ lib/features/translation_editor/widgets/ lib/features/translation_editor/screens/
git commit -m "refactor: split editor_providers.dart into focused provider files"
```

---

## Task 3: Cleanup editor_datagrid.dart (Batch C)

**Purpose:** Move non-grid helpers out of the grid widget. Extract two pure-ish utilities: the translation context builder (for prompt preview) and the row height calculator.

**Files:**
- Create: `lib/features/translation_editor/widgets/translation_context_builder.dart`
- Create: `lib/features/translation_editor/widgets/grid_row_height_calculator.dart`
- Modify: `lib/features/translation_editor/widgets/editor_datagrid.dart`

**Source ranges in current `editor_datagrid.dart`:**
- `_buildTranslationContext` → lines 428–499
- `_groupEntriesBySourceTerm` → lines 502–533
- `_calculateRowHeight` → lines 560–588
- `_calculateTextHeight` → lines 592–619

- [ ] **Step 1: Create translation_context_builder.dart**

File shape:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/services/glossary/models/glossary_term_with_variants.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/providers/shared/service_providers.dart' as shared_svc;
import 'package:twmt/features/settings/providers/settings_providers.dart';
import '../providers/editor_providers.dart';

/// Builds a TranslationContext for prompt preview in the translation editor.
///
/// Chooses provider/model from the toolbar's SelectedLlmModel first,
/// falls back to settings if no model is selected.
class TranslationContextBuilder {
  /// Build a translation context for prompt preview.
  /// Returns null if required data (project language, target language) cannot be resolved.
  static Future<TranslationContext?> build(
    WidgetRef ref,
    String projectId,
    String languageId,
  ) async {
    try {
      // Copy body of _buildTranslationContext verbatim here.
      // Change ref.read(projectLanguageRepositoryProvider) → ref.read(shared_svc... or shared_repo...)
      // depending on what Task 2 Step 10 settled for projectLanguageRepositoryProvider.
      // Change ref.read(glossaryRepositoryProvider) → unchanged (already via shared_svc).
      // Change ref.read(llmProviderModelRepositoryProvider) → unchanged (already via shared_svc).
      // Change ref.read(languageRepositoryProvider) → shared_repo.languageRepositoryProvider.
      // Call _groupEntriesBySourceTerm → move to the private top-level helper below.
      // ...
    } catch (e) {
      return null;
    }
  }
}

/// Group glossary entries by source term for variant support.
/// Case-insensitive grouping; filters to target-language entries only.
List<GlossaryTermWithVariants> _groupEntriesBySourceTerm(
  List<GlossaryEntry> entries,
  String targetLanguageCode,
) {
  // Copy body of _groupEntriesBySourceTerm verbatim from editor_datagrid.dart.
}
```

Complete the `build` method by pasting the body of `_buildTranslationContext` (lines 428–499 of the current `editor_datagrid.dart`) inside the `try`/`catch`, with the import aliases rewritten as noted above.

The `_groupEntriesBySourceTerm` helper is top-level and private to the file (underscore prefix).

- [ ] **Step 2: Create grid_row_height_calculator.dart**

File shape:

```dart
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../providers/editor_providers.dart';

/// Calculate dynamic row height based on text content.
/// Returns 48.0 for the header row, 56.0 as the minimum body row height.
double calculateRowHeight(
  RowHeightDetails details,
  List<TranslationRow> rows,
  double screenWidth,
) {
  // Copy body of _calculateRowHeight verbatim, replacing:
  //   _dataSource.translationRows → rows
  //   MediaQuery.of(context).size.width → screenWidth
}

/// Calculate the actual height needed for text using TextPainter.
/// Uses escaped text to match what the grid actually renders (newlines shown as \n).
double calculateTextHeight(String text, double maxWidth) {
  // Copy body of _calculateTextHeight verbatim.
}
```

- [ ] **Step 3: Update editor_datagrid.dart**

Delete the four private methods (`_buildTranslationContext`, `_groupEntriesBySourceTerm`, `_calculateRowHeight`, `_calculateTextHeight`).

Replace the `onQueryRowHeight: _calculateRowHeight,` line in `build()` (around line 262) with:
```dart
onQueryRowHeight: (details) => calculateRowHeight(
  details,
  _dataSource.translationRows,
  MediaQuery.of(context).size.width,
),
```

Replace the `_buildTranslationContext()` call inside `_handleViewPrompt` (around line 415) with:
```dart
final translationContext = await TranslationContextBuilder.build(
  ref,
  widget.projectId,
  widget.languageId,
);
```

Add imports:
```dart
import 'translation_context_builder.dart';
import 'grid_row_height_calculator.dart';
```

Remove now-unused imports from `editor_datagrid.dart` — specifically:
- `'../../../services/translation/models/translation_context.dart'` (only used by `_buildTranslationContext`)
- `'../../../models/domain/glossary_entry.dart'` (only used by `_groupEntriesBySourceTerm`)
- `'../../../services/glossary/models/glossary_term_with_variants.dart'` (ditto)
- `'../../settings/providers/settings_providers.dart'` (only used by `_buildTranslationContext`)
- `'../../../providers/shared/service_providers.dart' as shared_svc;` — verify if any other code in the file still uses `shared_svc.*`. If not, remove.

**Verify:** after removal, grep the remaining file for each removed import's symbols to confirm no orphan reference.

- [ ] **Step 4: Run analyze**

Run: `C:/src/flutter/bin/flutter analyze lib/`
Expected: 0 errors.

- [ ] **Step 5: Run characterisation tests**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/`
Expected: all green, including the Task 1 cases.

- [ ] **Step 6: Run full suite**

Run: `C:/src/flutter/bin/flutter test`
Expected: baseline maintained (986 + Task 1 cases passing, 30 pre-existing failing).

- [ ] **Step 7: Commit**

```bash
git add lib/features/translation_editor/widgets/
git commit -m "refactor: extract context builder and row height helpers from editor_datagrid"
```

---

## Task 4: Split editor_toolbar.dart (Batch D)

**Purpose:** Extract the three sub-widgets (`_buildModelSelector`, `_buildSkipTmCheckbox`, `_buildModRuleButton`) into their own files. Shell `editor_toolbar.dart` keeps the Row layout, action buttons, search controller, and the reusable `_buildActionButton` helper.

**Files:**
- Create: `lib/features/translation_editor/widgets/editor_toolbar_model_selector.dart`
- Create: `lib/features/translation_editor/widgets/editor_toolbar_skip_tm.dart`
- Create: `lib/features/translation_editor/widgets/editor_toolbar_mod_rule.dart`
- Modify: `lib/features/translation_editor/widgets/editor_toolbar.dart`

**Source ranges in current `editor_toolbar.dart`:**
- `_buildModelSelector({bool compact = false})` → lines 295–390
- `_buildSkipTmCheckbox({bool compact = false})` → lines 391–492
- `_buildModRuleButton({bool compact = false})` → lines 493–572

- [ ] **Step 1: Reread editor_toolbar.dart in full**

Open `lib/features/translation_editor/widgets/editor_toolbar.dart`. Map which widgets / providers each sub-method watches. Note which `_searchController` / `_buildActionButton` / widget.* callbacks they reference (these determine constructor params for the extracted widgets).

- [ ] **Step 2: Create editor_toolbar_model_selector.dart**

Extract `_buildModelSelector` into a `ConsumerWidget`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// + any imports the method body references (fluentui_system_icons, fluent_widgets, models, providers)
import '../providers/editor_providers.dart';

/// LLM model selector dropdown for the editor toolbar.
class EditorToolbarModelSelector extends ConsumerWidget {
  final bool compact;

  const EditorToolbarModelSelector({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Copy body of _buildModelSelector verbatim.
  }
}
```

- [ ] **Step 3: Create editor_toolbar_skip_tm.dart**

Extract `_buildSkipTmCheckbox` as a `ConsumerWidget`. Same pattern as Step 2. Constructor takes `bool compact`.

- [ ] **Step 4: Create editor_toolbar_mod_rule.dart**

Extract `_buildModRuleButton` as a `ConsumerWidget`. Same pattern. Constructor takes `bool compact` and `String projectId` (the ModRuleEditorDialog needs the project ID).

Re-check: if `_buildModRuleButton` also needs `languageId` or a callback from the parent, add it to the constructor. Match the actual body, not this plan's guess.

- [ ] **Step 5: Update editor_toolbar.dart**

Delete the three `_buildXxx` methods. In the `build()` method of `_EditorToolbarState`, replace the call sites:

- `_buildModelSelector(compact: isVeryCompact)` → `EditorToolbarModelSelector(compact: isVeryCompact)`
- `_buildSkipTmCheckbox(compact: isCompact)` → `EditorToolbarSkipTm(compact: isCompact)`
- `_buildModRuleButton(compact: isCompact)` → `EditorToolbarModRule(compact: isCompact, projectId: widget.projectId)` (add other params as discovered in Step 4)

Add imports:
```dart
import 'editor_toolbar_model_selector.dart';
import 'editor_toolbar_skip_tm.dart';
import 'editor_toolbar_mod_rule.dart';
```

Keep `_buildActionButton` — it's still used by multiple action buttons inside the Row in `build()`.

Remove now-unused imports. At minimum: `llm_provider_model.dart`, `llm_custom_rules_providers.dart`, `translation_settings_provider.dart`, `mod_rule_editor_dialog.dart` — but verify each against the remaining body before removing.

- [ ] **Step 6: Run analyze**

Run: `C:/src/flutter/bin/flutter analyze lib/`
Expected: 0 errors.

- [ ] **Step 7: Run characterisation tests**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/`
Expected: all green.

- [ ] **Step 8: Run full suite**

Run: `C:/src/flutter/bin/flutter test`
Expected: baseline maintained.

- [ ] **Step 9: Commit**

```bash
git add lib/features/translation_editor/widgets/
git commit -m "refactor: split editor_toolbar into model selector, skip-tm, mod-rule widgets"
```

---

## Task 5: Manual smoke + memory update (Batch E)

**Purpose:** End-to-end verification that the refactor preserved editor behaviour in the running app. Record completion in persistent memory.

**No code changes in this task.**

- [ ] **Step 1: Regenerate code from clean state**

Run:
```bash
C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 2: Start the app in debug mode**

Run: `C:/src/flutter/bin/flutter run -d windows`

Wait for the project list screen to load.

- [ ] **Step 3: Smoke checklist**

Execute in order, logging pass/fail for each:

1. Open an existing project and load a target language — grid shows rows.
2. Verify sort: click the "Key" column header — rows reorder ASC/DESC.
3. Apply a status filter (e.g., only translated) from the sidebar — row count decreases.
4. Apply a TM source filter — row count decreases further.
5. Type into the search field — list filters live by key/source/translated.
6. Clear all filters — full list returns.
7. Select 5 rows via checkbox, then shift-click to range-select.
8. Right-click a selected row → context menu appears.
9. "Mark reviewed" from context menu → all selected rows update status.
10. Select one row, context menu → "View history" — dialog opens with versions.
11. Select one row, context menu → "View prompt" — dialog shows a constructed TranslationContext.
12. Toolbar → select a non-default LLM model from the dropdown.
13. Launch a batch translation on a small selection (1–2 rows) — progress refreshes the grid.
14. Verify `SelectedLlmModel` persistence: navigate away from the editor, return — the selected model is still selected.
15. Edit a cell manually, then Ctrl-Z (undo), then Ctrl-Y (redo).
16. Export translations (small scope) — progress dialog appears, export completes.
17. Import a pack — rows refresh.

If any step fails, do NOT mark this task complete. Return to the relevant Task (2–4), diagnose, fix, recommit.

- [ ] **Step 4: Stop the app**

Close the Flutter desktop window. The `flutter run` process terminates.

- [ ] **Step 5: Verify line-count completion criteria**

Run:
```bash
wc -l lib/features/translation_editor/providers/editor_providers.dart \
      lib/features/translation_editor/widgets/editor_datagrid.dart \
      lib/features/translation_editor/widgets/editor_toolbar.dart
```

Expected:
- `editor_providers.dart` ≤ 150 (target ~120)
- `editor_datagrid.dart` ≤ 450
- `editor_toolbar.dart` ≤ 250

Also verify no new file exceeds 200 lines:
```bash
wc -l lib/features/translation_editor/providers/editor_row_models.dart \
      lib/features/translation_editor/providers/editor_filter_notifier.dart \
      lib/features/translation_editor/providers/editor_selection_notifier.dart \
      lib/features/translation_editor/providers/grid_data_providers.dart \
      lib/features/translation_editor/providers/llm_model_providers.dart \
      lib/features/translation_editor/providers/tm_suggestions_provider.dart \
      lib/features/translation_editor/providers/validation_issues_provider.dart \
      lib/features/translation_editor/widgets/translation_context_builder.dart \
      lib/features/translation_editor/widgets/grid_row_height_calculator.dart \
      lib/features/translation_editor/widgets/editor_toolbar_model_selector.dart \
      lib/features/translation_editor/widgets/editor_toolbar_skip_tm.dart \
      lib/features/translation_editor/widgets/editor_toolbar_mod_rule.dart
```

- [ ] **Step 6: Verify no ServiceLocator / GetIt introduced in new files**

Run:
```bash
grep -rn "ServiceLocator\.get\|GetIt\.instance" lib/features/translation_editor/providers/editor_row_models.dart lib/features/translation_editor/providers/editor_filter_notifier.dart lib/features/translation_editor/providers/editor_selection_notifier.dart lib/features/translation_editor/providers/grid_data_providers.dart lib/features/translation_editor/providers/llm_model_providers.dart lib/features/translation_editor/providers/tm_suggestions_provider.dart lib/features/translation_editor/providers/validation_issues_provider.dart lib/features/translation_editor/widgets/translation_context_builder.dart lib/features/translation_editor/widgets/grid_row_height_calculator.dart lib/features/translation_editor/widgets/editor_toolbar_model_selector.dart lib/features/translation_editor/widgets/editor_toolbar_skip_tm.dart lib/features/translation_editor/widgets/editor_toolbar_mod_rule.dart
```

Expected: no output (no matches).

- [ ] **Step 7: Verify no feature-internal call site still imports a deleted wrapper**

Deleted wrappers list: `projectRepositoryProvider` (wrapper), `languageRepositoryProvider` (wrapper), `translationUnitRepositoryProvider` (wrapper), `translationVersionRepositoryProvider` (wrapper), `translationMemoryServiceProvider` (wrapper), `searchServiceProvider` (wrapper), `validationServiceProvider` (wrapper), `translationBatchRepositoryProvider` (wrapper), `translationBatchUnitRepositoryProvider` (wrapper), `projectLanguageRepositoryProvider` (wrapper), `translationOrchestratorProvider` (wrapper), `exportOrchestratorServiceProvider` (wrapper), `llmProviderModelRepositoryProvider` (wrapper).

For each, grep in feature code to find usages:
```bash
for w in projectRepositoryProvider languageRepositoryProvider translationUnitRepositoryProvider translationVersionRepositoryProvider translationMemoryServiceProvider searchServiceProvider validationServiceProvider translationBatchRepositoryProvider translationBatchUnitRepositoryProvider projectLanguageRepositoryProvider translationOrchestratorProvider exportOrchestratorServiceProvider llmProviderModelRepositoryProvider; do
  echo "=== $w ==="
  grep -rn "\b$w\b" lib/features/translation_editor/ | grep -v "shared_repo\.\|shared_svc\."
done
```

Expected: for each, only the bridge-prefixed references show up (`shared_repo.xxx` / `shared_svc.xxx`) — any unprefixed reference means the migration was incomplete. Fix and recommit.

- [ ] **Step 8: Update persistent memory**

Edit `C:\Users\jmp\.claude\projects\E--Total-War-Mods-Translator\memory\project_refactoring_progress.md`:

1. Under "Phase 4 — Editor fragmentation ⏳ NOT STARTED", change status to `✅ DONE (2026-04-14)` and replace the skeleton note with a batch summary listing the 4 implementation commit hashes (A, B, C, D). Keep the line-count before/after for each target file.

2. In "Deferred technical debt accumulated during Task 3.2 → Bridge/wrapper cleanup (UI layer)", remove the first bullet ("Inline 12 thin-wrapper providers in `editor_providers.dart`...") — that debt is resolved by this phase.

3. Add a session bookmark entry:
   ```
   ## Session bookmark — 2026-04-14 evening

   Phase 4 fully complete. Working tree clean. Next session: begin Phase 5 (tests on critical services).
   ```

4. Update baseline numbers if they changed: the `986/30` baseline should still hold but may show `986+6/30` (Task 1 added 6 characterisation tests). Record the actual number from the final test run.

- [ ] **Step 9: No commit in this task**

This task produces no git changes. All commits were made in Tasks 1–4. Memory updates are in the claude home dir, not the repo.

---

## Phase 4 completion checkpoint

After Task 5 passes, confirm all spec acceptance criteria:

- [ ] `editor_providers.dart` ≤ 150 lines (target ~120 l.)
- [ ] `editor_datagrid.dart` ≤ 450 lines
- [ ] `editor_toolbar.dart` ≤ 250 lines
- [ ] No new file exceeds 200 lines
- [ ] Characterisation tests all green
- [ ] Full suite: 986 + 6 Task 1 cases passing, 30 pre-existing failures unchanged
- [ ] `flutter analyze lib/` 0 errors
- [ ] Manual smoke test all 17 steps pass
- [ ] No `ServiceLocator.get` / `GetIt.instance` in new files
- [ ] No feature-internal call site imports a deleted thin wrapper

If all green: Phase 4 is DONE. Working tree should be clean (design spec committed `effcc4a`, plus 4 refactor commits from Tasks 1–4).
