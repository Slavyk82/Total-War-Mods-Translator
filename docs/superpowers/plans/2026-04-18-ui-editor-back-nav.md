# Translation Editor — Back-nav, Read-only Grid, Inspector-driven Editing

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the translation editor on the shared detail-screen archetype: add a dedicated back button + crumb, make the DataGrid read-only and 4-column, route all editing through the inspector, and fix the unsaved-edit data-loss bug.

**Architecture:** Reuse the existing `DetailScreenToolbar` primitive stacked above the ex-`EditorTopBar` (renamed `EditorActionBar`). Reduce the Syncfusion DataGrid to `checkbox · key · source · target` with `allowEditing: false` and `selectionMode: none`; selection is fully driven by `editorSelectionProvider`. Auto-save any dirty inspector edit before rebinding to a new selected unit.

**Tech Stack:** Flutter desktop (Material), Riverpod 3, Syncfusion DataGrid, existing TWMT theme tokens (`context.tokens`).

**Spec:** `docs/superpowers/specs/2026-04-18-ui-editor-back-nav-design.md`.

---

## File Structure

### Modified

- `lib/features/translation_editor/screens/translation_editor_screen.dart` — stacked toolbars, drop `onRowSelected` plumbing.
- `lib/features/translation_editor/widgets/editor_top_bar.dart` → **renamed** `editor_action_bar.dart`: drop `_Crumb` widget + leading separator; class renamed `EditorActionBar`.
- `lib/features/translation_editor/widgets/editor_datagrid.dart` — drop 3 columns, `allowEditing: false`, `navigationMode: row`, `selectionMode: none`, drop `onRowSelected` param.
- `lib/features/translation_editor/widgets/editor_data_source.dart` — drop 3 cells, drop `buildEditWidget` + `onCellSubmit` + `newCellValue`, drop `_escapeForDisplay` / `_unescapeForStorage` / `_extractLocFileName` / `_getTmSourceText`, drop `_activeEditController`, drop unused `'actions'` cell, add selected-row background.
- `lib/features/translation_editor/widgets/grid_selection_handler.dart` — in `handleCellTap`, early-return when `columnName == 'checkbox'` (the `CheckboxCellRenderer` handles that tap itself).
- `lib/features/translation_editor/widgets/editor_inspector_panel.dart` — auto-save dirty target text in `_rebindIfNeeded` before overwriting the controller.

### Deleted

- `lib/features/translation_editor/widgets/cell_renderers/status_cell_renderer.dart` — orphan after STATUS column removed.
- `lib/features/translation_editor/widgets/cell_renderers/tm_source_cell_renderer.dart` — orphan after TM column removed.

### Tests modified / added

- `test/features/translation_editor/screens/translation_editor_screen_test.dart` — replace `EditorTopBar` assertions with `EditorActionBar` + `DetailScreenToolbar` assertions, swap `find.text('Projects')` for the new crumb format.
- `test/features/translation_editor/widgets/editor_top_bar_test.dart` → **renamed** `editor_action_bar_test.dart` — drop the `crumb shows project and language and pops on tap` test (crumb is no longer in the action bar).
- `test/features/translation_editor/widgets/editor_data_source_test.dart` — new assertions: 4 rendered cells per row (no status/locFile/tmSource), selected row highlight present.
- `test/features/translation_editor/widgets/editor_datagrid_test.dart` — NEW or extend existing: column list, `allowEditing`, checkbox-column early return on cell tap.
- `test/features/translation_editor/widgets/editor_inspector_panel_test.dart` — new test: dirty target text auto-saved before rebind.
- `test/features/translation_editor/widgets/editor_top_bar_test.dart` → renamed + updated: keep all non-crumb tests.

---

## Task 1: Stack `DetailScreenToolbar` on top of the editor

Add the 48 px `DetailScreenToolbar` above the existing `EditorTopBar`. Do NOT remove the `_Crumb` yet (Task 2 will). This keeps the tree valid between commits.

**Files:**
- Modify: `lib/features/translation_editor/screens/translation_editor_screen.dart`
- Test: `test/features/translation_editor/screens/translation_editor_screen_test.dart`

- [ ] **Step 1: Add failing test — DetailScreenToolbar is rendered**

In `test/features/translation_editor/screens/translation_editor_screen_test.dart`, add inside the `group('Navigation', ...)` block (replacing the existing `should expose Projects crumb for back navigation` test):

```dart
    group('Navigation', () {
      testWidgets('renders DetailScreenToolbar with crumb and back button',
          (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(DetailScreenToolbar), findsOneWidget);
        // Crumb format: "Work › Projects › <project> › <language>".
        expect(
          find.textContaining('Work › Projects › Test Project › Spanish'),
          findsOneWidget,
        );
        expect(find.byTooltip('Back'), findsOneWidget);
      });
    });
```

Add the import at the top of the file:

```dart
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
```

- [ ] **Step 2: Run test — expect failure (`DetailScreenToolbar` not found)**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/screens/translation_editor_screen_test.dart -p vm`

Expected: the new `renders DetailScreenToolbar with crumb and back button` test fails with "Expected: exactly one matching candidate. Actual: _TypeWidgetFinder:<zero widgets>".

- [ ] **Step 3: Implement — add DetailScreenToolbar above EditorTopBar**

Modify `lib/features/translation_editor/screens/translation_editor_screen.dart`:

At the top, add imports:

```dart
import 'package:go_router/go_router.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
```

Replace the entire `build` method body so the `Column` starts with the new toolbar. The new build method:

```dart
  @override
  Widget build(BuildContext context) {
    final projectAsync = ref.watch(currentProjectProvider(widget.projectId));
    final languageAsync = ref.watch(currentLanguageProvider(widget.languageId));
    final projectName = projectAsync.whenOrNull(data: (p) => p.name) ?? '';
    final languageName = languageAsync.whenOrNull(data: (l) => l.name) ?? '';

    return Material(
      color: context.tokens.bg,
      child: Column(
        children: [
          DetailScreenToolbar(
            crumb: 'Work › Projects › $projectName › $languageName',
            onBack: () {
              if (context.canPop()) {
                context.pop();
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
          EditorTopBar(
            projectId: widget.projectId,
            languageId: widget.languageId,
            onTranslationSettings: () => _getActions().handleTranslationSettings(),
            onTranslateAll: () => _getActions().handleTranslateAll(),
            onTranslateSelected: () => _getActions().handleTranslateSelected(),
            onValidate: () => _getActions().handleValidate(),
            onRescanValidation: () => _getActions().handleRescanValidation(),
            onExport: () => _getActions().handleExport(),
            onImportPack: () => _getActions().handleImportPack(),
          ),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EditorFilterPanel(
                  projectId: widget.projectId,
                  languageId: widget.languageId,
                ),
                Expanded(
                  child: EditorDataGrid(
                    projectId: widget.projectId,
                    languageId: widget.languageId,
                    onCellEdit: (unitId, newText) =>
                      _getActions().handleCellEdit(unitId, newText),
                    onForceRetranslate: () =>
                      _getActions().handleForceRetranslateSelected(),
                  ),
                ),
                EditorInspectorPanel(
                  projectId: widget.projectId,
                  languageId: widget.languageId,
                  onSave: (unitId, text) =>
                    _getActions().handleCellEdit(unitId, text),
                  onApplySuggestion: (unitId, text) =>
                    _getActions().handleCellEdit(unitId, text),
                ),
              ],
            ),
          ),

          EditorStatusBar(
            projectId: widget.projectId,
            languageId: widget.languageId,
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 4: Run test — expect pass**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/screens/translation_editor_screen_test.dart -p vm`

Expected: all tests pass (including the new `renders DetailScreenToolbar with crumb and back button`).

- [ ] **Step 5: Commit**

```bash
git add lib/features/translation_editor/screens/translation_editor_screen.dart \
        test/features/translation_editor/screens/translation_editor_screen_test.dart
git commit -m "feat: add DetailScreenToolbar above editor top bar"
```

---

## Task 2: Remove `_Crumb` from the top bar and rename it `EditorActionBar`

Now that `DetailScreenToolbar` owns the crumb, drop the inline crumb from the action bar. Rename the file + class to reflect its new responsibility.

**Files:**
- Rename: `lib/features/translation_editor/widgets/editor_top_bar.dart` → `editor_action_bar.dart` (class `EditorTopBar` → `EditorActionBar`).
- Modify: `lib/features/translation_editor/screens/translation_editor_screen.dart` — update import + type name.
- Rename test: `test/features/translation_editor/widgets/editor_top_bar_test.dart` → `editor_action_bar_test.dart` (class reference + helper factory name + drop the crumb test).
- Modify: `test/features/translation_editor/screens/translation_editor_screen_test.dart` — replace `EditorTopBar` with `EditorActionBar`.

- [ ] **Step 1: Write the failing test — action bar no longer has `Projects` word**

Edit `test/features/translation_editor/widgets/editor_top_bar_test.dart`:

- Delete the entire `testWidgets('crumb shows project and language and pops on tap', ...)` test (lines 115–152) and the `_PopCountingObserver` class at the bottom.
- Add a new test after `renders the search field`:

```dart
  testWidgets('does not render a Projects crumb anymore', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(body: _bar()),
      theme: AppTheme.atelierDarkTheme,
      screenSize: desktopTestSize,
      overrides: _baseOverrides(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Projects'), findsNothing);
  });
```

- [ ] **Step 2: Run test — expect the new test to fail**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_top_bar_test.dart -p vm`

Expected: `does not render a Projects crumb anymore` fails with "Expected: no matching candidates. Actual: _TextWidgetFinder:<1 widget ...>".

- [ ] **Step 3: Rename the file + class**

Move `lib/features/translation_editor/widgets/editor_top_bar.dart` to `editor_action_bar.dart`:

```bash
git mv lib/features/translation_editor/widgets/editor_top_bar.dart \
       lib/features/translation_editor/widgets/editor_action_bar.dart
```

In the new file, rename the class and trim the crumb:

- Replace every `EditorTopBar` token with `EditorActionBar` (the public class, its state `_EditorTopBarState` → `_EditorActionBarState`, and the doc comment's opening line "Top bar of the translation editor (56px)." → "Action bar of the translation editor (56px).").
- Delete the `class _Crumb extends StatelessWidget { ... }` definition entirely (lines 188–237 in the original).
- In the `build` method's `Row` children, delete the two leading entries:

```dart
              // Fixed-width left side: clickable crumb + separator.
              _Crumb(projectName: projectName, languageName: languageName),
              const _Sep(),
```

- Because the crumb no longer reads `projectAsync` / `languageAsync`, remove those two lines from `build`:

```dart
    final projectAsync = ref.watch(currentProjectProvider(widget.projectId));
    final languageAsync = ref.watch(currentLanguageProvider(widget.languageId));
    final projectName = projectAsync.whenOrNull(data: (p) => p.name) ?? '';
    final languageName = languageAsync.whenOrNull(data: (l) => l.name) ?? '';
```

Then remove the now-unused import `import 'package:twmt/features/translation_editor/providers/editor_providers.dart';` (confirm it's no longer referenced in this file — `editorFilterProvider` and `editorSelectionProvider` are imported from the same file, so keep the import but check it's still needed for those. Look at the imports section: the file imports `editor_providers.dart` for `editorFilterProvider` and `editorSelectionProvider`, both still used. Keep the import.)

- [ ] **Step 4: Update consumers — screen + tests**

In `lib/features/translation_editor/screens/translation_editor_screen.dart`:

```dart
// Replace:
import '../widgets/editor_top_bar.dart';
// With:
import '../widgets/editor_action_bar.dart';
```

And in the same file, replace the two occurrences of `EditorTopBar` in the `build` method (the widget constructor call in the `Column`) with `EditorActionBar`.

Rename the test file:

```bash
git mv test/features/translation_editor/widgets/editor_top_bar_test.dart \
       test/features/translation_editor/widgets/editor_action_bar_test.dart
```

In the renamed test file, replace:
- `import 'package:twmt/features/translation_editor/widgets/editor_top_bar.dart';` → `import 'package:twmt/features/translation_editor/widgets/editor_action_bar.dart';`
- `EditorTopBar _bar() => EditorTopBar(` → `EditorActionBar _bar() => EditorActionBar(`

In `test/features/translation_editor/screens/translation_editor_screen_test.dart`, replace:
- `import 'package:twmt/features/translation_editor/widgets/editor_top_bar.dart';` → `import 'package:twmt/features/translation_editor/widgets/editor_action_bar.dart';`
- Every `EditorTopBar` (in `find.byType` calls and test description strings) → `EditorActionBar`
- Change the assertion `expect(find.text('Projects'), findsOneWidget);` (in the `should render EditorTopBar with crumb navigation` test) — this test lives at line 102. Replace the whole test with:

```dart
      testWidgets('should render EditorActionBar', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(EditorActionBar), findsOneWidget);
      });
```

Delete the duplicated `testWidgets('should expose Projects crumb for back navigation', ...)` test (inside `group('Navigation', ...)`) — the new DetailScreenToolbar crumb test added in Task 1 replaces it.

- [ ] **Step 5: Run the three impacted test files**

Run:
```bash
C:/src/flutter/bin/flutter test \
  test/features/translation_editor/widgets/editor_action_bar_test.dart \
  test/features/translation_editor/screens/translation_editor_screen_test.dart \
  -p vm
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A lib/features/translation_editor/ test/features/translation_editor/
git commit -m "refactor: rename EditorTopBar to EditorActionBar and drop inline crumb"
```

---

## Task 3: Remove STATUS, LOC FILE and TM columns from the grid

Strip the 3 columns in `editor_datagrid.dart` and `editor_data_source.dart`, delete their orphan renderers, and simplify the data source.

**Files:**
- Modify: `lib/features/translation_editor/widgets/editor_datagrid.dart`
- Modify: `lib/features/translation_editor/widgets/editor_data_source.dart`
- Delete: `lib/features/translation_editor/widgets/cell_renderers/status_cell_renderer.dart`
- Delete: `lib/features/translation_editor/widgets/cell_renderers/tm_source_cell_renderer.dart`
- Test: `test/features/translation_editor/widgets/editor_data_source_test.dart`

- [ ] **Step 1: Write the failing test — data source exposes exactly 4 cells**

Edit `test/features/translation_editor/widgets/editor_data_source_test.dart` — at the top of `void main()`, add:

```dart
  test('rows expose exactly [checkbox, key, sourceText, translatedText]', () {
    final source = EditorDataSource(
      onCellEdit: (_, _) {},
      onCellTap: (_) {},
      onCheckboxTap: (_) {},
      isRowSelected: (_) => false,
    );

    final unit = TranslationUnit(
      id: 'u1',
      projectId: 'p',
      key: 'k1',
      sourceText: 'Hello',
      sourceLocFile: 'file.loc',
      createdAt: 0,
      updatedAt: 0,
    );
    final version = TranslationVersion(
      id: 'v1',
      unitId: 'u1',
      projectLanguageId: 'pl',
      translatedText: 'Bonjour',
      status: TranslationVersionStatus.translated,
      translationSource: TranslationSource.llm,
      createdAt: 0,
      updatedAt: 0,
    );
    source.updateDataSource([TranslationRow(unit: unit, version: version)]);

    final names = source.rows.single
        .getCells()
        .map((c) => c.columnName)
        .toList();
    expect(names, ['checkbox', 'key', 'sourceText', 'translatedText']);
  });
```

If the test file doesn't already import the models, add at the top:

```dart
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/widgets/editor_data_source.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
```

- [ ] **Step 2: Run test — expect failure (7 names instead of 4)**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_data_source_test.dart -p vm`

Expected: the new test fails with "Expected: `['checkbox', 'key', 'sourceText', 'translatedText']` Actual: `['checkbox', 'status', 'locFile', 'key', 'sourceText', 'translatedText', 'tmSource', 'actions']`".

- [ ] **Step 3: Strip cells in `editor_data_source.dart`**

In `lib/features/translation_editor/widgets/editor_data_source.dart`:

- Remove the imports:
  ```dart
  import 'cell_renderers/status_cell_renderer.dart';
  import 'cell_renderers/tm_source_cell_renderer.dart';
  ```
- Remove `import 'package:twmt/models/domain/translation_version.dart';` — the `TranslationVersionStatus` DataGridCell goes away with the status cell. (Keep it only if other references remain — search: `grep -n 'translation_version' editor_data_source.dart`. If only the removed status cell used it, drop the import.)
- Replace the entire `List<DataGridRow> get rows =>` getter with:

```dart
  @override
  List<DataGridRow> get rows => _rows.asMap().entries.map((entry) {
    final index = entry.key;
    final row = entry.value;

    return _rowCache.putIfAbsent(index, () {
      return DataGridRow(
        cells: [
          DataGridCell<String>(columnName: 'checkbox', value: row.id),
          DataGridCell<String>(columnName: 'key', value: row.key),
          DataGridCell<String>(columnName: 'sourceText', value: row.sourceText),
          DataGridCell<String?>(
            columnName: 'translatedText',
            value: row.translatedText,
          ),
        ],
      );
    });
  }).toList();
```

- Replace `DataGridRowAdapter buildRow(DataGridRow row)` with:

```dart
  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final cells = row.getCells();
    final unitId = cells[0].value as String;
    final keyValue = cells[1].value as String;
    final sourceTextValue = cells[2].value as String;
    final translatedTextValue = cells[3].value as String?;

    final isSelected = isRowSelected(unitId);
    final translationRow = rowById(unitId);

    void handleSecondaryTap(Offset position) {
      onCellSecondaryTap?.call(translationRow, position);
    }

    return DataGridRowAdapter(
      color: isSelected ? _selectedRowColor : null,
      cells: [
        RepaintBoundary(
          child: CheckboxCellRenderer(
            isSelected: isSelected,
            onTap: () => onCheckboxTap(unitId),
          ),
        ),
        RepaintBoundary(
          child: TextCellRenderer(
            text: keyValue,
            isKey: true,
            onSecondaryTap: handleSecondaryTap,
          ),
        ),
        TextCellRenderer(
          text: sourceTextValue,
          onSecondaryTap: handleSecondaryTap,
        ),
        TextCellRenderer(
          text: translatedTextValue,
          onSecondaryTap: handleSecondaryTap,
        ),
      ],
    );
  }
```

- Add a `Color? _selectedRowColor;` field and a setter near the top of the class:

```dart
  Color? _selectedRowColor;

  /// Token-aware background colour for selected rows. Plumbed in from the
  /// datagrid when it builds, so the data source stays theme-agnostic.
  // ignore: use_setters_to_change_properties
  void setSelectedRowColor(Color color) {
    _selectedRowColor = color;
  }
```

- Delete the following now-unused methods and fields:
  - `static String _getTmSourceText(TranslationRow row) { ... }`
  - `static String? _extractLocFileName(String? path) { ... }`
  - `static String _escapeForDisplay(String text) { ... }`
  - `static String _unescapeForStorage(String text) { ... }`
  - `Future<void> onCellSubmit(...) { ... }`
  - `dynamic newCellValue;`
  - `Widget? buildEditWidget(...) { ... }`
  - The `TextEditingController? _activeEditController;` field and the `_activeEditController?.dispose();` / `_activeEditController = null;` lines in `dispose()`.

Also delete the `onCellTap` parameter from the constructor (it's never used — `onCellTap: (unitId) {}` in the datagrid is a placeholder). Keep the API minimal:

```dart
  EditorDataSource({
    required this.onCellEdit,
    required this.onCheckboxTap,
    required this.isRowSelected,
    this.onCellSecondaryTap,
  });
```

And drop the field `final Function(String unitId) onCellTap;`.

- [ ] **Step 4: Drop the 3 columns in `editor_datagrid.dart`**

In `lib/features/translation_editor/widgets/editor_datagrid.dart`:

- In `initState`, remove the `onCellTap: (unitId) {}` argument from `EditorDataSource(...)` (match the new constructor signature).
- In the `columns` list of the `SfDataGrid` call, **remove** the three `GridColumn` entries named `status`, `locFile`, and `tmSource`. Final list is:

```dart
                columns: [
                  GridColumn(
                    columnName: 'checkbox',
                    width: 50,
                    allowSorting: false,
                    label: Container(
                      padding: const EdgeInsets.all(8.0),
                      alignment: Alignment.center,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: _handleSelectAllCheckbox,
                          child: Checkbox(
                            value: _getSelectAllCheckboxState(),
                            tristate: true,
                            onChanged: (_) => _handleSelectAllCheckbox(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  GridColumn(
                    columnName: 'key',
                    width: 150,
                    allowSorting: false,
                    label: _buildColumnHeader('KEY'),
                  ),
                  GridColumn(
                    columnName: 'sourceText',
                    columnWidthMode: ColumnWidthMode.fill,
                    allowSorting: false,
                    label: _buildColumnHeader('SOURCE'),
                  ),
                  GridColumn(
                    columnName: 'translatedText',
                    columnWidthMode: ColumnWidthMode.fill,
                    allowSorting: false,
                    label: _buildColumnHeader('TARGET'),
                  ),
                ],
```

- Inside `build` (just before the `return MouseRegion(...)`), before the return, push the tokenised selected-row colour into the data source so the `buildRow` override picks it up:

```dart
    _dataSource.setSelectedRowColor(context.tokens.accentBg);
```

- [ ] **Step 5: Delete the orphan renderers**

```bash
git rm lib/features/translation_editor/widgets/cell_renderers/status_cell_renderer.dart
git rm lib/features/translation_editor/widgets/cell_renderers/tm_source_cell_renderer.dart
```

- [ ] **Step 6: Verify no stale references**

Run:
```bash
```

Use Grep tool: pattern `StatusCellRenderer|TmSourceCellRenderer`, path `lib` and `test`. Expected: zero results.

- [ ] **Step 7: Run data source test — expect pass**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_data_source_test.dart -p vm`

Expected: all tests pass (including the new `rows expose exactly [checkbox, key, sourceText, translatedText]`).

- [ ] **Step 8: Run the whole editor test suite**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/ -p vm --exclude-tags=golden`

Expected: all tests pass. (Goldens are handled in Task 6.)

- [ ] **Step 9: Commit**

```bash
git add -A lib/features/translation_editor/ test/features/translation_editor/
git commit -m "refactor: reduce editor grid to checkbox/key/source/target"
```

---

## Task 4: Disable inline editing and adjust grid selection mode

Turn the grid into a read-only surface and move selection handling fully into `editorSelectionProvider`.

**Files:**
- Modify: `lib/features/translation_editor/widgets/editor_datagrid.dart`
- Modify: `lib/features/translation_editor/widgets/grid_selection_handler.dart`
- Test: `test/features/translation_editor/widgets/editor_data_source_test.dart` (or a new `editor_datagrid_test.dart`)

- [ ] **Step 1: Write the failing test — checkbox column cell tap does not trigger single-select**

Create `test/features/translation_editor/widgets/grid_selection_handler_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/widgets/editor_data_source.dart';
import 'package:twmt/features/translation_editor/widgets/grid_selection_handler.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';

import '../../../helpers/test_bootstrap.dart';

TranslationRow _row(String id) {
  final unit = TranslationUnit(
    id: id,
    projectId: 'p',
    key: 'k-$id',
    sourceText: 's-$id',
    sourceLocFile: 'f.loc',
    createdAt: 0,
    updatedAt: 0,
  );
  final version = TranslationVersion(
    id: '$id-v',
    unitId: id,
    projectLanguageId: 'pl',
    translatedText: 't-$id',
    status: TranslationVersionStatus.translated,
    translationSource: TranslationSource.llm,
    createdAt: 0,
    updatedAt: 0,
  );
  return TranslationRow(unit: unit, version: version);
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  test('checkbox column cell-tap is a no-op (CheckboxCellRenderer owns it)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dataSource = EditorDataSource(
      onCellEdit: (_, _) {},
      onCheckboxTap: (_) {},
      isRowSelected: (_) => false,
    );
    dataSource.updateDataSource([_row('a'), _row('b')]);

    final handler = GridSelectionHandler(
      dataSource: dataSource,
      controller: DataGridController(),
      ref: container,
      onSelectionChanged: (_, _) {},
    );

    handler.handleCellTap(
      DataGridCellTapDetails(
        rowColumnIndex: const RowColumnIndex(1, 0),
        column: GridColumn(columnName: 'checkbox', label: const SizedBox()),
        globalPosition: Offset.zero,
        localPosition: Offset.zero,
        kind: PointerDeviceKind.mouse,
      ),
    );

    // Checkbox cell was tapped but the handler should NOT promote it to a
    // single-select — that is `CheckboxCellRenderer`'s job via onCheckboxTap.
    expect(container.read(editorSelectionProvider).selectedCount, 0);
  });
}
```

Note: `WidgetRef` is replaced by `Ref`/`ProviderContainer` here; make sure `GridSelectionHandler.ref` accepts a `Ref`-like object. Looking at the current signature it takes `WidgetRef`. Adjust: either parametrise the handler on a narrower type (a function `T Function<T>(ProviderListenable<T>)` wrapper) or, simpler, call handler API via a real widget. If typing trouble surfaces, inline the same assertion inside a `testWidgets` that pumps a `Consumer` widget instead — the behavioural intent is what matters.

Concretely, if `WidgetRef` is required, switch the test to a `testWidgets` pattern:

```dart
testWidgets('checkbox column cell-tap is a no-op', (tester) async {
  late WidgetRef capturedRef;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const SizedBox();
            },
          ),
        ),
      ),
    ),
  );

  final dataSource = EditorDataSource(
    onCellEdit: (_, _) {},
    onCheckboxTap: (_) {},
    isRowSelected: (_) => false,
  );
  dataSource.updateDataSource([_row('a'), _row('b')]);

  final handler = GridSelectionHandler(
    dataSource: dataSource,
    controller: DataGridController(),
    ref: capturedRef,
    onSelectionChanged: (_, _) {},
  );

  handler.handleCellTap(
    DataGridCellTapDetails(
      rowColumnIndex: const RowColumnIndex(1, 0),
      column: GridColumn(columnName: 'checkbox', label: const SizedBox()),
      globalPosition: Offset.zero,
      localPosition: Offset.zero,
      kind: PointerDeviceKind.mouse,
    ),
  );

  expect(capturedRef.read(editorSelectionProvider).selectedCount, 0);
});
```

Use whichever variant compiles — both express the same assertion.

- [ ] **Step 2: Run test — expect failure (selection count is 1)**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/grid_selection_handler_test.dart -p vm`

Expected: fails with "Expected: <0> Actual: <1>".

- [ ] **Step 3: Implement — early-return on checkbox column in `handleCellTap`**

Edit `lib/features/translation_editor/widgets/grid_selection_handler.dart`:

Replace the top of `handleCellTap`:

```dart
  /// Handle cell tap with support for Ctrl and Shift modifiers
  void handleCellTap(DataGridCellTapDetails details) {
    if (details.rowColumnIndex.rowIndex == 0) return; // Header row

    // The CheckboxCellRenderer owns the tap gesture on the checkbox column,
    // so the grid's onCellTap must not also promote the row to a single
    // selection — that would clobber the multi-select the checkbox just
    // applied.
    if (details.column.columnName == 'checkbox') return;

    final rowIndex = details.rowColumnIndex.rowIndex - 1;
    if (rowIndex < 0 || rowIndex >= dataSource.rows.length) return;
    // ... rest unchanged ...
```

- [ ] **Step 4: Run test — expect pass**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/grid_selection_handler_test.dart -p vm`

Expected: pass.

- [ ] **Step 5: Disable inline editing on the grid**

Edit `lib/features/translation_editor/widgets/editor_datagrid.dart`:

Inside the `SfDataGrid(...)` constructor call in `build`, change:

```dart
                allowEditing: true,
```

to:

```dart
                allowEditing: false,
```

And change:

```dart
                selectionMode: SelectionMode.multiple,
                navigationMode: GridNavigationMode.cell,
```

to:

```dart
                selectionMode: SelectionMode.none,
                navigationMode: GridNavigationMode.row,
```

The `translatedText` GridColumn previously had `allowEditing: true` — after Task 3 it no longer does. Verify it's absent now.

- [ ] **Step 6: Run the editor test suite**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/ -p vm --exclude-tags=golden`

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/features/translation_editor/widgets/editor_datagrid.dart \
        lib/features/translation_editor/widgets/grid_selection_handler.dart \
        test/features/translation_editor/widgets/grid_selection_handler_test.dart
git commit -m "refactor: disable inline grid editing and let provider drive selection"
```

---

## Task 5: Drop the `onRowSelected` plumbing in the grid

The inspector already listens to `editorSelectionProvider` directly, so the callback is dead plumbing.

**Files:**
- Modify: `lib/features/translation_editor/widgets/editor_datagrid.dart`

- [ ] **Step 1: Read current state**

Confirm the parameter exists in `EditorDataGrid`:

```dart
  final Function(TranslationRow row)? onRowSelected;
```

and the call site in `_handleCellTap` fires it.

- [ ] **Step 2: Remove the parameter**

In `lib/features/translation_editor/widgets/editor_datagrid.dart`:

- Delete the field and the constructor entry for `onRowSelected`.
- In `_handleCellTap`, delete the `if (widget.onRowSelected != null) { ... }` block.

- [ ] **Step 3: Verify no consumers pass `onRowSelected`**

Use Grep tool: pattern `onRowSelected`, path `lib`. Expected: only the removed declaration lines; no call site passes it (the screen in Task 1 already omits it).

If the screen still passed it, delete there too.

- [ ] **Step 4: Run the editor test suite**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/ -p vm --exclude-tags=golden`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/translation_editor/widgets/editor_datagrid.dart
git commit -m "refactor: drop onRowSelected grid plumbing"
```

---

## Task 6: Auto-save unsaved inspector edits on selection switch

Currently `_rebindIfNeeded` overwrites `_targetController.text` whenever the bound unit id changes, silently dropping any unsaved text. Fix by firing `onSave` with the *previous* unit's dirty text before overwriting.

**Files:**
- Modify: `lib/features/translation_editor/widgets/editor_inspector_panel.dart`
- Test: `test/features/translation_editor/widgets/editor_inspector_panel_test.dart`

- [ ] **Step 1: Write the failing test**

In `test/features/translation_editor/widgets/editor_inspector_panel_test.dart`, add this new test after the existing `target field calls onSave when focus is lost`:

```dart
  testWidgets(
    'dirty target text auto-saves for previous unit when selection switches',
    (tester) async {
      final saves = <MapEntry<String, String>>[];
      final container = ProviderContainer(overrides: [
        filteredTranslationRowsProvider('p', 'fr')
            .overrideWith((_) async => [_row('1'), _row('2')]),
        currentProjectProvider('p').overrideWith((_) async => const Project(
              id: 'p',
              name: 'p',
              gameInstallationId: 'g',
              sourceLanguageCode: 'en',
              createdAt: 0,
              updatedAt: 0,
            )),
        currentLanguageProvider('fr').overrideWith((_) async => const Language(
              id: 'fr',
              code: 'fr',
              name: 'French',
              nativeName: 'Français',
            )),
        tmSuggestionsForUnitProvider('1', 'en', 'fr')
            .overrideWith((_) async => []),
        tmSuggestionsForUnitProvider('2', 'en', 'fr')
            .overrideWith((_) async => []),
      ]);
      addTearDown(container.dispose);
      container.read(editorSelectionProvider.notifier).toggleSelection('1');

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Scaffold(
            body: EditorInspectorPanel(
              projectId: 'p',
              languageId: 'fr',
              onSave: (id, text) => saves.add(MapEntry(id, text)),
              onApplySuggestion: (_, _) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Type something into unit 1's target.
      final field = find.byKey(const Key('editor-inspector-target-field'));
      await tester.tap(field);
      await tester.enterText(field, 'Draft unit 1 text');
      // Do NOT unfocus — we want to simulate the selection switch race.

      // Switch selection to unit 2.
      container.read(editorSelectionProvider.notifier)
        ..clearSelection()
        ..toggleSelection('2');
      await tester.pumpAndSettle();

      // Assert: unit 1 was auto-saved with the dirty text before rebind.
      expect(
        saves.any((e) => e.key == '1' && e.value == 'Draft unit 1 text'),
        isTrue,
        reason: 'Expected an auto-save for unit 1 with the typed text, '
            'got: $saves',
      );
    },
  );
```

- [ ] **Step 2: Run test — expect failure**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_inspector_panel_test.dart -p vm`

Expected: the new test fails — `saves` is empty because the current code overwrites the controller without saving.

- [ ] **Step 3: Implement auto-save before rebind**

Edit `lib/features/translation_editor/widgets/editor_inspector_panel.dart`:

Replace `_rebindIfNeeded` with:

```dart
  /// Sync the target controller text with the currently selected row.
  ///
  /// Before rebinding to a new unit, fire `onSave` for the *previous* unit
  /// whenever the controller holds text that differs from the previously
  /// bound row's persisted translation. This prevents silent data loss when
  /// the user types then switches selection without blurring the field.
  void _rebindIfNeeded() {
    final selection = ref.read(editorSelectionProvider);
    final rowsAsync = ref.read(
      filteredTranslationRowsProvider(widget.projectId, widget.languageId),
    );
    final rows = rowsAsync.value;

    if (selection.selectedCount != 1) {
      // Multi/zero select: flush any dirty text for the previously bound unit
      // before we drop the binding.
      _flushDirtyIfNeeded(rows);
      _boundUnitId = null;
      return;
    }

    if (rows == null) return;
    final selectedId = selection.selectedUnitIds.first;
    final idx = rows.indexWhere((r) => r.id == selectedId);
    if (idx < 0) return;
    final row = rows[idx];

    if (_boundUnitId != row.id) {
      _flushDirtyIfNeeded(rows);
      _boundUnitId = row.id;
      _targetController.text = row.translatedText ?? '';
    }
  }

  /// Fire `onSave(previousId, dirtyText)` if the controller holds text that
  /// differs from the previously bound row's persisted translation.
  void _flushDirtyIfNeeded(List<TranslationRow>? rows) {
    final previousId = _boundUnitId;
    if (previousId == null) return;
    if (rows == null) return;
    final prevIdx = rows.indexWhere((r) => r.id == previousId);
    if (prevIdx < 0) return;
    final previousPersisted = rows[prevIdx].translatedText ?? '';
    final currentText = _targetController.text;
    if (currentText != previousPersisted) {
      widget.onSave(previousId, currentText);
    }
  }
```

- [ ] **Step 4: Run test — expect pass**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_inspector_panel_test.dart -p vm`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/translation_editor/widgets/editor_inspector_panel.dart \
        test/features/translation_editor/widgets/editor_inspector_panel_test.dart
git commit -m "fix: auto-save dirty inspector edit before rebind on selection switch"
```

---

## Task 7: Regenerate goldens and run full regression

The toolbar split + 3 removed columns invalidate every existing editor golden. Regenerate after all code changes land.

**Files:**
- Regenerate: `test/features/translation_editor/**/*.png` (any existing PNG fixtures under the editor feature).

- [ ] **Step 1: List affected goldens**

Use Glob tool: pattern `test/features/translation_editor/**/*.png`. Record the list.

(If your workspace has already dropped PNG goldens per commit `2995835`, only toleranceless text/size goldens remain — still regenerate them via `--update-goldens`.)

- [ ] **Step 2: Regenerate goldens**

Run:
```bash
C:/src/flutter/bin/flutter test test/features/translation_editor/ --update-goldens -p vm
```

Expected: all tests pass; PNG fixtures rewritten.

- [ ] **Step 3: Run goldens back to verify determinism**

Run:
```bash
C:/src/flutter/bin/flutter test test/features/translation_editor/ -p vm
```

Expected: 0 failures.

- [ ] **Step 4: Run the full editor + detail test surface as a regression check**

Run:
```bash
C:/src/flutter/bin/flutter test \
  test/features/translation_editor/ \
  test/features/projects/screens/ \
  test/widgets/detail/ \
  -p vm
```

Expected: 0 failures.

- [ ] **Step 5: Run `dart analyze` and confirm no new lints**

Run: `C:/src/flutter/bin/flutter analyze lib test`

Expected: the repo's pre-existing lint count is unchanged. No new warnings surfaced by this plan.

- [ ] **Step 6: Commit the regenerated goldens (if any PNGs changed)**

```bash
git add -A test/features/translation_editor/
git commit -m "test: regenerate editor goldens after toolbar split and column trim"
```

If `git status` shows no changes under `test/features/translation_editor/`, skip this commit.

- [ ] **Step 7: Smoke-check in the Windows app**

Run once locally (not CI-gated):

```bash
C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs
C:/src/flutter/bin/flutter run -d windows
```

Walk through:
1. Open a project → open a language → the editor opens.
2. The new 48 px toolbar shows `← Work › Projects › <project> › <language>`; clicking `←` returns to the project detail screen.
3. The action bar below shows the 4 action buttons without a crumb.
4. The grid shows exactly 4 columns (checkbox / KEY / SOURCE / TARGET).
5. Clicking a row highlights it and populates the inspector (single-select).
6. Clicking a checkbox adds the row to multi-select without clearing the previous single-select.
7. Typing in the inspector's target then clicking another row preserves the edit on the first row (refresh the grid — TARGET cell reflects the typed text).

---

## Self-Review

**Spec coverage:**
- G1 (back button + crumb): Task 1 ✓
- G2 (no inline editing): Task 4 ✓
- G3 (4 columns only): Task 3 ✓
- G4 (single-click selects row): Task 4 + existing `_handleNormalClick` behaviour (already clears before selecting); Task 4 adds the checkbox-column short-circuit so multi-select isn't clobbered ✓
- G5 (auto-save before rebind): Task 6 ✓
- Non-goals honoured (no command palette, no encoding work, no filter panel rework) ✓

**Placeholder scan:** no "TBD"/"TODO"/"handle edge cases" entries. Every code block is a concrete edit. The single conditional instruction is in Task 4 Step 1 ("if `WidgetRef` is required, switch to testWidgets pattern") — both variants are written out in full.

**Type consistency:**
- `EditorDataSource` constructor: Task 3 Step 3 removes `onCellTap`; Task 3 Step 4 matches the new signature (no `onCellTap: (unitId) {}` in the datagrid's `initState`). ✓
- `setSelectedRowColor` defined in Task 3 Step 3 and called in Task 3 Step 4. ✓
- `EditorActionBar` used consistently from Task 2 onward (screen + tests). ✓
- `DetailScreenToolbar(crumb:, onBack:)` matches the primitive's signature in `lib/widgets/detail/detail_screen_toolbar.dart:15-20`. ✓
- `_flushDirtyIfNeeded` takes `List<TranslationRow>?` — same element type used by `_rebindIfNeeded`. ✓

---

## Execution notes

- Keep commits at task granularity. If a task fails review, reset that single commit.
- Task 2 renames a file — handle via `git mv` so the blame survives.
- Task 6's race test enters text without unfocusing; if the DUT starts flaking, prefer the explicit `FocusManager.instance.primaryFocus?.unfocus()` *after* the selection switch and assert the save still fires exactly once (set → compare length + first-entry value).
