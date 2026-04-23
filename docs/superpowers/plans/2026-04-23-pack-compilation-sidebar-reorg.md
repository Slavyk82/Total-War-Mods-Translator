# Pack Compilation — Sidebar Reorganization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Conflicting Projects panel into a new right sidebar and move the Steam Workshop BBCode section into the left sticky form panel of the Pack Compilation editor.

**Architecture:** Additive changes to the shared wizard layout widgets — `WizardScreenLayout` gains an optional `rightPanel`, `StickyFormPanel` gains an optional `extras` slot, and a new `RightStickyPanel` widget mirrors the left panel's visual treatment. The Pack Compilation editor then wires the two existing advisory widgets (`ConflictingProjectsPanel`, `CompilationBBCodeSection`) into those slots instead of stacking them in the dynamic zone.

**Tech Stack:** Flutter (Material), Riverpod, existing `twmt_theme_tokens`. No new dependencies.

**Parallelization note:** Tasks 1, 2, and 3 are fully independent (different files, additive APIs) and can be dispatched to parallel subagents. Task 4 must run after all three complete.

**Spec:** `docs/superpowers/specs/2026-04-23-pack-compilation-sidebar-reorg-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/widgets/wizard/wizard_screen_layout.dart` | Modify | Add optional third column (right panel) |
| `lib/widgets/wizard/sticky_form_panel.dart` | Modify | Add optional `extras` slot below actions |
| `lib/widgets/wizard/right_sticky_panel.dart` | Create | Mirror of `StickyFormPanel` for right-side advisory content |
| `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart` | Modify | Wire BBCode into form `extras`, Conflicts into `rightPanel`, simplify `_EditingView` |
| `test/widgets/wizard/wizard_screen_layout_test.dart` | Modify | Cover `rightPanel` param |
| `test/widgets/wizard/sticky_form_panel_test.dart` | Modify | Cover `extras` slot |
| `test/widgets/wizard/right_sticky_panel_test.dart` | Create | Smoke tests for new widget |

---

## Task 1: Extend `WizardScreenLayout` with `rightPanel`

**Files:**
- Modify: `lib/widgets/wizard/wizard_screen_layout.dart`
- Modify: `test/widgets/wizard/wizard_screen_layout_test.dart`

- [ ] **Step 1: Add failing test for `rightPanel` param**

Append to `test/widgets/wizard/wizard_screen_layout_test.dart` (before the closing `}` of `main`):

```dart
  testWidgets('renders optional right panel to the right of dynamic zone',
      (t) async {
    await t.pumpWidget(wrap(const WizardScreenLayout(
      toolbar: Text('t'),
      formPanel: StickyFormPanel(
        sections: [FormSection(label: 'S', children: [Text('left')])],
      ),
      dynamicZone: DynamicZonePanel(child: Text('center')),
      rightPanel: SizedBox(width: 380, child: Text('rightSide')),
    )));
    final centerRect = t.getRect(find.text('center'));
    final rightRect = t.getRect(find.text('rightSide'));
    expect(centerRect.left, lessThan(rightRect.left));
  });

  testWidgets('omits right panel when null', (t) async {
    await t.pumpWidget(wrap(const WizardScreenLayout(
      toolbar: Text('t'),
      formPanel: StickyFormPanel(
        sections: [FormSection(label: 'S', children: [Text('left')])],
      ),
      dynamicZone: DynamicZonePanel(child: Text('center')),
    )));
    expect(find.text('center'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/widgets/wizard/wizard_screen_layout_test.dart`
Expected: FAIL — "The named parameter 'rightPanel' isn't defined" compile-error on the new test.

- [ ] **Step 3: Add `rightPanel` to the widget**

Replace the full contents of `lib/widgets/wizard/wizard_screen_layout.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/dynamic_zone_panel.dart';
import 'package:twmt/widgets/wizard/sticky_form_panel.dart';

/// Composition §7.5 wizard screen chrome: toolbar + sticky form + dynamic
/// zone, with an optional right-side advisory panel.
class WizardScreenLayout extends StatelessWidget {
  final Widget toolbar;
  final StickyFormPanel formPanel;
  final DynamicZonePanel dynamicZone;
  final Widget? rightPanel;

  const WizardScreenLayout({
    super.key,
    required this.toolbar,
    required this.formPanel,
    required this.dynamicZone,
    this.rightPanel,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toolbar,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                formPanel,
                Expanded(child: dynamicZone),
                if (rightPanel != null) rightPanel!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `flutter test test/widgets/wizard/wizard_screen_layout_test.dart`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/wizard/wizard_screen_layout.dart test/widgets/wizard/wizard_screen_layout_test.dart
git commit -m "feat: add optional right panel slot to WizardScreenLayout"
```

---

## Task 2: Extend `StickyFormPanel` with `extras` slot

**Files:**
- Modify: `lib/widgets/wizard/sticky_form_panel.dart`
- Modify: `test/widgets/wizard/sticky_form_panel_test.dart`

- [ ] **Step 1: Add failing test for `extras` slot**

Append to `test/widgets/wizard/sticky_form_panel_test.dart` (before the closing `}` of `main`):

```dart
  testWidgets('renders extras below actions when provided', (t) async {
    await t.pumpWidget(wrap(StickyFormPanel(
      sections: const [FormSection(label: 'S', children: [Text('field')])],
      actions: const [Text('Action-1')],
      extras: const Text('extras-content'),
    )));
    final actionRect = t.getRect(find.text('Action-1'));
    final extrasRect = t.getRect(find.text('extras-content'));
    expect(actionRect.top, lessThan(extrasRect.top));
  });

  testWidgets('omits extras when null', (t) async {
    await t.pumpWidget(wrap(const StickyFormPanel(
      sections: [FormSection(label: 'S', children: [Text('field')])],
    )));
    expect(find.text('extras-content'), findsNothing);
  });
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/widgets/wizard/sticky_form_panel_test.dart`
Expected: FAIL — "The named parameter 'extras' isn't defined".

- [ ] **Step 3: Add `extras` slot to the widget**

Replace the full contents of `lib/widgets/wizard/sticky_form_panel.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/summary_box.dart';

/// Sticky left column for §7.5 wizard screens.
///
/// Renders a fixed-width panel (default 380) containing [sections] at top,
/// an optional [summary] in the middle, stacked [actions] below, and an
/// optional [extras] widget at the bottom for auxiliary content that does
/// not fit the form-field idiom (e.g. an output/advisory card).
/// The panel scrolls internally when content exceeds the viewport.
class StickyFormPanel extends StatelessWidget {
  final List<Widget> sections;
  final SummaryBox? summary;
  final List<Widget> actions;
  final Widget? extras;
  final double width;
  final EdgeInsetsGeometry padding;

  const StickyFormPanel({
    super.key,
    required this.sections,
    this.summary,
    this.actions = const [],
    this.extras,
    this.width = 380,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.panel,
          border: Border(right: BorderSide(color: tokens.border)),
        ),
        child: Padding(
          padding: padding,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...sections,
                if (summary != null) ...[
                  const SizedBox(height: 8),
                  summary!,
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    actions[i],
                  ],
                ],
                if (extras != null) ...[
                  const SizedBox(height: 16),
                  extras!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `flutter test test/widgets/wizard/sticky_form_panel_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/wizard/sticky_form_panel.dart test/widgets/wizard/sticky_form_panel_test.dart
git commit -m "feat: add extras slot to StickyFormPanel"
```

---

## Task 3: Create `RightStickyPanel` widget

**Files:**
- Create: `lib/widgets/wizard/right_sticky_panel.dart`
- Create: `test/widgets/wizard/right_sticky_panel_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/widgets/wizard/right_sticky_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/right_sticky_panel.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 800,
            child: Row(children: [const Expanded(child: SizedBox()), child]),
          ),
        ),
      );

  testWidgets('panel width defaults to 380', (t) async {
    await t.pumpWidget(wrap(const RightStickyPanel(children: [Text('c')])));
    final sized = t.widget<SizedBox>(find.ancestor(
      of: find.text('c'),
      matching: find.byType(SizedBox),
    ).first);
    expect(sized.width, 380);
  });

  testWidgets('respects custom width', (t) async {
    await t.pumpWidget(wrap(const RightStickyPanel(
      width: 320,
      children: [Text('c')],
    )));
    final sized = t.widget<SizedBox>(find.ancestor(
      of: find.text('c'),
      matching: find.byType(SizedBox),
    ).first);
    expect(sized.width, 320);
  });

  testWidgets('renders children in order', (t) async {
    await t.pumpWidget(wrap(const RightStickyPanel(children: [
      Text('first'),
      Text('second'),
    ])));
    final firstRect = t.getRect(find.text('first'));
    final secondRect = t.getRect(find.text('second'));
    expect(firstRect.top, lessThan(secondRect.top));
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/widgets/wizard/right_sticky_panel_test.dart`
Expected: FAIL — "Target of URI doesn't exist: 'package:twmt/widgets/wizard/right_sticky_panel.dart'".

- [ ] **Step 3: Create the widget**

Create `lib/widgets/wizard/right_sticky_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Sticky right column for §7.5 wizard screens.
///
/// Mirrors [StickyFormPanel]'s visual treatment (fixed width, themed
/// background, hairline divider) but attaches to the right edge — divider
/// on the left — and takes an arbitrary list of [children] instead of the
/// form-specific sections/summary/actions slots. Intended for advisory or
/// companion content (e.g. conflict analysis) shown alongside the wizard's
/// dynamic zone.
class RightStickyPanel extends StatelessWidget {
  final List<Widget> children;
  final double width;
  final EdgeInsetsGeometry padding;

  const RightStickyPanel({
    super.key,
    required this.children,
    this.width = 380,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.panel,
          border: Border(left: BorderSide(color: tokens.border)),
        ),
        child: Padding(
          padding: padding,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `flutter test test/widgets/wizard/right_sticky_panel_test.dart`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/wizard/right_sticky_panel.dart test/widgets/wizard/right_sticky_panel_test.dart
git commit -m "feat: add RightStickyPanel widget for wizard right-side advisories"
```

---

## Task 4: Wire Pack Compilation editor to new slots

**Dependencies:** Tasks 1, 2, 3 must be complete.

**Files:**
- Modify: `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart`

- [ ] **Step 1: Replace the `build` method's `WizardScreenLayout` return and the `_EditingView` widget**

In `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart`, replace lines 160-270 (from `final state = ref.watch(compilationEditorProvider);` through the end of `build`'s return statement).

Find this block (lines ~160-270):

```dart
    final state = ref.watch(compilationEditorProvider);
    final languagesAsync = ref.watch(allLanguagesProvider);
    final currentGameAsync = ref.watch(currentGameInstallationProvider);
    final conflictsAsync = ref.watch(compilationConflictAnalysisProvider);
    final notifier = ref.read(compilationEditorProvider.notifier);
    final languages = languagesAsync.asData?.value ?? const <Language>[];
    final gameInstallation = currentGameAsync.asData?.value;

    return WizardScreenLayout(
      toolbar: DetailScreenToolbar(
        // ...
      ),
      formPanel: StickyFormPanel(
        // ...
      ),
      dynamicZone: DynamicZonePanel(
        // ...
      ),
    );
```

Replace with:

```dart
    final state = ref.watch(compilationEditorProvider);
    final languagesAsync = ref.watch(allLanguagesProvider);
    final currentGameAsync = ref.watch(currentGameInstallationProvider);
    final conflictsAsync = ref.watch(compilationConflictAnalysisProvider);
    final notifier = ref.read(compilationEditorProvider.notifier);
    final languages = languagesAsync.asData?.value ?? const <Language>[];
    final gameInstallation = currentGameAsync.asData?.value;

    final showConflicts = !state.isCompiling &&
        state.selectedProjectIds.length >= 2 &&
        state.selectedLanguageId != null;

    return WizardScreenLayout(
      toolbar: DetailScreenToolbar(
        crumbs: [
          const CrumbSegment('Publishing'),
          const CrumbSegment('Pack compilation', route: AppRoutes.packCompilation),
          CrumbSegment(
            state.isEditing
                ? (state.name.isEmpty ? 'Untitled' : state.name)
                : 'New',
          ),
        ],
        onBack: _handleBack,
      ),
      formPanel: StickyFormPanel(
        sections: [
          FormSection(
            label: 'Basics',
            children: [
              _LabeledField(
                label: 'Name',
                child: _TokenTextField(
                  controller: _nameCtl,
                  hint: 'My French Translations',
                  enabled: !state.isCompiling,
                  onChanged: notifier.updateName,
                ),
              ),
              _LabeledField(
                label: 'Target language',
                child: _LanguageDropdown(
                  languages: languages,
                  selectedId: state.selectedLanguageId,
                  enabled: !state.isCompiling && !state.isEditing,
                  onChanged: (id) => notifier.updateLanguage(id),
                ),
              ),
            ],
          ),
          FormSection(
            label: 'Output',
            children: [
              _LabeledField(
                label: 'Prefix',
                child: _TokenTextField(
                  controller: _prefixCtl,
                  hint: '!!!!!!!!!!_fr_compilation_twmt_',
                  enabled: !state.isCompiling,
                  onChanged: notifier.updatePrefix,
                ),
              ),
              _LabeledField(
                label: 'Pack name',
                child: _TokenTextField(
                  controller: _packNameCtl,
                  hint: 'my_pack',
                  enabled: !state.isCompiling,
                  onChanged: notifier.updatePackName,
                ),
              ),
            ],
          ),
        ],
        summary: SummaryBox(
          label: 'Will generate',
          semantics: _summarySemantics(conflictsAsync),
          lines: _summaryLines(state, conflictsAsync, languages),
        ),
        actions: [
          SmallTextButton(
            label: 'Cancel',
            icon: FluentIcons.dismiss_24_regular,
            onTap: state.isCompiling ? null : _handleBack,
          ),
          SmallTextButton(
            label: state.isCompiling ? 'Compiling...' : 'Compile',
            icon: state.isCompiling
                ? FluentIcons.stop_24_regular
                : FluentIcons.play_24_regular,
            onTap: _buildCompileCallback(state, notifier, gameInstallation),
          ),
        ],
        extras: state.isCompiling ? null : const CompilationBBCodeSection(),
      ),
      dynamicZone: DynamicZonePanel(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: state.isCompiling
              ? _CompilingView(
                  key: const ValueKey('compiling'),
                  state: state,
                  onStop: () => notifier.cancelCompilation(),
                )
              : _EditingView(
                  key: const ValueKey('editing'),
                  state: state,
                  currentGameAsync: currentGameAsync,
                  hasSuccess: state.successMessage != null &&
                      state.errorMessage == null &&
                      !state.isCompiling,
                ),
        ),
      ),
      rightPanel: showConflicts
          ? RightStickyPanel(
              children: [
                SizedBox(
                  height: 560,
                  child: ConflictingProjectsPanel(
                    selectedProjectIds: state.selectedProjectIds,
                    onToggleProject: (id) => ref
                        .read(compilationEditorProvider.notifier)
                        .toggleProject(id),
                  ),
                ),
              ],
            )
          : null,
    );
```

- [ ] **Step 2: Simplify `_EditingView` to a project-selection-only column**

In the same file, replace the `_EditingView.build` method (currently lines ~362-417). Find:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showConflicts = state.selectedProjectIds.length >= 2 &&
        state.selectedLanguageId != null;
    final hasSelection = state.selectedProjectIds.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Post-compile success banner. Visible only when the last
        // generatePack run reported a success message and no error.
        if (hasSuccess) ...[
          _CompileSuccessBanner(message: state.successMessage!),
          const SizedBox(height: 16),
        ],
        // Primary project selection list. Sized region so the internal
        // Expanded/ListView render correctly inside the wizard column.
        SizedBox(
          height: 420,
          child: CompilationProjectSelectionSection(
            state: state,
            currentGameAsync: currentGameAsync,
            // ...
            onToggle: (id) =>
                ref.read(compilationEditorProvider.notifier).toggleProject(id),
            onSelectAll: (ids) => ref
                .read(compilationEditorProvider.notifier)
                .selectAllProjects(ids),
            onDeselectAll: () => ref
                .read(compilationEditorProvider.notifier)
                .deselectAllProjects(),
          ),
        ),
        if (showConflicts) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: ConflictingProjectsPanel(
              selectedProjectIds: state.selectedProjectIds,
              // ...
              onToggleProject: (id) => ref
                  .read(compilationEditorProvider.notifier)
                  .toggleProject(id),
            ),
          ),
        ],
        if (hasSelection) ...[
          const SizedBox(height: 16),
          const CompilationBBCodeSection(),
        ],
      ],
    );
  }
```

Replace with:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasSuccess) ...[
          _CompileSuccessBanner(message: state.successMessage!),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: CompilationProjectSelectionSection(
            state: state,
            currentGameAsync: currentGameAsync,
            onToggle: (id) =>
                ref.read(compilationEditorProvider.notifier).toggleProject(id),
            onSelectAll: (ids) => ref
                .read(compilationEditorProvider.notifier)
                .selectAllProjects(ids),
            onDeselectAll: () => ref
                .read(compilationEditorProvider.notifier)
                .deselectAllProjects(),
          ),
        ),
      ],
    );
  }
```

- [ ] **Step 3: Add the new import**

At the top of the same file, add this import alongside the existing wizard imports (keep alphabetical ordering with the others — after `import 'package:twmt/widgets/wizard/dynamic_zone_panel.dart';`):

```dart
import 'package:twmt/widgets/wizard/right_sticky_panel.dart';
```

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart`
Expected: "No issues found!" (or warnings unrelated to this change).

- [ ] **Step 5: Run existing editor tests**

Run: `flutter test test/features/pack_compilation/screens/pack_compilation_editor_screen_test.dart`
Expected: PASS (both tests — the `WizardScreenLayout` smoke test still finds one instance).

- [ ] **Step 6: Run full test suite for affected areas**

Run: `flutter test test/widgets/wizard test/features/pack_compilation`
Expected: All tests PASS.

- [ ] **Step 7: Manual smoke (user-executed)**

The engineer should run `flutter run -d windows` and verify in order:
1. Navigate to Publishing → Pack compilation → New.
2. With 0 projects selected: left sidebar shows only Basics/Output/Cancel/Compile (BBCode self-hides); no right sidebar; project list fills the center.
3. Select 1 project: BBCode section appears at the bottom of the **left** sidebar; no right sidebar yet.
4. Select a target language and a second project: right sidebar appears with the Conflicting Projects panel; center still shows the project list.
5. Click Compile: right sidebar disappears during compilation; left sidebar BBCode hides; center swaps to the progress + log view.
6. After a successful compile: success banner sits above the project list; BBCode returns in the left sidebar.

- [ ] **Step 8: Commit**

```bash
git add lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart
git commit -m "refactor: move compilation conflicts to right sidebar and BBCode to form panel"
```

---

## Final verification

- [ ] **Step 1: Run full analyzer**

Run: `flutter analyze`
Expected: No new issues introduced by this work.

- [ ] **Step 2: Run full test suite**

Run: `flutter test`
Expected: All tests PASS.
