# Translation Editor — Back navigation, read-only grid, selection-driven inspector

**Status:** Spec · 2026-04-18
**Scope:** Standalone follow-up to Plan 4 (UI editor). Targets `lib/features/translation_editor/`.
**Out of spec tree:** This is not a numbered plan in the UI redesign series (5f was the last). Treat as a focused polish plan.

---

## 1. Motivation

Plan 4 shipped a three-panel editor (filter · grid · inspector) with a single 56 px `EditorTopBar` carrying the crumb inline. After use, three frictions surfaced:

1. **Back navigation is implicit.** The only way out is clicking the word `Projects` inside the crumb. Every other detail screen in the app (Project Detail, Glossary Detail, wizards) uses `DetailScreenToolbar`'s dedicated `←` button. The editor is the odd one out.
2. **Inline grid editing duplicates the inspector.** The grid allows direct edits in the `TARGET` column and the inspector has a Source/Target editor. Two entry points for the same write, two mental models.
3. **Three columns are dead weight in the default workflow.** `STATUS` (60 px icon header, no label), `LOC FILE` (150 px) and `TM` (120 px) eat ~330 px that `SOURCE` / `TARGET` need. Status is already surfaced by row highlight + inspector; loc file is filterable from the left panel; TM suggestions live in the inspector.

This spec aligns the editor on the shared detail-screen archetype, moves editing entirely into the inspector, and slims the grid to what the user actually reads.

## 2. Goals

- G1. Replace the editor's single 56 px top bar with the standard `DetailScreenToolbar` (48 px, back button + crumb) stacked above the existing action bar.
- G2. Remove inline editing from the Syncfusion DataGrid. All edits happen in the inspector panel.
- G3. Remove `STATUS`, `LOC FILE` and `TM` columns. Grid is reduced to `checkbox · key · source · target`.
- G4. Left-click on any row selects it (single-select) and populates the inspector. Checkbox / Ctrl+Click / Shift+Click drive multi-select.
- G5. Fix the pre-existing Plan 4 follow-up: unsaved inspector edits are silently discarded when selection switches — auto-save before rebind.

## 3. Non-goals

- N1. Command palette (`Ctrl+K`) wiring — already deferred.
- N2. Dynamic encoding in the status bar — already deferred.
- N3. Retokenising the inspector, filter panel, or status bar — already on Plan 4 tokens.
- N4. Adding new columns or new filter groups.
- N5. Changing the translation write path (`GridActionsHandler.handleCellEdit` stays as-is; only its callers change).

## 4. Design

### 4.1 Toolbar split (G1)

Two stacked bars replace the current single 56 px bar:

```
┌────────────────────────────────────────────────────────────────────┐
│ ← Work › Projects › <Project> › <Language>                   48px  │  DetailScreenToolbar
├────────────────────────────────────────────────────────────────────┤
│ [Model] [Skip-TM] │ [Rules] [Selection] [Translate all]     …56px  │  EditorActionBar
│            [Validate ▾] [Pack ▾]   ⚙  │  🔍 Search                  │
├────────────────────────────────────────────────────────────────────┤
│ Filters (200) │        Grid (4 cols, fill)        │ Inspector (320)│
├────────────────────────────────────────────────────────────────────┤
│ StatusBar (28)                                                     │
└────────────────────────────────────────────────────────────────────┘
```

- Reuse `lib/widgets/detail/detail_screen_toolbar.dart` with no modification. Its API (`crumb: String`, `onBack: VoidCallback`) already fits.
- Crumb text: `'Work › Projects › ${projectName} › ${languageName}'`. Matches the format used in `ProjectDetailScreen` (`'Work › Projects › ${p.name}'`).
- `onBack: () => Navigator.of(context).pop()`. The editor is pushed onto the navigator by `ProjectDetailScreen._handleOpenEditor`, which already calls `ref.invalidate(projectDetailsProvider(...))` on return. No change on the project side.
- The existing `EditorTopBar` loses its `_Crumb` + separator and is renamed `EditorActionBar`. Everything else (model selector, skip-tm, rules chip, 4 action buttons, settings icon, search field) stays identical and retains the `LayoutBuilder` compact-mode behaviour below 1600 px viewport.
- Total header height rises from 56 to 104 px. Acceptable trade for a consistent navigation model.

### 4.2 Read-only grid, 4 columns (G2, G3)

Final column set (left to right):

| # | columnName        | width        | allowEditing | Notes                                  |
|---|-------------------|--------------|--------------|----------------------------------------|
| 1 | `checkbox`        | 50           | —            | Header tri-state select-all, unchanged |
| 2 | `key`             | 150          | false        | Unchanged cell renderer                |
| 3 | `sourceText`      | fill         | false        | Unchanged cell renderer                |
| 4 | `translatedText`  | fill         | **false**    | Same `TextCellRenderer`, read-only     |

Changes in `editor_datagrid.dart`:

- Remove the 3 `GridColumn` entries for `status`, `locFile`, `tmSource`.
- Set `allowEditing: false` on the `SfDataGrid` itself (was `true`).
- Remove `allowEditing: true` from the `translatedText` column.
- Switch `navigationMode` to `GridNavigationMode.row` (was `cell`). With no editable cells the cell-focus ring is visual noise and can interact badly with the tap handler from §4.3.
- Switch `selectionMode` from `SelectionMode.multiple` to `SelectionMode.none`. Selection is driven entirely by `editorSelectionProvider`; the native Syncfusion highlight is replaced by a token-aware row background in `editor_data_source.dart` (see §4.3).

Changes in `editor_data_source.dart`:

- `buildRow()` (or its equivalent) drops the `DataGridCell` objects for `status`, `locFile`, `tmSource`.
- The `newCellValue` / `saveCellValue` callbacks become dead code paths; remove them.
- Add row background highlight: rows whose `unit.id` is in `editorSelectionProvider.selectedIds` render with `tokens.accentBg` background, others with the normal alternating palette.

Cell renderer audit (`lib/features/translation_editor/widgets/cell_renderers/`):

- `StatusCellRenderer` — used only by the removed `status` column. **Delete.**
- `ActionsCellRenderer` — already flagged as dead code in Plan 4 follow-ups. **Delete** now that we touch this area.
- `TextCellRenderer`, `CheckboxCellRenderer`, `context_menu_builder.dart` — kept.

### 4.3 Selection semantics (G4)

The checkbox column and left-click on a row have distinct meanings:

| Gesture                              | Effect                                                                                   |
|--------------------------------------|------------------------------------------------------------------------------------------|
| Left-click anywhere on a row (not the checkbox) | Single-select: clear previous selection, add this row, inspector → single mode. |
| Click on the row's checkbox          | Toggle this row in the current selection set (multi-select).                             |
| Ctrl+Click on a row                  | Same as checkbox toggle.                                                                 |
| Shift+Click on a row                 | Range-select from the last single-click anchor to the clicked row.                       |
| Right-click on a row                 | Unchanged — existing context menu.                                                       |
| Click in empty grid area             | No-op (Syncfusion doesn't emit this event).                                              |

Implementation is in `grid_selection_handler.dart` (already exists):

- `handleCellTap(DataGridCellTapDetails details)` branches on `columnName`:
  - `checkbox` → existing `handleCheckboxTap` path (toggle in set).
  - any other column → inspect `HardwareKeyboard.instance.isControlPressed` / `isShiftPressed`:
    - Ctrl pressed: toggle (same as checkbox path).
    - Shift pressed: compute `[anchorRowId .. targetRowId]` range from the cached `_lastAnchorRowId`, set selection to that range.
    - Neither: `selectSingleRow(rowId, rowIndex)` (clears then sets). Update `_lastAnchorRowId = rowId`.
- `editorSelectionProvider` is the single source of truth. No changes to its API.

Changes in `translation_editor_screen.dart`:

- `EditorDataGrid.onRowSelected` parameter is removed. The inspector already listens to `editorSelectionProvider` directly — the callback was redundant plumbing.

### 4.4 Inspector auto-save (G5)

`EditorInspectorPanel._bindControllerForUnit` currently overwrites the text controller when the selected unit ID changes, silently dropping unsaved edits.

Fix:

- Before rebinding, if `_controller.text` differs from the previously bound unit's persisted translation AND the previous unit still exists, call `widget.onSave(previousUnitId, _controller.text)` (which routes through `GridActionsHandler.handleCellEdit`).
- Then proceed with the existing rebind logic.

No UI change — the save is silent, consistent with Apple Notes / IDE-style blur-saves. If a future iteration needs a dirty badge in the inspector header, that's out of scope here.

### 4.5 Filter panel, status bar — unchanged

- `EditorFilterPanel` keeps its filter groups including "Fichier loc" (filtering by loc file without showing the column).
- `EditorStatusBar` unchanged.

## 5. Testing

### 5.1 New / updated widget tests

- `translation_editor_screen_test.dart`: assert presence of `DetailScreenToolbar` with expected crumb + `onBack` popping the route. Drop any assertion that looked for the old `_Crumb`.
- `editor_datagrid_test.dart`:
  - The grid's `columns` property contains exactly 4 entries with `columnName` in `{checkbox, key, sourceText, translatedText}`.
  - `allowEditing == false` on the grid, `allowEditing == false` on the `translatedText` column.
  - Left-click on `sourceText` cell of row 1 → `editorSelectionProvider.selectedIds == {row1.id}`; previously selected rows are cleared.
  - Click the checkbox of row 2 after single-selecting row 1 → `selectedCount == 2`.
  - Simulate Ctrl+Click on row 2 after single-selecting row 1 → `selectedCount == 2` (matches checkbox behaviour).
- `editor_inspector_panel_test.dart`: type text into target, change the selected unit id in `editorSelectionProvider`, assert `onSave` was called with the dirty text for the *previous* unit before rebind.

### 5.2 Goldens

Plan 4 shipped 4 goldens (2 themes × 2 states) under `test/features/translation_editor/`. Both the toolbar split and the 3-column removal invalidate all 4. Regenerate with `--update-goldens` as part of the implementation plan's final task.

### 5.3 Regression targets

- All existing tests in `test/features/translation_editor/` must pass.
- `dart analyze` must stay at current lint baseline (no new warnings).

## 6. Files touched

**Modified:**
- `lib/features/translation_editor/screens/translation_editor_screen.dart`
- `lib/features/translation_editor/widgets/editor_top_bar.dart` → renamed `editor_action_bar.dart`, `_Crumb` removed
- `lib/features/translation_editor/widgets/editor_datagrid.dart`
- `lib/features/translation_editor/widgets/editor_data_source.dart`
- `lib/features/translation_editor/widgets/grid_selection_handler.dart`
- `lib/features/translation_editor/widgets/editor_inspector_panel.dart`

**Deleted:**
- `lib/features/translation_editor/widgets/cell_renderers/status_cell_renderer.dart`
- `lib/features/translation_editor/widgets/cell_renderers/actions_cell_renderer.dart` (dead code from Plan 4)

**Unchanged but consumed:**
- `lib/widgets/detail/detail_screen_toolbar.dart`
- `lib/features/translation_editor/widgets/editor_inspector_panel.dart` (minimal edit for §4.4)
- `lib/features/translation_editor/widgets/editor_filter_panel.dart`
- `lib/features/translation_editor/widgets/editor_status_bar.dart`
- `lib/features/translation_editor/providers/editor_selection_notifier.dart`

## 7. Risks & mitigations

- **Syncfusion focus ring on non-editable cells.** Switching `navigationMode` from `cell` to `row` should suppress it. If a focus ring still leaks through, fall back to wrapping the grid in a `FocusScope` that swallows keyboard navigation inside the grid area.
- **Shift-range across a sorted view.** Sorting is disabled (`allowSorting: false`), so the underlying `translationRows` order is stable. Range computation uses list indices — safe.
- **Auto-save fires during typing.** §4.4 only triggers on selection change, not on every keystroke. Rapid typing followed by selection switch still saves once, which is desired.
- **Deleted cell renderers referenced elsewhere.** Grep before deletion — `StatusCellRenderer` and `ActionsCellRenderer` should be unreferenced outside the datagrid.

## 8. Open follow-ups (explicitly deferred)

These remain on the backlog and are not addressed here:

- Command palette `Ctrl+K` overlay (Plan 4 follow-up).
- Dynamic encoding in status bar (Plan 4 follow-up).
- Session-level token / cost tracking (Plan 4 follow-up).
- `Ctrl+R` retranslate intent wiring or footer-hint removal (Plan 4 follow-up).
- Spec/doc reconciliation on chev token naming (Plan 4 follow-up).
