# Validation Review — inspector panel & grid alignment

Date: 2026-04-19
Status: Draft

## Goal

Align the Validation Review screen layout with the Translation Editor:

- Shrink the central DataGrid rows to the editor height so the two screens feel
  consistent side by side.
- Add a resizable right-hand inspector panel that shows the full content of the
  row the user just clicked on, mirroring `EditorInspectorPanel`.

## Motivation

Today the Validation Review screen ships its row detail inline: 80 px tall rows,
multi-line cells for Source and Translation, and three action buttons
(Edit / Accept / Reject) in a trailing column. The Translation Editor uses a
different model — 44 px rows with truncated text, a right-hand inspector that
renders the full source and target for the currently selected unit, and a
drag-resizable width.

Users switch between the two screens constantly and the visual mismatch is
jarring. Migrating the review screen to the editor's pattern also lets the long
fields breathe (full text + scroll) instead of competing for grid column width.

## Scope

In scope:

- `lib/features/translation_editor/screens/validation_review_screen.dart`
- `lib/features/translation_editor/widgets/validation_review_data_source.dart`
- New widget: `lib/features/translation_editor/widgets/validation_review_inspector_panel.dart`
- New provider: `lib/features/translation_editor/providers/validation_inspector_width_notifier.dart`
- Test updates for the two files above, plus a new test for the inspector.

Out of scope:

- The top `ValidationReviewHeader` and `ValidationReviewToolbar` keep their
  current structure.
- Bulk selection semantics stay untouched (checkbox column + bulk Accept/Reject
  in the toolbar).
- No changes to the underlying `ValidationIssue` model or the action
  callbacks.

## Design

### 1. Central DataGrid — align on the editor

Change the two row-height properties on `SfDataGrid`:

- `rowHeight`: `80` → `44`
- `headerRowHeight`: `48` → `30`

Drop the `maxLines: 3` inside `_buildTextCell`; the cell now renders a single
truncated line (`TextOverflow.ellipsis`). The inspector panel shows the full
text.

Remove the `actions` GridColumn entirely. The three action buttons move to the
inspector. This frees roughly 200 px of horizontal space that goes back to the
Source and Translation columns.

Grid columns after the change:

| Column          | Width  | Role                           |
|-----------------|--------|--------------------------------|
| checkbox        | 50     | bulk selection (unchanged)     |
| severity        | 100    | icon cell (unchanged)          |
| issueType       | 140    | label chip (unchanged)         |
| key             | 200    | monospace key (unchanged)      |
| description     | 250    | short description (unchanged) |
| sourceText      | fill   | single-line truncated          |
| translatedText  | fill   | single-line truncated          |

### 2. Right-hand inspector panel

New widget `ValidationReviewInspectorPanel`, shaped like `EditorInspectorPanel`:

- A `Container` with a left border, hosting a `Row` of `[_ResizeHandle,
  Expanded(Padding(body))]`.
- Width is read from a new `validationInspectorWidthProvider` with the same
  clamp bounds as the editor (`minWidth=240`, `maxWidth=640`,
  `defaultWidth=320`).
- `_ResizeHandle` is copied verbatim from `EditorInspectorPanel`. Shared
  extraction is out of scope for this pass — if a third screen ever wants it,
  we move it to a common widget file then.

Three render branches, driven by `_currentVersionId` (see §3):

- **No current issue** → `_EmptyState` with the same copy pattern as the
  editor: "Select an issue to view details".
- **Current issue exists** → full body:
  - `_Header` (14 pt accent title "Issue" + position indicator
    `current-index / total` in mono).
  - `_KeyChip` with the unit key (monospace, faint panel).
  - Severity + issue type row: severity icon, coloured type chip, description
    text.
  - `_SourceBlock` (equal-sized, scrollable internal content, label
    "SOURCE · $sourceCode").
  - `_TranslationBlock` (equal-sized, scrollable, label
    "TRANSLATION · $targetCode"). Read-only — matches today's behaviour where
    edits happen via the Edit dialog, not inline.
  - `_ActionsRow`: three tappable tiles — Edit, Accept, Reject — reusing the
    visual style of the current `_buildSmallActionButton` (tinted container,
    coloured border, icon + label), but laid out in a single row that fills
    the panel width. When the issue is processing, swap the row for a centred
    spinner with an "Applying…" label.

We intentionally do **not** surface a multi-select body. When several rows are
checked, the inspector keeps showing the current row (the row the user last
clicked). The bulk actions already live in the toolbar at the top of the
screen; duplicating them in the panel would just clutter it.

### 3. Selection model

Two independent concepts:

- **Bulk selection** (`_selectedVersionIds`): the checkbox column. Used by the
  bulk Accept/Reject buttons in the toolbar. Unchanged.
- **Current issue** (new `_currentVersionId`): the issue whose detail is shown
  in the inspector. Set only by a non-checkbox click in the grid body.

Behaviour:

- Clicking a cell in any non-checkbox column sets `_currentVersionId` to that
  row's `versionId`. Checkboxes do not update it.
- Clicking a checkbox toggles only the bulk selection.
- When `_currentVersionId` is set but the underlying issue has been
  processed (i.e. removed from `_activeIssues`) — the inspector falls back to
  the empty state placeholder, same as when nothing is selected.
- On screen mount `_currentVersionId` is null → empty state.

Keyboard navigation (parity with the editor):

- The grid hosts a dedicated `FocusNode`. Once the user clicks any cell the
  node takes focus, and Up/Down arrows move `_currentVersionId` one row up or
  down within `_filteredIssues` (clamped to the list bounds).
- No Ctrl+A behaviour is added here — it already exists for the editor and
  isn't part of this work.

### 4. Inspector width provider

New file `validation_inspector_width_notifier.dart` — a copy/paste of
`editor_inspector_width_notifier.dart` with the class renamed. Same bounds
(`240`/`640`/`320`).

Keeping the providers separate avoids the editor and the validation screen
stomping on each other's preferred widths when the user opens one after the
other in the same session.

### 5. Layout integration

The screen's outer structure becomes:

```
Scaffold
  Column (vertical)
    ValidationReviewHeader
    ValidationReviewToolbar
    Expanded
      Row (horizontal)
        Expanded
          Padding(20) → Container(border) → SfDataGrid  (existing grid widget)
        ValidationReviewInspectorPanel                    (new)
```

The grid Padding/border chrome is preserved. The inspector sits flush against
the right edge of the scaffold, its left border merging with the scaffold's
margin.

## Testing

- `validation_review_data_source_test.dart`: drop the "actions column renders
  three buttons" tests (if any). Existing text-cell and checkbox-cell tests
  stay — they still pass with single-line rendering.
- `validation_review_screen_test.dart`: add tests for
  - inspector renders empty state on mount,
  - clicking a row populates the inspector with its key / source / translation,
  - clicking a checkbox does not update the inspector,
  - Up/Down arrows walk the current issue through `_filteredIssues`,
  - inspector shows a spinner while the issue is processing.
- New `validation_review_inspector_panel_test.dart` mirroring
  `editor_inspector_panel_test.dart`: empty state, single-issue body, processing
  spinner, key-chip content.
- New `validation_inspector_width_notifier_test.dart` mirroring the editor one:
  clamp bounds, default width, setWidth.

## Risks

- `onCellTap` is currently wired to toggle the checkbox when the tap lands on
  the checkbox column. Expanding it to update `_currentVersionId` on any other
  column needs a small guard so we don't treat header taps as row selections.
- If an accept/reject call removes the row from `_activeIssues`, the inspector
  must drop to the empty state cleanly. The inspector reads its row from
  `_filteredIssues` — already recomputed on every build — so the branch falls
  back to empty state automatically.
- The 44 px height is tight for the `issueType` badge chip padding. If the
  chip visually overflows we lower its vertical padding from 4 to 2.
