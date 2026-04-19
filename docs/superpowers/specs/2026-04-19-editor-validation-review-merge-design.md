# Editor / Validation Review — screen merge

Date: 2026-04-19
Status: Draft

## Goal

Fold the standalone Validation Review screen into the Translation Editor
screen. The review is modelled as a pre-configured filter + contextual
inspector section, eliminating ~60% of duplicated layout (DetailScreenToolbar +
FilterToolbar + DataGrid + Inspector + StatusBar) between the two screens.

After the merge:

- There is a single screen for editing and reviewing translations.
- Clicking "Validate" rescans, applies `statusFilters = {needsReview}`, and
  surfaces a new `SEVERITY` pill group for filtering by error / warning.
- The existing inspector gains a conditional "Validation Issues" section with
  Accept / Reject / Edit actions when the selected row has open issues.
- Bulk Accept / Reject appear contextually in the `FilterToolbar` trailing
  when any selected row has `status == needsReview`.
- The Validation Review screen, its data source, its inspector panel, its
  route, and its export-report action are deleted.

## Motivation

The Validation Review screen and the Translation Editor screen already share
the same visual skeleton (detail toolbar → filter toolbar → DataGrid →
inspector → status bar). The review screen is, conceptually, nothing more than
"the editor filtered to `needsReview` rows, with a severity sub-filter and
three extra actions in the inspector". Keeping it as a separate screen
duplicates layout, state machines (selection, search, filter pills, key
handling), and forces the user to navigate away from the editor to resolve
issues they can see inline.

Merging the two screens:

- Removes ~900 lines of near-duplicate UI code.
- Keeps the user in the editor, so flipping between "edit" and "review"
  amounts to toggling a pill.
- Centralises the grid / selection / keyboard-navigation logic on a single
  code path, which Plan 4 of the UI redesign will harden further.

## Scope

### In scope

- `lib/features/translation_editor/providers/editor_filter_notifier.dart` —
  extend with `severityFilters`.
- `lib/features/translation_editor/providers/editor_providers.dart` — new
  `versionValidationIssuesProvider`, filtering logic update.
- `lib/features/translation_editor/widgets/editor_inspector_panel.dart` —
  conditional "Validation Issues" section.
- `lib/features/translation_editor/widgets/editor_datagrid.dart` /
  `editor_filter_toolbar.dart` (or equivalent trailing slot) — contextual
  bulk cluster + conditional SEVERITY pill group.
- `lib/features/translation_editor/screens/actions/editor_actions_validation.dart`
  — refactor `handleValidate` to rescan + apply filter; delete
  `exportValidationReport` / `_writeIssueToBuffer`.
- `lib/features/translation_editor/screens/translation_editor_screen.dart` —
  plug the new pill group + bulk cluster.
- `lib/features/translation_editor/widgets/editor_action_sidebar.dart` —
  fuse `Validate` and `Rescan validation` buttons.
- Router — drop the validation-review route if it exists.
- Tests under `test/features/translation_editor/` — update editor tests,
  delete obsolete review-screen tests.

### Deleted

- `lib/features/translation_editor/screens/validation_review_screen.dart`
- `lib/features/translation_editor/widgets/validation_review_data_source.dart`
- `lib/features/translation_editor/widgets/validation_review_inspector_panel.dart`
- `test/features/translation_editor/screens/validation_review_screen_test.dart`
- `test/features/translation_editor/widgets/validation_review_data_source_test.dart`
- `test/features/translation_editor/widgets/validation_review_inspector_panel_test.dart`
- `exportValidationReport` / `_writeIssueToBuffer` in
  `editor_actions_validation.dart`, together with the `FilePicker` dependency
  if it becomes unused.

### Out of scope

- Any change to the underlying `ValidationIssue` model or to the
  `acceptBatch` / `rejectBatch` / `normalizeStatusEncoding` repository
  methods.
- Changes to the validation rules / `validationServiceProvider` itself.
- The status-pill count logic outside `needsReview` is untouched.
- Reworking `EditorStatusBar`. No `reviewed / remaining` counters are added.

## Design

### 1. Filter model — severity sub-filter

Extend `EditorFilterState`:

```dart
class EditorFilterState {
  final Set<TranslationVersionStatus> statusFilters;
  final Set<TmSourceType> tmSourceFilters;
  final Set<ValidationSeverity> severityFilters; // NEW
  final String searchQuery;
  final bool showOnlyWithIssues;
  // ...
}
```

- `EditorFilter` notifier gets `setSeverityFilters(Set<ValidationSeverity>)`.
- `clearFilters()` resets `severityFilters` too.
- `hasActiveFilters` includes `severityFilters.isNotEmpty`.

`ValidationSeverity` is the existing enum from
`providers/batch/batch_operations_provider.dart` — the same enum the old
review screen consumes. Keeping it in the `batch` layer avoids introducing
a cross-layer re-export.

### 2. Filtering logic

The filtering pipeline applies filters in this order (existing order
preserved, severity slotted in last):

1. Search query
2. Status filters
3. TM source filters
4. `showOnlyWithIssues`
5. **Severity filters** (new)

A version matches the severity filter if at least one of its parsed
validation issues has a severity in `severityFilters`. An empty
`severityFilters` set is a no-op (all versions pass).

Issues are decoded via the existing
`parseValidationIssues(version.validationIssues)` helper in
`utils/validation_issues_parser.dart`.

### 3. Per-version issues provider

New light-weight provider:

```dart
@riverpod
List<ParsedValidationIssue> versionValidationIssues(
  Ref ref,
  String versionId,
) {
  // Reads the version from the current row-model cache / repo, decodes.
}
```

Consumed by:

- `EditorInspectorPanel` to render the "Validation Issues" section.
- A derived provider `visibleSeverityCountsProvider` which returns
  `({int errors, int warnings})` over the currently filtered rows, used to
  drive the pill counts.

Caching is Riverpod's default (auto-dispose per versionId). Decode cost is
negligible (small JSON blobs).

### 4. Inspector — "Validation Issues" section

Inside `EditorInspectorPanel`, add a section above the existing "Source"
block, visible **only** when the selected version has
`status == needsReview` and `versionValidationIssues(versionId)` is
non-empty.

Layout:

```
┌─ Validation Issues ──────────────────────────┐
│ ⚠ Placeholder mismatch: missing %s           │
│ ⚠ Length ratio out of bounds (0.4x)          │
│                                              │
│ [ Accept ]  [ Reject ]  [ Edit ]             │
└──────────────────────────────────────────────┘
```

- Icons are severity-tinted (`tokens.err` for error, `tokens.warn` for
  warning).
- Buttons reuse the existing `FluentButton` primary/secondary styles.
- `Accept` calls the same logic as the current `_handleAcceptTranslation`
  (lifted out of `editor_actions_validation.dart` and called from the
  inspector).
- `Reject` calls `_handleRejectTranslation`.
- `Edit` opens `ValidationEditDialog` (kept; moved to
  `widgets/` if still useful only for this flow) and, on confirm, calls
  `_handleEditTranslation`.

Wiring: the inspector receives callbacks `onAccept / onReject / onEdit` from
`TranslationEditorScreen`, which delegates to the `EditorActionsValidation`
mixin. No new action class is introduced.

### 5. FilterToolbar — conditional SEVERITY pill group

In the editor's `FilterToolbar`:

- Existing `STATUS` pill group stays as-is.
- A new `SEVERITY` pill group is built **only if**
  `filterState.statusFilters.contains(needsReview)`.
- Two pills: `Errors (n)`, `Warnings (n)` where `n` is read from
  `visibleSeverityCountsProvider`.
- Multi-select allowed (matches the STATUS pill group behaviour).
- `Clear` resets `severityFilters`.

When `needsReview` is removed from `statusFilters`, the group disappears and
`severityFilters` is wiped automatically (avoids dangling filters).

### 6. FilterToolbar — contextual bulk cluster

Current editor: no contextual bulk cluster for review actions.
Current review: `_BulkActionCluster` in the `FilterToolbar` trailing
(Accept / Reject / Deselect).

After merge:

- Extract `_BulkActionCluster` into a shared widget
  `widgets/lists/bulk_action_cluster.dart` (or equivalent).
- In `TranslationEditorScreen`, render the cluster in `FilterToolbar`
  trailing when **at least one** selected row has `status == needsReview`.
  Rows that are not in `needsReview` are filtered out by the bulk action
  itself (pass the filtered list to `acceptBatch` / `rejectBatch`).
- The selection count shown is the count of *review-eligible* rows in the
  selection, not the full selection count.

### 7. "Validate" action — rescan + apply filter

In `editor_actions_validation.dart`:

- `handleValidate` is rewritten: trigger the existing rescan flow
  (`handleRescanValidation`'s body), then set
  `statusFilters = {needsReview}` and `severityFilters = {}`.
- `handleRescanValidation` is collapsed into `handleValidate`; the separate
  sidebar button is removed.
- No more navigation — `MaterialPageRoute` push is deleted.
- The `Validate` sidebar button keeps its label. Its spinner state follows
  the rescan progress dialog already in use.

If there are zero `needsReview` versions after rescan, the current info
dialog ("No issues to review / All translations have passed validation")
still appears.

### 8. Export report — removed

`exportValidationReport` and `_writeIssueToBuffer` in
`editor_actions_validation.dart` are deleted. The `FilePicker.saveFile` call
site on the review screen goes with it. The `file_picker` dependency stays
if used elsewhere; otherwise it is dropped from `pubspec.yaml`.

This removal is deliberate and confirmed by the user. No replacement.

### 9. Status bar — unchanged

`EditorStatusBar` is not modified. No `reviewed / remaining` counters are
added. Users get the existing editor status line regardless of the active
filter.

### 10. Route cleanup

If `AppRoutes` defines a validation-review route, it is removed. Any
`go_router` `GoRoute` wiring for `/validation-review` is deleted. Breadcrumb
`CrumbSegment('Validation Review')` usages disappear with the screen.

## Data flow

```
Sidebar "Validate" click
   └─> handleValidate (mixin)
         ├─> rescan flow (versionRepo.updateValidationBatch, progress dialog)
         ├─> editorFilter.setStatusFilters({needsReview})
         └─> editorFilter.setSeverityFilters({})

User toggles Severity pill
   └─> editorFilter.setSeverityFilters({...})
         └─> filtered rows recomputed (editor_providers)
               └─> grid + pill counts update

User selects a row
   └─> selection notifier updates
         └─> inspector reads versionValidationIssues(versionId)
               └─> renders "Validation Issues" block if non-empty

User clicks Accept in inspector
   └─> TranslationEditorScreen callback
         └─> EditorActionsValidation._handleAcceptTranslation
               └─> versionRepo.update(...)
                     └─> refreshProviders() -> grid re-renders
```

## Error handling

- Rescan failures: existing behaviour — close the progress dialog, show
  `EditorDialogs.showErrorDialog`.
- Accept / Reject / Edit failures: existing behaviour — log via
  `loggingServiceProvider`; the version remains `needsReview` so the row
  stays visible.
- Parsing errors in `parseValidationIssues`: existing behaviour — legacy
  entries surface as a single `type: 'legacy'` issue, unchanged.
- Empty selection + bulk Accept: the cluster is not rendered in this state,
  so no click is possible.

## Testing

### New / extended

- `editor_filter_notifier_test.dart` — `setSeverityFilters`, `clearFilters`
  wipes severity, `hasActiveFilters` includes severity.
- `editor_providers_test.dart` — filtering logic with severity applied.
- `editor_inspector_panel_test.dart` — renders "Validation Issues" section
  when version has issues; hidden otherwise; Accept / Reject / Edit
  callbacks fire.
- `editor_filter_toolbar_test.dart` — SEVERITY pill group visible iff
  `statusFilters` contains `needsReview`; pill counts from
  `visibleSeverityCountsProvider`; multi-select and clear behaviour.
- `editor_datagrid_test.dart` (or a dedicated screen test) — bulk cluster
  appears only when ≥ 1 selected row has `status == needsReview`.
- `editor_actions_validation_test.dart` — `handleValidate` performs rescan,
  sets the `needsReview` filter, no navigation.

### Deleted

- `validation_review_screen_test.dart`
- `validation_review_data_source_test.dart`
- `validation_review_inspector_panel_test.dart`

### Patterns

Reuse the hardened patterns from UI Plan 3
(`feedback_flutter_test_patterns.md` in memory): theme test helpers,
`override first-wins` for providers, `ServiceLocator.isRegistered`, real
field names — no ad-hoc workarounds.

## Migration plan (commit order)

1. **`feat: severity sub-filter in editor filter state`** — extend
   `EditorFilterState`, notifier, filtering logic, provider for per-version
   issues. Unit tests. No UI impact.
2. **`feat: validation issues section in editor inspector`** — inspector
   change + callbacks, Accept / Reject / Edit wiring. Inspector tests.
3. **`feat: severity pill group in editor filter toolbar`** — conditional
   pill group + counts provider. Toolbar tests.
4. **`feat: contextual bulk cluster in editor toolbar`** — extract
   `_BulkActionCluster`, plug into editor. Screen tests.
5. **`refactor: merge validate and rescan into single action`** — rewrite
   `handleValidate`, delete separate rescan button. Action tests updated.
   After this commit the editor can fully replace the review screen.
6. **`chore: delete validation review screen and export report`** — remove
   screen, data source, inspector panel, route, tests, export-report code,
   dangling provider usages. Run `flutter analyze`, full test suite, manual
   smoke test in `flutter run -d windows`.

Each commit is independently `flutter analyze`-clean and test-green.

## Risks

- **Loss of the ISSUE column on the grid.** Accepted by user in Q2. The
  issue text moves to the inspector; users need one click to see it.
- **Loss of export report.** Accepted by user. No replacement.
- **`batchValidationResultsProvider` consumption.** Before removal, grep the
  codebase; delete only if uniquely consumed by the review screen.
- **`FilePicker.saveFile` usage.** Drop the `file_picker` dependency only
  after confirming no other call site uses it.
- **Breadcrumb fidelity.** Users lose the `Validation Review` segment. Low
  impact; the context is communicated by the pill group instead.
