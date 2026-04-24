# Harmonize 4 Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the 7 light-harmonization decisions from `docs/superpowers/specs/2026-04-24-harmonize-4-screens-design.md` to the 4 target screens (Translation Editor, Compilation Editor, Publish on Steam, Projects).

**Architecture:** A sequence of localized, low-blast-radius edits. One preparatory refactor (extracting `_CoverThumbnail` to a shared widget), one data-model migration (translation editor filter: `Set` → nullable single value) with its call-site propagation, then purely cosmetic token/widget/layout swaps. No new subsystems; no new tokens.

**Tech Stack:** Flutter, Riverpod (generator), Syncfusion SfDataGrid (unchanged), existing design tokens via `context.tokens`.

---

## File Map

**Created (1):**
- `lib/widgets/lists/project_cover_thumbnail.dart` — public replacement for the private `_CoverThumbnail` in Projects. 80×80 square thumbnail with image or game-icon fallback.

**Modified (8):**
- `lib/features/translation_editor/providers/editor_filter_notifier.dart` — switch `statusFilters: Set<...>` / `severityFilters: Set<...>` → `statusFilter: T?` / `severityFilter: T?`. Rename setters.
- `lib/features/translation_editor/providers/grid_data_providers.dart` — adapt filter predicate to nullable single value (lines 128-129, 161-165, `_matchesSeverity` helper).
- `lib/features/translation_editor/screens/translation_editor_screen.dart` — rename label `STATUS` → `STATE`; pill `onToggle` radio-like; `ListSearchField` width 200; update references to `statusFilters`/`severityFilters`.
- `lib/features/translation_editor/screens/actions/editor_actions_validation.dart` — update two call sites (lines 55, 58) to new single-value setters.
- `lib/features/steam_publish/widgets/steam_publish_toolbar.dart` — `ListSearchField(width: 200)`; reorder trailing so search is last.
- `lib/features/steam_publish/widgets/steam_publish_list.dart` — align row padding/colors/selection to Projects' `_ProjectRow`.
- `lib/features/projects/screens/projects_screen.dart` — `_SearchField` width 200; reorder trailing (search last); remove private `_CoverThumbnail` and use shared widget.
- `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart` — pass `width: 240` to `StickyFormPanel`.
- `lib/features/pack_compilation/widgets/compilation_project_selection.dart` — replace `CompilationSmallButton` → `SmallTextButton`, `_ProjectFilterField` → `ListSearchField(width: 200)`, rewrite project list items using `ListRow` + `ProjectCoverThumbnail`; swap `theme.colorScheme.*` → `context.tokens.*`.

**Tests updated (1):**
- `test/features/translation_editor/providers/editor_filter_notifier_test.dart` — reflect new single-value API (`setStatusFilter` / `setSeverityFilter`, fields `statusFilter` / `severityFilter`).

Potentially affected (grep before edit): `test/features/translation_editor/screens/translation_editor_screen_test.dart`, `test/features/translation_editor/widgets/editor_filter_toolbar_test.dart`, `test/features/translation_editor/screens/actions/handle_validate_test.dart`.

---

### Task 1: Extract `_CoverThumbnail` into a shared widget

Moves the existing private widget from Projects into `lib/widgets/lists/project_cover_thumbnail.dart` unchanged. Unblocks Task 6. Projects continues to render identically.

**Files:**
- Create: `lib/widgets/lists/project_cover_thumbnail.dart`
- Modify: `lib/features/projects/screens/projects_screen.dart` (lines 1160-1234: remove private class; update call site `_CoverThumbnail(...)` → `ProjectCoverThumbnail(...)`).

- [ ] **Step 1: Create the shared widget file**

```dart
// lib/widgets/lists/project_cover_thumbnail.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// 80×80 cover thumbnail for a project row.
///
/// Shows the project image when [imageUrl] is set, `assets/twmt_icon.png`
/// when the project represents a full-game translation, and a game-specific
/// Fluent icon fallback otherwise.
class ProjectCoverThumbnail extends StatelessWidget {
  final String? imageUrl;
  final bool isGameTranslation;
  final String? gameCode;

  const ProjectCoverThumbnail({
    super.key,
    required this.imageUrl,
    required this.isGameTranslation,
    required this.gameCode,
  });

  IconData _iconFor(String? code) {
    switch (code?.toLowerCase()) {
      case 'wh3':
      case 'wh2':
      case 'wh1':
        return FluentIcons.shield_24_regular;
      case 'troy':
        return FluentIcons.crown_24_regular;
      case 'threekingdoms':
      case '3k':
        return FluentIcons.people_24_regular;
      default:
        return FluentIcons.games_24_regular;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget fallback() => Icon(
          _iconFor(gameCode),
          size: 44,
          color: tokens.textMid,
        );

    Widget img;
    if (isGameTranslation) {
      img = Image.asset(
        'assets/twmt_icon.png',
        fit: BoxFit.cover,
        width: 80,
        height: 80,
        cacheWidth: 160,
        cacheHeight: 160,
        errorBuilder: (_, _, _) => fallback(),
      );
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      img = Image.file(
        File(imageUrl!),
        fit: BoxFit.cover,
        width: 80,
        height: 80,
        cacheWidth: 160,
        cacheHeight: 160,
        errorBuilder: (_, _, _) => fallback(),
      );
    } else {
      img = fallback();
    }
    return Center(
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: tokens.panel,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: img,
      ),
    );
  }
}
```

- [ ] **Step 2: Update `projects_screen.dart` — delete private class and use the shared one**

In `lib/features/projects/screens/projects_screen.dart`:

1. Add near the other widget imports at the top: `import 'package:twmt/widgets/lists/project_cover_thumbnail.dart';`
2. Delete lines 1160-1234 (the entire `class _CoverThumbnail extends StatelessWidget { ... }` block).
3. Find every call to `_CoverThumbnail(` inside the file (there is one, inside `_ProjectRow`) and replace it with `ProjectCoverThumbnail(` — named arguments are identical so only the class name changes.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze`
Expected: 0 errors, 0 warnings for the two touched files (pre-existing info-level lints, if any, unchanged).

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/lists/project_cover_thumbnail.dart lib/features/projects/screens/projects_screen.dart
git commit -m "refactor: extract ProjectCoverThumbnail into a shared widget"
```

---

### Task 2: Migrate translation editor filter state to single-value per group

Switches `statusFilters: Set<TranslationVersionStatus>` and `severityFilters: Set<ValidationSeverity>` to nullable single-value fields, and renames the setters accordingly. Preserves the existing "dropping `needsReview` from status wipes severity" invariant.

**Files:**
- Modify: `lib/features/translation_editor/providers/editor_filter_notifier.dart`
- Test: `test/features/translation_editor/providers/editor_filter_notifier_test.dart`

- [ ] **Step 1: Update the test file to the new API (failing state)**

Replace the contents of `test/features/translation_editor/providers/editor_filter_notifier_test.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';

void main() {
  group('EditorFilter — single-value severity filter', () {
    test('defaults to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(editorFilterProvider);
      expect(state.severityFilter, isNull);
      expect(state.hasActiveFilters, isFalse);
    });

    test('setSeverityFilter replaces the value and flips hasActiveFilters', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(editorFilterProvider.notifier)
          .setSeverityFilter(ValidationSeverity.error);
      final state = container.read(editorFilterProvider);
      expect(state.severityFilter, ValidationSeverity.error);
      expect(state.hasActiveFilters, isTrue);
    });

    test('setSeverityFilter(null) clears severity', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editorFilterProvider.notifier);
      notifier.setSeverityFilter(ValidationSeverity.error);
      notifier.setSeverityFilter(null);
      expect(container.read(editorFilterProvider).severityFilter, isNull);
    });

    test('clearFilters wipes severityFilter', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editorFilterProvider.notifier);
      notifier.setSeverityFilter(ValidationSeverity.warning);
      notifier.clearFilters();
      expect(container.read(editorFilterProvider).severityFilter, isNull);
    });

    test('dropping needsReview from status wipes severityFilter', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editorFilterProvider.notifier);
      notifier.setStatusFilter(TranslationVersionStatus.needsReview);
      notifier.setSeverityFilter(ValidationSeverity.error);
      notifier.setStatusFilter(TranslationVersionStatus.translated);
      expect(container.read(editorFilterProvider).severityFilter, isNull);
    });

    test('setStatusFilter(null) does not wipe severityFilter when status was not needsReview', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editorFilterProvider.notifier);
      notifier.setStatusFilter(TranslationVersionStatus.translated);
      notifier.setSeverityFilter(ValidationSeverity.error);
      notifier.setStatusFilter(null);
      expect(container.read(editorFilterProvider).severityFilter,
          ValidationSeverity.error);
    });
  });
}
```

- [ ] **Step 2: Run the tests — expect compile failure**

Run: `flutter test test/features/translation_editor/providers/editor_filter_notifier_test.dart`
Expected: FAIL / compile errors (`setStatusFilter` / `severityFilter` do not exist yet).

- [ ] **Step 3: Rewrite the notifier to the new API**

Replace the body of `lib/features/translation_editor/providers/editor_filter_notifier.dart` with:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';
import 'editor_row_models.dart';

part 'editor_filter_notifier.g.dart';

/// Filter state for the translation editor.
///
/// The STATUS and SEVERITY groups are each single-select (nullable): at most
/// one value active per group, independently of each other.
class EditorFilterState {
  final TranslationVersionStatus? statusFilter;
  final Set<TmSourceType> tmSourceFilters;
  final ValidationSeverity? severityFilter;
  final String searchQuery;
  final bool showOnlyWithIssues;

  const EditorFilterState({
    this.statusFilter,
    this.tmSourceFilters = const {},
    this.severityFilter,
    this.searchQuery = '',
    this.showOnlyWithIssues = false,
  });

  bool get hasActiveFilters =>
      statusFilter != null ||
      tmSourceFilters.isNotEmpty ||
      severityFilter != null ||
      searchQuery.isNotEmpty ||
      showOnlyWithIssues;

  EditorFilterState copyWith({
    TranslationVersionStatus? statusFilter,
    bool clearStatusFilter = false,
    Set<TmSourceType>? tmSourceFilters,
    ValidationSeverity? severityFilter,
    bool clearSeverityFilter = false,
    String? searchQuery,
    bool? showOnlyWithIssues,
  }) {
    return EditorFilterState(
      statusFilter:
          clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      tmSourceFilters: tmSourceFilters ?? this.tmSourceFilters,
      severityFilter: clearSeverityFilter
          ? null
          : (severityFilter ?? this.severityFilter),
      searchQuery: searchQuery ?? this.searchQuery,
      showOnlyWithIssues: showOnlyWithIssues ?? this.showOnlyWithIssues,
    );
  }
}

@riverpod
class EditorFilter extends _$EditorFilter {
  @override
  EditorFilterState build() {
    return const EditorFilterState();
  }

  /// Set the STATUS pill selection. Pass `null` to clear.
  ///
  /// Dropping `needsReview` from status also wipes the severity sub-filter —
  /// severity is only meaningful when status is `needsReview`.
  void setStatusFilter(TranslationVersionStatus? value) {
    final wasNeedsReview =
        state.statusFilter == TranslationVersionStatus.needsReview;
    final dropsNeedsReview =
        wasNeedsReview && value != TranslationVersionStatus.needsReview;
    state = state.copyWith(
      statusFilter: value,
      clearStatusFilter: value == null,
      clearSeverityFilter: dropsNeedsReview,
    );
  }

  void setTmSourceFilters(Set<TmSourceType> filters) {
    state = state.copyWith(tmSourceFilters: filters);
  }

  /// Set the SEVERITY pill selection. Pass `null` to clear.
  void setSeverityFilter(ValidationSeverity? value) {
    state = state.copyWith(
      severityFilter: value,
      clearSeverityFilter: value == null,
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setShowOnlyWithIssues(bool show) {
    state = state.copyWith(showOnlyWithIssues: show);
  }

  void clearFilters() {
    state = const EditorFilterState();
  }
}
```

- [ ] **Step 4: Regenerate Riverpod code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `editor_filter_notifier.g.dart` regenerated without errors.

- [ ] **Step 5: Run the filter tests — expect pass**

Run: `flutter test test/features/translation_editor/providers/editor_filter_notifier_test.dart`
Expected: All 6 tests PASS.

- [ ] **Step 6: Do NOT commit yet**

Call sites still reference the old API (`statusFilters`, `setStatusFilters`, etc.). Task 3 fixes the grid predicate, Task 4 fixes the screen, Task 5 fixes the validation action. Commit at the end of Task 5 once the build is green again.

---

### Task 3: Update grid filter predicate to use the new API

`grid_data_providers.dart` is the only non-screen consumer of the old fields.

**Files:**
- Modify: `lib/features/translation_editor/providers/grid_data_providers.dart` (around lines 128-129, 161-165, and the `_matchesSeverity` helper near line 173).

- [ ] **Step 1: Update the status filter predicate (~line 128)**

Find:
```dart
    if (filterState.statusFilters.isNotEmpty) {
      if (!filterState.statusFilters.contains(row.status)) {
        return false;
      }
    }
```
Replace with:
```dart
    if (filterState.statusFilter != null) {
      if (filterState.statusFilter != row.status) {
        return false;
      }
    }
```

- [ ] **Step 2: Update the severity filter predicate (~line 161-165)**

Find:
```dart
    // Severity filter (only meaningful when statusFilters contains needsReview;
    // ...
    if (!_matchesSeverity(row, filterState.severityFilters)) {
      return false;
    }
```
Replace with:
```dart
    // Severity filter (only meaningful when statusFilter is needsReview;
    // state.setStatusFilter clears severity when it leaves needsReview).
    if (!_matchesSeverity(row, filterState.severityFilter)) {
      return false;
    }
```

- [ ] **Step 3: Update the `_matchesSeverity` helper**

Find the helper signature and body (near line 173):
```dart
bool _matchesSeverity(
  EditorRow row,
  Set<ValidationSeverity> filters,
) {
  if (filters.isEmpty) return true;
  // ... existing body referencing `filters.contains(...)`
}
```
Change to a single nullable value. Exact replacement: change the parameter type to `ValidationSeverity?`, rename `filters` → `filter`, and replace the empty-set short-circuit with a null short-circuit. Each `filters.contains(x)` becomes `filter == x`:
```dart
bool _matchesSeverity(
  EditorRow row,
  ValidationSeverity? filter,
) {
  if (filter == null) return true;
  // ... replace `filters.contains(x)` with `filter == x` throughout
}
```

**Note:** Before editing, read the full current body of `_matchesSeverity` (`grep -n -A 30 "_matchesSeverity" lib/features/translation_editor/providers/grid_data_providers.dart`) and translate every reference mechanically. Do not change its semantics beyond the multi/single migration.

- [ ] **Step 4: Run static analysis**

Run: `flutter analyze lib/features/translation_editor/providers/grid_data_providers.dart`
Expected: 0 errors for this file (the rest of the codebase may still fail — Tasks 4 & 5 finish the propagation).

- [ ] **Step 5: No commit yet** — continue to Task 4.

---

### Task 4: Update `translation_editor_screen.dart` (label, pills, search width)

Three changes rolled into one file:
- Title literal `'STATUS'` → `'STATE'`.
- Pill `onToggle` for both groups becomes radio-like (click-again deselects, click-other replaces).
- `ListSearchField` receives `width: 200`.
- All references to `filter.statusFilters` / `filter.severityFilters` migrate to the new single-value fields.

**Files:**
- Modify: `lib/features/translation_editor/screens/translation_editor_screen.dart`

- [ ] **Step 1: Change the group title**

At line ~357, change:
```dart
          title: 'STATUS',
```
to:
```dart
          title: 'STATE',
```

- [ ] **Step 2: Migrate STATUS pill group to radio-like**

Find the block around lines 332-370 (`_buildStatusGroup` or equivalent that computes `active = filter.statusFilters.contains(status)` and updates via `Set.from(...)`). Replace:

```dart
      final active = filter.statusFilters.contains(status);
      // ...
      onToggle: () {
        final updated =
            Set<TranslationVersionStatus>.from(filter.statusFilters);
        if (active) {
          updated.remove(status);
        } else {
          updated.add(status);
        }
        ref.read(editorFilterProvider.notifier).setStatusFilters(updated);
      },
```

with:

```dart
      final active = filter.statusFilter == status;
      // ...
      onToggle: () {
        ref
            .read(editorFilterProvider.notifier)
            .setStatusFilter(active ? null : status);
      },
```

- [ ] **Step 3: Update the "clear all" callback (~line 361)**

Find:
```dart
          .setStatusFilters(const {}),
```
Replace with:
```dart
          .setStatusFilter(null),
```

- [ ] **Step 4: Update the `needsReview` check for SEVERITY group visibility (~line 246)**

Find:
```dart
                  if (filter.statusFilters
                      .contains(TranslationVersionStatus.needsReview))
```
Replace with:
```dart
                  if (filter.statusFilter ==
                      TranslationVersionStatus.needsReview)
```

- [ ] **Step 5: Migrate SEVERITY pill group to radio-like (~lines 381-396)**

Replace:
```dart
      final active = filter.severityFilters.contains(severity);
      // ...
      onToggle: () {
        final updated =
            Set<ValidationSeverity>.from(filter.severityFilters);
        if (active) {
          updated.remove(severity);
        } else {
          updated.add(severity);
        }
        ref
            .read(editorFilterProvider.notifier)
            .setSeverityFilters(updated);
      },
```

with:

```dart
      final active = filter.severityFilter == severity;
      // ...
      onToggle: () {
        ref
            .read(editorFilterProvider.notifier)
            .setSeverityFilter(active ? null : severity);
      },
```

- [ ] **Step 6: Set the search field width to 200 (~line 232)**

Find the `ListSearchField(...)` instantiation inside the FilterToolbar trailing. Add a `width: 200` parameter:

```dart
ListSearchField(
  width: 200,
  hintText: 'Search key · source · target',
  // ...existing params unchanged...
),
```

- [ ] **Step 7: Static analysis**

Run: `flutter analyze lib/features/translation_editor/screens/translation_editor_screen.dart`
Expected: 0 errors.

- [ ] **Step 8: No commit yet** — continue to Task 5.

---

### Task 5: Update `editor_actions_validation.dart` call sites + commit migration

Two call sites at lines 55 and 58 still use the old setters.

**Files:**
- Modify: `lib/features/translation_editor/screens/actions/editor_actions_validation.dart`

- [ ] **Step 1: Replace the two setter calls**

Find (lines 53-58):
```dart
    ref
        .read(editorFilterProvider.notifier)
        .setStatusFilters({TranslationVersionStatus.needsReview});
    ref
        .read(editorFilterProvider.notifier)
        .setSeverityFilters(const {});
```
Replace with:
```dart
    ref
        .read(editorFilterProvider.notifier)
        .setStatusFilter(TranslationVersionStatus.needsReview);
    ref
        .read(editorFilterProvider.notifier)
        .setSeverityFilter(null);
```

- [ ] **Step 2: Sweep for any remaining references to the old API**

Run:
```bash
grep -rn "statusFilters\|severityFilters\|setStatusFilters\|setSeverityFilters" lib/ test/ --include='*.dart'
```
Expected: only hits in `*.g.dart` generated files (if any) — but since we regenerated in Task 2, even those should be gone. Fix any straggling call sites using the same mechanical translation (set → single value).

- [ ] **Step 3: Full analyze and test run**

Run: `flutter analyze`
Expected: 0 errors (pre-existing info-level lints unchanged).

Run: `flutter test test/features/translation_editor/`
Expected: all tests PASS. If tests in `translation_editor_screen_test.dart`, `editor_filter_toolbar_test.dart`, or `handle_validate_test.dart` still reference old API names, update them using the same translation rules (set → single value; setters renamed).

- [ ] **Step 4: Commit Tasks 2–5 together**

```bash
git add lib/features/translation_editor/providers/editor_filter_notifier.dart \
        lib/features/translation_editor/providers/editor_filter_notifier.g.dart \
        lib/features/translation_editor/providers/grid_data_providers.dart \
        lib/features/translation_editor/screens/translation_editor_screen.dart \
        lib/features/translation_editor/screens/actions/editor_actions_validation.dart \
        test/features/translation_editor/providers/editor_filter_notifier_test.dart
# plus any other test files touched in Step 3
git commit -m "refactor: translation editor filters switch to single-value per group

STATUS and SEVERITY pill groups become radio-like (click-again deselects).
Renames the group title from STATUS to STATE to match the other screens.
Shrinks the top search field to 200px."
```

---

### Task 6: Harmonize Compilation editor's project-selection section

Visual alignment of `compilation_project_selection.dart` with the Projects screen. Replace legacy widgets with token-based harmonized ones and show cover thumbnails.

**Files:**
- Modify: `lib/features/pack_compilation/widgets/compilation_project_selection.dart`

- [ ] **Step 1: Replace imports**

At the top of the file, add/replace imports so the following are present:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/project_cover_thumbnail.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../../../models/domain/game_installation.dart';
import '../../../widgets/common/fluent_spinner.dart' hide FluentProgressBar;
import '../../../widgets/fluent/fluent_progress_indicator.dart';
import '../providers/pack_compilation_providers.dart';
```

Drop any now-unused imports (`cached_network_image`, the old `CompilationSmallButton` source file if it lived elsewhere — grep after the edit).

- [ ] **Step 2: Replace "Select All" / "Deselect All" buttons with `SmallTextButton`**

Find (around lines 94-110):
```dart
                projectsAsync.whenData((projects) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CompilationSmallButton(
                        label: 'Select All',
                        onTap: () =>
                            onSelectAll(projects.map((p) => p.id).toList()),
                      ),
                      const SizedBox(width: 8),
                      CompilationSmallButton(
                        label: 'Deselect All',
                        onTap: onDeselectAll,
                      ),
                    ],
                  );
                }).value ?? const SizedBox.shrink(),
```
Replace with:
```dart
                projectsAsync.whenData((projects) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SmallTextButton(
                        label: 'Select all',
                        onTap: () =>
                            onSelectAll(projects.map((p) => p.id).toList()),
                      ),
                      const SizedBox(width: 8),
                      SmallTextButton(
                        label: 'Deselect all',
                        onTap: onDeselectAll,
                      ),
                    ],
                  );
                }).value ?? const SizedBox.shrink(),
```

- [ ] **Step 3: Replace `_ProjectFilterField` with `ListSearchField`**

Find (around lines 89-93):
```dart
                SizedBox(
                  width: 200,
                  child: _ProjectFilterField(filter: filter),
                ),
```
Replace with:
```dart
                ListSearchField(
                  width: 200,
                  hintText: 'Search projects...',
                  value: filter,
                  onChanged: (value) => ref
                      .read(projectFilterProvider.notifier)
                      .setFilter(value),
                ),
```

`projectFilterProvider` is a generator-based Notifier holding a `String` with `setFilter(String)` and `clear()` methods — see `pack_compilation_providers.dart:54-65`. If `ListSearchField`'s prop names differ from the ones shown (e.g. `onChanged` vs `onQueryChanged`), open `lib/widgets/lists/list_search_field.dart` and use the real parameter names — do not invent.

- [ ] **Step 4: Swap header colors/decorations to tokens**

In the section header (around lines 40-86), replace:
- `theme.colorScheme.surface` → `context.tokens.panel`
- `theme.dividerColor` → `context.tokens.border`
- `theme.colorScheme.primary` → `context.tokens.accent`
- `theme.colorScheme.primary.withValues(alpha: 0.1)` → `context.tokens.accentBg`
- `BorderRadius.circular(8)` on the outer container → `BorderRadius.circular(context.tokens.radiusSm)`
- `BorderRadius.circular(12)` on the `X selected` chip → `BorderRadius.circular(context.tokens.radiusPill)`

Pull `final tokens = context.tokens;` near the top of `build` if the current code only accesses `Theme.of(context)`.

- [ ] **Step 5: Rewrite the project list items as `ListRow` with a cover thumbnail**

The current implementation builds project tiles with an ad-hoc `Container` + `Row`. Rewrite the per-item rendering using `ListRow` and three columns:

```dart
// Inside the Expanded ListView.builder...
itemBuilder: (context, i) {
  final p = projects[i];
  final selected = state.selectedProjectIds.contains(p.id);
  return ListRow(
    selected: selected,
    onTap: () => onToggle(p.id),
    columns: [
      ListRowColumn.fixed(
        width: 80,
        child: ProjectCoverThumbnail(
          imageUrl: p.imageUrl,
          isGameTranslation: p.project.isGameTranslation,
          gameCode: gameInstallation?.gameCode,
        ),
      ),
      ListRowColumn.flex(
        flex: 3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                p.displayName,
                style: TextStyle(
                  color: tokens.text,
                  fontFamily: tokens.fontBody,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${p.translatedUnits}/${p.totalUnits} translated '
                '· ${p.progressPercent.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: tokens.textDim,
                  fontFamily: tokens.fontMono,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
      ListRowColumn.fixed(
        width: 48,
        child: Checkbox(
          value: selected,
          onChanged: (_) => onToggle(p.id),
        ),
      ),
    ],
  );
},
```

Field sources (verified from models):
- `p` is a `ProjectWithTranslationInfo` (`lib/features/pack_compilation/models/project_with_translation_info.dart`) exposing `id`, `displayName`, `imageUrl`, `totalUnits`, `translatedUnits`, `progressPercent`, and a nested `project` getter.
- `isGameTranslation` lives on the inner `Project` domain (`lib/models/domain/project.dart:144`) — accessed via `p.project.isGameTranslation`.
- `gameCode` is **not** on the project; it is on the enclosing `GameInstallation` selected in the editor. The surrounding `build` already binds `final gameInstallation = currentGameAsync.asData?.value;` — pass `gameInstallation?.gameCode` to the thumbnail.
- The meta text above reuses what the old tile already showed (translated / total / progress). If the old tile rendered a different secondary line, mirror that instead — do not invent new content.

- [ ] **Step 6: Delete now-unused private widgets**

Remove from this file any `_ProjectFilterField`, `CompilationSmallButton`, `_ProjectTile`, or helper classes that are no longer referenced. Verify with a final grep inside the file itself.

- [ ] **Step 7: Static analysis + build**

Run: `flutter analyze lib/features/pack_compilation/widgets/compilation_project_selection.dart`
Expected: 0 errors.

Run: `flutter analyze`
Expected: no new errors introduced elsewhere (the removed `CompilationSmallButton` may be imported from another file — if so, update that file's import too).

- [ ] **Step 8: Commit**

```bash
git add lib/features/pack_compilation/widgets/compilation_project_selection.dart
git commit -m "refactor: harmonize compilation project-selection with Projects style

Use SmallTextButton, ListSearchField, ListRow, and ProjectCoverThumbnail
in place of the legacy CompilationSmallButton / _ProjectFilterField /
ad-hoc tile rendering. Swap Material theme colors for design tokens."
```

---

### Task 7: Set Compilation editor sidebar width to 240

Single-parameter change in the editor screen.

**Files:**
- Modify: `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart`

- [ ] **Step 1: Pass `width: 240` to `StickyFormPanel`**

Find the `StickyFormPanel(...)` instantiation inside `WizardScreenLayout(formPanel: ...)` and add `width: 240,` to its named arguments:

```dart
formPanel: StickyFormPanel(
  width: 240,
  sections: [...existing...],
  summary: ...,
  actions: [...],
  extras: ...,
),
```

- [ ] **Step 2: Launch the app and check the sidebar visually**

Run: `flutter run -d linux` (or the platform in use).
Navigate to: create or open a compilation.
Verify: the left form panel is visibly narrower than before and matches the translation editor sidebar width. All name / packName / prefix fields, the `SummaryBox`, and the `Cancel` / `Compile` actions remain readable and do not overflow.

If a label or field overflows:
- Shorten the label text (preferred) or
- Reduce the panel's internal horizontal padding from 24 to 16.
Do **not** increase the 240 width.

- [ ] **Step 3: Commit**

```bash
git add lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart
git commit -m "style: set compilation editor sidebar width to 240 to match translation editor"
```

---

### Task 8: Publish on Steam — search width 200 + search-rightmost reorder

Pure toolbar change.

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_publish_toolbar.dart`

- [ ] **Step 1: Change search width**

Find (around line 90) the `ListSearchField(...)` instantiation. Add `width: 200,`:

```dart
ListSearchField(
  width: 200,
  hintText: 'Search packs...',
  // ...existing params...
),
```

- [ ] **Step 2: Move `ListSearchField` to the end of the trailing list**

Find the `trailing: [ ... ]` array in this file (around lines 70-118) — currently structured as:

```
[SelectAll, SelectOutdated, ListSearchField, Sort, SortDir, Publish, Refresh, Settings]
```

Reorder the children so the `ListSearchField(...)` is the last element:

```
[SelectAll, SelectOutdated, Sort, SortDir, Publish, Refresh, Settings, ListSearchField]
```

**How:** cut the `ListSearchField(...)` widget block and paste it immediately before the closing `]` of the trailing array. Do not change any other child.

- [ ] **Step 3: Static analysis**

Run: `flutter analyze lib/features/steam_publish/widgets/steam_publish_toolbar.dart`
Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_toolbar.dart
git commit -m "style: steam publish search is 200px and sits rightmost on the toolbar"
```

---

### Task 9: Align Publish on Steam rows to Projects' visual style

Match paddings / colors / typography so the two list rows feel identical (hover, selection highlight, muted meta text). Keep `ListRow.height = 56` as-is.

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_publish_list.dart`

- [ ] **Step 1: Read both row implementations side by side**

Open `steam_publish_list.dart` and `lib/features/projects/screens/projects_screen.dart` (specifically `_ProjectRow` around lines 870-920 and the column helper functions it uses).

Identify any divergence for each of the following and make them match:
- Row horizontal padding (`ListRow`'s `contentPadding` or per-column `Padding`).
- Selection treatment — Projects relies on `ListRow(selected: true)`'s built-in left-accent border + `tokens.rowSelected` background. Steam should use the same `selected` flag rather than custom decoration.
- Hover color — whatever Projects uses (check if Projects customises it or inherits from `ListRow` default). Steam should match.
- Primary text — `tokens.text` + `tokens.fontBody` (default weight from Projects).
- Meta text — `tokens.textDim` + `tokens.fontMono`, size 12, as in Projects.
- Divider — Projects uses no per-row divider (the `ListRow` default handles separation). Remove any explicit `Divider()` in Steam rows.

- [ ] **Step 2: Apply the changes**

For each divergence found in Step 1, replace the Steam value with the Projects value. Do not touch columns or content — only shared visual chrome.

- [ ] **Step 3: Verify visually**

Run: `flutter run -d linux`.
Navigate: Publish on Steam, then Projects (two separate sessions of the same binary).
Compare: padding, hover color, selection highlight, typography. The two rows should look like they come from the same design system (only the column layout differs).

- [ ] **Step 4: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_list.dart
git commit -m "style: align steam publish row rendering to match Projects"
```

---

### Task 10: Projects — search width 200 + search-rightmost reorder

Mirror of Task 8 for the Projects screen.

**Files:**
- Modify: `lib/features/projects/screens/projects_screen.dart` (around the `_SearchField` wrapper — lines 484-502 — and the `trailing` array — lines 135-141).

- [ ] **Step 1: Change search width**

In `_SearchField` (around line 491), find the `ListSearchField(...)` inside the wrapper and add `width: 200,`:

```dart
return ListSearchField(
  width: 200,
  hintText: 'Search projects...',
  // ...existing params...
);
```

If `_SearchField` merely forwards a child `ListSearchField` without extra decoration, consider inlining it — but only if the wrapper has no other consumers in the file. Otherwise leave `_SearchField` in place and just modify the inner width.

- [ ] **Step 2: Move `_SearchField` to the end of the trailing list**

Find the `trailing: [ ... ]` array (around lines 135-141) containing `[_SearchField(), _SortButton(), _SelectionModeButton()]`. Reorder to:

```
[_SortButton(), _SelectionModeButton(), _SearchField()]
```

- [ ] **Step 3: Static analysis**

Run: `flutter analyze lib/features/projects/screens/projects_screen.dart`
Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/projects/screens/projects_screen.dart
git commit -m "style: projects search is 200px and sits rightmost on the toolbar"
```

---

### Task 11: Final verification

One pass across all 4 screens to confirm the design intent landed.

- [ ] **Step 1: Full static analysis**

Run: `flutter analyze`
Expected: 0 errors (pre-existing info-level lints unchanged).

- [ ] **Step 2: Full test run**

Run: `flutter test`
Expected: all tests PASS.

- [ ] **Step 3: Manual smoke check**

Run: `flutter run -d linux`.
For each of the 4 screens, verify:

| Screen | Check |
|---|---|
| Translation Editor | Group title reads `STATE`. Clicking a STATUS pill activates it; clicking it again deselects. Only one STATUS pill can be active at a time. `SEVERITY` group behaves the same way. Search field ~200px. |
| Compilation Editor | Left sidebar visibly narrower (240px). "Select Projects" section shows cover thumbnails, harmonized buttons, and a `ListSearchField` matching the Projects visual style. |
| Publish on Steam | Rows visually match Projects (padding, hover, selection highlight, typography). Search field 200px, to the right of all buttons. |
| Projects | Search field 200px. Search sits to the right of sort and selection-mode buttons. |

- [ ] **Step 4: No commit needed** — this is verification only. If a check fails, return to the corresponding task's remediation step.
