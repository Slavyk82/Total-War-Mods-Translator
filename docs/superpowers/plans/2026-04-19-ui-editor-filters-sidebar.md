# Translation Editor — Filters as Pills, Actions in Sidebar

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework `TranslationEditorScreen` to match the `§7.1 Filterable list` archetype: filters move into a `FilterToolbar` (bubble pills) above the body, and the left sidebar is repurposed to host every control previously in `EditorActionBar` (search · context toggles · action buttons · settings).

**Architecture:** Reuse the shared `FilterToolbar` / `FilterPillGroup` / `FilterPill` primitives from `lib/widgets/lists/` — same ones used on the Projects screen. Replace the left `EditorFilterPanel` (200 px, checkbox filters) with a new `EditorActionSidebar` (240 px, 4 labelled sections). Delete `EditorActionBar` entirely; its callbacks and widgets migrate unchanged into the sidebar.

**Tech Stack:** Flutter desktop (Material), Riverpod 3, shared list primitives (`lib/widgets/lists/`), shared wizard primitives (`lib/widgets/wizard/token_text_field.dart`), existing TWMT theme tokens (`context.tokens`).

**Spec:** `docs/superpowers/specs/2026-04-19-ui-editor-filters-sidebar-design.md`.

---

## File Structure

### Added

- `lib/features/translation_editor/widgets/editor_action_sidebar.dart` — new 240 px left panel with §SEARCH, §CONTEXT, §ACTIONS, §SETTINGS sections.
- `test/features/translation_editor/widgets/editor_action_sidebar_test.dart` — new widget test covering all 4 sections and their callbacks.
- `test/features/translation_editor/widgets/editor_filter_toolbar_test.dart` — new widget test covering the STATUS / TM SOURCE pill interactions.

### Deleted

- `lib/features/translation_editor/widgets/editor_filter_panel.dart` — replaced by `editor_action_sidebar.dart`.
- `lib/features/translation_editor/widgets/editor_action_bar.dart` — content absorbed into the sidebar + filter toolbar.
- `test/features/translation_editor/widgets/editor_filter_panel_test.dart` — superseded by `editor_action_sidebar_test.dart` and `editor_filter_toolbar_test.dart`.
- `test/features/translation_editor/widgets/editor_action_bar_test.dart` — `EditorActionBar` no longer exists.

### Modified

- `lib/features/translation_editor/screens/translation_editor_screen.dart` — insert `FilterToolbar`, swap `EditorFilterPanel`→`EditorActionSidebar`, drop `EditorActionBar`, own `FocusNode` for `Ctrl+F`.
- `test/features/translation_editor/screens/translation_editor_screen_test.dart` — replace `EditorActionBar` assertions with `FilterToolbar` + `EditorActionSidebar` assertions.

### Untouched

- `EditorToolbarModelSelector`, `EditorToolbarSkipTm`, `EditorToolbarModRule` — reused with their existing `compact: true` flag.
- `EditorDataGrid`, `EditorInspectorPanel`, `EditorStatusBar`, `DetailScreenToolbar`, `NextStepCta`.
- All editor providers (`editorFilterProvider`, `editorSelectionProvider`, `editorStatsProvider`, `translationSettingsProvider`, `currentProjectProvider`, `currentLanguageProvider`).
- `TranslationEditorActions`.

---

## Task 1: Scaffold `EditorActionSidebar` with §SEARCH section only

Create a new widget file exposing an `EditorActionSidebar` that renders a 240 px-wide panel with a single §SEARCH section containing a `TokenTextField`. The sidebar will not yet be wired into the screen — that happens in Task 6.

**Files:**
- Create: `lib/features/translation_editor/widgets/editor_action_sidebar.dart`
- Create: `test/features/translation_editor/widgets/editor_action_sidebar_test.dart`

- [ ] **Step 1: Create the new widget file (minimal stub)**

Write `lib/features/translation_editor/widgets/editor_action_sidebar.dart` with this content:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';

/// Left sidebar of the translation editor (240 px).
///
/// Replaces the ex-`EditorFilterPanel`. Filters moved to the top
/// `FilterToolbar` (STATUS + TM SOURCE pill groups). This panel now hosts
/// every control previously in `EditorActionBar`, organised into 4 labelled
/// sections: §SEARCH · §CONTEXT · §ACTIONS · §SETTINGS.
class EditorActionSidebar extends ConsumerStatefulWidget {
  final String projectId;
  final String languageId;
  final FocusNode searchFocusNode;
  final VoidCallback onTranslationSettings;
  final VoidCallback onTranslateAll;
  final VoidCallback onTranslateSelected;
  final VoidCallback onValidate;
  final VoidCallback onRescanValidation;
  final VoidCallback onExport;
  final VoidCallback onImportPack;

  const EditorActionSidebar({
    super.key,
    required this.projectId,
    required this.languageId,
    required this.searchFocusNode,
    required this.onTranslationSettings,
    required this.onTranslateAll,
    required this.onTranslateSelected,
    required this.onValidate,
    required this.onRescanValidation,
    required this.onExport,
    required this.onImportPack,
  });

  @override
  ConsumerState<EditorActionSidebar> createState() =>
      _EditorActionSidebarState();
}

class _EditorActionSidebarState extends ConsumerState<EditorActionSidebar> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      ref.read(editorFilterProvider.notifier).setSearchQuery(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(right: BorderSide(color: tokens.border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(label: 'Search', tokens: tokens),
            const SizedBox(height: 10),
            TokenTextField(
              controller: _searchController,
              focusNode: widget.searchFocusNode,
              hint: 'Search · filter · run',
              enabled: true,
              onChanged: _onSearchChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final TwmtThemeTokens tokens;
  const _SectionHeader({required this.label, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: tokens.fontDisplay.copyWith(
              fontStyle: tokens.fontDisplayStyle,
              fontSize: 13,
              color: tokens.accent,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tokens.border, Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Write a failing test for §SEARCH rendering and debounce**

Create `test/features/translation_editor/widgets/editor_action_sidebar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/features/translation_editor/widgets/editor_action_sidebar.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Widget build({
    FocusNode? focusNode,
    VoidCallback? onTranslationSettings,
    VoidCallback? onTranslateAll,
    VoidCallback? onTranslateSelected,
    VoidCallback? onValidate,
    VoidCallback? onRescanValidation,
    VoidCallback? onExport,
    VoidCallback? onImportPack,
  }) {
    return createThemedTestableWidget(
      Scaffold(
        body: EditorActionSidebar(
          projectId: 'p',
          languageId: 'fr',
          searchFocusNode: focusNode ?? FocusNode(),
          onTranslationSettings: onTranslationSettings ?? () {},
          onTranslateAll: onTranslateAll ?? () {},
          onTranslateSelected: onTranslateSelected ?? () {},
          onValidate: onValidate ?? () {},
          onRescanValidation: onRescanValidation ?? () {},
          onExport: onExport ?? () {},
          onImportPack: onImportPack ?? () {},
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
    );
  }

  testWidgets('renders §SEARCH header and search field', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('typing in search field debounces to editorFilterProvider',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: EditorActionSidebar(
            projectId: 'p',
            languageId: 'fr',
            searchFocusNode: FocusNode(),
            onTranslationSettings: () {},
            onTranslateAll: () {},
            onTranslateSelected: () {},
            onValidate: () {},
            onRescanValidation: () {},
            onExport: () {},
            onImportPack: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello');
    // Wait past the 200ms debounce.
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      container.read(editorFilterProvider).searchQuery,
      equals('hello'),
    );
  });
}
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_action_sidebar_test.dart -p vm`

Expected: 2 tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/features/translation_editor/widgets/editor_action_sidebar.dart test/features/translation_editor/widgets/editor_action_sidebar_test.dart
git commit -m "feat: add EditorActionSidebar scaffold with §SEARCH section"
```

---

## Task 2: Add §CONTEXT section (model · skip-tm · rules)

Append a §CONTEXT section below §SEARCH containing the three existing compact widgets: `EditorToolbarModelSelector`, `EditorToolbarSkipTm`, `EditorToolbarModRule`.

**Files:**
- Modify: `lib/features/translation_editor/widgets/editor_action_sidebar.dart`
- Modify: `test/features/translation_editor/widgets/editor_action_sidebar_test.dart`

- [ ] **Step 1: Write the failing test — §CONTEXT header + three widgets**

Append this test to `editor_action_sidebar_test.dart` (inside `void main() { ... }`):

```dart
  testWidgets('renders §CONTEXT header with model · skip-tm · rules', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.text('Context'), findsOneWidget);
    // Three context widgets present (model selector may render empty if no
    // models are available in test fakes, so we assert by widget type).
    expect(
      find.byWidgetPredicate((w) =>
          w.runtimeType.toString() == 'EditorToolbarSkipTm'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((w) =>
          w.runtimeType.toString() == 'EditorToolbarModRule'),
      findsOneWidget,
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_action_sidebar_test.dart -p vm`

Expected: 1 test fails (`Context` header not found).

- [ ] **Step 3: Add the §CONTEXT section to the sidebar**

In `lib/features/translation_editor/widgets/editor_action_sidebar.dart`, add imports at the top:

```dart
import 'editor_toolbar_mod_rule.dart';
import 'editor_toolbar_model_selector.dart';
import 'editor_toolbar_skip_tm.dart';
```

Then in `_EditorActionSidebarState.build`, update the `Column` children to include the context section after the search field:

```dart
          children: [
            _SectionHeader(label: 'Search', tokens: tokens),
            const SizedBox(height: 10),
            TokenTextField(
              controller: _searchController,
              focusNode: widget.searchFocusNode,
              hint: 'Search · filter · run',
              enabled: true,
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Context', tokens: tokens),
            const SizedBox(height: 10),
            const EditorToolbarModelSelector(compact: true),
            const SizedBox(height: 10),
            const EditorToolbarSkipTm(compact: true),
            const SizedBox(height: 10),
            EditorToolbarModRule(
              compact: true,
              projectId: widget.projectId,
            ),
          ],
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_action_sidebar_test.dart -p vm`

Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/translation_editor/widgets/editor_action_sidebar.dart test/features/translation_editor/widgets/editor_action_sidebar_test.dart
git commit -m "feat: add §CONTEXT section to EditorActionSidebar"
```

---

## Task 3: Add §ACTIONS section (6 entries, 3 primary + 2 secondary + Selection)

Append a §ACTIONS section with the six action rows specified in `§4.3` of the spec. Add a private `_SidebarActionButton` widget for the 4 full-width primary rows. The 2 secondary rows reuse `SmallTextButton` from `lib/widgets/lists/small_text_button.dart`.

**Files:**
- Modify: `lib/features/translation_editor/widgets/editor_action_sidebar.dart`
- Modify: `test/features/translation_editor/widgets/editor_action_sidebar_test.dart`

- [ ] **Step 1: Write failing tests for each action callback**

Append these tests to `editor_action_sidebar_test.dart`:

```dart
  testWidgets('tapping Translate all invokes onTranslateAll', (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onTranslateAll: () => tapped = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Translate all'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('Selection is disabled when no selection', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    // Row is present but its GestureDetector has a null onTap.
    final selectionFinder = find.ancestor(
      of: find.text('Selection'),
      matching: find.byType(GestureDetector),
    );
    expect(selectionFinder, findsWidgets);
  });

  testWidgets('tapping Validate selected invokes onValidate', (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onValidate: () => tapped = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Validate selected'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('tapping Rescan all invokes onRescanValidation', (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onRescanValidation: () => tapped = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rescan all'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('tapping Generate pack invokes onExport', (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onExport: () => tapped = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate pack'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('tapping Import pack invokes onImportPack', (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onImportPack: () => tapped = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import pack'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_action_sidebar_test.dart -p vm`

Expected: the 6 new tests fail (labels not found).

- [ ] **Step 3: Add imports for the new widgets**

In `editor_action_sidebar.dart`, add these imports at the top:

```dart
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
```

- [ ] **Step 4: Add the `_SidebarActionButton` private widget**

Add this class at the bottom of `editor_action_sidebar.dart`:

```dart
class _SidebarActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  const _SidebarActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onTap != null;
    final bg = primary
        ? tokens.accent
        : (enabled ? tokens.panel2 : Colors.transparent);
    final fg = primary
        ? tokens.accentFg
        : (enabled ? tokens.text : tokens.textFaint);
    final borderColor = primary
        ? tokens.accent
        : tokens.border;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12.5,
                    color: fg,
                    fontWeight: FontWeight.w500,
                  ),
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

- [ ] **Step 5: Append §ACTIONS to the sidebar Column**

In `_EditorActionSidebarState.build`, inside the `Column` children list, replace the current final child (the last `EditorToolbarModRule`) with that same widget followed by the actions section. The full children list becomes:

```dart
          children: [
            _SectionHeader(label: 'Search', tokens: tokens),
            const SizedBox(height: 10),
            TokenTextField(
              controller: _searchController,
              focusNode: widget.searchFocusNode,
              hint: 'Search · filter · run',
              enabled: true,
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Context', tokens: tokens),
            const SizedBox(height: 10),
            const EditorToolbarModelSelector(compact: true),
            const SizedBox(height: 10),
            const EditorToolbarSkipTm(compact: true),
            const SizedBox(height: 10),
            EditorToolbarModRule(
              compact: true,
              projectId: widget.projectId,
            ),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Actions', tokens: tokens),
            const SizedBox(height: 10),
            _SidebarActionButton(
              icon: FluentIcons.translate_24_regular,
              label: 'Translate all',
              primary: true,
              onTap: widget.onTranslateAll,
            ),
            const SizedBox(height: 8),
            Consumer(
              builder: (context, ref, _) {
                final selection = ref.watch(editorSelectionProvider);
                return _SidebarActionButton(
                  icon: FluentIcons.translate_24_filled,
                  label: 'Selection',
                  onTap: selection.hasSelection
                      ? widget.onTranslateSelected
                      : null,
                );
              },
            ),
            const SizedBox(height: 16),
            _SidebarActionButton(
              icon: FluentIcons.checkmark_circle_24_regular,
              label: 'Validate selected',
              onTap: widget.onValidate,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: SmallTextButton(
                label: 'Rescan all',
                onTap: widget.onRescanValidation,
              ),
            ),
            const SizedBox(height: 16),
            _SidebarActionButton(
              icon: FluentIcons.box_24_regular,
              label: 'Generate pack',
              onTap: widget.onExport,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: SmallTextButton(
                label: 'Import pack',
                onTap: widget.onImportPack,
              ),
            ),
          ],
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_action_sidebar_test.dart -p vm`

Expected: all tests pass (9 total).

- [ ] **Step 7: Commit**

```bash
git add lib/features/translation_editor/widgets/editor_action_sidebar.dart test/features/translation_editor/widgets/editor_action_sidebar_test.dart
git commit -m "feat: add §ACTIONS section to EditorActionSidebar"
```

---

## Task 4: Add §SETTINGS section (Translation settings full-width button)

Append a §SETTINGS section below §ACTIONS with one `_SidebarActionButton` invoking `onTranslationSettings`.

**Files:**
- Modify: `lib/features/translation_editor/widgets/editor_action_sidebar.dart`
- Modify: `test/features/translation_editor/widgets/editor_action_sidebar_test.dart`

- [ ] **Step 1: Write failing test for §SETTINGS**

Append to `editor_action_sidebar_test.dart`:

```dart
  testWidgets('tapping Translation settings invokes onTranslationSettings',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(onTranslationSettings: () => tapped = true));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.text('Translation settings'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_action_sidebar_test.dart -p vm`

Expected: 1 test fails.

- [ ] **Step 3: Append §SETTINGS to the sidebar Column**

In `_EditorActionSidebarState.build`, append after the `Import pack` row:

```dart
            const SizedBox(height: 20),
            _SectionHeader(label: 'Settings', tokens: tokens),
            const SizedBox(height: 10),
            _SidebarActionButton(
              icon: FluentIcons.settings_24_regular,
              label: 'Translation settings',
              onTap: widget.onTranslationSettings,
            ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_action_sidebar_test.dart -p vm`

Expected: all tests pass (10 total).

- [ ] **Step 5: Commit**

```bash
git add lib/features/translation_editor/widgets/editor_action_sidebar.dart test/features/translation_editor/widgets/editor_action_sidebar_test.dart
git commit -m "feat: add §SETTINGS section to EditorActionSidebar"
```

---

## Task 5: Add filter toolbar test + helpers

Create a new test file asserting the behaviour of the filter pills that will be rendered by the screen. The test pumps the full `TranslationEditorScreen` once the glue task (Task 6) is in place — so we write the test file as a characterisation test that drives the `editorFilterProvider` directly via tapping pills.

**Files:**
- Create: `test/features/translation_editor/widgets/editor_filter_toolbar_test.dart`

- [ ] **Step 1: Create the filter-toolbar test file (initially failing — the screen still uses `EditorFilterPanel`)**

Write `test/features/translation_editor/widgets/editor_filter_toolbar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
import 'package:twmt/features/translation_editor/providers/translation_settings_provider.dart';
import 'package:twmt/features/translation_editor/screens/translation_editor_screen.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  const projectId = 'p';
  const languageId = 'fr';

  setUp(() async {
    await setupMockServices();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1920, 1080);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
    await tearDownMockServices();
  });

  Widget build({List<Override> extraOverrides = const []}) {
    return ProviderScope(
      overrides: [
        currentProjectProvider(projectId).overrideWith(
          (ref) async => Project(
            id: projectId,
            name: 'Test Project',
            gameInstallationId: 'g',
            projectType: 'mod',
            createdAt: DateTime.now().millisecondsSinceEpoch,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
        currentLanguageProvider(languageId).overrideWith(
          (ref) async => const Language(
            id: languageId,
            code: 'fr',
            name: 'French',
            nativeName: 'Francais',
          ),
        ),
        translationRowsProvider(projectId, languageId)
            .overrideWith((ref) async => <TranslationRow>[]),
        editorStatsProvider(projectId, languageId).overrideWith(
          (ref) async => const EditorStats(
            totalUnits: 100,
            pendingCount: 50,
            translatedCount: 40,
            needsReviewCount: 10,
            completionPercentage: 40.0,
          ),
        ),
        translationSettingsProvider.overrideWith(
          () => _Settings(),
        ),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: const SizedBox(
          width: 1920,
          height: 1080,
          child: TranslationEditorScreen(
            projectId: projectId,
            languageId: languageId,
          ),
        ),
      ),
    );
  }

  testWidgets('renders FilterToolbar with STATUS and TM SOURCE groups',
      (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byType(FilterToolbar), findsOneWidget);
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.text('TM SOURCE'), findsOneWidget);

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Translated'), findsOneWidget);
    expect(find.text('Needs review'), findsOneWidget);
    expect(find.text('Exact match'), findsOneWidget);
    expect(find.text('Fuzzy match'), findsOneWidget);
    expect(find.text('LLM'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('tapping Pending pill toggles editorFilterProvider.statusFilters',
      (tester) async {
    final container = ProviderContainer(overrides: [
      editorStatsProvider(projectId, languageId).overrideWith(
        (ref) async => const EditorStats(
          totalUnits: 100,
          pendingCount: 50,
          translatedCount: 40,
          needsReviewCount: 10,
          completionPercentage: 40.0,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    // Tap the Pending pill.
    await tester.tap(find.widgetWithText(FilterPill, 'Pending'));
    await tester.pumpAndSettle();

    // Read the provider from the screen's scope via any ProviderScope.
    final element = tester.element(find.byType(TranslationEditorScreen));
    final innerContainer =
        ProviderScope.containerOf(element, listen: false);
    expect(
      innerContainer.read(editorFilterProvider).statusFilters,
      contains(TranslationVersionStatus.pending),
    );
  });
}

class _Settings extends TranslationSettingsNotifier {
  @override
  TranslationSettings build() => const TranslationSettings(
        unitsPerBatch: 0,
        parallelBatches: 5,
        skipTranslationMemory: false,
      );

  @override
  void setSkipTranslationMemory(bool value) {}

  @override
  Future<void> updateSettings({int? unitsPerBatch, int? parallelBatches}) async {}

  @override
  Future<TranslationSettings> ensureLoaded() async => state;
}
```

- [ ] **Step 2: Run the new test — expect failure (FilterToolbar not yet rendered)**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_filter_toolbar_test.dart -p vm`

Expected: both tests fail (`FilterToolbar` not found; `STATUS` / `TM SOURCE` labels missing). That's the red state for the next task to turn green.

- [ ] **Step 3: Commit the failing test — explicit red gate**

```bash
git add test/features/translation_editor/widgets/editor_filter_toolbar_test.dart
git commit -m "test: add failing editor filter toolbar test (red for next task)"
```

---

## Task 6: Wire `FilterToolbar` + `EditorActionSidebar` into the screen

Swap `EditorFilterPanel` → `EditorActionSidebar`, drop `EditorActionBar`, and insert a `FilterToolbar` between `DetailScreenToolbar` and the body. Move the `_searchFocusNode` to the screen state and hand it down to the sidebar. Delete the old widget files.

**Files:**
- Modify: `lib/features/translation_editor/screens/translation_editor_screen.dart`
- Modify: `test/features/translation_editor/screens/translation_editor_screen_test.dart`
- Delete: `lib/features/translation_editor/widgets/editor_filter_panel.dart`
- Delete: `lib/features/translation_editor/widgets/editor_action_bar.dart`
- Delete: `test/features/translation_editor/widgets/editor_filter_panel_test.dart`
- Delete: `test/features/translation_editor/widgets/editor_action_bar_test.dart`

- [ ] **Step 1: Update the screen test to assert the new widget types**

Replace the contents of `test/features/translation_editor/screens/translation_editor_screen_test.dart` with the following (keeping the existing bootstrap/setup exactly, only changing assertions):

Find and replace these three blocks:

```dart
// OLD:
import 'package:twmt/features/translation_editor/widgets/editor_action_bar.dart';
```

```dart
// NEW:
import 'package:twmt/features/translation_editor/widgets/editor_action_sidebar.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
```

Replace both `EditorActionBar` assertion blocks (there are two):

```dart
// OLD:
      testWidgets('should render EditorActionBar', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(EditorActionBar), findsOneWidget);
      });
```

With:

```dart
      testWidgets('should render EditorActionSidebar and FilterToolbar',
          (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(EditorActionSidebar), findsOneWidget);
        expect(find.byType(FilterToolbar), findsOneWidget);
      });
```

And the second occurrence inside `group('Toolbar', ...)`:

```dart
// OLD:
      testWidgets('should render EditorActionBar component', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(EditorActionBar), findsOneWidget);
      });
```

With:

```dart
      testWidgets('should render FilterToolbar with project name', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(FilterToolbar), findsOneWidget);
        // The project name shows up in the leading of the filter toolbar.
        // Note: DetailScreenToolbar's crumb also contains 'Test Project',
        // so findsWidgets is the correct matcher here.
        expect(find.text('Test Project'), findsWidgets);
      });
```

Also, update the comment block at line 32-34 that references `EditorActionBar` and 1280 px min-width — the new sidebar is always 240 px and no horizontal scroll exists in the filter toolbar. Replace:

```dart
    // Reference desktop size from spec §8.7. The EditorActionBar's middle action
    // group is wrapped in a horizontal SingleChildScrollView, so this viewport
    // (and even the 1280px min-width) renders without layout overflow.
    const wideScreenSize = Size(1920, 1080);
```

With:

```dart
    // Reference desktop size from spec §8.7. The filter toolbar row 2 is a
    // horizontal SingleChildScrollView, so narrow viewports (down to the
    // 1280px min-width) render without layout overflow.
    const wideScreenSize = Size(1920, 1080);
```

- [ ] **Step 2: Rewrite `translation_editor_screen.dart`**

Replace the contents of `lib/features/translation_editor/screens/translation_editor_screen.dart` with:

```dart
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/crumb_segment.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/workflow/next_step_cta.dart';
import '../../../providers/shared/repository_providers.dart' as shared_repo;
import '../providers/translation_settings_provider.dart';
import '../widgets/editor_action_sidebar.dart';
import '../widgets/editor_datagrid.dart';
import '../widgets/editor_inspector_panel.dart';
import '../widgets/editor_status_bar.dart';
import 'translation_editor_actions.dart';

/// Translation editor screen.
///
/// Three-panel body (action sidebar · DataGrid · inspector) sandwiched between
/// a stacked header (`DetailScreenToolbar` + `FilterToolbar`) and
/// `EditorStatusBar`. The top-bar `EditorActionBar` was retired — all its
/// controls (search · model · skip-tm · rules · action buttons · settings)
/// now live in `EditorActionSidebar`. Filters became pills in `FilterToolbar`.
class TranslationEditorScreen extends ConsumerStatefulWidget {
  const TranslationEditorScreen({
    super.key,
    required this.projectId,
    required this.languageId,
  });

  final String projectId;
  final String languageId;

  @override
  ConsumerState<TranslationEditorScreen> createState() =>
      _TranslationEditorScreenState();
}

class _TranslationEditorScreenState
    extends ConsumerState<TranslationEditorScreen> {
  final FocusNode _searchFocus = FocusNode(debugLabel: 'editor-search');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(translationSettingsProvider.notifier)
          .setSkipTranslationMemory(false);
      _clearModUpdateImpact();
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _clearModUpdateImpact() async {
    final projectRepo = ref.read(shared_repo.projectRepositoryProvider);
    await projectRepo.clearModUpdateImpact(widget.projectId);
  }

  TranslationEditorActions _getActions() {
    return TranslationEditorActions(
      ref: ref,
      context: context,
      projectId: widget.projectId,
      languageId: widget.languageId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final projectAsync = ref.watch(currentProjectProvider(widget.projectId));
    final languageAsync = ref.watch(currentLanguageProvider(widget.languageId));
    final statsAsync = ref.watch(
      editorStatsProvider(widget.projectId, widget.languageId),
    );
    final filter = ref.watch(editorFilterProvider);
    final projectName = projectAsync.whenOrNull(data: (p) => p.name) ?? '';
    final languageName = languageAsync.whenOrNull(data: (l) => l.name) ?? '';

    final stats = statsAsync.asData?.value;
    final isFullyTranslated = stats != null &&
        stats.totalUnits > 0 &&
        stats.completionPercentage >= 100.0;

    final shortcuts = <ShortcutActivator, Intent>{
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
          const _FocusSearchIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyT):
          const _TranslateAllIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyT): const _TranslateSelectedIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyV): const _ValidateIntent(),
    };

    final actions = <Type, Action<Intent>>{
      _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
        onInvoke: (_) {
          _searchFocus.requestFocus();
          return null;
        },
      ),
      _TranslateAllIntent: CallbackAction<_TranslateAllIntent>(
        onInvoke: (_) {
          _getActions().handleTranslateAll();
          return null;
        },
      ),
      _TranslateSelectedIntent: CallbackAction<_TranslateSelectedIntent>(
        onInvoke: (_) {
          _getActions().handleTranslateSelected();
          return null;
        },
      ),
      _ValidateIntent: CallbackAction<_ValidateIntent>(
        onInvoke: (_) {
          _getActions().handleValidate();
          return null;
        },
      ),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        child: Material(
          color: context.tokens.bg,
          child: Column(
            children: [
              DetailScreenToolbar(
                crumbs: [
                  const CrumbSegment('Work'),
                  const CrumbSegment('Projects', route: AppRoutes.projects),
                  CrumbSegment(
                    projectName,
                    route: AppRoutes.projectDetail(widget.projectId),
                  ),
                  CrumbSegment(languageName),
                ],
                trailing: [
                  if (isFullyTranslated)
                    NextStepCta(
                      label: 'Compile this pack',
                      icon: FluentIcons.box_multiple_24_regular,
                      onTap: () => context.goPackCompilation(),
                    ),
                ],
                onBack: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              FilterToolbar(
                leading: ListToolbarLeading(
                  icon: FluentIcons.folder_24_regular,
                  title: projectName,
                ),
                pillGroups: [
                  _buildStatusGroup(filter, stats),
                  _buildTmSourceGroup(filter),
                ],
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EditorActionSidebar(
                      projectId: widget.projectId,
                      languageId: widget.languageId,
                      searchFocusNode: _searchFocus,
                      onTranslationSettings: () =>
                          _getActions().handleTranslationSettings(),
                      onTranslateAll: () => _getActions().handleTranslateAll(),
                      onTranslateSelected: () =>
                          _getActions().handleTranslateSelected(),
                      onValidate: () => _getActions().handleValidate(),
                      onRescanValidation: () =>
                          _getActions().handleRescanValidation(),
                      onExport: () => _getActions().handleExport(),
                      onImportPack: () => _getActions().handleImportPack(),
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
        ),
      ),
    );
  }

  FilterPillGroup _buildStatusGroup(EditorFilterState filter, EditorStats? stats) {
    FilterPill pill(
      String label,
      TranslationVersionStatus status,
      int? count,
    ) {
      final active = filter.statusFilters.contains(status);
      return FilterPill(
        label: label,
        selected: active,
        count: count,
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
      );
    }

    return FilterPillGroup(
      label: 'STATUS',
      clearLabel: 'Clear',
      onClear: () => ref
          .read(editorFilterProvider.notifier)
          .setStatusFilters(const {}),
      pills: [
        pill('Pending', TranslationVersionStatus.pending, stats?.pendingCount),
        pill('Translated', TranslationVersionStatus.translated,
            stats?.translatedCount),
        pill('Needs review', TranslationVersionStatus.needsReview,
            stats?.needsReviewCount),
      ],
    );
  }

  FilterPillGroup _buildTmSourceGroup(EditorFilterState filter) {
    FilterPill pill(String label, TmSourceType type) {
      final active = filter.tmSourceFilters.contains(type);
      return FilterPill(
        label: label,
        selected: active,
        onToggle: () {
          final updated = Set<TmSourceType>.from(filter.tmSourceFilters);
          if (active) {
            updated.remove(type);
          } else {
            updated.add(type);
          }
          ref.read(editorFilterProvider.notifier).setTmSourceFilters(updated);
        },
      );
    }

    return FilterPillGroup(
      label: 'TM SOURCE',
      clearLabel: 'Clear',
      onClear: () => ref
          .read(editorFilterProvider.notifier)
          .setTmSourceFilters(const {}),
      pills: [
        pill('Exact match', TmSourceType.exactMatch),
        pill('Fuzzy match', TmSourceType.fuzzyMatch),
        pill('LLM', TmSourceType.llm),
        pill('Manual', TmSourceType.manual),
        pill('None', TmSourceType.none),
      ],
    );
  }
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _TranslateAllIntent extends Intent {
  const _TranslateAllIntent();
}

class _TranslateSelectedIntent extends Intent {
  const _TranslateSelectedIntent();
}

class _ValidateIntent extends Intent {
  const _ValidateIntent();
}
```

- [ ] **Step 3: Delete the old widget files and their tests**

```bash
git rm lib/features/translation_editor/widgets/editor_filter_panel.dart lib/features/translation_editor/widgets/editor_action_bar.dart test/features/translation_editor/widgets/editor_filter_panel_test.dart test/features/translation_editor/widgets/editor_action_bar_test.dart
```

- [ ] **Step 4: Run the full translation_editor test folder**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/ -p vm`

Expected: all tests pass — sidebar (10), filter toolbar (2), screen (existing group), inspector/datagrid/status bar (unchanged).

- [ ] **Step 5: Run `flutter analyze` on the edited files**

Run: `C:/src/flutter/bin/flutter analyze lib/features/translation_editor/ test/features/translation_editor/`

Expected: no new lints introduced (pre-existing lints in other files are acceptable).

- [ ] **Step 6: Commit**

```bash
git add lib/features/translation_editor/screens/translation_editor_screen.dart test/features/translation_editor/screens/translation_editor_screen_test.dart
git commit -m "feat: wire FilterToolbar and EditorActionSidebar into editor screen"
```

---

## Task 7: Check for editor goldens and regenerate if present

The progress memory mentions Plan 4 shipped "4 goldens (2 themes × 2 states, stable)" for the editor — but those may have been pruned in later refactors. Verify and regenerate if they still exist.

**Files:**
- Potentially modify: any `*_golden_test.dart` under `test/features/translation_editor/` + their sibling `goldens/*.png`.

- [ ] **Step 1: Search for any golden test under the editor folder**

Run:

```bash
grep -rln 'matchesGoldenFile' test/features/translation_editor/
```

Expected: either zero matches (goldens no longer present in this branch) or one/two test files. Record the result.

- [ ] **Step 2a: If zero matches — skip the rest of this task**

Document the absence in the task 8 smoke-test report and move on. Golden coverage can be re-added in a follow-up if needed.

- [ ] **Step 2b: If matches — inspect the test(s)**

Read the golden file(s). Confirm they render `TranslationEditorScreen` at a known viewport (check the Plan 4 / back-nav plan for the viewport convention — typically 1920×1080). If they render a subtree that no longer exists (`EditorActionBar`, `EditorFilterPanel`), update the render tree to the new screen.

- [ ] **Step 3b: Regenerate goldens**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/ -p vm --update-goldens`

Expected: the `.png` files under the matching `goldens/` folder are rewritten.

- [ ] **Step 4b: Visually inspect each regenerated golden**

Open each PNG and confirm:
- The filter toolbar shows `STATUS` and `TM SOURCE` pill groups.
- The leading reads the fixture's project name.
- The sidebar is 240 px and shows the 4 section headers in order (Search · Context · Actions · Settings).
- The `Translate all` button renders in the accent colour (primary).

If any golden looks wrong, diagnose and fix before committing.

- [ ] **Step 5b: Re-run goldens without `--update-goldens` to confirm they match**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/ -p vm`

Expected: all tests pass, including goldens.

- [ ] **Step 6b: Commit**

```bash
git add test/features/translation_editor/
git commit -m "test: regenerate editor goldens for filter-pills + sidebar layout"
```

---

## Task 8: Full test + analyze sweep

Verify no regressions anywhere.

- [ ] **Step 1: Run the full test suite**

Run: `C:/src/flutter/bin/flutter test -p vm`

Expected: baseline count (1301/0 per `feat/ui-editor-back-nav` merge) preserved or improved. Any new failures must be investigated and fixed — no test should be disabled to hide a regression.

- [ ] **Step 2: Run `flutter analyze` across the repo**

Run: `C:/src/flutter/bin/flutter analyze`

Expected: ≤ the 35 pre-existing lints from Plan 5f. No new lints in the touched files.

- [ ] **Step 3: Manual smoke test — run the app**

Run: `C:/src/flutter/bin/flutter run -d windows`

In the app:
1. Open a project and a language to land on the editor.
2. Confirm the toolbar shows the project name and the STATUS + TM SOURCE pill groups.
3. Click each pill and confirm the data grid filters accordingly; click the group clear pill and confirm it deselects all in that group.
4. In the sidebar:
   - Type in §SEARCH → confirm the grid filters after 200 ms.
   - Press `Ctrl+F` → confirm the search field regains focus.
   - Pick a different model in §CONTEXT → confirm the change persists.
   - Toggle Skip TM → confirm the chip flips colour.
   - Click `Translate all` → confirm the translation flow kicks off.
   - With nothing selected, confirm `Selection` is visually disabled.
   - Click `Rescan all` and `Import pack` (secondary rows) → confirm they trigger the respective flows.
   - Click `Translation settings` → confirm the dialog opens.
5. Confirm the status bar still shows live unit counts at the bottom.

- [ ] **Step 4: Commit any small adjustments from smoke testing**

If the smoke test surfaces any visual/interaction issues, fix them and commit with a descriptive message. Otherwise, skip.

---

## Done

All spec sections implemented:

- §2 shape: `DetailScreenToolbar` + `FilterToolbar` + 3-panel body + `EditorStatusBar`.
- §3 filter toolbar: leading = project name (Task 6), trailing empty, 2 pill groups with counts on STATUS (Task 6), per-group clear pills (Task 6).
- §4 sidebar: 240 px, 4 sections in order, shared `_SectionHeader` primitive (Tasks 1–4).
- §5 screen glue: `FilterToolbar` inserted, `EditorActionBar` retired, `FocusNode` lifted to screen state (Task 6).
- §6 files touched: see summary in this plan's `File Structure` section — matches the spec.
- §7 tests: 3 test files (`editor_action_sidebar_test.dart`, `editor_filter_toolbar_test.dart`, `translation_editor_screen_test.dart`) + regenerated goldens.
