# Editor / Validation Review Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fold the standalone Validation Review screen into the Translation Editor screen, via a severity sub-filter on the existing STATUS=needsReview filter and a conditional "Validation Issues" section inside the editor inspector.

**Architecture:** Extend `EditorFilterState` with `severityFilters`, add severity filtering to `filteredTranslationRowsProvider`, add a `visibleSeverityCounts` provider for pill counts, extend `EditorInspectorPanel` with a Validation Issues section (Accept/Reject/Edit), make the SEVERITY pill group and bulk cluster conditional on the filter state, merge "Validate" + "Rescan validation" into one button, and delete `ValidationReviewScreen` and its adjuncts.

**Tech Stack:** Flutter (Windows desktop), Riverpod 3 (codegen), `flutter_riverpod`, `riverpod_annotation`, Syncfusion DataGrid, Fluent UI icons. Tests run with `flutter test`.

**Build command reminders** (per `CLAUDE.md`):
- Regenerate `*.g.dart`: `dart run build_runner build --delete-conflicting-outputs`
- Debug run: `flutter run -d windows`
- Flutter SDK path: `C:/src/flutter/bin`

---

## File Structure

### Created

- `lib/widgets/lists/bulk_action_cluster.dart` — shared Accept/Reject/Deselect cluster (extracted from the review screen's `_BulkActionCluster`).

### Modified

- `lib/features/translation_editor/providers/editor_filter_notifier.dart` — add `severityFilters` field + notifier method.
- `lib/features/translation_editor/providers/grid_data_providers.dart` — severity filtering in `filteredTranslationRowsProvider` + new `visibleSeverityCountsProvider`.
- `lib/features/translation_editor/widgets/editor_inspector_panel.dart` — "Validation Issues" section + Accept/Reject/Edit callbacks.
- `lib/features/translation_editor/widgets/editor_action_sidebar.dart` — remove the separate "Rescan all" button; keep "Validate selected" only.
- `lib/features/translation_editor/screens/translation_editor_screen.dart` — add SEVERITY pill group, plug inspector callbacks, render bulk cluster conditionally in `FilterToolbar.trailing`.
- `lib/features/translation_editor/screens/actions/editor_actions_validation.dart` — rewrite `handleValidate` as `rescan + setStatusFilters({needsReview})`, delete `handleRescanValidation` / `exportValidationReport` / `_writeIssueToBuffer`, promote `_handleAcceptTranslation` / `_handleRejectTranslation` / `_handleEditTranslation` / `_handleBulkAcceptTranslation` / `_handleBulkRejectTranslation` to public (no leading underscore) so the inspector can call them.
- `lib/features/translation_editor/screens/translation_editor_actions.dart` — no change expected (the mixin exposes the methods automatically once renamed).
- `lib/providers/batch/batch_operations_provider.dart` — delete `BatchValidationState` class and `BatchValidationResults` notifier (no other consumer after the review screen goes).

### Deleted

- `lib/features/translation_editor/screens/validation_review_screen.dart`
- `lib/features/translation_editor/widgets/validation_review_data_source.dart`
- `lib/features/translation_editor/widgets/validation_review_inspector_panel.dart`
- `lib/features/translation_editor/providers/validation_inspector_width_notifier.dart` (and its `.g.dart`)
- `test/features/translation_editor/screens/validation_review_screen_test.dart`
- `test/features/translation_editor/widgets/validation_review_data_source_test.dart`
- `test/features/translation_editor/widgets/validation_review_inspector_panel_test.dart`
- `test/features/translation_editor/providers/validation_inspector_width_notifier_test.dart`

### Kept

- `lib/features/translation_editor/widgets/validation_edit_dialog.dart` — reused by the new Edit button in the inspector. Depends on `batch.ValidationIssue`, which stays alive.
- `lib/features/translation_editor/utils/validation_issues_parser.dart` — unchanged; used by the severity filter + inspector.

---

## Task 1: Extend `EditorFilterState` with `severityFilters`

**Files:**
- Modify: `lib/features/translation_editor/providers/editor_filter_notifier.dart`
- Test: `test/features/translation_editor/providers/editor_filter_notifier_test.dart` (create)

### - [ ] Step 1: Write the failing unit test

Create `test/features/translation_editor/providers/editor_filter_notifier_test.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';

void main() {
  group('EditorFilter — severityFilters', () {
    test('defaults to empty set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(editorFilterProvider);
      expect(state.severityFilters, isEmpty);
      expect(state.hasActiveFilters, isFalse);
    });

    test('setSeverityFilters replaces the set and flips hasActiveFilters', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(editorFilterProvider.notifier)
          .setSeverityFilters({ValidationSeverity.error});
      final state = container.read(editorFilterProvider);
      expect(state.severityFilters, {ValidationSeverity.error});
      expect(state.hasActiveFilters, isTrue);
    });

    test('clearFilters wipes severityFilters', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editorFilterProvider.notifier);
      notifier.setSeverityFilters(
          {ValidationSeverity.error, ValidationSeverity.warning});
      notifier.clearFilters();
      expect(container.read(editorFilterProvider).severityFilters, isEmpty);
    });
  });
}
```

### - [ ] Step 2: Run test to confirm failure

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/providers/editor_filter_notifier_test.dart`

Expected: FAIL — `severityFilters` / `setSeverityFilters` don't exist.

### - [ ] Step 3: Extend `EditorFilterState` and notifier

Edit `lib/features/translation_editor/providers/editor_filter_notifier.dart` — add the import, the new field, the method, and include severity in `hasActiveFilters` / `clearFilters`:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';
import 'editor_row_models.dart';

part 'editor_filter_notifier.g.dart';

class EditorFilterState {
  final Set<TranslationVersionStatus> statusFilters;
  final Set<TmSourceType> tmSourceFilters;
  final Set<ValidationSeverity> severityFilters;
  final String searchQuery;
  final bool showOnlyWithIssues;

  const EditorFilterState({
    this.statusFilters = const {},
    this.tmSourceFilters = const {},
    this.severityFilters = const {},
    this.searchQuery = '',
    this.showOnlyWithIssues = false,
  });

  bool get hasActiveFilters =>
      statusFilters.isNotEmpty ||
      tmSourceFilters.isNotEmpty ||
      severityFilters.isNotEmpty ||
      searchQuery.isNotEmpty ||
      showOnlyWithIssues;

  EditorFilterState copyWith({
    Set<TranslationVersionStatus>? statusFilters,
    Set<TmSourceType>? tmSourceFilters,
    Set<ValidationSeverity>? severityFilters,
    String? searchQuery,
    bool? showOnlyWithIssues,
  }) {
    return EditorFilterState(
      statusFilters: statusFilters ?? this.statusFilters,
      tmSourceFilters: tmSourceFilters ?? this.tmSourceFilters,
      severityFilters: severityFilters ?? this.severityFilters,
      searchQuery: searchQuery ?? this.searchQuery,
      showOnlyWithIssues: showOnlyWithIssues ?? this.showOnlyWithIssues,
    );
  }
}

@riverpod
class EditorFilter extends _$EditorFilter {
  @override
  EditorFilterState build() => const EditorFilterState();

  void setStatusFilters(Set<TranslationVersionStatus> filters) {
    // Dropping needsReview from the status set also wipes the severity
    // sub-filter — severity is only meaningful under needsReview.
    final droppingNeedsReview = state.statusFilters
            .contains(TranslationVersionStatus.needsReview) &&
        !filters.contains(TranslationVersionStatus.needsReview);
    state = state.copyWith(
      statusFilters: filters,
      severityFilters: droppingNeedsReview ? const {} : state.severityFilters,
    );
  }

  void setTmSourceFilters(Set<TmSourceType> filters) {
    state = state.copyWith(tmSourceFilters: filters);
  }

  void setSeverityFilters(Set<ValidationSeverity> filters) {
    state = state.copyWith(severityFilters: filters);
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

### - [ ] Step 4: Add a test for the `setStatusFilters` side-effect

Append to `test/features/translation_editor/providers/editor_filter_notifier_test.dart`, inside the same `group`:

```dart
    test('dropping needsReview from status wipes severityFilters', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(editorFilterProvider.notifier);
      notifier.setStatusFilters({TranslationVersionStatus.needsReview});
      notifier.setSeverityFilters({ValidationSeverity.error});
      notifier.setStatusFilters({TranslationVersionStatus.translated});
      expect(container.read(editorFilterProvider).severityFilters, isEmpty);
    });
```

Add the import at the top: `import 'package:twmt/models/domain/translation_version.dart';`.

### - [ ] Step 5: Regenerate code and run tests

```bash
C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs
C:/src/flutter/bin/flutter test test/features/translation_editor/providers/editor_filter_notifier_test.dart
```

Expected: all 4 tests PASS.

### - [ ] Step 6: Commit

```bash
git add lib/features/translation_editor/providers/editor_filter_notifier.dart \
        lib/features/translation_editor/providers/editor_filter_notifier.g.dart \
        test/features/translation_editor/providers/editor_filter_notifier_test.dart
git commit -m "feat: severity sub-filter in editor filter state"
```

---

## Task 2: Severity filtering in `filteredTranslationRowsProvider`

**Files:**
- Modify: `lib/features/translation_editor/providers/grid_data_providers.dart`
- Test: `test/features/translation_editor/providers/grid_data_providers_test.dart` (create)

### - [ ] Step 1: Write the failing test

Create `test/features/translation_editor/providers/grid_data_providers_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';

TranslationRow _row({
  required String id,
  required TranslationVersionStatus status,
  String? issuesJson,
}) {
  final unit = TranslationUnit(
    id: id,
    projectId: 'p',
    key: 'key-$id',
    sourceText: 'src-$id',
    createdAt: 0,
    updatedAt: 0,
  );
  final version = TranslationVersion(
    id: '$id-v',
    unitId: id,
    projectLanguageId: 'pl',
    translatedText: 'dst-$id',
    status: status,
    translationSource: TranslationSource.manual,
    validationIssues: issuesJson,
    createdAt: 0,
    updatedAt: 0,
  );
  return TranslationRow(unit: unit, version: version);
}

String _issues(List<({String rule, String sev, String msg})> entries) {
  return jsonEncode(entries
      .map((e) => {'rule': e.rule, 'severity': e.sev, 'message': e.msg})
      .toList());
}

void main() {
  group('filteredTranslationRows — severityFilters', () {
    test('keeps only versions with issues matching the selected severity',
        () async {
      final rows = [
        _row(
          id: 'a',
          status: TranslationVersionStatus.needsReview,
          issuesJson:
              _issues([(rule: 'variables', sev: 'error', msg: 'missing %s')]),
        ),
        _row(
          id: 'b',
          status: TranslationVersionStatus.needsReview,
          issuesJson: _issues(
              [(rule: 'length', sev: 'warning', msg: 'length ratio')]),
        ),
        _row(
          id: 'c',
          status: TranslationVersionStatus.translated,
        ),
      ];

      final container = ProviderContainer(overrides: [
        translationRowsProvider('p', 'fr').overrideWith((_) async => rows),
      ]);
      addTearDown(container.dispose);

      container
          .read(editorFilterProvider.notifier)
          .setStatusFilters({TranslationVersionStatus.needsReview});
      container
          .read(editorFilterProvider.notifier)
          .setSeverityFilters({ValidationSeverity.error});

      final filtered = await container
          .read(filteredTranslationRowsProvider('p', 'fr').future);
      expect(filtered.map((r) => r.id).toList(), ['a']);
    });

    test('empty severityFilters is a no-op', () async {
      final rows = [
        _row(id: 'a', status: TranslationVersionStatus.needsReview),
        _row(id: 'b', status: TranslationVersionStatus.needsReview),
      ];

      final container = ProviderContainer(overrides: [
        translationRowsProvider('p', 'fr').overrideWith((_) async => rows),
      ]);
      addTearDown(container.dispose);

      container
          .read(editorFilterProvider.notifier)
          .setStatusFilters({TranslationVersionStatus.needsReview});

      final filtered = await container
          .read(filteredTranslationRowsProvider('p', 'fr').future);
      expect(filtered.length, 2);
    });
  });
}
```

### - [ ] Step 2: Run test to confirm failure

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/providers/grid_data_providers_test.dart`

Expected: FAIL — the filter does not know about severity yet, so `['a', 'b']` comes back instead of `['a']`.

### - [ ] Step 3: Plug severity into `filteredTranslationRowsProvider`

In `lib/features/translation_editor/providers/grid_data_providers.dart`, add the import:

```dart
import 'package:twmt/features/translation_editor/utils/validation_issues_parser.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart' as batch;
import 'package:twmt/services/translation/models/translation_exceptions.dart'
    as v_exc;
```

Append a helper and call it from the `.where` block:

```dart
bool _matchesSeverity(
    TranslationRow row, Set<batch.ValidationSeverity> severities) {
  if (severities.isEmpty) return true;
  final parsed = parseValidationIssues(row.version.validationIssues);
  if (parsed.isEmpty) return false;
  for (final issue in parsed) {
    final mapped = issue.severity == v_exc.ValidationSeverity.error
        ? batch.ValidationSeverity.error
        : batch.ValidationSeverity.warning;
    if (severities.contains(mapped)) return true;
  }
  return false;
}
```

Inside `filteredTranslationRows`, right before the closing `return true;`, add:

```dart
    // Severity filter (only meaningful when statusFilters contains needsReview;
    // applied unconditionally because an empty set short-circuits).
    if (!_matchesSeverity(row, filterState.severityFilters)) {
      return false;
    }
```

### - [ ] Step 4: Run the test again

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/providers/grid_data_providers_test.dart`

Expected: both tests PASS.

### - [ ] Step 5: Commit

```bash
git add lib/features/translation_editor/providers/grid_data_providers.dart \
        test/features/translation_editor/providers/grid_data_providers_test.dart
git commit -m "feat: severity filter in editor filtered rows"
```

---

## Task 3: `visibleSeverityCounts` provider

**Files:**
- Modify: `lib/features/translation_editor/providers/grid_data_providers.dart` (append new provider)
- Test: `test/features/translation_editor/providers/grid_data_providers_test.dart` (extend)

### - [ ] Step 1: Add failing test

Append to the test file (`grid_data_providers_test.dart`), inside `main()`:

```dart
  group('visibleSeverityCounts', () {
    test('counts versions by severity over needsReview rows regardless of the '
        'severity filter itself', () async {
      final rows = [
        _row(
          id: 'a',
          status: TranslationVersionStatus.needsReview,
          issuesJson:
              _issues([(rule: 'variables', sev: 'error', msg: 'missing %s')]),
        ),
        _row(
          id: 'b',
          status: TranslationVersionStatus.needsReview,
          issuesJson: _issues([
            (rule: 'variables', sev: 'error', msg: 'x'),
            (rule: 'length', sev: 'warning', msg: 'y'),
          ]),
        ),
        _row(
          id: 'c',
          status: TranslationVersionStatus.needsReview,
          issuesJson: _issues(
              [(rule: 'length', sev: 'warning', msg: 'length ratio')]),
        ),
        _row(
          id: 'd',
          status: TranslationVersionStatus.translated,
        ),
      ];

      final container = ProviderContainer(overrides: [
        translationRowsProvider('p', 'fr').overrideWith((_) async => rows),
      ]);
      addTearDown(container.dispose);

      // A status filter that *excludes* needsReview must not zero out the
      // counts — the counts are computed before the status filter.
      container
          .read(editorFilterProvider.notifier)
          .setStatusFilters({TranslationVersionStatus.translated});

      final counts = await container
          .read(visibleSeverityCountsProvider('p', 'fr').future);
      expect(counts.errors, 2);
      expect(counts.warnings, 2);
    });
  });
```

### - [ ] Step 2: Run to confirm failure

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/providers/grid_data_providers_test.dart`

Expected: FAIL — `visibleSeverityCountsProvider` undefined.

### - [ ] Step 3: Implement the provider

At the bottom of `lib/features/translation_editor/providers/grid_data_providers.dart`, add:

```dart
/// Per-severity count over all `needsReview` versions for the project+language,
/// independent of the currently-applied severity / status filters. Used by
/// the SEVERITY pill group so the counts don't zero out the moment the user
/// picks a pill.
@riverpod
Future<({int errors, int warnings})> visibleSeverityCounts(
  Ref ref,
  String projectId,
  String languageId,
) async {
  final allRows =
      await ref.watch(translationRowsProvider(projectId, languageId).future);
  var errors = 0;
  var warnings = 0;
  for (final row in allRows) {
    if (row.status != TranslationVersionStatus.needsReview) continue;
    final parsed = parseValidationIssues(row.version.validationIssues);
    var rowHasError = false;
    var rowHasWarning = false;
    for (final issue in parsed) {
      if (issue.severity == v_exc.ValidationSeverity.error) rowHasError = true;
      if (issue.severity == v_exc.ValidationSeverity.warning) {
        rowHasWarning = true;
      }
    }
    if (rowHasError) errors++;
    if (rowHasWarning) warnings++;
  }
  return (errors: errors, warnings: warnings);
}
```

### - [ ] Step 4: Regenerate code and run tests

```bash
C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs
C:/src/flutter/bin/flutter test test/features/translation_editor/providers/grid_data_providers_test.dart
```

Expected: all tests PASS.

### - [ ] Step 5: Commit

```bash
git add lib/features/translation_editor/providers/grid_data_providers.dart \
        lib/features/translation_editor/providers/grid_data_providers.g.dart \
        test/features/translation_editor/providers/grid_data_providers_test.dart
git commit -m "feat: visible severity counts provider"
```

---

## Task 4: "Validation Issues" section in editor inspector

**Files:**
- Modify: `lib/features/translation_editor/widgets/editor_inspector_panel.dart`
- Test: `test/features/translation_editor/widgets/editor_inspector_panel_test.dart` (extend)

### - [ ] Step 1: Write the failing test

Append a new `testWidgets` to `test/features/translation_editor/widgets/editor_inspector_panel_test.dart`:

```dart
  testWidgets(
      'shows Validation Issues section with Accept/Reject/Edit for needsReview row',
      (tester) async {
    TranslationRow needsReviewRow() {
      final unit = TranslationUnit(
        id: '1',
        projectId: 'p',
        key: 'k',
        sourceText: 'source',
        createdAt: 0,
        updatedAt: 0,
      );
      final version = TranslationVersion(
        id: '1-v',
        unitId: '1',
        projectLanguageId: 'pl',
        translatedText: 'dst',
        status: TranslationVersionStatus.needsReview,
        translationSource: TranslationSource.manual,
        validationIssues:
            '[{"rule":"variables","severity":"error","message":"missing %s"}]',
        createdAt: 0,
        updatedAt: 0,
      );
      return TranslationRow(unit: unit, version: version);
    }

    var accepted = false;
    var rejected = false;
    var edited = false;

    final container = ProviderContainer(overrides: [
      filteredTranslationRowsProvider('p', 'fr')
          .overrideWith((_) async => [needsReviewRow()]),
      currentProjectProvider('p').overrideWith(
        (_) async => Project(
          id: 'p',
          name: 'p',
          gameInstallationId: 'g',
          projectType: 'mod',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
      currentLanguageProvider('fr').overrideWith(
        (_) async => const Language(
            id: 'fr', code: 'fr', name: 'French', nativeName: 'Francais'),
      ),
    ]);
    addTearDown(container.dispose);

    // Single-select the needsReview row.
    container.read(editorSelectionProvider.notifier).selectSingle('1', 0);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1920,
            height: 1080,
            child: EditorInspectorPanel(
              projectId: 'p',
              languageId: 'fr',
              onSave: (_, _) {},
              onAcceptIssue: (_) => accepted = true,
              onRejectIssue: (_) => rejected = true,
              onEditIssue: (_) => edited = true,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('missing %s'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    expect(accepted, isTrue);
    await tester.tap(find.text('Reject'));
    expect(rejected, isTrue);
    await tester.tap(find.text('Edit'));
    expect(edited, isTrue);
  });
```

Add the missing imports at the top of the test file:

```dart
import 'package:twmt/providers/batch/batch_operations_provider.dart';
```

### - [ ] Step 2: Run to confirm failure

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_inspector_panel_test.dart`

Expected: FAIL — `onAcceptIssue`/`onRejectIssue`/`onEditIssue` named args don't exist; no "Validation Issues" section.

### - [ ] Step 3: Extend the panel with the new section + callbacks

Edit `lib/features/translation_editor/widgets/editor_inspector_panel.dart`:

1. Add imports at the top:

```dart
import 'package:twmt/features/translation_editor/utils/validation_issues_parser.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart'
    as batch;
import 'package:twmt/services/translation/models/translation_exceptions.dart'
    as v_exc;
```

2. Add typedefs near `OnInspectorSave`:

```dart
typedef OnInspectorIssueAction = void Function(batch.ValidationIssue issue);
```

3. Add three optional callbacks to `EditorInspectorPanel` and pass them down:

```dart
class EditorInspectorPanel extends ConsumerStatefulWidget {
  final String projectId;
  final String languageId;
  final OnInspectorSave onSave;
  final OnInspectorIssueAction? onAcceptIssue;
  final OnInspectorIssueAction? onRejectIssue;
  final OnInspectorIssueAction? onEditIssue;

  const EditorInspectorPanel({
    super.key,
    required this.projectId,
    required this.languageId,
    required this.onSave,
    this.onAcceptIssue,
    this.onRejectIssue,
    this.onEditIssue,
  });
  // ...
}
```

4. In `_EditorInspectorPanelState.build`, pass the callbacks into `_SingleSelectionBody`:

```dart
        body = _SingleSelectionBody(
          row: row,
          index: idx + 1,
          total: rows.length,
          controller: _targetController,
          onSave: (text) => widget.onSave(row.id, text),
          onAcceptIssue: widget.onAcceptIssue,
          onRejectIssue: widget.onRejectIssue,
          onEditIssue: widget.onEditIssue,
          tokens: tokens,
          projectId: widget.projectId,
          languageId: widget.languageId,
        );
```

5. Add the three optional fields to `_SingleSelectionBody` and render the new section conditionally, above the `_KeyChip`:

```dart
class _SingleSelectionBody extends ConsumerWidget {
  final TranslationRow row;
  final int index;
  final int total;
  final TextEditingController controller;
  final void Function(String) onSave;
  final OnInspectorIssueAction? onAcceptIssue;
  final OnInspectorIssueAction? onRejectIssue;
  final OnInspectorIssueAction? onEditIssue;
  final TwmtThemeTokens tokens;
  final String projectId;
  final String languageId;

  const _SingleSelectionBody({
    required this.row,
    required this.index,
    required this.total,
    required this.controller,
    required this.onSave,
    required this.onAcceptIssue,
    required this.onRejectIssue,
    required this.onEditIssue,
    required this.tokens,
    required this.projectId,
    required this.languageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(currentProjectProvider(projectId)).value;
    final language = ref.watch(currentLanguageProvider(languageId)).value;
    final sourceCode = project?.sourceLanguageCode ?? 'en';
    final targetCode = language?.code ?? 'fr';

    final showValidationSection =
        row.status == TranslationVersionStatus.needsReview &&
            row.version.validationIssues != null;
    final parsed = showValidationSection
        ? parseValidationIssues(row.version.validationIssues)
        : const <ParsedValidationIssue>[];
    final hasIssues = parsed.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(index: index, total: total, tokens: tokens),
        const SizedBox(height: 10),
        if (hasIssues) ...[
          _ValidationIssuesSection(
            row: row,
            issues: parsed,
            onAccept: onAcceptIssue,
            onReject: onRejectIssue,
            onEdit: onEditIssue,
            tokens: tokens,
          ),
          const SizedBox(height: 14),
        ],
        _KeyChip(
          text: '${row.sourceLocFile ?? ''} / ${row.key}',
          tokens: tokens,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _SourceBlock(
            text: row.sourceText,
            lang: sourceCode,
            tokens: tokens,
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _TargetBlock(
            controller: controller,
            lang: targetCode,
            onSave: onSave,
            tokens: tokens,
          ),
        ),
      ],
    );
  }
}
```

6. Add the new `_ValidationIssuesSection` widget at the bottom of the file:

```dart
class _ValidationIssuesSection extends StatelessWidget {
  final TranslationRow row;
  final List<ParsedValidationIssue> issues;
  final OnInspectorIssueAction? onAccept;
  final OnInspectorIssueAction? onReject;
  final OnInspectorIssueAction? onEdit;
  final TwmtThemeTokens tokens;

  const _ValidationIssuesSection({
    required this.row,
    required this.issues,
    required this.onAccept,
    required this.onReject,
    required this.onEdit,
    required this.tokens,
  });

  batch.ValidationIssue _toBatch(ParsedValidationIssue p) {
    final sev = p.severity == v_exc.ValidationSeverity.error
        ? batch.ValidationSeverity.error
        : batch.ValidationSeverity.warning;
    return batch.ValidationIssue(
      unitKey: row.key,
      unitId: row.unit.id,
      versionId: row.version.id,
      severity: sev,
      issueType: p.type,
      description: p.description,
      sourceText: row.sourceText,
      translatedText: row.translatedText ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    // The bulk actions target the version, not individual issues — we pass the
    // first parsed issue to the callback so the mixin has the version+unit ids
    // it needs. The action is idempotent regardless of which issue we hand in.
    final primary = issues.first;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VALIDATION ISSUES',
            style: tokens.fontMono.copyWith(
              fontSize: 9.5,
              color: tokens.textFaint,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          for (final issue in issues) ...[
            _IssueRow(issue: issue, tokens: tokens),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _IssueActionButton(
                  label: 'Accept',
                  icon: FluentIcons.checkmark_24_regular,
                  color: tokens.accent,
                  onTap: onAccept == null ? null : () => onAccept!(_toBatch(primary)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _IssueActionButton(
                  label: 'Reject',
                  icon: FluentIcons.dismiss_24_regular,
                  color: tokens.err,
                  onTap: onReject == null ? null : () => onReject!(_toBatch(primary)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _IssueActionButton(
                  label: 'Edit',
                  icon: FluentIcons.edit_24_regular,
                  color: tokens.accent,
                  onTap: onEdit == null ? null : () => onEdit!(_toBatch(primary)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final ParsedValidationIssue issue;
  final TwmtThemeTokens tokens;
  const _IssueRow({required this.issue, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final isError = issue.severity == v_exc.ValidationSeverity.error;
    final color = isError ? tokens.err : tokens.warn;
    final icon = isError
        ? FluentIcons.error_circle_24_filled
        : FluentIcons.warning_24_filled;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            issue.description,
            style: TextStyle(fontSize: 12, color: tokens.textMid),
          ),
        ),
      ],
    );
  }
}

class _IssueActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _IssueActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: enabled ? 0.10 : 0.04),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### - [ ] Step 4: Add a second test — section hidden for non-needsReview rows

Append to the same `testWidgets` group:

```dart
  testWidgets('hides Validation Issues section for translated rows',
      (tester) async {
    TranslationRow translatedRow() {
      final unit = TranslationUnit(
        id: '2',
        projectId: 'p',
        key: 'k2',
        sourceText: 's',
        createdAt: 0,
        updatedAt: 0,
      );
      final version = TranslationVersion(
        id: '2-v',
        unitId: '2',
        projectLanguageId: 'pl',
        translatedText: 't',
        status: TranslationVersionStatus.translated,
        translationSource: TranslationSource.manual,
        createdAt: 0,
        updatedAt: 0,
      );
      return TranslationRow(unit: unit, version: version);
    }

    final container = ProviderContainer(overrides: [
      filteredTranslationRowsProvider('p', 'fr')
          .overrideWith((_) async => [translatedRow()]),
      currentProjectProvider('p').overrideWith(
        (_) async => Project(
          id: 'p',
          name: 'p',
          gameInstallationId: 'g',
          projectType: 'mod',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
      currentLanguageProvider('fr').overrideWith(
        (_) async => const Language(
            id: 'fr', code: 'fr', name: 'French', nativeName: 'Francais'),
      ),
    ]);
    addTearDown(container.dispose);
    container.read(editorSelectionProvider.notifier).selectSingle('2', 0);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1920,
            height: 1080,
            child: EditorInspectorPanel(
              projectId: 'p',
              languageId: 'fr',
              onSave: (_, _) {},
              onAcceptIssue: (_) {},
              onRejectIssue: (_) {},
              onEditIssue: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('VALIDATION ISSUES'), findsNothing);
  });
```

### - [ ] Step 5: Run tests

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_inspector_panel_test.dart`

Expected: all tests PASS.

### - [ ] Step 6: Commit

```bash
git add lib/features/translation_editor/widgets/editor_inspector_panel.dart \
        test/features/translation_editor/widgets/editor_inspector_panel_test.dart
git commit -m "feat: validation issues section in editor inspector"
```

---

## Task 5: SEVERITY pill group in FilterToolbar

**Files:**
- Modify: `lib/features/translation_editor/screens/translation_editor_screen.dart`
- Test: `test/features/translation_editor/widgets/editor_filter_toolbar_test.dart` (extend)

### - [ ] Step 1: Write failing tests

Replace the final closing brace of the `main()` body in `editor_filter_toolbar_test.dart` and add these tests before it:

```dart
  testWidgets('hides SEVERITY pill group when needsReview is not in statusFilters',
      (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(find.text('SEVERITY'), findsNothing);
  });

  testWidgets('shows SEVERITY pill group with counts when needsReview is selected',
      (tester) async {
    await tester.pumpWidget(build(extraOverrides: [
      visibleSeverityCountsProvider(projectId, languageId).overrideWith(
        (_) async => (errors: 3, warnings: 7),
      ),
    ]));
    await tester.pumpAndSettle();

    // Flip the filter state via the running provider scope.
    final element = tester.element(find.byType(TranslationEditorScreen));
    final container = ProviderScope.containerOf(element, listen: false);
    container
        .read(editorFilterProvider.notifier)
        .setStatusFilters({TranslationVersionStatus.needsReview});
    await tester.pumpAndSettle();

    expect(find.text('SEVERITY'), findsOneWidget);
    expect(find.widgetWithText(FilterPill, 'Errors'), findsOneWidget);
    expect(find.widgetWithText(FilterPill, 'Warnings'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // error count
    expect(find.text('7'), findsOneWidget); // warning count
  });
```

Add to the imports at the top of the test file if missing:

```dart
import 'package:twmt/providers/batch/batch_operations_provider.dart';
```

### - [ ] Step 2: Run to confirm failure

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_filter_toolbar_test.dart`

Expected: FAIL — SEVERITY group not rendered.

### - [ ] Step 3: Add the conditional pill group to the screen

In `lib/features/translation_editor/screens/translation_editor_screen.dart`:

1. Add imports:

```dart
import 'package:twmt/providers/batch/batch_operations_provider.dart';
```

2. Inside `build`, after reading `filter`, also watch the counts:

```dart
    final severityCountsAsync = ref.watch(
      visibleSeverityCountsProvider(widget.projectId, widget.languageId),
    );
    final severityCounts = severityCountsAsync.asData?.value ??
        (errors: 0, warnings: 0);
```

3. Change the `FilterToolbar.pillGroups` list to append the severity group conditionally:

```dart
                pillGroups: [
                  _buildStatusGroup(filter, stats),
                  if (filter.statusFilters
                      .contains(TranslationVersionStatus.needsReview))
                    _buildSeverityGroup(filter, severityCounts),
                ],
```

4. Add the builder method next to `_buildStatusGroup`:

```dart
  FilterPillGroup _buildSeverityGroup(
    EditorFilterState filter,
    ({int errors, int warnings}) counts,
  ) {
    FilterPill pill(
      String label,
      ValidationSeverity severity,
      int count,
    ) {
      final active = filter.severityFilters.contains(severity);
      return FilterPill(
        label: label,
        selected: active,
        count: count,
        onToggle: () {
          final updated =
              Set<ValidationSeverity>.from(filter.severityFilters);
          if (active) {
            updated.remove(severity);
          } else {
            updated.add(severity);
          }
          ref.read(editorFilterProvider.notifier)
              .setSeverityFilters(updated);
        },
      );
    }

    return FilterPillGroup(
      label: 'SEVERITY',
      clearLabel: 'Clear',
      onClear: () => ref
          .read(editorFilterProvider.notifier)
          .setSeverityFilters(const {}),
      pills: [
        pill('Errors', ValidationSeverity.error, counts.errors),
        pill('Warnings', ValidationSeverity.warning, counts.warnings),
      ],
    );
  }
```

### - [ ] Step 4: Run tests

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_filter_toolbar_test.dart`

Expected: all tests PASS.

### - [ ] Step 5: Commit

```bash
git add lib/features/translation_editor/screens/translation_editor_screen.dart \
        test/features/translation_editor/widgets/editor_filter_toolbar_test.dart
git commit -m "feat: severity pill group in editor filter toolbar"
```

---

## Task 6: Shared `BulkActionCluster` + contextual display in editor

**Files:**
- Create: `lib/widgets/lists/bulk_action_cluster.dart`
- Modify: `lib/features/translation_editor/screens/translation_editor_screen.dart`
- Test: `test/features/translation_editor/screens/translation_editor_screen_test.dart` (extend)
- Test: `test/widgets/lists/bulk_action_cluster_test.dart` (create)

### - [ ] Step 1: Create the shared widget with a unit test first

Create `test/widgets/lists/bulk_action_cluster_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/bulk_action_cluster.dart';

void main() {
  testWidgets('renders count and fires callbacks', (tester) async {
    var accepted = false;
    var rejected = false;
    var deselected = false;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.atelierDarkTheme,
      home: Scaffold(
        body: BulkActionCluster(
          selectedCount: 4,
          onAccept: () => accepted = true,
          onReject: () => rejected = true,
          onDeselect: () => deselected = true,
        ),
      ),
    ));

    expect(find.text('4 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Accept selected'));
    expect(accepted, isTrue);
    await tester.tap(find.byTooltip('Reject selected'));
    expect(rejected, isTrue);
    await tester.tap(find.byTooltip('Deselect all'));
    expect(deselected, isTrue);
  });
}
```

### - [ ] Step 2: Run to confirm failure

Run: `C:/src/flutter/bin/flutter test test/widgets/lists/bulk_action_cluster_test.dart`

Expected: FAIL — no such widget.

### - [ ] Step 3: Implement the shared widget

Create `lib/widgets/lists/bulk_action_cluster.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';

/// Compact Accept/Reject/Deselect cluster rendered in the FilterToolbar
/// trailing slot whenever at least one selected row has open validation
/// issues. Matches the editor toolbar's tokenised mini-action rail.
class BulkActionCluster extends StatelessWidget {
  const BulkActionCluster({
    super.key,
    required this.selectedCount,
    required this.onAccept,
    required this.onReject,
    required this.onDeselect,
  });

  final int selectedCount;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onDeselect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$selectedCount selected',
          style: tokens.fontMono.copyWith(
            fontSize: 12,
            color: tokens.textDim,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 10),
        SmallIconButton(
          icon: FluentIcons.checkmark_24_regular,
          tooltip: 'Accept selected',
          size: 32,
          iconSize: 16,
          foreground: tokens.accent,
          onTap: onAccept,
        ),
        const SizedBox(width: 6),
        SmallIconButton(
          icon: FluentIcons.dismiss_24_regular,
          tooltip: 'Reject selected',
          size: 32,
          iconSize: 16,
          foreground: tokens.err,
          onTap: onReject,
        ),
        const SizedBox(width: 6),
        SmallIconButton(
          icon: FluentIcons.dismiss_circle_24_regular,
          tooltip: 'Deselect all',
          size: 32,
          iconSize: 16,
          onTap: onDeselect,
        ),
      ],
    );
  }
}
```

### - [ ] Step 4: Run the cluster test

Run: `C:/src/flutter/bin/flutter test test/widgets/lists/bulk_action_cluster_test.dart`

Expected: PASS.

### - [ ] Step 5: Write a failing screen-level test for the contextual display

Append to `test/features/translation_editor/screens/translation_editor_screen_test.dart` (create the file with standard scaffolding if absent — follow `editor_filter_toolbar_test.dart` layout):

```dart
  testWidgets('bulk cluster is hidden when no needsReview row is selected',
      (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(find.byType(BulkActionCluster), findsNothing);
  });

  testWidgets('bulk cluster appears when a needsReview row is selected',
      (tester) async {
    // Row fixtures: one needsReview, one translated.
    final rows = [
      TranslationRow(
        unit: TranslationUnit(
          id: 'a',
          projectId: 'p',
          key: 'ka',
          sourceText: 'sa',
          createdAt: 0,
          updatedAt: 0,
        ),
        version: TranslationVersion(
          id: 'av',
          unitId: 'a',
          projectLanguageId: 'pl',
          translatedText: 'ta',
          status: TranslationVersionStatus.needsReview,
          translationSource: TranslationSource.manual,
          validationIssues:
              '[{"rule":"variables","severity":"error","message":"x"}]',
          createdAt: 0,
          updatedAt: 0,
        ),
      ),
    ];

    await tester.pumpWidget(build(extraOverrides: [
      translationRowsProvider(projectId, languageId)
          .overrideWith((_) async => rows),
    ]));
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(TranslationEditorScreen));
    final container = ProviderScope.containerOf(element, listen: false);
    container.read(editorSelectionProvider.notifier).selectSingle('a', 0);
    await tester.pumpAndSettle();

    expect(find.byType(BulkActionCluster), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
  });
```

Add the new imports needed:

```dart
import 'package:twmt/widgets/lists/bulk_action_cluster.dart';
import 'package:twmt/models/domain/translation_unit.dart';
```

### - [ ] Step 6: Run to confirm screen test failure

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/screens/translation_editor_screen_test.dart`

Expected: FAIL — the cluster is never rendered.

### - [ ] Step 7: Wire the cluster into the screen

In `lib/features/translation_editor/screens/translation_editor_screen.dart`:

1. Add imports:

```dart
import 'package:twmt/widgets/lists/bulk_action_cluster.dart';
```

2. Inside `build`, after `filter` is read, compute the review-eligible selection:

```dart
    final rowsAsync = ref.watch(
      filteredTranslationRowsProvider(widget.projectId, widget.languageId),
    );
    final visibleRows = rowsAsync.asData?.value ?? const <TranslationRow>[];
    final selection = ref.watch(editorSelectionProvider);
    final selectedNeedsReviewRows = visibleRows
        .where((r) =>
            selection.selectedUnitIds.contains(r.id) &&
            r.status == TranslationVersionStatus.needsReview)
        .toList();
```

3. Prepend the cluster to `FilterToolbar.trailing` (before `ListSearchField`):

```dart
                trailing: [
                  if (selectedNeedsReviewRows.isNotEmpty)
                    BulkActionCluster(
                      selectedCount: selectedNeedsReviewRows.length,
                      onAccept: () => _getActions()
                          .handleBulkAcceptTranslation(
                              selectedNeedsReviewRows),
                      onReject: () => _getActions()
                          .handleBulkRejectTranslation(
                              selectedNeedsReviewRows),
                      onDeselect: () => ref
                          .read(editorSelectionProvider.notifier)
                          .clearSelection(),
                    ),
                  ListSearchField(
                    // ...existing args unchanged
                  ),
                ],
```

`handleBulkAcceptTranslation` / `handleBulkRejectTranslation` become public methods in the next task. For now, add temporary placeholders in the screen if needed — or wait to commit Task 6 until Task 7's rename is also applied. The simpler path: **do Task 6 Steps 1–5 now (shared widget + unit test), then stop; move the screen wiring (Steps 6–8) to the end of Task 7 so the public method rename lands in one shot.**

### - [ ] Step 8: Commit the shared widget only

```bash
git add lib/widgets/lists/bulk_action_cluster.dart \
        test/widgets/lists/bulk_action_cluster_test.dart
git commit -m "feat: shared bulk action cluster widget"
```

---

## Task 7: Rewrite `handleValidate` + promote action methods + wire inspector/bulk

**Files:**
- Modify: `lib/features/translation_editor/screens/actions/editor_actions_validation.dart`
- Modify: `lib/features/translation_editor/widgets/editor_action_sidebar.dart`
- Modify: `lib/features/translation_editor/screens/translation_editor_screen.dart`
- Test: `test/features/translation_editor/screens/translation_editor_screen_test.dart` (extend from Task 6 Steps 5–6 — now finishable)

### - [ ] Step 1: Rewrite `handleValidate` — rescan then set filter

In `lib/features/translation_editor/screens/actions/editor_actions_validation.dart`:

1. Delete `exportValidationReport`, `_writeIssueToBuffer`, the `dart:io` + `file_picker` imports, the navigation import for `validation_review_screen.dart`, and the whole body of the old `handleValidate`.
2. Promote the five callbacks to public:
   - `_handleAcceptTranslation` → `handleAcceptTranslation`
   - `_handleRejectTranslation` → `handleRejectTranslation`
   - `_handleEditTranslation` → `handleEditTranslation`
   - `_handleBulkAcceptTranslation` → `handleBulkAcceptTranslation`
   - `_handleBulkRejectTranslation` → `handleBulkRejectTranslation`
3. Update the single method `handleBulkAcceptTranslation` / `handleBulkRejectTranslation` to accept `List<TranslationRow>` instead of `List<batch.ValidationIssue>` — the bulk cluster gives us rows, and `acceptBatch`/`rejectBatch` only need `version.id`. Signatures:

```dart
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';

Future<void> handleBulkAcceptTranslation(List<TranslationRow> rows) async {
  final versionRepo =
      ref.read(shared_repo.translationVersionRepositoryProvider);
  final ids = rows.map((r) => r.version.id).toSet().toList();
  final result = await versionRepo.acceptBatch(ids);
  if (result.isErr) {
    ref.read(loggingServiceProvider).error(
          'Failed to batch accept translations',
          {'count': ids.length, 'error': result.error},
        );
  } else {
    ref.read(loggingServiceProvider).info(
          'Batch accepted translations',
          {'count': result.value},
        );
  }
  refreshProviders();
}

Future<void> handleBulkRejectTranslation(List<TranslationRow> rows) async {
  final versionRepo =
      ref.read(shared_repo.translationVersionRepositoryProvider);
  final ids = rows.map((r) => r.version.id).toSet().toList();
  final result = await versionRepo.rejectBatch(ids);
  if (result.isErr) {
    ref.read(loggingServiceProvider).error(
          'Failed to batch reject translations',
          {'count': ids.length, 'error': result.error},
        );
  } else {
    ref.read(loggingServiceProvider).info(
          'Batch rejected translations',
          {'count': result.value},
        );
  }
  refreshProviders();
}
```

4. Rewrite `handleValidate` to call the existing rescan flow then apply the filter. The existing `handleRescanValidation` body already does the progress-dialog + rescan; extract it to a private method `_performRescan` that returns the count tuple `{scanned, newIssues, cleared, unchanged}`. Then:

```dart
Future<void> handleValidate() async {
  final outcome = await _performRescan();
  if (outcome == null) return; // user saw the info dialog already
  // Apply the review filter. The SEVERITY pill group will appear because
  // the filter state now contains `needsReview`.
  ref
      .read(editorFilterProvider.notifier)
      .setStatusFilters({TranslationVersionStatus.needsReview});
  ref
      .read(editorFilterProvider.notifier)
      .setSeverityFilters(const {});
  refreshProviders();

  if (!context.mounted) return;
  if (outcome.newIssues == 0 && outcome.unchanged > 0 && outcome.cleared == 0) {
    // Keep the informational dialog for the "nothing changed" case — users
    // clicking Validate expect feedback even if the world didn't move.
    EditorDialogs.showInfoDialog(
      context,
      'No issues to review',
      'All translations have passed validation.',
    );
  }
}
```

5. Delete the public `handleRescanValidation` method — the rescan is now an implementation detail of `handleValidate`. `translation_editor_screen.dart` currently wires `onRescanValidation: () => _getActions().handleRescanValidation()`; that line is removed in Step 3.

6. Add the `_performRescan` helper: copy the current body of `handleRescanValidation` from progress-dialog start to statistics summary, replace the final "showInfoDialog" with a `return (scanned: scanned, newIssues: newIssues, cleared: cleared, unchanged: unchanged);`, return `null` from the early-exit "Nothing to scan" branch.

Full replacement signature:

```dart
Future<({int scanned, int newIssues, int cleared, int unchanged})?>
    _performRescan() async { /* previous handleRescanValidation body,
       minus the final showInfoDialog, returning the tuple instead */ }
```

7. Drop `BatchValidationResults`/`batchValidationResultsProvider` usage (the call `ref.read(batch.batchValidationResultsProvider.notifier).setResults(...)` inside the old `handleValidate` is now gone).

### - [ ] Step 2: Remove the Rescan button and rename the Validate button

In `lib/features/translation_editor/widgets/editor_action_sidebar.dart`:

1. Drop `final VoidCallback onRescanValidation;` and its constructor entry.
2. Remove the `SmallTextButton` labelled "Rescan all" (keep the "Validate selected" action, keeping the primary-action height and tokenised look).

```dart
            _SectionHeader(label: 'Review', tokens: tokens),
            const SizedBox(height: 10),
            _SidebarActionButton(
              icon: FluentIcons.checkmark_circle_24_regular,
              label: 'Validate',
              onTap: onValidate,
            ),
```

### - [ ] Step 3: Update the screen to pass the new callbacks

In `lib/features/translation_editor/screens/translation_editor_screen.dart`:

1. Drop `onRescanValidation` from `EditorActionSidebar`:

```dart
                    EditorActionSidebar(
                      projectId: widget.projectId,
                      languageId: widget.languageId,
                      onTranslateAll: () => _getActions().handleTranslateAll(),
                      onTranslateSelected: () =>
                          _getActions().handleTranslateSelected(),
                      onValidate: () => _getActions().handleValidate(),
                      onExport: () => _getActions().handleExport(),
                      onImportPack: () => _getActions().handleImportPack(),
                    ),
```

2. Wire the inspector callbacks — `Accept` / `Reject` delegate straight to the action mixin; `Edit` opens `ValidationEditDialog` and applies the edit:

```dart
                    EditorInspectorPanel(
                      projectId: widget.projectId,
                      languageId: widget.languageId,
                      onSave: (unitId, text) =>
                          _getActions().handleCellEdit(unitId, text),
                      onAcceptIssue: (issue) =>
                          _getActions().handleAcceptTranslation(issue),
                      onRejectIssue: (issue) =>
                          _getActions().handleRejectTranslation(issue),
                      onEditIssue: (issue) async {
                        final newText = await showDialog<String>(
                          context: context,
                          builder: (_) => ValidationEditDialog(issue: issue),
                        );
                        if (newText != null) {
                          await _getActions()
                              .handleEditTranslation(issue, newText);
                        }
                      },
                    ),
```

Add the needed imports to the screen:

```dart
import '../widgets/validation_edit_dialog.dart';
```

3. Finish the wiring started in Task 6 Step 7 — plug `BulkActionCluster` and call the now-public bulk methods. The exact block in `FilterToolbar.trailing`:

```dart
                trailing: [
                  if (selectedNeedsReviewRows.isNotEmpty)
                    BulkActionCluster(
                      selectedCount: selectedNeedsReviewRows.length,
                      onAccept: () async {
                        await _getActions()
                            .handleBulkAcceptTranslation(
                                selectedNeedsReviewRows);
                      },
                      onReject: () async {
                        await _getActions()
                            .handleBulkRejectTranslation(
                                selectedNeedsReviewRows);
                      },
                      onDeselect: () => ref
                          .read(editorSelectionProvider.notifier)
                          .clearSelection(),
                    ),
                  ListSearchField(
                    // existing
                  ),
                ],
```

### - [ ] Step 4: Delete the `editor_action_sidebar_test.dart` assertion about "Rescan all"

Open `test/features/translation_editor/widgets/editor_action_sidebar_test.dart`. Grep for `Rescan` and delete / adjust any assertion expecting that label. Keep the `Validate` assertion (now without the "selected" suffix — update if needed).

### - [ ] Step 5: Add a test for the rewritten `handleValidate`

Append to `test/features/translation_editor/screens/translation_editor_screen_test.dart` (or create `test/features/translation_editor/screens/actions/editor_actions_validation_test.dart`):

```dart
  testWidgets('Validate button sets statusFilters to {needsReview}',
      (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(_SidebarActionButton, 'Validate'));
    // Rescan progress dialog appears then auto-dismisses with empty data;
    // pumpAndSettle flushes the whole chain.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final element = tester.element(find.byType(TranslationEditorScreen));
    final container = ProviderScope.containerOf(element, listen: false);
    expect(
      container.read(editorFilterProvider).statusFilters,
      contains(TranslationVersionStatus.needsReview),
    );
  });
```

`_SidebarActionButton` is private; target by label instead: `find.text('Validate')` inside the sidebar, then `tester.tap(find.ancestor(of: find.text('Validate'), matching: find.byType(GestureDetector)).first);`.

### - [ ] Step 6: Regenerate and run all editor tests

```bash
C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs
C:/src/flutter/bin/flutter test test/features/translation_editor/
```

Expected: all tests PASS. If the editor characterisation test fails on the removed "Rescan all" button, update it — the user confirmed this cleanup.

### - [ ] Step 7: Manual smoke test in a running app

```bash
C:/src/flutter/bin/flutter run -d windows
```

Verify:
1. Clicking **Validate** runs the rescan progress dialog, then the grid filters to `needsReview` rows.
2. The `SEVERITY` pill group appears with accurate Errors / Warnings counts.
3. Selecting a needsReview row shows the Validation Issues section in the inspector with Accept / Reject / Edit.
4. Clicking Accept clears the issue and the row leaves the filtered set.
5. Multi-selecting 2+ needsReview rows shows the bulk cluster in the toolbar; Accept bulk clears all of them.
6. Dropping `Needs review` from the STATUS group hides the SEVERITY group and wipes severity filters.

### - [ ] Step 8: Commit

```bash
git add lib/features/translation_editor/screens/actions/editor_actions_validation.dart \
        lib/features/translation_editor/widgets/editor_action_sidebar.dart \
        lib/features/translation_editor/screens/translation_editor_screen.dart \
        test/features/translation_editor/
git commit -m "refactor: merge validate and rescan and wire inspector actions"
```

---

## Task 8: Delete the Validation Review screen and its adjuncts

**Files:**
- Delete: see "Deleted" list in File Structure above.
- Modify: `lib/providers/batch/batch_operations_provider.dart` (remove `BatchValidationState` + `BatchValidationResults`).
- Test: delete the corresponding test files listed above.

### - [ ] Step 1: Delete the review screen files

```bash
rm lib/features/translation_editor/screens/validation_review_screen.dart
rm lib/features/translation_editor/widgets/validation_review_data_source.dart
rm lib/features/translation_editor/widgets/validation_review_inspector_panel.dart
rm lib/features/translation_editor/providers/validation_inspector_width_notifier.dart
rm lib/features/translation_editor/providers/validation_inspector_width_notifier.g.dart

rm test/features/translation_editor/screens/validation_review_screen_test.dart
rm test/features/translation_editor/widgets/validation_review_data_source_test.dart
rm test/features/translation_editor/widgets/validation_review_inspector_panel_test.dart
rm test/features/translation_editor/providers/validation_inspector_width_notifier_test.dart
```

### - [ ] Step 2: Remove `BatchValidationState` + `BatchValidationResults` from batch provider

Open `lib/providers/batch/batch_operations_provider.dart`. Delete the `BatchValidationState` class and the `@riverpod class BatchValidationResults extends _$BatchValidationResults { ... }` block (everything between `/// State for batch validation results` and the closing brace of the notifier, roughly lines 256–345).

Keep `ValidationIssue` and `ValidationSeverity` — still consumed by the editor inspector and the edit dialog.

### - [ ] Step 3: Regenerate code

```bash
C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs
```

### - [ ] Step 4: Prune the batch provider test

Open `test/providers/batch_operations_provider_test.dart`. Delete any `group` that targets `BatchValidationResults` / `BatchValidationState`. Leave the remaining tests untouched.

### - [ ] Step 5: Analyze + run the full test suite

```bash
C:/src/flutter/bin/flutter analyze
C:/src/flutter/bin/flutter test
```

Expected:
- `analyze`: 0 issues.
- `test`: all green.

If `analyze` flags an unused `file_picker` import somewhere, remove it. If `pubspec.yaml` still lists `file_picker` and the entire codebase no longer uses it, drop the dependency:

```bash
C:/src/flutter/bin/flutter pub remove file_picker
```

Then re-run `flutter analyze` + `flutter test`.

### - [ ] Step 6: Manual smoke test (second pass)

```bash
C:/src/flutter/bin/flutter run -d windows
```

Verify nothing regressed since Task 7's smoke test — especially the Validate flow, the inspector actions, and the bulk cluster. The Validation Review standalone screen must no longer be reachable.

### - [ ] Step 7: Commit

```bash
git add -A
git commit -m "chore: delete validation review screen and associated code"
```

---

## Self-review checklist (ran before handoff)

- Spec §1 (filter model) → Tasks 1 + 2 cover `severityFilters` + filtering logic.
- Spec §2 (per-version issues) → Task 3 covers counts; the inspector parses inline in Task 4.
- Spec §4 (inspector section) → Task 4.
- Spec §5 (SEVERITY pill group) → Task 5.
- Spec §6 (bulk cluster) → Task 6 + finished in Task 7 Step 3.
- Spec §7 (Validate rescan+filter) → Task 7.
- Spec §8 (export removed) → Task 7 Step 1.
- Spec §9 (status bar unchanged) → no task needed.
- Spec §10 (route cleanup) → Task 8. No `/validation-review` route exists currently (grep of `lib/config` came up empty), so deletion of the screen file + `MaterialPageRoute` push is sufficient.
- Placeholder scan → all steps have concrete code or concrete commands.
- Type consistency → `handleBulkAcceptTranslation` / `handleBulkRejectTranslation` take `List<TranslationRow>` in Task 6 Step 7, Task 7 Step 1, and Task 7 Step 3 — consistent.
- Test patterns match the repo conventions (ProviderContainer tear-down, `ProviderScope.containerOf` for running scopes, real repo fakes via `TestBootstrap.registerFakes()` or `setupMockServices()` as each file already does).
