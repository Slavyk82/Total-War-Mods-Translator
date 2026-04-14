# Phase 4 — Editor Fragmentation Design

**Status:** approved 2026-04-14
**Branch:** `refactor/incremental-2026-04-12`
**Parent plan:** [`docs/superpowers/plans/2026-04-12-incremental-refactoring.md`](../plans/2026-04-12-incremental-refactoring.md) (Phase 4 skeleton — superseded by this spec where they disagree)
**Execution mode:** subagent-driven (all subagents `model: "opus"`)

## Why this design supersedes the original skeleton

The 2026-04-12 audit described two god files: `editor_providers.dart` (749 l.) and `editor_datagrid.dart` (669 l.). Re-reading both on 2026-04-14 reveals significant drift:

- `editor_datagrid.dart` is **no longer a god file** — responsibilities have already been distributed across `editor_data_source.dart`, `grid_actions_handler.dart`, `grid_selection_handler.dart`, the `cell_renderers/` subdirectory (5 files), `editor_toolbar.dart`, `editor_sidebar.dart`, and the `screens/actions/` folder (7 action files).
- `editor_toolbar.dart` **already exists** as a separate 573-line file. The original plan's Task 4.5 ("extract editor_toolbar from editor_datagrid") is obsolete.
- `editor_toolbar.dart` at 573 lines is now the single largest file in the feature — bigger than `editor_datagrid.dart`.
- `editor_providers.dart` mixes seven concerns, not three: data models, bridge wrappers (Phase 3 deferred debt), filter/selection notifiers, SQL materialisation, LLM model selection, TM suggestions, validation issues.

This spec recalibrates Phase 4 on the actual state of the code.

## Scope decisions (resolved 2026-04-14)

| Axis | Decision | Rationale |
|---|---|---|
| Scope boundary | Recalibrated (option B) | Original skeleton is stale. Fragmenting based on 7 real concerns in providers + datagrid non-grid code + toolbar god file. |
| Characterisation tests | Required first (Task 4.1 honoured) | Editor is the core UX; 986 existing tests cover services/repos, not widget behaviour. |
| Execution mode | Subagent-driven, same as Phase 3 | Pattern is rodé; conventions are documented. |
| `editor_providers.dart` fate | Keep as focused home (~120 l.) with re-exports (option C) | A pure re-export hub accumulates debt; full deletion forces 15 mechanical migrations with no functional benefit. |
| Phase 3 deferred wrappers | Inline in scope (option A) | Each extracted provider will import bridge anyway; eliminate indirection now. |
| Batch granularity | One batch per target file (approach 2) | Intra-file extractions are not independent. File-level batches give the implementer coherent context and avoid merge conflicts. |

## Target file layout

```
lib/features/translation_editor/
├── providers/
│   ├── editor_providers.dart          744 l. → ~120 l.  (re-exports + TranslationInProgress, currentProject, currentLanguage)
│   ├── editor_row_models.dart         NEW   ~140 l.     (TranslationRow, EditorStats, TmSourceType, parseStatus, parseTranslationSource, getTmSourceType)
│   ├── editor_filter_notifier.dart    NEW   ~60 l.      (EditorFilterState + @riverpod EditorFilter)
│   ├── editor_selection_notifier.dart NEW   ~70 l.      (EditorSelectionState + @riverpod EditorSelection)
│   ├── grid_data_providers.dart       NEW   ~170 l.     (translationRows, filteredTranslationRows, editorStats)
│   ├── llm_model_providers.dart       NEW   ~65 l.      (availableLlmModels, SelectedLlmModel)
│   ├── tm_suggestions_provider.dart   NEW   ~60 l.      (tmSuggestionsForUnit)
│   ├── validation_issues_provider.dart NEW  ~30 l.      (validationIssues)
│   └── translation_settings_provider.dart   (unchanged)
└── widgets/
    ├── editor_datagrid.dart           668 l. → ~420 l.  (SfDataGrid shell, columns, batch event listeners, context menu dispatch)
    ├── translation_context_builder.dart NEW ~130 l.    (TranslationContextBuilder.build + groupEntriesBySourceTerm)
    ├── grid_row_height_calculator.dart  NEW ~70 l.     (calculateRowHeight, calculateTextHeight)
    ├── editor_toolbar.dart            573 l. → ~240 l. (Row shell + _buildActionButton helper + callback wiring)
    ├── editor_toolbar_model_selector.dart NEW ~95 l.   (LLM model dropdown)
    ├── editor_toolbar_skip_tm.dart        NEW ~105 l.  (skip TM checkbox)
    ├── editor_toolbar_mod_rule.dart       NEW ~85 l.   (mod rule button + dialog launcher)
    └── ... (other widgets unchanged)

test/features/translation_editor/
└── editor_characterisation_test.dart  NEW   ~200–300 l.
```

## File-by-file content

### `editor_row_models.dart`

Pure domain — no `@riverpod` annotations.

- `class TranslationRow` (view model combining unit + version)
- `class EditorStats`
- `enum TmSourceType { exactMatch, fuzzyMatch, llm, manual, none }`
- `TmSourceType getTmSourceType(TranslationRow row)` — top-level helper
- `TranslationVersionStatus parseStatus(String)` — renamed from `_parseStatus` (now public)
- `TranslationSource parseTranslationSource(String?)` — renamed from `_parseTranslationSource` (now public)

Exports `parseStatus` / `parseTranslationSource` because `grid_data_providers.dart` needs them for JSON row parsing.

### `editor_filter_notifier.dart`

- `class EditorFilterState` (immutable: statusFilters, tmSourceFilters, searchQuery, showOnlyWithIssues, `copyWith`, `hasActiveFilters` getter)
- `@riverpod class EditorFilter extends _$EditorFilter` with methods `setStatusFilters / setTmSourceFilters / setSearchQuery / setShowOnlyWithIssues / clearFilters`
- Imports `editor_row_models.dart` for `TmSourceType`

### `editor_selection_notifier.dart`

- `class EditorSelectionState` (immutable Set<String> selectedUnitIds, `hasSelection`, `selectedCount`, `isSelected`, `copyWith`)
- `@riverpod class EditorSelection extends _$EditorSelection` with methods `toggleSelection / selectAll / clearSelection / selectRange`

### `grid_data_providers.dart`

- `@riverpod Future<List<TranslationRow>> translationRows(Ref, String projectId, String languageId)` — single SQL JOIN via `getTranslationRowsJoined`, skip filter via `TranslationSkipFilter.shouldSkip`
- `@riverpod Future<List<TranslationRow>> filteredTranslationRows(Ref, String projectId, String languageId)` — watches `translationRows` + `editorFilter` + applies filters
- `@riverpod Future<EditorStats> editorStats(Ref, String projectId, String languageId)` — watches `translationRows` + queries `versionRepo.getLanguageStatistics`
- Direct bridge imports: `shared_repo.translationUnitRepositoryProvider`, `shared_repo.projectLanguageRepositoryProvider`, `shared_svc.translationVersionRepositoryProvider`

### `llm_model_providers.dart`

- `@riverpod Future<List<LlmProviderModel>> availableLlmModels(Ref)` — query enabled, non-archived models; errors logged via `loggingServiceProvider`, returns empty list on failure
- `@Riverpod(keepAlive: true) class SelectedLlmModel extends _$SelectedLlmModel` with `setModel / clear` — **`keepAlive: true` must be preserved**

### `tm_suggestions_provider.dart`

- `@riverpod Future<List<TmMatch>> tmSuggestionsForUnit(Ref, String unitId, String sourceLangCode, String targetLangCode)` — exact match + fuzzy match (threshold 0.70, max 5), sort by similarity desc

### `validation_issues_provider.dart`

- `@riverpod Future<List<ValidationIssue>> validationIssues(Ref, String sourceText, String translatedText)` — logs error and returns empty list on failure

### `editor_providers.dart` (final state)

Only contains:
- Header re-exports:
  ```dart
  export 'editor_row_models.dart';
  export 'editor_filter_notifier.dart';
  export 'editor_selection_notifier.dart';
  export 'grid_data_providers.dart';
  export 'llm_model_providers.dart';
  export 'tm_suggestions_provider.dart';
  export 'validation_issues_provider.dart';
  ```
- `@Riverpod(keepAlive: true) class TranslationInProgress` — navigation guard
- `@riverpod Future<Project> currentProject(Ref, String projectId)`
- `@riverpod Future<Language> currentLanguage(Ref, String languageId)`
- `@riverpod UndoRedoManager undoRedoManager(Ref)` — returns `UndoRedoManager()`; this is not a bridge wrapper (creates a fresh instance), kept here as an orphan provider

### `translation_context_builder.dart`

- `class TranslationContextBuilder` with static method `Future<TranslationContext?> build(WidgetRef ref, String projectId, String languageId)` — relocated `_buildTranslationContext` from `editor_datagrid.dart`
- `List<GlossaryTermWithVariants> _groupEntriesBySourceTerm(List<GlossaryEntry>, String targetLanguageCode)` — relocated helper

The single call site in `editor_datagrid.dart._handleViewPrompt` becomes `TranslationContextBuilder.build(ref, widget.projectId, widget.languageId)`.

### `grid_row_height_calculator.dart`

Top-level functions (no class):
- `double calculateRowHeight(RowHeightDetails details, List<TranslationRow> rows, double screenWidth)`
- `double calculateTextHeight(String text, double maxWidth)`

### `editor_datagrid.dart` (final state)

- `EditorDataGrid` widget — props unchanged (projectId, languageId, onCellEdit, onRowDoubleTap, onForceRetranslate, onRowSelected)
- `_EditorDataGridState` with: data source init, selection handler wiring, batch event subscriptions, `_refreshTranslations`, SfDataGrid build with columns, cell tap/secondary tap handlers, context menu dispatcher, dialog launchers (delete, history, prompt preview), select-all-checkbox state
- No longer contains: `_buildTranslationContext`, `_groupEntriesBySourceTerm`, `_calculateRowHeight`, `_calculateTextHeight`, `_ColumnHeader` (moves to its own internal file if splitting further becomes useful — not in this scope)

### Toolbar sub-widgets

Each is a `ConsumerStatefulWidget` (state needed for local controllers) or `ConsumerWidget` (if stateless after extraction).

- `editor_toolbar_model_selector.dart` — `EditorToolbarModelSelector({required bool compact})`: dropdown listing `availableLlmModels`, writes `selectedLlmModelProvider`
- `editor_toolbar_skip_tm.dart` — `EditorToolbarSkipTm({required bool compact})`: checkbox bound to `translationSettingsProvider`
- `editor_toolbar_mod_rule.dart` — `EditorToolbarModRule({required bool compact, required String projectId})`: button + `ModRuleEditorDialog` launcher

### `editor_toolbar.dart` (final state)

- `EditorToolbar` props unchanged
- `_EditorToolbarState`: search TextEditingController, build() returns the responsive Row horizontale that composes the three sub-widgets + action buttons
- `_buildActionButton(...)` stays private — reused by multiple action buttons

## Dependency graph

```
editor_row_models.dart (leaf)
  ↑
  ├─ editor_filter_notifier.dart (TmSourceType)
  ├─ grid_data_providers.dart    (TranslationRow, parseStatus, parseTranslationSource, EditorStats)
  └─ widgets/editor_datagrid.dart (TranslationRow for type annotations)

editor_filter_notifier.dart
  ↑
  ├─ grid_data_providers.dart    (filteredTranslationRows watches editorFilterProvider)
  ├─ widgets/editor_sidebar.dart (read + mutate filter)
  └─ widgets/editor_toolbar.dart (search query mutation)

editor_selection_notifier.dart
  ↑
  ├─ widgets/grid_selection_handler.dart
  ├─ widgets/editor_toolbar.dart
  └─ screens/actions/editor_actions_translation.dart

grid_data_providers.dart
  ↑
  ├─ widgets/editor_datagrid.dart (watch filteredTranslationRowsProvider; invalidate translationRowsProvider)
  ├─ widgets/grid_actions_handler.dart (invalidate after edit)
  └─ screens/actions/editor_actions_*.dart

llm_model_providers.dart         → widgets/editor_datagrid.dart, editor_toolbar sub-widgets
tm_suggestions_provider.dart      → TM suggestions panel
validation_issues_provider.dart   → validation panel
```

No cycles. `editor_row_models.dart` is the DAG root.

## Invariants (must not regress)

1. `filteredTranslationRows` watches `translationRows` + `editorFilter` — filter changes trigger re-filter without re-query.
2. `editorStats` watches `translationRows` — stats refresh automatically on translation changes.
3. `EditorDataGrid` invalidates `translationRowsProvider` on `BatchCompletedEvent` and on every 10th `BatchProgressEvent` for the current project-language.
4. `SelectedLlmModel` has `keepAlive: true` — selection persists across screen disposal.
5. `TranslationInProgress` has `keepAlive: true` — blocks navigation during active batch.
6. `EditorDataGrid` caches previous rows in `_cachedRows` to keep the grid visible during refresh.
7. Right-click selection fallback: if the right-clicked row is not in the current selection, select only it before showing the context menu.
8. Select-all checkbox is tristate: false / null (indeterminate) / true based on current selection vs. total rows.

## Error handling

No semantic changes. All `Result.ok/err`, `throw Exception`, `rowsAsync.hasError`/`asData?.value` handling, and the `_cachedRows` fallback are copied **verbatim** into the new files. Subagents are instructed explicitly: "Copy methods verbatim — do not refactor behaviour in extraction batches."

## Rollback strategy during refactor

1. **One commit per batch.** If a batch breaks anything, `git reset --hard HEAD` restores the last green state.
2. **Mandatory gates before each commit:**
   - `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs`
   - `C:/src/flutter/bin/flutter analyze lib/` — must return 0 errors
   - `C:/src/flutter/bin/flutter test test/features/translation_editor/` — characterisation tests green
   - Full suite baseline: 986 passing / 30 failing maintained
3. **Spec-review before dispatch** — subagent prompt reviewed by an opus spec-reviewer before the implementer starts.
4. **Code-review after commit** — opus code-reviewer reads the diff before the next batch is dispatched.
5. **Smoke test after Batch D** — manual Flutter desktop session before any merge to `main`.
6. **Escalation** — if a batch fails twice with the same problem, pause subagent mode, diagnose in main thread, adjust the plan, resume.

## Anticipated silent-regression cases (targeted by characterisation tests)

- Multi-status filter no longer combining correctly after `EditorFilter` extraction.
- `SelectedLlmModel.build() => null` losing `keepAlive: true` during migration → model forgotten between screen opens.
- `filteredTranslationRows` watching two providers instead of one → double rebuild.
- Context menu losing a callback after dialog launcher extraction.
- `TranslationRow` exported from two files simultaneously (re-export collision) during the split transition.
- Dropped `ref.watch` → `ref.read` change in Notifier mutators breaking reactivity.
- Missing `.future` on async provider watch changing the Future chaining.

## Batches

### Batch A — Characterisation tests (blocking prerequisite)

**Files:**
- Create: `test/features/translation_editor/editor_characterisation_test.dart`

**Cases to cover (minimum):**
1. Loading `translation_editor_screen` for a project+language displays N rows (happy path).
2. `editorFilterProvider.setStatusFilters({translated})` narrows the visible list.
3. `editorFilterProvider.setSearchQuery` filters on source + key + translated text.
4. `editorSelectionProvider.toggleSelection` + mark-reviewed action updates all selected rows.
5. `SelectedLlmModel` state persists after screen disposal (keepAlive).
6. `TranslationInProgress` set to true blocks navigation (or emits the expected blocking signal).

**Pattern:** use the existing screen-level test pattern from `test/features/translation_editor/screens/translation_editor_screen_test.dart`. Use Riverpod `overrideWithValue` for fakes per the bridge-testing convention (Phase 3 Batch 6/10 precedent).

**Gate:** all characterisation tests green on current (pre-refactor) code.

**Commit:** `test: add characterisation tests for translation editor pre-fragmentation`

### Batch B — Split `editor_providers.dart`

**Files:**
- Create: 7 provider files listed above
- Modify: `editor_providers.dart` → reduce to re-exports + 3 orphan providers
- Modify: internal feature call sites to remove dependency on the 12 thin wrappers (replace with direct `shared_repo.*` / `shared_svc.*` imports)

**Instructions to implementer:**
- Copy state classes and notifier methods verbatim.
- Rename `_parseStatus` → `parseStatus`, `_parseTranslationSource` → `parseTranslationSource` (public) in `editor_row_models.dart`.
- Run `build_runner` after creating files.
- Check that `loggingServiceProvider` is imported where error logging is done (previously `ref.read(loggingServiceProvider)` in `availableLlmModels` and `validationIssues`).
- Verify `SelectedLlmModel` keeps `@Riverpod(keepAlive: true)`.
- Verify `TranslationInProgress` stays in `editor_providers.dart` with its `@Riverpod(keepAlive: true)`.
- Delete thin wrappers: `projectRepositoryProvider`, `languageRepositoryProvider`, `translationUnitRepositoryProvider`, `translationVersionRepositoryProvider`, `translationMemoryServiceProvider`, `searchServiceProvider`, `undoRedoManagerProvider` (keep — it's a real provider), `validationServiceProvider`, `translationBatchRepositoryProvider`, `translationBatchUnitRepositoryProvider`, `projectLanguageRepositoryProvider`, `translationOrchestratorProvider`, `exportOrchestratorServiceProvider`, `llmProviderModelRepositoryProvider`. Note: `undoRedoManagerProvider` is not a bridge wrapper — it creates a fresh `UndoRedoManager()` — keep it.

**Gate:**
- `build_runner` clean
- `flutter analyze lib/` 0 errors
- Characterisation tests green
- Full suite 986/30 maintained

**Commit:** `refactor: split editor_providers.dart into focused provider files`

### Batch C — Cleanup `editor_datagrid.dart`

**Files:**
- Create: `translation_context_builder.dart`, `grid_row_height_calculator.dart`
- Modify: `editor_datagrid.dart` — remove `_buildTranslationContext`, `_groupEntriesBySourceTerm`, `_calculateRowHeight`, `_calculateTextHeight`. Replace call sites with calls to the new helpers.

**Instructions to implementer:**
- `TranslationContextBuilder.build(WidgetRef ref, String projectId, String languageId)` receives `ref` directly and uses `ref.read` inside (same semantics as the original which was inside `_EditorDataGridState` with `ref` from `ConsumerStatefulWidget`).
- The helper handles the same fallback chain (selected model → `llmProviderSettingsProvider`).
- `calculateRowHeight` and `calculateTextHeight` are pure functions — no `ref` / no state.
- Row height call site in `editor_datagrid.dart._calculateRowHeight` becomes:
  ```dart
  onQueryRowHeight: (details) => calculateRowHeight(
    details,
    _dataSource.translationRows,
    MediaQuery.of(context).size.width,
  ),
  ```

**Gate:** same as Batch B.

**Commit:** `refactor: extract context builder and row height helpers from editor_datagrid`

### Batch D — Split `editor_toolbar.dart`

**Files:**
- Create: `editor_toolbar_model_selector.dart`, `editor_toolbar_skip_tm.dart`, `editor_toolbar_mod_rule.dart`
- Modify: `editor_toolbar.dart` — delete the three `_buildXxx` method bodies, replace in `build()` with the new widgets

**Instructions to implementer:**
- Each sub-widget exposes a clear public API: constructor parameters replace the closure over `_EditorToolbarState` (e.g., `compact`, callbacks, `projectId` where needed).
- `_buildActionButton` stays as a private helper in `editor_toolbar.dart` (used by multiple action buttons in the main toolbar `build()`).
- Sub-widgets can each be `ConsumerWidget` unless they manage local controllers.
- Do not change the toolbar's public API (props on `EditorToolbar` stay identical).

**Gate:** same as Batch B.

**Commit:** `refactor: split editor_toolbar into model selector, skip-tm, mod-rule widgets`

### Batch E — Manual smoke test + memory update

**No code changes.**

**Smoke procedure** (Flutter Desktop Windows):
1. `flutter run -d windows` on the refactor branch.
2. Open an existing project, load a target language.
3. Verify grid shows rows, sorted correctly, with pagination/scroll working.
4. Apply a status filter (translated only) — row count decreases.
5. Apply a TM source filter — row count decreases further.
6. Clear filters — full list returns.
7. Type a search query — list filters by key/source/translated.
8. Select 5 rows via checkbox + range select (shift-click).
9. Right-click a selected row → context menu shows, "Mark reviewed" updates all selected.
10. Open prompt preview dialog — context builder returns a valid TranslationContext.
11. Launch a batch translation (1 row) → progress events refresh grid incrementally.
12. Open history dialog for a translated row.
13. Export translations (small scope) → export dialog and progress screen work.
14. Import a pack → rows refresh.
15. Undo/redo (ctrl-z, ctrl-y) on a cell edit.

**Pass criteria:** all 15 steps work without visible regression vs. pre-refactor behaviour.

**Memory update:** edit `C:\Users\jmp\.claude\projects\E--Total-War-Mods-Translator\memory\project_refactoring_progress.md`:
- Mark Phase 4 ✅ with commit hashes from Batches A–D.
- Clear the "Deferred technical debt accumulated during Task 3.2 → Bridge/wrapper cleanup (UI layer)" entries that are now resolved.
- Add a Phase 4 session bookmark.

## Completion criteria (Phase 4 checkpoint)

- [ ] `editor_providers.dart` ≤ 150 lines (target ~120 l.).
- [ ] `editor_datagrid.dart` ≤ 450 lines (revised up from plan's ~300 — the grid shell + columns + event listeners + context menu dispatch are legitimately ~420 l.).
- [ ] `editor_toolbar.dart` ≤ 250 lines.
- [ ] No new file exceeds 200 lines.
- [ ] Characterisation tests: all green.
- [ ] Full suite: 986 passing / 30 failing maintained (no new regressions).
- [ ] `flutter analyze lib/`: 0 errors.
- [ ] Manual smoke test: all 15 steps pass.
- [ ] No `ServiceLocator.get` / `GetIt.instance` introduced in new files.
- [ ] No feature-internal call site imports a deleted thin wrapper (grep confirms).

## Out of scope for Phase 4

- Other deferred debt listed in memory (`retry_utils.dart` logger widening, database static logger footguns, LIKE escape, FTS5 missing index, `TestBootstrap.registerFakes()` helper, collapse historyServiceProvider / releaseNotesServiceProvider / gameLocalizationServiceProvider pass-through wrappers). These remain for Phase 5 or subsequent cleanup.
- Converting `ModsScreenController` to a `@riverpod` Notifier.
- Inlining `ModsProjectService.create` factory or `deleteCompilation` top-level function.
- UI polish on error display (`TmBrowserDataGrid` `error.toString()` overflow).

## Follow-ups enabled by this phase

- Phase 5 (tests on critical services) can now layer tests on `grid_data_providers.dart`, `llm_model_providers.dart`, `tm_suggestions_provider.dart` independently.
- Future refactors can split `editor_datagrid.dart` further (e.g., extract the context-menu dispatcher into its own controller) with a smaller blast radius.
- `editor_toolbar.dart` sub-widgets become independently testable.
