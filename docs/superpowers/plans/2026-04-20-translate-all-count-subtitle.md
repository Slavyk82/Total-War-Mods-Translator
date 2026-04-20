# Translate-all count subtitle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render a small count subtitle directly under the sidebar's primary `Translate all` button, showing how many untranslated units it will queue.

**Architecture:** Read `editorStatsProvider(projectId, languageId).pendingCount` inside the existing `Consumer` block in `EditorActionSidebar`. When there is no grid selection, the stats provider is in a `data` state, and `pendingCount > 0`, render a dim centred `Text` directly below the button. The `_SidebarActionButton` widget is untouched (no API change, other buttons keep their layout).

**Tech Stack:** Flutter desktop, Riverpod 3 (generated providers), existing test harness (`createThemedTestableWidget` with `overrides`).

**Reference spec:** `docs/superpowers/specs/2026-04-20-translate-all-count-subtitle-design.md`

**Files touched:**

- Modify: `lib/features/translation_editor/widgets/editor_action_sidebar.dart` — wrap the `Translate` Consumer's output in a `Column` that optionally renders a subtitle below the button. Lines ~74–90 today.
- Modify: `test/features/translation_editor/widgets/editor_action_sidebar_test.dart` — extend the local `build` helper to override `editorStatsProvider`, then add 5 widget tests covering the visibility matrix.

No new files, no renames, no provider changes.

---

## Task 1: Override `editorStatsProvider` in the sidebar test harness

The sidebar currently has no dependency on `editorStatsProvider`. Once Task 3 adds one, every existing `build()` call in the test file would make the provider resolve through the real repository stack, which is not wired up in these tests. Add the override up front with a default of `EditorStats.empty()` so all existing tests remain green after the implementation lands.

**Files:**
- Modify: `test/features/translation_editor/widgets/editor_action_sidebar_test.dart`

- [ ] **Step 1: Add imports for the stats provider, its model, and `AsyncValue`**

At the top of the file, alongside the existing imports, add:

```dart
import 'dart:async';

import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
```

Keep the existing imports (`editor_providers.dart`, `editor_action_sidebar.dart`, etc.) untouched.

- [ ] **Step 2: Extend the `build` helper signature**

Replace the existing `build({...})` function (lines 16–37) with the version below. New params: `pendingCount` (nullable; defaults to `0` → empty stats) and `statsLoading` (defaults to `false`, for the never-resolving case). The `projectId` / `languageId` hardcoded strings stay `'p'` / `'fr'` so the override key matches the widget's.

```dart
  Widget build({
    VoidCallback? onTranslateAll,
    VoidCallback? onTranslateSelected,
    VoidCallback? onValidate,
    VoidCallback? onExport,
    VoidCallback? onImportPack,
    int? pendingCount,
    bool statsLoading = false,
  }) {
    final statsOverride = statsLoading
        ? editorStatsProvider('p', 'fr')
            .overrideWith((_) => Completer<EditorStats>().future)
        : editorStatsProvider('p', 'fr').overrideWith(
            (_) async => EditorStats(
              totalUnits: (pendingCount ?? 0),
              pendingCount: pendingCount ?? 0,
              translatedCount: 0,
              needsReviewCount: 0,
              completionPercentage: 0.0,
            ),
          );
    return createThemedTestableWidget(
      Scaffold(
        body: EditorActionSidebar(
          projectId: 'p',
          languageId: 'fr',
          onTranslateAll: onTranslateAll ?? () {},
          onTranslateSelected: onTranslateSelected ?? () {},
          onValidate: onValidate ?? () {},
          onExport: onExport ?? () {},
          onImportPack: onImportPack ?? () {},
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [statsOverride],
    );
  }
```

- [ ] **Step 3: Run the sidebar test file to confirm no regressions**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_action_sidebar_test.dart`

Expected: all 9 existing tests pass. They do not assert on subtitle text and the default `pendingCount: 0` produces no subtitle once Task 3 lands — so nothing should flip red from the harness change alone.

- [ ] **Step 4: Commit**

```bash
git add test/features/translation_editor/widgets/editor_action_sidebar_test.dart
git commit -m "test: wire editorStatsProvider override into sidebar test harness"
```

---

## Task 2: Red — failing tests for the subtitle visibility matrix

Write all five tests before touching production code. Each pins one row of the matrix from the spec: plural, singular, zero, selected, loading.

**Files:**
- Modify: `test/features/translation_editor/widgets/editor_action_sidebar_test.dart`

- [ ] **Step 1: Append the five tests at the end of `main()` (just before the final `}`)**

```dart
  testWidgets('shows "<n> units" subtitle under Translate all when count > 1',
      (tester) async {
    await tester.pumpWidget(build(pendingCount: 42));
    await tester.pumpAndSettle();

    expect(find.text('Translate all'), findsOneWidget);
    expect(find.text('42 units'), findsOneWidget);
  });

  testWidgets('subtitle uses singular form when exactly 1 unit is pending',
      (tester) async {
    await tester.pumpWidget(build(pendingCount: 1));
    await tester.pumpAndSettle();

    expect(find.text('1 unit'), findsOneWidget);
    expect(find.text('1 units'), findsNothing);
  });

  testWidgets('no subtitle is rendered when pendingCount is 0',
      (tester) async {
    await tester.pumpWidget(build(pendingCount: 0));
    await tester.pumpAndSettle();

    // Button still there, but no count hint under it.
    expect(find.text('Translate all'), findsOneWidget);
    expect(find.textContaining('units'), findsNothing);
    expect(find.textContaining(' unit'), findsNothing);
  });

  testWidgets('no subtitle is rendered when rows are selected',
      (tester) async {
    await tester.pumpWidget(build(pendingCount: 42));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(EditorActionSidebar)),
      listen: false,
    );
    container
        .read(editorSelectionProvider.notifier)
        .selectAll(['a', 'b', 'c']);
    await tester.pumpAndSettle();

    // Label flipped to "Translate selection"; the count hint belongs to the
    // "Translate all" variant and must disappear alongside the label change.
    expect(find.text('Translate selection'), findsOneWidget);
    expect(find.text('42 units'), findsNothing);
  });

  testWidgets('no subtitle is rendered while editorStats is loading',
      (tester) async {
    await tester.pumpWidget(build(statsLoading: true));
    await tester.pump(); // 1 frame: provider still pending, no settle.

    expect(find.text('Translate all'), findsOneWidget);
    // We don't flash a placeholder while stats resolve.
    expect(find.textContaining('units'), findsNothing);
    expect(find.textContaining(' unit'), findsNothing);
  });
```

- [ ] **Step 2: Run the new tests to confirm they fail**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_action_sidebar_test.dart`

Expected failures:
- `shows "<n> units" subtitle...` → FAIL (`'42 units'` not found)
- `subtitle uses singular form...` → FAIL (`'1 unit'` not found)
- `no subtitle ... when pendingCount is 0` → PASS (nothing to render already)
- `no subtitle ... when rows are selected` → PASS (subtitle doesn't exist yet)
- `no subtitle ... while editorStats is loading` → PASS (subtitle doesn't exist yet)

At least the two positive-case tests must be red before Task 3 begins.

- [ ] **Step 3: Do NOT commit yet**

Task 2 ends with failing tests on disk. The commit comes at the end of Task 3 with the implementation.

---

## Task 3: Green — render the subtitle conditionally

Wrap the existing `Consumer` in a `Column` so that when the button says `Translate all` and we have a valid positive count, a dim centred caption appears directly below the 36 px button with a 4 px gap.

**Files:**
- Modify: `lib/features/translation_editor/widgets/editor_action_sidebar.dart`

- [ ] **Step 1: Add the import for `editorStatsProvider`**

Near the top of the file, next to the existing `editor_providers.dart` import, add:

```dart
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
```

- [ ] **Step 2: Replace the `Consumer` block inside the `Translate` section**

Replace the current lines (the `Consumer(builder: (context, ref, _) { ... })` starting around line 74 and ending at the closing `);` around line 90) with:

```dart
            Consumer(
              builder: (context, ref, _) {
                final selection = ref.watch(editorSelectionProvider);
                final hasSelection = selection.hasSelection;
                final label =
                    hasSelection ? 'Translate selection' : 'Translate all';
                // Ctrl+T is selection-aware at the screen scope, so the hint
                // stays constant regardless of the current grid state.
                final button = _SidebarActionButton(
                  icon: FluentIcons.translate_24_regular,
                  label: label,
                  primary: true,
                  shortcutHint: 'Ctrl+T',
                  onTap: hasSelection ? onTranslateSelected : onTranslateAll,
                );

                // Count hint renders only for the "Translate all" variant,
                // and only once editorStats has resolved with a positive
                // pending count — we never flash a placeholder.
                if (hasSelection) return button;
                final statsAsync =
                    ref.watch(editorStatsProvider(projectId, languageId));
                final pending = statsAsync.asData?.value.pendingCount ?? 0;
                if (pending <= 0) return button;

                final suffix = pending == 1 ? 'unit' : 'units';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    button,
                    const SizedBox(height: 4),
                    Text(
                      '$pending $suffix',
                      textAlign: TextAlign.center,
                      style: tokens.fontBody.copyWith(
                        fontSize: 10.5,
                        color: tokens.textDim,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                );
              },
            ),
```

The surrounding `_SectionHeader(label: 'Translate', ...)`, spacing `SizedBox`es, and every other sidebar section stay untouched.

- [ ] **Step 3: Run the sidebar tests to confirm green**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_action_sidebar_test.dart`

Expected: all 14 tests pass (9 pre-existing + 5 new).

- [ ] **Step 4: Run the full app test suite to confirm no collateral damage**

Run: `C:/src/flutter/bin/flutter test`

Expected: the project-wide suite stays at its previous green count, plus the 5 new tests added in Task 2. If any unrelated test fails, stop and investigate rather than patching.

- [ ] **Step 5: Commit**

```bash
git add lib/features/translation_editor/widgets/editor_action_sidebar.dart test/features/translation_editor/widgets/editor_action_sidebar_test.dart
git commit -m "feat: show pending-unit count under Translate all in sidebar"
```

---

## Task 4: Manual smoke check in the running app

Widget tests cover the logic; the UI verdict still needs a human eye on the actual pixels (colour contrast, spacing, alignment with the other sections).

- [ ] **Step 1: Launch the app in debug mode**

Run: `C:/src/flutter/bin/flutter run -d windows`

- [ ] **Step 2: Open a project + language that has pending units**

Navigate to the translation editor. Confirm:
- The subtitle is visible under `Translate all`, centred, in a dim colour that reads as a caption rather than a second button label.
- The count matches the `Pending` pill at the top of the screen.
- Selecting a few grid rows flips the label to `Translate selection` and the subtitle disappears on the same frame.
- Translating a batch to completion updates the count without a manual refresh (stats already watch `translationRowsProvider`).
- On a fully translated language (`Pending` pill shows 0), the subtitle is absent.

- [ ] **Step 3: Report result**

If the visual check passes, the feature is done — no further commit is required. If spacing / typography needs a nudge, capture the fix as a one-line adjustment to the `Text` style in `editor_action_sidebar.dart` and commit on its own.
