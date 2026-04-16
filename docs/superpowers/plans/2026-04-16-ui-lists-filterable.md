# Plan 5a · Liste filtrable — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopter l'archétype « Liste filtrable » §7.1 du parent spec sur 5 écrans (Projects, Mods, Steam Publish, Glossary, Translation Memory) via extraction de primitives partagées, en préservant strictement les features actuelles.

**Architecture:** Nouveau dossier `lib/widgets/lists/` contenant 4 primitives composables (`FilterToolbar`, `FilterPill`+`FilterPillGroup`, `ListRow`+`ListRowHeader`, `TokenDataGridTheme`). Les 5 écrans composent ces primitives, éliminent `FluentScaffold`, et consomment `context.tokens` exclusivement. Golden tests par écran (2 thèmes × 1 état = 10 goldens).

**Tech Stack:** Flutter Desktop · Riverpod · Syncfusion Flutter DataGrid · Google Fonts · GoRouter · `flutter_test` goldens.

**Spec:** [`docs/superpowers/specs/2026-04-16-ui-lists-filterable-design.md`](../specs/2026-04-16-ui-lists-filterable-design.md)

**Predecessors:** Plan 1 (tokens), Plan 2 (navigation), Plan 3 (cards primitives), Plan 4 (editor + `editorGridThemeFromTokens`).

---

## Worktree setup (pre-Task 1)

- [ ] **Create worktree & branch**

```bash
git worktree add .worktrees/ui-lists -b feat/ui-lists-filterable main
cd .worktrees/ui-lists
```

- [ ] **Copy `windows/` and regenerate generated code**

```bash
cp -r ../../windows ./
C:/src/flutter/bin/flutter pub get
C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Baseline verify — tests pass before any change**

```bash
C:/src/flutter/bin/flutter test
```

Expected: suite green (baseline ~1314 tests).

---

## Task 1 · Extract shared primitives

**Files:**
- Create: `lib/widgets/lists/token_data_grid_theme.dart`
- Create: `lib/widgets/lists/filter_pill.dart`
- Create: `lib/widgets/lists/filter_toolbar.dart`
- Create: `lib/widgets/lists/list_row.dart`
- Delete: `lib/features/translation_editor/widgets/editor_data_grid_theme.dart`
- Modify: `lib/features/translation_editor/widgets/editor_datagrid.dart` (update import)
- Test: `test/widgets/lists/filter_pill_test.dart`
- Test: `test/widgets/lists/filter_toolbar_test.dart`
- Test: `test/widgets/lists/list_row_test.dart`
- Test: `test/widgets/lists/token_data_grid_theme_test.dart`

### 1.1 — Relocate `editorGridThemeFromTokens` → `buildTokenDataGridTheme`

- [ ] **Step 1 · Create new file with factored-out helper**

Create `lib/widgets/lists/token_data_grid_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Maps [TwmtThemeTokens] to a Syncfusion [SfDataGridThemeData].
/// Single source of truth for any list screen using SfDataGrid:
/// editor, glossary, translation memory.
SfDataGridThemeData buildTokenDataGridTheme(TwmtThemeTokens tokens) {
  return SfDataGridThemeData(
    headerColor: tokens.panel,
    gridLineColor: tokens.border,
    selectionColor: tokens.accentBg,
    currentCellStyle: DataGridCurrentCellStyle(
      borderColor: tokens.accent,
      borderWidth: 1.0,
    ),
    rowHoverColor: tokens.panel2,
    rowHoverTextStyle: TextStyle(color: tokens.text),
    frozenPaneLineColor: tokens.border,
  );
}
```

- [ ] **Step 2 · Update Editor import**

Edit `lib/features/translation_editor/widgets/editor_datagrid.dart` — replace the import:

```dart
// Before:
import 'package:twmt/features/translation_editor/widgets/editor_data_grid_theme.dart';

// After:
import 'package:twmt/widgets/lists/token_data_grid_theme.dart';
```

Then replace the function call (grep for `editorGridThemeFromTokens` in that file — rename to `buildTokenDataGridTheme`).

- [ ] **Step 3 · Delete old file**

```bash
rm lib/features/translation_editor/widgets/editor_data_grid_theme.dart
```

- [ ] **Step 4 · Write theme test**

Create `test/widgets/lists/token_data_grid_theme_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/widgets/lists/token_data_grid_theme.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

void main() {
  test('buildTokenDataGridTheme maps atelier tokens to SfDataGridThemeData', () {
    final atelier = AppTheme.atelierDarkTheme
        .extension<TwmtThemeTokens>()!;
    final theme = buildTokenDataGridTheme(atelier);

    expect(theme.headerColor, atelier.panel);
    expect(theme.gridLineColor, atelier.border);
    expect(theme.selectionColor, atelier.accentBg);
    expect(theme.rowHoverColor, atelier.panel2);
  });

  test('buildTokenDataGridTheme maps forge tokens', () {
    final forge = AppTheme.forgeDarkTheme.extension<TwmtThemeTokens>()!;
    final theme = buildTokenDataGridTheme(forge);

    expect(theme.headerColor, forge.panel);
    expect(theme.selectionColor, forge.accentBg);
  });
}
```

- [ ] **Step 5 · Run tests (theme + editor regressions)**

```bash
C:/src/flutter/bin/flutter test test/widgets/lists/token_data_grid_theme_test.dart test/features/translation_editor/
```

Expected: all green. If Editor golden tests drift, the grid theme change is identical (same function body) — investigate, don't blindly update goldens.

- [ ] **Step 6 · Commit**

```bash
git add lib/widgets/lists/token_data_grid_theme.dart \
        lib/features/translation_editor/widgets/editor_datagrid.dart \
        test/widgets/lists/token_data_grid_theme_test.dart
git rm lib/features/translation_editor/widgets/editor_data_grid_theme.dart
git commit -m "refactor: relocate SfDataGrid theme helper to shared lists folder"
```

### 1.2 — `FilterPill` + `FilterPillGroup`

- [ ] **Step 1 · Write failing test**

Create `test/widgets/lists/filter_pill_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('FilterPill off state uses panel2 bg + textMid fg', (t) async {
    await t.pumpWidget(wrap(
      FilterPill(label: 'ALL', selected: false, onToggle: () {}),
    ));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final container = t.widget<Container>(
      find.descendant(of: find.byType(FilterPill), matching: find.byType(Container)),
    );
    final deco = container.decoration as BoxDecoration;
    expect(deco.color, tokens.panel2);
  });

  testWidgets('FilterPill on state uses accentBg + accent border', (t) async {
    await t.pumpWidget(wrap(
      FilterPill(label: 'ALL', selected: true, onToggle: () {}),
    ));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final container = t.widget<Container>(
      find.descendant(of: find.byType(FilterPill), matching: find.byType(Container)),
    );
    final deco = container.decoration as BoxDecoration;
    expect(deco.color, tokens.accentBg);
    expect((deco.border as Border).top.color, tokens.accent);
  });

  testWidgets('FilterPill shows count in mono', (t) async {
    await t.pumpWidget(wrap(
      FilterPill(label: 'ALL', selected: false, count: 42, onToggle: () {}),
    ));
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('FilterPill onToggle fires', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(
      FilterPill(label: 'X', selected: false, onToggle: () => tapped = true),
    ));
    await t.tap(find.byType(FilterPill));
    expect(tapped, isTrue);
  });

  testWidgets('FilterPillGroup renders label + children', (t) async {
    await t.pumpWidget(wrap(
      FilterPillGroup(
        label: 'ÉTAT',
        pills: [
          FilterPill(label: 'A', selected: false, onToggle: () {}),
          FilterPill(label: 'B', selected: true, onToggle: () {}),
        ],
      ),
    ));
    expect(find.text('ÉTAT'), findsOneWidget);
    expect(find.byType(FilterPill), findsNWidgets(2));
  });
}
```

- [ ] **Step 2 · Run test — expect failure (file not created)**

```bash
C:/src/flutter/bin/flutter test test/widgets/lists/filter_pill_test.dart
```

Expected: compile error `Target of URI doesn't exist: 'package:twmt/widgets/lists/filter_pill.dart'`.

- [ ] **Step 3 · Implement `FilterPill` + `FilterPillGroup`**

Create `lib/widgets/lists/filter_pill.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// A toggleable filter pill per §6.2 of the UI spec.
/// Off: bg panel2 / fg textMid. On: bg accentBg / border accent / fg accent.
/// Radius follows tokens.radiusPill (20).
class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final int? count;
  final VoidCallback onToggle;

  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onToggle,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bg = selected ? tokens.accentBg : tokens.panel2;
    final borderColor = selected ? tokens.accent : tokens.border;
    final labelColor = selected ? tokens.accent : tokens.textMid;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(tokens.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: tokens.fontBody.copyWith(
                  fontSize: 12,
                  color: labelColor,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: tokens.fontMono.copyWith(
                    fontSize: 11,
                    color: tokens.textFaint,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled group of [FilterPill]s — label caps-mono textDim + row of pills.
class FilterPillGroup extends StatelessWidget {
  final String label;
  final List<FilterPill> pills;

  const FilterPillGroup({super.key, required this.label, required this.pills});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: tokens.fontMono.copyWith(
            fontSize: 10,
            color: tokens.textDim,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        for (final p in pills) ...[
          p,
          if (p != pills.last) const SizedBox(width: 6),
        ],
      ],
    );
  }
}
```

- [ ] **Step 4 · Run test to verify green**

```bash
C:/src/flutter/bin/flutter test test/widgets/lists/filter_pill_test.dart
```

Expected: 5 tests pass.

- [ ] **Step 5 · Commit**

```bash
git add lib/widgets/lists/filter_pill.dart test/widgets/lists/filter_pill_test.dart
git commit -m "feat: add FilterPill and FilterPillGroup primitives"
```

### 1.3 — `FilterToolbar`

- [ ] **Step 1 · Write failing test**

Create `test/widgets/lists/filter_toolbar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('FilterToolbar renders leading + trailing on row 1', (t) async {
    await t.pumpWidget(wrap(
      const FilterToolbar(
        leading: Text('Projects'),
        trailing: [Icon(Icons.search)],
      ),
    ));
    expect(find.text('Projects'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });

  testWidgets('FilterToolbar hides pill row when pillGroups empty', (t) async {
    await t.pumpWidget(wrap(
      const FilterToolbar(
        leading: Text('X'),
        pillGroups: [],
      ),
    ));
    expect(find.byType(FilterPillGroup), findsNothing);
  });

  testWidgets('FilterToolbar shows pillGroups on row 2', (t) async {
    await t.pumpWidget(wrap(
      FilterToolbar(
        leading: const Text('X'),
        pillGroups: [
          FilterPillGroup(
            label: 'STATE',
            pills: [FilterPill(label: 'A', selected: false, onToggle: () {})],
          ),
        ],
      ),
    ));
    expect(find.text('STATE'), findsOneWidget);
    expect(find.byType(FilterPill), findsOneWidget);
  });
}
```

- [ ] **Step 2 · Run test — expect missing file failure**

```bash
C:/src/flutter/bin/flutter test test/widgets/lists/filter_toolbar_test.dart
```

Expected: import error.

- [ ] **Step 3 · Implement `FilterToolbar`**

Create `lib/widgets/lists/filter_toolbar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';

/// Double-row toolbar for §7.1 filterable lists.
/// Row 1: leading (crumb/title/count) + trailing (search, sort, actions).
/// Row 2: horizontally scrollable list of [FilterPillGroup]s (hidden if empty).
class FilterToolbar extends StatelessWidget {
  final Widget leading;
  final List<Widget> trailing;
  final List<FilterPillGroup> pillGroups;

  const FilterToolbar({
    super.key,
    required this.leading,
    this.trailing = const [],
    this.pillGroups = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: tokens.panel,
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          child: Row(
            children: [
              Expanded(child: leading),
              for (final w in trailing) ...[const SizedBox(width: 12), w],
            ],
          ),
        ),
        if (pillGroups.isNotEmpty)
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: tokens.panel,
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < pillGroups.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    pillGroups[i],
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4 · Run test — expect green**

```bash
C:/src/flutter/bin/flutter test test/widgets/lists/filter_toolbar_test.dart
```

Expected: 3 tests pass.

- [ ] **Step 5 · Commit**

```bash
git add lib/widgets/lists/filter_toolbar.dart test/widgets/lists/filter_toolbar_test.dart
git commit -m "feat: add FilterToolbar primitive"
```

### 1.4 — `ListRow` + `ListRowHeader`

- [ ] **Step 1 · Write failing test**

Create `test/widgets/lists/list_row_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/list_row.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('ListRow lays out children across columns', (t) async {
    await t.pumpWidget(wrap(
      ListRow(
        columns: const [
          ListRowColumn.fixed(80),
          ListRowColumn.flex(1),
          ListRowColumn.fixed(120),
        ],
        children: const [Text('A'), Text('B'), Text('C')],
      ),
    ));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('ListRow selected border-left uses accent', (t) async {
    await t.pumpWidget(wrap(
      const ListRow(
        selected: true,
        columns: [ListRowColumn.flex(1)],
        children: [Text('row')],
      ),
    ));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final container = t.widget<Container>(
      find.ancestor(of: find.text('row'), matching: find.byType(Container)).first,
    );
    final deco = container.decoration as BoxDecoration;
    expect((deco.border as Border).left.color, tokens.accent);
    expect((deco.border as Border).left.width, 2);
  });

  testWidgets('ListRow onTap fires', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(
      ListRow(
        columns: const [ListRowColumn.flex(1)],
        onTap: () => tapped = true,
        children: const [Text('row')],
      ),
    ));
    await t.tap(find.text('row'));
    expect(tapped, isTrue);
  });

  testWidgets('ListRow trailingAction renders', (t) async {
    await t.pumpWidget(wrap(
      ListRow(
        columns: const [ListRowColumn.flex(1)],
        trailingAction: const Icon(Icons.more_vert),
        children: const [Text('row')],
      ),
    ));
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('ListRowHeader renders labels in caps mono', (t) async {
    await t.pumpWidget(wrap(
      const ListRowHeader(
        columns: [ListRowColumn.fixed(80), ListRowColumn.flex(1)],
        labels: ['NAME', 'DESCRIPTION'],
      ),
    ));
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('DESCRIPTION'), findsOneWidget);
  });
}
```

- [ ] **Step 2 · Run test — expect missing file failure**

```bash
C:/src/flutter/bin/flutter test test/widgets/lists/list_row_test.dart
```

- [ ] **Step 3 · Implement `ListRow` + `ListRowHeader`**

Create `lib/widgets/lists/list_row.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Column sizing for [ListRow] and [ListRowHeader].
/// `fixed(px)` reserves exact pixels. `flex(n)` distributes remaining space
/// proportionally. At most 2 flex columns recommended per §7.1.
sealed class ListRowColumn {
  const ListRowColumn();
  const factory ListRowColumn.fixed(double width) = _Fixed;
  const factory ListRowColumn.flex(int weight) = _Flex;
}

final class _Fixed extends ListRowColumn {
  final double width;
  const _Fixed(this.width);
}

final class _Flex extends ListRowColumn {
  final int weight;
  const _Flex(this.weight);
}

/// Grid-column row for §7.1 card lists. Fixed column widths prevent vertical
/// misalignment between rows. Border-left accent 2px when [selected].
class ListRow extends StatelessWidget {
  final List<ListRowColumn> columns;
  final List<Widget> children;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailingAction;
  final double height;

  const ListRow({
    super.key,
    required this.columns,
    required this.children,
    this.selected = false,
    this.onTap,
    this.trailingAction,
    this.height = 56,
  })  : assert(columns.length == children.length,
            'columns.length must equal children.length');

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bg = selected ? tokens.rowSelected : tokens.panel2;

    final content = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          left: BorderSide(
            color: selected ? tokens.accent : Colors.transparent,
            width: 2,
          ),
          bottom: BorderSide(color: tokens.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            _cell(columns[i], children[i]),
          if (trailingAction != null) ...[
            const SizedBox(width: 8),
            trailingAction!,
          ],
        ],
      ),
    );

    if (onTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: content),
      );
    }
    return content;
  }

  Widget _cell(ListRowColumn col, Widget child) {
    return switch (col) {
      _Fixed(:final width) => SizedBox(width: width, child: child),
      _Flex(:final weight) => Expanded(flex: weight, child: child),
    };
  }
}

/// Header row mirror of [ListRow]. Labels rendered in mono 10-11px caps.
class ListRowHeader extends StatelessWidget {
  final List<ListRowColumn> columns;
  final List<String> labels;
  final double height;

  const ListRowHeader({
    super.key,
    required this.columns,
    required this.labels,
    this.height = 32,
  }) : assert(columns.length == labels.length);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = tokens.fontMono.copyWith(
      fontSize: 11,
      color: tokens.textDim,
      letterSpacing: 0.8,
    );
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            _cell(columns[i], Text(labels[i].toUpperCase(), style: style)),
        ],
      ),
    );
  }

  Widget _cell(ListRowColumn col, Widget child) {
    return switch (col) {
      _Fixed(:final width) => SizedBox(width: width, child: child),
      _Flex(:final weight) => Expanded(flex: weight, child: child),
    };
  }
}
```

- [ ] **Step 4 · Run test — expect green**

```bash
C:/src/flutter/bin/flutter test test/widgets/lists/list_row_test.dart
```

Expected: 5 tests pass.

- [ ] **Step 5 · Run the full suite to check nothing regressed**

```bash
C:/src/flutter/bin/flutter test
```

Expected: +15 new tests passing, all pre-existing tests still green. Editor goldens must match (only import path changed).

- [ ] **Step 6 · Commit**

```bash
git add lib/widgets/lists/list_row.dart test/widgets/lists/list_row_test.dart
git commit -m "feat: add ListRow and ListRowHeader primitives"
```

---

## Task 2 · Refactor Projects list

**Files:**
- Modify: `lib/features/projects/screens/projects_screen.dart`
- Modify: `lib/features/projects/widgets/projects_toolbar.dart` (may replace internals or delete in favour of `FilterToolbar`)
- Test: `test/features/projects/screens/projects_screen_test.dart`
- Test: `test/features/projects/screens/projects_screen_golden_test.dart`

### 2.1 — Planning read

- [ ] **Step 1 · Open current screen + toolbar**

```bash
C:/src/flutter/bin/flutter test --list test/features/projects/
```

Read `projects_screen.dart` and `projects_toolbar.dart` in full. Note:
- Existing filters (search, state, languages, etc.)
- Existing actions (New Project, batch operations if any)
- Existing `_buildHeader` contents (these become `FilterToolbar.leading`)

Map current controls → `FilterToolbar` slots:
- `leading` = crumb + title `Projects` + count `N projects`
- `trailing` = `[SearchField, SortButton, NewProjectButton]`
- `pillGroups` = existing filter dropdowns converted to pill groups IF already present; OTHERWISE leave empty (refresh-strict per spec §4 decision 4).

### 2.2 — Rewrite screen

- [ ] **Step 1 · Replace `FluentScaffold` + `_buildHeader` with `FilterToolbar`**

Edit `lib/features/projects/screens/projects_screen.dart`. Remove `FluentScaffold` wrap. New skeleton:

```dart
@override
Widget build(BuildContext context) {
  final tokens = context.tokens;
  final projectsAsync = ref.watch(paginatedProjectsProvider);
  final languagesAsync = ref.watch(allLanguagesProvider);
  final selectionState = ref.watch(batchProjectSelectionProvider);

  return Container(
    color: tokens.bg,
    child: Column(
      children: [
        FilterToolbar(
          leading: _buildLeading(projectsAsync),
          trailing: _buildTrailingActions(),
          pillGroups: const [],
        ),
        Expanded(
          child: projectsAsync.when(
            data: (projects) => _buildList(projects, selectionState),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _buildError(e),
          ),
        ),
      ],
    ),
  );
}

Widget _buildLeading(AsyncValue<ProjectsPage> async) {
  final tokens = context.tokens;
  final count = async.asData?.value.total ?? 0;
  return Row(
    children: [
      Text('Projects', style: tokens.fontDisplay.copyWith(fontSize: 20)),
      const SizedBox(width: 12),
      Text('$count', style: tokens.fontMono.copyWith(color: tokens.textDim)),
    ],
  );
}
```

- [ ] **Step 2 · Replace project card rows with `ListRow`**

Inside `_buildList`, convert the existing `ProjectCard`/grid to a `ListView.builder` emitting `ListRow`. Preserve existing row click → navigate to `/work/projects/:id` (unchanged). Pass each project's status/pct as the trailing action or a dedicated column.

Exact columns (verify against mockup `archetypes-extra.html`):

```dart
const columns = [
  ListRowColumn.fixed(56),   // cover thumbnail
  ListRowColumn.flex(3),      // name + meta
  ListRowColumn.fixed(140),   // target lang
  ListRowColumn.fixed(200),   // progress bar
  ListRowColumn.fixed(180),   // last modified (mono)
  ListRowColumn.fixed(150),   // status pill / action
];
```

- [ ] **Step 3 · Remove all `Theme.of(context).colorScheme.*` from this file**

Grep `grep -n "Theme.of(context)" lib/features/projects/screens/projects_screen.dart` — replace each with `tokens.X` (panel for surfaces, textMid for secondary, text for primary, etc.). No hard-coded `Color(0xFF...)` remaining.

- [ ] **Step 4 · Write / update screen widget tests**

Create or update `test/features/projects/screens/projects_screen_test.dart`:

```dart
testWidgets('ProjectsScreen shows FilterToolbar and ListRows', (t) async {
  await t.pumpWidget(createThemedTestableWidget(
    const ProjectsScreen(),
    theme: AppTheme.atelierDarkTheme,
    overrides: populatedProjectsOverrides,
  ));
  await t.pumpAndSettle();
  expect(find.byType(FilterToolbar), findsOneWidget);
  expect(find.byType(ListRow), findsWidgets);
});

testWidgets('ProjectsScreen empty state when no projects', (t) async {
  await t.pumpWidget(createThemedTestableWidget(
    const ProjectsScreen(),
    theme: AppTheme.atelierDarkTheme,
    overrides: emptyProjectsOverrides,
  ));
  await t.pumpAndSettle();
  expect(find.byType(ListRow), findsNothing);
  expect(find.textContaining('No projects'), findsOneWidget);
});

testWidgets('Tapping a row triggers navigation callback', (t) async {
  // set up go_router fake + assert push
});
```

Use existing `populatedProjectsOverrides` / `emptyProjectsOverrides` if present in `test/helpers/` — otherwise define minimal overrides for `paginatedProjectsProvider`, `allLanguagesProvider`, `batchProjectSelectionProvider` returning fake data.

- [ ] **Step 5 · Write golden test**

Create `test/features/projects/screens/projects_screen_golden_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/screens/projects_screen.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pumpUnder(
    WidgetTester tester,
    ThemeData theme,
    List<Override> overrides,
  ) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const ProjectsScreen(),
      theme: theme,
      overrides: overrides,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('projects atelier populated', (t) async {
    await pumpUnder(t, AppTheme.atelierDarkTheme, populatedOverrides);
    await expectLater(
      find.byType(ProjectsScreen),
      matchesGoldenFile('../goldens/projects_atelier_populated.png'),
    );
  });

  testWidgets('projects forge populated', (t) async {
    await pumpUnder(t, AppTheme.forgeDarkTheme, populatedOverrides);
    await expectLater(
      find.byType(ProjectsScreen),
      matchesGoldenFile('../goldens/projects_forge_populated.png'),
    );
  });
}
```

- [ ] **Step 6 · Generate goldens once & inspect**

```bash
C:/src/flutter/bin/flutter test --update-goldens test/features/projects/screens/projects_screen_golden_test.dart
```

Open the PNG files produced at `test/features/projects/goldens/` in an image viewer. Verify visually:
- Crumb + title + count on left
- Search / sort / New Project on right
- Rows aligned across columns
- Atelier warm palette, Forge cyan accents

- [ ] **Step 7 · Re-run tests without `--update-goldens` to lock baseline**

```bash
C:/src/flutter/bin/flutter test test/features/projects/
```

Expected: all green.

- [ ] **Step 8 · Commit**

```bash
git add lib/features/projects/ test/features/projects/
git commit -m "feat: migrate Projects list to FilterToolbar + ListRow archetype"
```

---

## Task 3 · Refactor Mods list

**Files:**
- Modify: `lib/features/mods/screens/mods_screen.dart`
- Modify: `lib/features/mods/widgets/mods_toolbar.dart` (internal rewrite; `_FilterChip` removed in favour of `FilterPill`)
- Delete: `lib/features/mods/widgets/detected_mods_data_grid.dart` (SfDataGrid replaced)
- Create: `lib/features/mods/widgets/mods_list.dart` (new `ListView.builder` wrapper)
- Test: `test/features/mods/screens/mods_screen_test.dart`
- Test: `test/features/mods/screens/mods_screen_golden_test.dart`

### 3.1 — SfDataGrid → `ListView.builder(ListRow)`

- [ ] **Step 1 · Read current `DetectedModsDataGrid` to extract column logic**

Note all columns it renders + their cell builders. Map each to a `ListRowColumn`.

Approximate mapping (verify):

```dart
const modsColumns = [
  ListRowColumn.fixed(56),   // thumbnail
  ListRowColumn.flex(3),      // title + workshop id mono
  ListRowColumn.fixed(140),   // last update (mono relative)
  ListRowColumn.fixed(160),   // project state badge
  ListRowColumn.fixed(140),   // action button
];
```

- [ ] **Step 2 · Create `ModsList` widget**

Create `lib/features/mods/widgets/mods_list.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/mods/providers/mods_providers.dart';
import 'package:twmt/models/detected_mod.dart';
import 'package:twmt/widgets/lists/list_row.dart';

class ModsList extends ConsumerWidget {
  final List<DetectedMod> mods;
  final void Function(DetectedMod mod) onModTap;

  const ModsList({super.key, required this.mods, required this.onModTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const ListRowHeader(
          columns: modsColumns,
          labels: ['', 'TITLE', 'UPDATED', 'STATE', 'ACTION'],
        ),
        Expanded(
          child: ListView.builder(
            itemCount: mods.length,
            itemBuilder: (ctx, i) {
              final mod = mods[i];
              return ListRow(
                columns: modsColumns,
                onTap: () => onModTap(mod),
                children: [
                  _Thumbnail(mod: mod),
                  _TitleBlock(mod: mod),
                  _UpdatedCell(mod: mod),
                  _StateCell(mod: mod),
                  _ActionCell(mod: mod),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

const modsColumns = [
  ListRowColumn.fixed(56),
  ListRowColumn.flex(3),
  ListRowColumn.fixed(140),
  ListRowColumn.fixed(160),
  ListRowColumn.fixed(140),
];

// _Thumbnail, _TitleBlock, _UpdatedCell, _StateCell, _ActionCell:
// copy logic from DetectedModsDataGrid cell builders.
// Each uses context.tokens for all colors.
```

- [ ] **Step 3 · Rewrite `ModsToolbar` to use `FilterToolbar` + `FilterPill`**

Edit `lib/features/mods/widgets/mods_toolbar.dart`. Replace `_FilterChip` usages with `FilterPill`. Wrap entire toolbar return with `FilterToolbar`. Delete `_FilterChip` class.

Column groups (refresh-strict — match current filters):

```dart
FilterToolbar(
  leading: _buildLeading(...),
  trailing: [SearchField, SortButton, RescanButton],
  pillGroups: [
    FilterPillGroup(
      label: 'STATE',
      pills: [
        FilterPill(label: 'All', selected: !anyFilter, onToggle: _clearFilters),
        FilterPill(label: 'New', ...),
        FilterPill(label: 'Imported', ...),
        FilterPill(label: 'Outdated', ...),
      ],
    ),
  ],
)
```

- [ ] **Step 4 · Rewrite `mods_screen.dart` `build()` to use the new composition**

Mirror the Projects pattern. Remove `FluentScaffold` + `_buildHeader`. Replace `DetectedModsDataGrid` with `ModsList`.

- [ ] **Step 5 · Delete `DetectedModsDataGrid`**

```bash
rm lib/features/mods/widgets/detected_mods_data_grid.dart
```

And remove the `syncfusion_flutter_datagrid` import from `mods_screen.dart` if no other file in mods feature uses it.

- [ ] **Step 6 · Write/update screen tests**

Create `test/features/mods/screens/mods_screen_test.dart`:

```dart
testWidgets('ModsScreen renders FilterToolbar + ModsList', (t) async {
  await t.pumpWidget(createThemedTestableWidget(
    const ModsScreen(),
    theme: AppTheme.atelierDarkTheme,
    overrides: populatedModsOverrides,
  ));
  await t.pumpAndSettle();
  expect(find.byType(FilterToolbar), findsOneWidget);
  expect(find.byType(ListRow), findsWidgets);
});

testWidgets('ModsScreen pill toggle filters list', (t) async {
  await t.pumpWidget(createThemedTestableWidget(
    const ModsScreen(),
    theme: AppTheme.atelierDarkTheme,
    overrides: populatedModsOverrides,
  ));
  await t.pumpAndSettle();
  final initial = t.widgetList(find.byType(ListRow)).length;
  await t.tap(find.text('Outdated'));
  await t.pumpAndSettle();
  expect(t.widgetList(find.byType(ListRow)).length, lessThan(initial));
});
```

- [ ] **Step 7 · Write golden test (mirror Projects pattern)**

Create `test/features/mods/screens/mods_screen_golden_test.dart` with `atelier_populated` + `forge_populated` goldens.

- [ ] **Step 8 · Generate goldens, inspect, re-run**

```bash
C:/src/flutter/bin/flutter test --update-goldens test/features/mods/screens/mods_screen_golden_test.dart
C:/src/flutter/bin/flutter test test/features/mods/
```

- [ ] **Step 9 · Commit**

```bash
git add lib/features/mods/ test/features/mods/
git rm lib/features/mods/widgets/detected_mods_data_grid.dart
git commit -m "feat: migrate Mods list to FilterToolbar + ListRow (drop SfDataGrid)"
```

---

## Task 4 · Refactor Steam Publish list

**Files:**
- Modify: `lib/features/steam_publish/screens/steam_publish_screen.dart`
- Create or modify: `lib/features/steam_publish/widgets/steam_publish_list.dart`
- Modify: existing toolbar widget in `lib/features/steam_publish/widgets/` (fold into `FilterToolbar`)
- Test: `test/features/steam_publish/screens/steam_publish_screen_test.dart`
- Test: `test/features/steam_publish/screens/steam_publish_screen_golden_test.dart`

### 4.1 — Same pattern as Mods, with selection preserved

- [ ] **Step 1 · Extract existing batch-selection logic into a Riverpod provider**

Read `steam_publish_screen.dart` (583 LOC). Find wherever `Set<ID> _selected` lives. Extract to `steamPublishSelectionProvider = StateProvider<Set<String>>((_) => {})` (or similar) in `lib/features/steam_publish/providers/steam_publish_providers.dart`. Keep `ListRow` dumb — it receives `selected: selection.contains(id)` and `onTap: () => selection.toggle(id)`.

- [ ] **Step 2 · Write provider unit test**

```dart
test('steamPublishSelectionProvider toggles ids', () {
  final container = ProviderContainer();
  container.read(steamPublishSelectionProvider.notifier).state = {'a'};
  expect(container.read(steamPublishSelectionProvider), {'a'});
});
```

Run: `C:/src/flutter/bin/flutter test test/features/steam_publish/providers/`. Expected: pass.

- [ ] **Step 3 · Create `SteamPublishList` widget — same ListRow pattern as Mods**

Column layout (verify with current screen):

```dart
const steamColumns = [
  ListRowColumn.fixed(40),    // checkbox
  ListRowColumn.fixed(56),    // cover
  ListRowColumn.flex(3),      // title + pack filename mono
  ListRowColumn.fixed(160),   // publish state
  ListRowColumn.fixed(140),   // last published mono
  ListRowColumn.fixed(180),   // action
];
```

The first column renders a Checkbox; `ListRow.selected` binds to `selection.contains(id)`; `onTap` toggles.

- [ ] **Step 4 · Replace `_buildHeader`/toolbar with `FilterToolbar`**

`leading` = crumb + title + count ("N packs · M selected"). `trailing` = [SelectAllButton, SelectOutdatedButton, SearchField, LoginButton]. `pillGroups` = [] (no existing categorical filters — deferred per spec §7 "État de publication").

- [ ] **Step 5 · Rewrite screen `build()` to compose**

```dart
Column(children: [
  FilterToolbar(...),
  Expanded(child: SteamPublishList(...)),
])
```

Remove `FluentScaffold`. Replace all `Theme.of(context).colorScheme.*` with `context.tokens`.

- [ ] **Step 6 · Screen widget tests**

```dart
testWidgets('SteamPublishScreen select-all toggles selection', (t) async {
  await t.pumpWidget(createThemedTestableWidget(
    const SteamPublishScreen(),
    theme: AppTheme.atelierDarkTheme,
    overrides: steamPublishOverrides,
  ));
  await t.pumpAndSettle();
  await t.tap(find.text('Select all'));
  await t.pumpAndSettle();
  final selectedRows = t.widgetList<ListRow>(find.byType(ListRow))
      .where((r) => r.selected);
  expect(selectedRows.length, greaterThan(0));
});
```

- [ ] **Step 7 · Golden test (atelier + forge)**

Same pattern as Tasks 2–3.

- [ ] **Step 8 · Generate goldens + commit**

```bash
C:/src/flutter/bin/flutter test --update-goldens test/features/steam_publish/
C:/src/flutter/bin/flutter test test/features/steam_publish/
git add lib/features/steam_publish/ test/features/steam_publish/
git commit -m "feat: migrate Steam Publish list to filter toolbar archetype"
```

---

## Task 5 · Refactor Glossary (dense-list)

**Files:**
- Modify: `lib/features/glossary/screens/glossary_screen.dart`
- Modify: `lib/features/glossary/widgets/glossary_list.dart` (wrap with `SfDataGridTheme`)
- Modify: `lib/features/glossary/widgets/glossary_list_header.dart` (fold into `FilterToolbar` at screen level)
- Test: `test/features/glossary/screens/glossary_screen_test.dart`
- Test: `test/features/glossary/screens/glossary_screen_golden_test.dart`

### 5.1 — Retokenise the existing SfDataGrid, rewrap chrome

- [ ] **Step 1 · Read `glossary_list.dart` and locate `SfDataGrid(...)` call site**

Wrap it with `SfDataGridTheme(data: buildTokenDataGridTheme(context.tokens), child: SfDataGrid(...))`.

Example:

```dart
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/token_data_grid_theme.dart';

Widget build(BuildContext context) {
  final tokens = context.tokens;
  return SfDataGridTheme(
    data: buildTokenDataGridTheme(tokens),
    child: SfDataGrid(
      // ...existing config unchanged
    ),
  );
}
```

- [ ] **Step 2 · Replace `GlossaryListHeader` usage with `FilterToolbar`**

In `glossary_screen.dart` `_buildGlossaryListView`:

```dart
return Column(
  children: [
    FilterToolbar(
      leading: _buildLeading(glossariesAsync),
      trailing: [NewGlossaryButton, ImportButton, ExportButton, SearchField],
      pillGroups: const [],
    ),
    Expanded(
      child: glossariesAsync.when(
        data: (glossaries) => glossaries.isEmpty
            ? GlossaryEmptyState(...)
            : GlossaryList(...),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _buildError(e),
      ),
    ),
  ],
);
```

- [ ] **Step 3 · Keep the inline entry editor panel behavior unchanged**

Decision from spec §9 open Q4: inline editor panel stays on the right side. No change to `_buildGlossaryEditorView`. Only replace `FluentScaffold` wrap in the editor view with `Container(color: tokens.bg, child: ...)`.

- [ ] **Step 4 · Remove hard-coded colors**

Grep `Theme.of(context).colorScheme` and `Color(0x` in `lib/features/glossary/screens/glossary_screen.dart` + `lib/features/glossary/widgets/`. Replace all with `context.tokens.X`.

- [ ] **Step 5 · Widget tests**

```dart
testWidgets('GlossaryScreen list view uses FilterToolbar', (t) async {
  await t.pumpWidget(createThemedTestableWidget(
    const GlossaryScreen(),
    theme: AppTheme.atelierDarkTheme,
    overrides: populatedGlossaryOverrides,
  ));
  await t.pumpAndSettle();
  expect(find.byType(FilterToolbar), findsOneWidget);
  expect(find.byType(SfDataGrid), findsOneWidget);
});

testWidgets('GlossaryScreen editor view opens on glossary tap', (t) async {
  // verify switching behavior unchanged
});
```

- [ ] **Step 6 · Golden test**

Create `test/features/glossary/screens/glossary_screen_golden_test.dart` — 2 goldens (atelier + forge) on **list view populated**. No golden for editor view in 5a (covered in 5b when entry detail is redone).

- [ ] **Step 7 · Generate + inspect + commit**

```bash
C:/src/flutter/bin/flutter test --update-goldens test/features/glossary/
C:/src/flutter/bin/flutter test test/features/glossary/
git add lib/features/glossary/ test/features/glossary/
git commit -m "feat: migrate Glossary list to filter toolbar + tokenised SfDataGrid"
```

---

## Task 6 · Refactor Translation Memory (dense-list)

**Files:**
- Modify: `lib/features/translation_memory/screens/translation_memory_screen.dart`
- Modify: `lib/features/translation_memory/widgets/tm_browser_data_grid.dart`
- Test: `test/features/translation_memory/screens/translation_memory_screen_test.dart`
- Test: `test/features/translation_memory/screens/translation_memory_screen_golden_test.dart`

### 6.1 — Same pattern as Glossary

- [ ] **Step 1 · Wrap `TmBrowserDataGrid`'s SfDataGrid with `SfDataGridTheme`**

Edit `tm_browser_data_grid.dart`. Apply the same `SfDataGridTheme(data: buildTokenDataGridTheme(context.tokens), child: ...)` pattern.

- [ ] **Step 2 · Rewrite screen `build()` to use `FilterToolbar`**

Decision from spec §9 open Q5: keep `TmStatisticsPanel` visible **in this plan** (preserve-features). Its rewrite to statusbar pattern is a follow-up. New layout:

```dart
return Container(
  color: context.tokens.bg,
  child: Column(
    children: [
      FilterToolbar(
        leading: _buildLeading(),
        trailing: [SearchField, ImportTmxButton, ExportTmxButton],
        pillGroups: const [],
      ),
      Expanded(
        child: Row(
          children: [
            SizedBox(
              width: 280,
              child: TmStatisticsPanel(),
            ),
            VerticalDivider(width: 1, color: context.tokens.border),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: TmBrowserDataGrid()),
                  TmPaginationBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  ),
);
```

- [ ] **Step 3 · Retokenise `TmStatisticsPanel` + `TmPaginationBar`**

Grep hard-coded colors in `lib/features/translation_memory/widgets/tm_statistics_panel.dart` and `tm_pagination_bar.dart`. Replace with `context.tokens`.

- [ ] **Step 4 · Widget tests**

```dart
testWidgets('TranslationMemoryScreen renders FilterToolbar + SfDataGrid + stats panel', (t) async {
  await t.pumpWidget(createThemedTestableWidget(
    const TranslationMemoryScreen(),
    theme: AppTheme.atelierDarkTheme,
    overrides: populatedTmOverrides,
  ));
  await t.pumpAndSettle();
  expect(find.byType(FilterToolbar), findsOneWidget);
  expect(find.byType(SfDataGrid), findsOneWidget);
  expect(find.byType(TmStatisticsPanel), findsOneWidget);
});
```

- [ ] **Step 5 · Golden test (atelier + forge, populated)**

- [ ] **Step 6 · Generate + commit**

```bash
C:/src/flutter/bin/flutter test --update-goldens test/features/translation_memory/
C:/src/flutter/bin/flutter test test/features/translation_memory/
git add lib/features/translation_memory/ test/features/translation_memory/
git commit -m "feat: migrate Translation Memory to filter toolbar + tokenised SfDataGrid"
```

---

## Task 7 · Final verification + goldens consolidation

- [ ] **Step 1 · Run full test suite**

```bash
C:/src/flutter/bin/flutter test
```

Expected: ~1360 tests, all green. If any golden drifts (expected from shared primitive tweaks), identify which, understand why, and either revert the primitive change or regenerate specifically that golden with a one-line justification in the commit message.

- [ ] **Step 2 · Run analyzer**

```bash
C:/src/flutter/bin/flutter analyze
```

Expected: zero new warnings. Pre-existing infos acceptable.

- [ ] **Step 3 · Manual smoke — launch app**

```bash
C:/src/flutter/bin/flutter run -d windows
```

Navigate through all 5 screens (`/work/projects`, `/sources/mods`, `/publishing/steam`, `/resources/glossary`, `/resources/tm`). Verify:
- Atelier theme warm, Forge theme cool
- Filter pills toggle
- Row click navigates (Projects → detail, Mods → creation flow, Glossary → editor panel)
- SfDataGrid colors match app palette (no default blue)
- No `Colors.*` leaking

- [ ] **Step 4 · Sanity-grep for regressions**

```bash
C:/src/flutter/bin/flutter analyze
```

Manually grep for leftover `FluentScaffold` in the 5 refactored screens:

```bash
grep -rn "FluentScaffold" lib/features/projects lib/features/mods lib/features/steam_publish lib/features/glossary lib/features/translation_memory
```

Expected: zero results.

- [ ] **Step 5 · Final commit if any tweaks needed**

```bash
git add -A
git commit -m "chore: final Plan 5a cleanups"
```

- [ ] **Step 6 · Invoke finishing-a-development-branch**

Hand off to `superpowers:finishing-a-development-branch` skill. Present merge options (direct merge to main, or PR) per project convention. Do NOT auto-merge — wait for user decision.

---

## Self-review checklist (completed before handoff)

**Spec coverage:**
- §3 scope (5 écrans, 2 sous-archetypes) → Tasks 2-6 (one per screen)
- §4 primitives → Task 1 (four primitives + relocation)
- §5 tests (15 primitive + 20 screen + 10 goldens) → embedded in every task
- §6 migration (worktree + commit discipline) → pre-Task 1 + per-task commits
- §7 follow-ups deferred → respected (no invented filters, no column resize, no view switcher, no breadcrumb global removal)
- §8 risks → golden drift handled in Task 7 step 1; Steam Publish batch isolation handled in Task 4 step 1; Editor import breakage handled in Task 1.1
- §9 open questions resolved:
  - Q1 `ListRowColumn` → sealed class `fixed(double)` / `flex(int)` (Task 1.4 step 3)
  - Q2 row height → 56px default with per-screen override option (passed in Projects via inherited default; Mods/Steam keep 56)
  - Q3 column order → figé par task inline (Tasks 2-4 step 1)
  - Q4 Glossary inline editor → preserved (Task 5.1 step 3)
  - Q5 TM statistics panel → preserved (Task 6.1 step 2)

**Placeholder scan:** no TBD/TODO. Every step has exact code or exact command. Exception: Tasks 2-6 "read current file to extract X" steps are research-then-implement — they're followed by concrete implementation steps with full code blocks.

**Type consistency:**
- `ListRowColumn` sealed class with `fixed(double)` / `flex(int)` — used verbatim in Tasks 2, 3, 4 column declarations
- `FilterToolbar({required leading, trailing, pillGroups})` — matches across Tasks 2-6 usage
- `buildTokenDataGridTheme(TwmtThemeTokens tokens)` — signature unchanged from Task 1 to Tasks 5, 6
- `context.tokens.X` accessor used consistently (never `Theme.of(context).extension<TwmtThemeTokens>()!.X` except inside the accessor itself)
