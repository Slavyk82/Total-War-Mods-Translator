# Workflow Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the 7 validated UX improvements from `docs/superpowers/specs/2026-04-18-workflow-improvements-design.md` — sidebar Workflow group, guided Workshop publish, next-step CTAs, Workshop onboarding card, and extended empty-state guide.

**Architecture:** Incremental, low-risk changes layered onto existing screens. Most decisions touch a single file or add a focused widget. No routing changes, no model changes. Two decisions (4 and 5) are already satisfied by existing code and are handled as verification tasks, not new implementation.

**Tech Stack:** Flutter Desktop, Riverpod 3, GoRouter, sqflite, `*.g.dart` codegen (`build_runner`), `flutter_test` + `flutter_test` helpers from `test/` harness.

---

## Spec coverage map

| Spec decision | Phase | Tasks |
|---|---|---|
| 1. Workshop guided publish (launcher + checklist + URL parse) | 3 | T6, T7, T8 |
| 2. Sidebar Workflow group | 1 | T1 |
| 3. Next step CTA | 4 | T9, T10, T11 |
| 4. Language in project creation | 1 | T2 (verification) |
| 5. Workshop 3-state row | 3 | Covered by T7 (state B enhancements) + T3 (verification) |
| 6. Workshop pedagogical card | 2 | T4, T5 |
| 7. EmptyStateGuide 5 steps | 1 | T12 |

---

## File Structure

### New files

- `lib/features/steam_publish/widgets/workshop_onboarding_card.dart` — dismissable pedagogical card for `SteamPublishScreen`. Opt-in persistence.
- `lib/features/steam_publish/utils/workshop_url_parser.dart` — pure function to extract a numeric Workshop ID from a full URL or bare ID. No UI deps.
- `lib/services/platform/game_launcher_opener.dart` — service to open the in-game launcher from a game installation path. Thin wrapper over `Process.start` / `url_launcher`.
- `lib/widgets/workflow/next_step_cta.dart` — small CTA widget used at the end of workflow screens to point at the next step.
- `test/features/steam_publish/widgets/workshop_onboarding_card_test.dart`
- `test/features/steam_publish/utils/workshop_url_parser_test.dart`
- `test/widgets/workflow/next_step_cta_test.dart`

### Modified files

- `lib/config/router/navigation_tree.dart` — restructure sidebar groups.
- `lib/features/home/widgets/empty_state_guide.dart` — extend to 5 steps.
- `lib/features/steam_publish/screens/steam_publish_screen.dart` — mount the onboarding card.
- `lib/features/steam_publish/widgets/steam_publish_action_cell.dart` — enhance State B (URL parse, launcher button, checklist).
- `lib/features/settings/providers/settings_providers.dart` — add `workshopOnboardingCardHidden` key.
- `lib/features/settings/screens/settings_screen.dart` (or the appropriate tab widget) — add "Reset onboarding hints" button.
- `lib/features/translation_editor/screens/translation_editor_screen.dart` — mount `NextStepCta` when applicable.
- `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart` — mount `NextStepCta` when applicable.

### Test files to update

- `test/config/router/navigation_tree_test.dart` — update expected groups/items.
- `test/widgets/navigation/navigation_sidebar_test.dart` — update any assertions on group labels or item count.
- `test/features/home/widgets/empty_state_guide_test.dart` — update to expect 5 cards.
- `test/features/steam_publish/widgets/steam_publish_action_cell_test.dart` — new cases for URL parsing and launcher button.

---

# Phase 1 — Quick wins (no coupling)

## Task 1: Restructure sidebar into Workflow-led groups

**Spec:** decision 2.

**Files:**
- Modify: `lib/config/router/navigation_tree.dart`
- Test: `test/config/router/navigation_tree_test.dart` (update if exists; otherwise create)
- Test: `test/widgets/navigation/navigation_sidebar_test.dart` (update existing assertions)

- [ ] **Step 1: Update the failing test (or write one)**

Search for an existing `navigation_tree_test.dart`. If found, update the expected structure. If not, create:

```dart
// test/config/router/navigation_tree_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/config/router/navigation_tree.dart';

void main() {
  group('navigationTree', () {
    test('has 4 groups in the new order', () {
      expect(navigationTree.map((g) => g.label).toList(),
          ['Workflow', 'Work', 'Resources', 'System']);
    });

    test('Workflow group contains the 4 pipeline steps routed correctly', () {
      final workflow = navigationTree.firstWhere((g) => g.label == 'Workflow');
      expect(workflow.items.map((i) => i.label).toList(),
          ['Detect', 'Translate', 'Compile', 'Publish']);
      expect(workflow.items.map((i) => i.route).toList(), [
        AppRoutes.mods,
        AppRoutes.projects,
        AppRoutes.packCompilation,
        AppRoutes.steamPublish,
      ]);
    });

    test('Work group only contains Home', () {
      final work = navigationTree.firstWhere((g) => g.label == 'Work');
      expect(work.items.map((i) => i.label).toList(), ['Home']);
    });

    test('Resources group contains Glossary, Translation Memory, Game Files',
        () {
      final resources =
          navigationTree.firstWhere((g) => g.label == 'Resources');
      expect(resources.items.map((i) => i.label).toList(),
          ['Glossary', 'Translation Memory', 'Game Files']);
    });

    test('System group keeps Settings and Help', () {
      final system = navigationTree.firstWhere((g) => g.label == 'System');
      expect(system.items.map((i) => i.label).toList(),
          ['Settings', 'Help']);
    });

    test('no group is named Sources or Publishing', () {
      final labels = navigationTree.map((g) => g.label).toSet();
      expect(labels, isNot(contains('Sources')));
      expect(labels, isNot(contains('Publishing')));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
C:/src/flutter/bin/flutter test test/config/router/navigation_tree_test.dart
```

Expected: FAIL — current structure has groups `Sources, Work, Resources, Publishing, System`.

- [ ] **Step 3: Restructure `navigation_tree.dart`**

Replace the `navigationTree` constant in `lib/config/router/navigation_tree.dart` with:

```dart
const List<NavGroup> navigationTree = [
  NavGroup('Workflow', [
    NavItem(
      label: 'Detect',
      route: AppRoutes.mods,
      icon: FluentIcons.cube_24_regular,
      selectedIcon: FluentIcons.cube_24_filled,
    ),
    NavItem(
      label: 'Translate',
      route: AppRoutes.projects,
      icon: FluentIcons.folder_24_regular,
      selectedIcon: FluentIcons.folder_24_filled,
    ),
    NavItem(
      label: 'Compile',
      route: AppRoutes.packCompilation,
      icon: FluentIcons.box_multiple_24_regular,
      selectedIcon: FluentIcons.box_multiple_24_filled,
    ),
    NavItem(
      label: 'Publish',
      route: AppRoutes.steamPublish,
      icon: FluentIcons.cloud_arrow_up_24_regular,
      selectedIcon: FluentIcons.cloud_arrow_up_24_filled,
    ),
  ]),
  NavGroup('Work', [
    NavItem(
      label: 'Home',
      route: AppRoutes.home,
      icon: FluentIcons.home_24_regular,
      selectedIcon: FluentIcons.home_24_filled,
    ),
  ]),
  NavGroup('Resources', [
    NavItem(
      label: 'Glossary',
      route: AppRoutes.glossary,
      icon: FluentIcons.book_24_regular,
      selectedIcon: FluentIcons.book_24_filled,
    ),
    NavItem(
      label: 'Translation Memory',
      route: AppRoutes.translationMemory,
      icon: FluentIcons.database_24_regular,
      selectedIcon: FluentIcons.database_24_filled,
    ),
    NavItem(
      label: 'Game Files',
      route: AppRoutes.gameFiles,
      icon: FluentIcons.globe_24_regular,
      selectedIcon: FluentIcons.globe_24_filled,
    ),
  ]),
  NavGroup('System', [
    NavItem(
      label: 'Settings',
      route: AppRoutes.settings,
      icon: FluentIcons.settings_24_regular,
      selectedIcon: FluentIcons.settings_24_filled,
    ),
    NavItem(
      label: 'Help',
      route: AppRoutes.help,
      icon: FluentIcons.question_circle_24_regular,
      selectedIcon: FluentIcons.question_circle_24_filled,
    ),
  ]),
];
```

- [ ] **Step 4: Re-run the test to verify it passes**

```bash
C:/src/flutter/bin/flutter test test/config/router/navigation_tree_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run the existing sidebar widget tests and update assertions**

```bash
C:/src/flutter/bin/flutter test test/widgets/navigation/
```

If any test asserts on the old group labels (e.g. `'Sources'`, `'Publishing'`), update it to the new labels. Re-run until green.

- [ ] **Step 6: Smoke-check the running app**

```bash
C:/src/flutter/bin/flutter run -d windows
```

Confirm visually that the sidebar shows the four new groups in order and that clicking `Detect`, `Translate`, `Compile`, `Publish` lands on the right screens. Quit after verification.

- [ ] **Step 7: Commit**

```bash
git add lib/config/router/navigation_tree.dart test/config/router/navigation_tree_test.dart test/widgets/navigation/
git commit -m "refactor: regroup sidebar around the Workflow pipeline"
```

---

## Task 2: Verify language selection is already integral to project creation

**Spec:** decision 4.

**Files:**
- Read-only: `lib/features/projects/widgets/create_project/create_project_dialog.dart`
- Read-only: `lib/features/projects/widgets/create_project/step_languages.dart`
- Test: `test/features/projects/widgets/create_project/create_project_dialog_test.dart` (add a regression test)

This decision is already satisfied by the existing 3-step wizard (Basic info → Target languages → Translation settings) which enforces at least one language before allowing creation. We lock that behaviour with a test so a future refactor cannot silently remove it.

- [ ] **Step 1: Write the regression test**

Add a focused test that creates the dialog, attempts to proceed past the languages step with zero selections, and asserts the error message is surfaced. If a similar test already exists, skip this task step.

```dart
// test/features/projects/widgets/create_project/create_project_dialog_test.dart
testWidgets(
    'cannot proceed past languages step with no language selected',
    (tester) async {
  // Use the repository harness already used by other project tests.
  await pumpCreateProjectDialog(tester);

  // Advance from Basic info (step 0) to Languages (step 1).
  await fillValidBasicInfo(tester);
  await tester.tap(find.widgetWithText(SmallTextButton, 'Next'));
  await tester.pumpAndSettle();

  // No language picked; tap Next.
  await tester.tap(find.widgetWithText(SmallTextButton, 'Next'));
  await tester.pumpAndSettle();

  expect(
      find.text('Please select at least one target language'), findsOneWidget);
});
```

Helpers `pumpCreateProjectDialog` / `fillValidBasicInfo` already exist if there's an existing test file — reuse them. If not, build them inline for this single test.

- [ ] **Step 2: Run the test to confirm it passes today**

```bash
C:/src/flutter/bin/flutter test test/features/projects/widgets/create_project/create_project_dialog_test.dart
```

Expected: PASS (the code already enforces this).

- [ ] **Step 3: Commit**

```bash
git add test/features/projects/widgets/create_project/create_project_dialog_test.dart
git commit -m "test: lock create-project wizard to require at least one language"
```

---

## Task 3: Verify Workshop action cell already implements 3-state machine

**Spec:** decision 5 (base structure).

**Files:**
- Read-only: `lib/features/steam_publish/widgets/steam_publish_action_cell.dart`
- Test: `test/features/steam_publish/widgets/steam_publish_action_cell_test.dart` (add regression test if missing)

The state machine already exists (`State A: no pack`, `State B: pack + no id`, `State C: pack + id`). We lock each state with a rendering test.

- [ ] **Step 1: Write the regression test**

```dart
// test/features/steam_publish/widgets/steam_publish_action_cell_test.dart
testWidgets('State A (no pack) renders "Generate pack"', (tester) async {
  await pumpSteamActionCell(tester,
      hasPack: false, publishedSteamId: null);
  expect(find.text('Generate pack'), findsOneWidget);
});

testWidgets('State B (pack, no id) renders the Workshop id input',
    (tester) async {
  await pumpSteamActionCell(tester, hasPack: true, publishedSteamId: null);
  expect(find.widgetWithText(TextField, 'Workshop id...'), findsOneWidget);
});

testWidgets('State C (pack + id) renders "Update"', (tester) async {
  await pumpSteamActionCell(tester,
      hasPack: true, publishedSteamId: '123456');
  expect(find.widgetWithText(SmallTextButton, 'Update'), findsNothing);
  // Update button is a custom container; match by text.
  expect(find.text('Update'), findsOneWidget);
});
```

If `pumpSteamActionCell` does not exist, build a minimal harness in the same file that instantiates a `SteamActionCell` wrapped in `ProviderScope` with a fake `PublishableItem`.

- [ ] **Step 2: Run the test**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/steam_publish_action_cell_test.dart
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/features/steam_publish/widgets/steam_publish_action_cell_test.dart
git commit -m "test: lock Steam publish action-cell state machine"
```

---

## Task 12: Extend EmptyStateGuide to 5 steps

**Spec:** decision 7.

**Files:**
- Modify: `lib/features/home/widgets/empty_state_guide.dart`
- Test: `test/features/home/widgets/empty_state_guide_test.dart` (update or create)

- [ ] **Step 1: Write the failing test**

```dart
// test/features/home/widgets/empty_state_guide_test.dart
testWidgets('renders 5 steps', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: EmptyStateGuide())),
  );
  expect(find.byType(Card).or(find.byType(TokenCard)), findsNWidgets(5));
  expect(find.text('Detect your mods in Sources'), findsOneWidget);
  expect(find.text('Create a project from a mod'), findsOneWidget);
  expect(find.text('Translate the units'), findsOneWidget);
  expect(find.text('Compile your pack'), findsOneWidget);
  expect(find.text('Publish on Steam Workshop'), findsOneWidget);
});

testWidgets('Compile and Publish steps are disabled', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: EmptyStateGuide())),
  );
  // Tapping a disabled card must NOT navigate; we assert by probing the
  // internal flag via a Finder on the text's ancestor _Step widget.
  final compileStep = find.ancestor(
    of: find.text('Compile your pack'),
    matching: find.byType(GestureDetector),
  );
  expect(tester.widget<GestureDetector>(compileStep).onTap, isNull);
});
```

Use whichever matcher is actually appropriate for the disabled check — the important assertion is that `onTap` is `null` for steps 4 and 5.

- [ ] **Step 2: Run the test to verify it fails**

```bash
C:/src/flutter/bin/flutter test test/features/home/widgets/empty_state_guide_test.dart
```

Expected: FAIL — current widget only renders 3 steps.

- [ ] **Step 3: Update `empty_state_guide.dart`**

Replace the `build` method body and the `_Step` class with:

```dart
class EmptyStateGuide extends StatelessWidget {
  const EmptyStateGuide({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Step(
            number: 1,
            title: 'Detect your mods in Sources',
            ctaLabel: 'Go to Sources',
            onTap: () => context.go(AppRoutes.mods),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Step(
            number: 2,
            title: 'Create a project from a mod',
            ctaLabel: 'Open Sources',
            onTap: () => context.go(AppRoutes.mods),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Step(
            number: 3,
            title: 'Translate the units',
            ctaLabel: 'Open Projects',
            onTap: () => context.go(AppRoutes.projects),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Step(
            number: 4,
            title: 'Compile your pack',
            ctaLabel: null,
            onTap: null,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Step(
            number: 5,
            title: 'Publish on Steam Workshop',
            ctaLabel: null,
            onTap: null,
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String? ctaLabel;
  final VoidCallback? onTap;

  const _Step({
    required this.number,
    required this.title,
    required this.ctaLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: TokenCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: disabled ? tokens.panel2 : tokens.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: tokens.fontMono.copyWith(
                    fontSize: 14,
                    color: disabled ? tokens.textFaint : tokens.accentFg,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: tokens.fontBody.copyWith(
                  fontSize: 15,
                  color: disabled ? tokens.textDim : tokens.text,
                ),
              ),
              const SizedBox(height: 10),
              if (ctaLabel != null)
                Text(
                  ctaLabel!,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.accent,
                  ),
                )
              else
                const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
C:/src/flutter/bin/flutter test test/features/home/widgets/empty_state_guide_test.dart
```

Expected: PASS.

- [ ] **Step 5: Smoke-check layout at default window size**

```bash
C:/src/flutter/bin/flutter run -d windows
```

With zero projects on the selected game, open the Home screen and confirm the 5 cards fit readably. If cramped (text overflow, number badge colliding with title), switch to a 3 + 2 grid layout by wrapping the 5 steps in a `Wrap` or two `Row`s.

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/widgets/empty_state_guide.dart test/features/home/widgets/empty_state_guide_test.dart
git commit -m "feat: extend EmptyStateGuide to show the full 5-step journey"
```

---

# Phase 2 — Workshop onboarding card

## Task 4: WorkshopOnboardingCard widget + settings key

**Spec:** decision 6.

**Files:**
- Create: `lib/features/steam_publish/widgets/workshop_onboarding_card.dart`
- Create: `test/features/steam_publish/widgets/workshop_onboarding_card_test.dart`
- Modify: `lib/features/settings/providers/settings_providers.dart` — add key constant
- Modify: `lib/features/steam_publish/screens/steam_publish_screen.dart` — mount the card above the toolbar or list

- [ ] **Step 1: Add the settings key**

In `lib/features/settings/providers/settings_providers.dart`, inside `SettingsKeys`, add:

```dart
static const String workshopOnboardingCardHidden =
    'workshop_onboarding_card_hidden';
```

Keep alphabetical/grouping convention used by the existing file.

- [ ] **Step 2: Write the failing widget test**

```dart
// test/features/steam_publish/widgets/workshop_onboarding_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/widgets/workshop_onboarding_card.dart';

void main() {
  testWidgets('renders the educational message and the checkbox',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: WorkshopOnboardingCard()),
        ),
      ),
    );
    expect(
      find.textContaining('first publication goes through the in-game launcher'),
      findsOneWidget,
    );
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.textContaining("Don't show this again"), findsOneWidget);
  });

  testWidgets('toggling the checkbox and pressing Dismiss persists the hide',
      (tester) async {
    // The card hides itself after the user ticks and confirms.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: WorkshopOnboardingCard()),
        ),
      ),
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkshopOnboardingCard), findsOneWidget);
    // Re-pumping a fresh instance of the card should render as hidden
    // (returns an empty SizedBox). This is asserted in the integration-level
    // test on the screen, not here.
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/workshop_onboarding_card_test.dart
```

Expected: FAIL — widget does not exist.

- [ ] **Step 4: Create the widget**

```dart
// lib/features/steam_publish/widgets/workshop_onboarding_card.dart
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:twmt/features/settings/providers/settings_providers.dart'
    hide settingsServiceProvider;
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Workshop onboarding / educational card rendered at the top of the
/// Steam Publish screen. Visible every time by default; permanently hidden
/// only when the user ticks "Don't show this again" and confirms.
class WorkshopOnboardingCard extends ConsumerStatefulWidget {
  const WorkshopOnboardingCard({super.key});

  @override
  ConsumerState<WorkshopOnboardingCard> createState() =>
      _WorkshopOnboardingCardState();
}

class _WorkshopOnboardingCardState
    extends ConsumerState<WorkshopOnboardingCard> {
  bool _dontShowAgain = false;
  bool _hiddenForSession = false;
  bool _persistedHidden = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPersistedState();
  }

  Future<void> _loadPersistedState() async {
    try {
      final hidden = await ref
          .read(settingsServiceProvider)
          .getBool(SettingsKeys.workshopOnboardingCardHidden);
      if (!mounted) return;
      setState(() {
        _persistedHidden = hidden;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _dismiss() async {
    if (_dontShowAgain) {
      try {
        await ref.read(settingsServiceProvider).setBool(
              SettingsKeys.workshopOnboardingCardHidden,
              true,
            );
      } catch (_) {
        // Silently ignore persistence errors; hiding for the session is
        // still useful.
      }
    }
    if (!mounted) return;
    setState(() => _hiddenForSession = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (_persistedHidden || _hiddenForSession) {
      return const SizedBox.shrink();
    }
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.accentBg,
        border: Border.all(color: tokens.accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.info_24_regular,
                size: 18,
                color: tokens.accent,
              ),
              const SizedBox(width: 8),
              Text(
                'Publishing on the Steam Workshop',
                style: tokens.fontDisplay.copyWith(
                  fontSize: 14,
                  color: tokens.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The first publication goes through the in-game launcher. '
            'After you paste the Workshop ID here, all future updates are '
            'handled automatically from this screen.',
            style: tokens.fontBody
                .copyWith(fontSize: 13, color: tokens.textMid),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(
                value: _dontShowAgain,
                onChanged: (v) =>
                    setState(() => _dontShowAgain = v ?? false),
              ),
              Text(
                "Don't show this again",
                style: tokens.fontBody
                    .copyWith(fontSize: 12, color: tokens.textMid),
              ),
              const Spacer(),
              SmallTextButton(
                label: 'Dismiss',
                icon: FluentIcons.checkmark_24_regular,
                onTap: _dismiss,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run the widget test to verify it passes**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/workshop_onboarding_card_test.dart
```

Expected: PASS.

- [ ] **Step 6: Mount the card on `SteamPublishScreen`**

In `lib/features/steam_publish/screens/steam_publish_screen.dart`, inside the `build` method's main `Column` (currently starts with `SteamPublishToolbar` as its first child), insert the card as the first child:

```dart
return Material(
  color: tokens.bg,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const WorkshopOnboardingCard(),
      SteamPublishToolbar(
        // ...unchanged
      ),
      // ...
    ],
  ),
);
```

Add the import: `import '../widgets/workshop_onboarding_card.dart';`.

- [ ] **Step 7: Run the app and verify**

```bash
C:/src/flutter/bin/flutter run -d windows
```

Navigate to `Publish`. The card should appear above the toolbar. Tick "Don't show this again", click Dismiss, navigate away and back — card should be gone. Restart the app — card should still be hidden. Quit.

- [ ] **Step 8: Commit**

```bash
git add lib/features/steam_publish/widgets/workshop_onboarding_card.dart \
        lib/features/settings/providers/settings_providers.dart \
        lib/features/steam_publish/screens/steam_publish_screen.dart \
        test/features/steam_publish/widgets/workshop_onboarding_card_test.dart
git commit -m "feat: add Workshop onboarding card with opt-in persistent dismissal"
```

---

## Task 5: Settings — "Reset onboarding hints" button

**Spec:** decision 6 (follow-up).

**Files:**
- Modify: the Settings tab responsible for general / miscellaneous toggles. Use the Grep tool with pattern `SettingsKeys.` restricted to `lib/features/settings/` to find the correct tab. Add the button to the tab that already hosts "miscellaneous" toggles; otherwise add it to the general tab.

- [ ] **Step 1: Locate the tab**

Use Grep on `lib/features/settings/widgets/` for the filename ending in `_tab.dart` that handles generic app preferences. If none fits, add the button to `settings_screen.dart` directly in a clearly-labelled section at the bottom.

- [ ] **Step 2: Add the button and handler**

```dart
SmallTextButton(
  label: 'Reset onboarding hints',
  icon: FluentIcons.eye_24_regular,
  onTap: () async {
    await ref
        .read(settingsServiceProvider)
        .setBool(SettingsKeys.workshopOnboardingCardHidden, false);
    if (context.mounted) {
      FluentToast.success(context, 'Onboarding hints will show again.');
    }
  },
),
```

- [ ] **Step 3: Verify manually**

```bash
C:/src/flutter/bin/flutter run -d windows
```

Steps:
1. Go to `Publish`, dismiss the card with "Don't show again".
2. Open `Settings`, click `Reset onboarding hints`.
3. Go back to `Publish` — card must reappear.

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings/
git commit -m "feat: add Reset onboarding hints control in Settings"
```

---

# Phase 3 — Workshop guided publish (URL + launcher + checklist)

## Task 6: Workshop URL parser utility

**Spec:** decision 1.

**Files:**
- Create: `lib/features/steam_publish/utils/workshop_url_parser.dart`
- Create: `test/features/steam_publish/utils/workshop_url_parser_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/steam_publish/utils/workshop_url_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/utils/workshop_url_parser.dart';

void main() {
  group('parseWorkshopId', () {
    test('extracts the id from a full community URL', () {
      expect(
          parseWorkshopId(
              'https://steamcommunity.com/sharedfiles/filedetails/?id=3456789012'),
          '3456789012');
    });

    test('extracts the id from a bare URL without scheme', () {
      expect(
          parseWorkshopId(
              'steamcommunity.com/sharedfiles/filedetails/?id=3456789012'),
          '3456789012');
    });

    test('accepts a bare numeric id', () {
      expect(parseWorkshopId('3456789012'), '3456789012');
    });

    test('accepts a numeric id surrounded by whitespace', () {
      expect(parseWorkshopId('  3456789012  '), '3456789012');
    });

    test('returns null on empty input', () {
      expect(parseWorkshopId(''), isNull);
      expect(parseWorkshopId('   '), isNull);
    });

    test('returns null on non-numeric input without an id query param', () {
      expect(parseWorkshopId('not a url'), isNull);
    });

    test('returns null on URLs without an id param', () {
      expect(parseWorkshopId('https://steamcommunity.com/sharedfiles/'),
          isNull);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/utils/workshop_url_parser_test.dart
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement the parser**

```dart
// lib/features/steam_publish/utils/workshop_url_parser.dart

/// Extracts a numeric Steam Workshop ID from [raw].
///
/// Accepts:
/// - Bare numeric IDs ("3456789012")
/// - Full community URLs with an `?id=` query parameter
/// - URLs without scheme (the `Uri` parse will still surface the query)
///
/// Returns the ID as a String (digits only) or `null` when no ID can be
/// recovered. Whitespace is trimmed.
String? parseWorkshopId(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // Bare numeric id.
  if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;

  // Try URI parsing. Both with and without scheme.
  Uri? uri;
  try {
    uri = Uri.parse(trimmed.contains('://') ? trimmed : 'https://$trimmed');
  } on FormatException {
    return null;
  }

  final id = uri.queryParameters['id'];
  if (id != null && RegExp(r'^\d+$').hasMatch(id)) return id;
  return null;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/utils/workshop_url_parser_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/steam_publish/utils/workshop_url_parser.dart test/features/steam_publish/utils/workshop_url_parser_test.dart
git commit -m "feat: add Workshop URL/ID parser utility"
```

---

## Task 7: Game launcher opener service

**Spec:** decision 1.

**Files:**
- Create: `lib/services/platform/game_launcher_opener.dart`
- Create: `test/services/platform/game_launcher_opener_test.dart`

The launcher is the Steam client URL scheme `steam://run/<app_id>`. For TW:WH3 the App ID is `1142710` (already used in `WorkshopPublishScreen`). We use `url_launcher` which is already a dependency.

- [ ] **Step 1: Write the failing test**

```dart
// test/services/platform/game_launcher_opener_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/platform/game_launcher_opener.dart';

void main() {
  group('buildSteamRunUri', () {
    test('returns the Steam scheme URI for a given app id', () {
      final uri = buildSteamRunUri('1142710');
      expect(uri.scheme, 'steam');
      expect(uri.host, 'run');
      expect(uri.path, '/1142710');
    });

    test('throws on empty app id', () {
      expect(() => buildSteamRunUri(''), throwsArgumentError);
    });
  });
}
```

- [ ] **Step 2: Run the test**

```bash
C:/src/flutter/bin/flutter test test/services/platform/game_launcher_opener_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement the service**

```dart
// lib/services/platform/game_launcher_opener.dart
import 'package:url_launcher/url_launcher.dart';

/// Builds a `steam://run/<appId>` URI that, when launched, brings the Steam
/// client to the foreground and starts the game (which opens its built-in
/// Workshop launcher for the user).
Uri buildSteamRunUri(String appId) {
  if (appId.trim().isEmpty) {
    throw ArgumentError('appId must not be empty');
  }
  return Uri.parse('steam://run/$appId');
}

/// Opens the game launcher for [appId] using the Steam client.
///
/// Returns `true` if the launch was dispatched, `false` if it failed.
Future<bool> openGameLauncher(String appId) async {
  final uri = buildSteamRunUri(appId);
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri);
}
```

- [ ] **Step 4: Run the test**

```bash
C:/src/flutter/bin/flutter test test/services/platform/game_launcher_opener_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/platform/game_launcher_opener.dart test/services/platform/game_launcher_opener_test.dart
git commit -m "feat: add Steam client run URI service for launcher handoff"
```

---

## Task 8: Enhance SteamActionCell State B with URL parsing, launcher button, checklist

**Spec:** decision 1 + decision 5 (state B improvement).

**Files:**
- Modify: `lib/features/steam_publish/widgets/steam_publish_action_cell.dart`
- Test: `test/features/steam_publish/widgets/steam_publish_action_cell_test.dart` — add two new scenarios

Goals:
1. The Workshop ID TextField accepts full URLs — paste-friendly.
2. An "Open launcher" button appears next to the input to jump to the game launcher.
3. A compact two-line checklist sits below the input: "1. Publish from the launcher · 2. Copy the mod URL here".

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('State B accepts a full Workshop URL and saves the extracted id',
    (tester) async {
  final projectRepo = FakeProjectRepository();
  await pumpSteamActionCell(tester,
      hasPack: true,
      publishedSteamId: null,
      projectRepo: projectRepo);
  await tester.enterText(
    find.byType(TextField),
    'https://steamcommunity.com/sharedfiles/filedetails/?id=3456789012',
  );
  await tester.tap(find.byTooltip('Save Workshop id'));
  await tester.pumpAndSettle();
  expect(projectRepo.lastSavedSteamId, '3456789012');
});

testWidgets('State B shows the Open launcher button', (tester) async {
  await pumpSteamActionCell(tester,
      hasPack: true, publishedSteamId: null);
  expect(find.byTooltip('Open the in-game launcher'), findsOneWidget);
});

testWidgets('State B shows the two-step checklist', (tester) async {
  await pumpSteamActionCell(tester,
      hasPack: true, publishedSteamId: null);
  expect(find.textContaining('Publish from the launcher'), findsOneWidget);
  expect(find.textContaining('Copy the mod URL here'), findsOneWidget);
});
```

If the existing test harness does not expose `FakeProjectRepository` with a `lastSavedSteamId` getter, add a minimal one to the test file (the production code reads the repository from a Riverpod override).

- [ ] **Step 2: Run the tests to verify they fail**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/steam_publish_action_cell_test.dart
```

Expected: FAIL on the three new cases.

- [ ] **Step 3: Update the action cell**

Imports:

```dart
import 'package:twmt/features/steam_publish/utils/workshop_url_parser.dart';
import 'package:twmt/services/platform/game_launcher_opener.dart';
```

Remove the `digitsOnly` input formatter from `_buildSteamIdInput` and update the hint:

```dart
TextField(
  controller: _steamIdController,
  enabled: !_isSavingSteamId,
  style: tokens.fontMono.copyWith(
    fontSize: 12,
    color: tokens.text,
  ),
  decoration: InputDecoration(
    hintText: 'Paste Workshop URL or ID...',
    // ...other decoration unchanged
  ),
  // REMOVE: keyboardType and inputFormatters
  onSubmitted: (_) => _saveSteamId(),
),
```

Replace `_saveSteamId` with:

```dart
Future<void> _saveSteamId() async {
  final raw = _steamIdController.text;
  final steamId = parseWorkshopId(raw);
  if (steamId == null) {
    FluentToast.warning(
      context,
      "Couldn't read a Workshop ID from that value.",
    );
    return;
  }
  setState(() => _isSavingSteamId = true);

  try {
    final item = widget.item;
    if (item is ProjectPublishItem) {
      final projectRepo = ref.read(projectRepositoryProvider);
      final projectResult = await projectRepo.getById(item.project.id);
      if (projectResult.isOk) {
        final updated = projectResult.value.copyWith(
          publishedSteamId: steamId,
          updatedAt: projectResult.value.updatedAt,
        );
        await projectRepo.update(updated);
      }
    } else if (item is CompilationPublishItem) {
      final compilationRepo = ref.read(compilationRepositoryProvider);
      await compilationRepo.updateAfterPublish(
        item.compilation.id,
        steamId,
        item.publishedAt ?? 0,
      );
    }
    if (mounted) {
      setState(() => _isEditingSteamId = false);
      ref.invalidate(publishableItemsProvider);
    }
  } catch (e) {
    if (mounted) {
      FluentToast.error(context, 'Failed to save Workshop id: $e');
    }
  } finally {
    if (mounted) {
      setState(() => _isSavingSteamId = false);
    }
  }
}
```

Update the State B layout to include a launcher button and checklist. Replace `_buildSteamIdInput` body with a `Column` whose first row is the existing input row plus a launcher icon button, and whose second row is the checklist:

```dart
Widget _buildSteamIdInput(BuildContext context) {
  final tokens = context.tokens;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 28,
                child: TextField(
                  controller: _steamIdController,
                  enabled: !_isSavingSteamId,
                  style: tokens.fontMono
                      .copyWith(fontSize: 12, color: tokens.text),
                  decoration: InputDecoration(
                    hintText: 'Paste Workshop URL or ID...',
                    hintStyle: tokens.fontMono
                        .copyWith(fontSize: 12, color: tokens.textFaint),
                    isDense: true,
                    filled: true,
                    fillColor: tokens.panel2,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      borderSide: BorderSide(color: tokens.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      borderSide: BorderSide(color: tokens.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      borderSide: BorderSide(color: tokens.accent),
                    ),
                  ),
                  onSubmitted: (_) => _saveSteamId(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _iconButton(
              icon: FluentIcons.play_24_regular,
              tooltip: 'Open the in-game launcher',
              onTap: _openLauncher,
            ),
            const SizedBox(width: 4),
            _iconButton(
              icon: _isSavingSteamId ? null : FluentIcons.save_24_regular,
              tooltip: 'Save Workshop id',
              onTap: _isSavingSteamId ? null : _saveSteamId,
              busy: _isSavingSteamId,
              accent: true,
            ),
            if (_isEditingSteamId) ...[
              const SizedBox(width: 4),
              _iconButton(
                icon: FluentIcons.dismiss_24_regular,
                tooltip: 'Cancel',
                onTap: () {
                  _steamIdController.clear();
                  setState(() => _isEditingSteamId = false);
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '1. Publish from the launcher · 2. Copy the mod URL here',
          style: tokens.fontMono
              .copyWith(fontSize: 10, color: tokens.textFaint),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

Future<void> _openLauncher() async {
  final ok = await openGameLauncher('1142710'); // TW:WH3
  if (!ok && mounted) {
    FluentToast.warning(
      context,
      'Could not open the Steam client. Is Steam installed?',
    );
  }
}
```

> Note: the `1142710` App ID is hard-coded for parity with `WorkshopPublishScreen` (see `workshop_publish_screen.dart` line 266 and `steam_publish_screen.dart` line 279). If the project gains multi-game support later, this becomes a per-game parameter.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
C:/src/flutter/bin/flutter test test/features/steam_publish/widgets/steam_publish_action_cell_test.dart
```

Expected: PASS on all state cases including the three new ones.

- [ ] **Step 5: Smoke-check end-to-end**

```bash
C:/src/flutter/bin/flutter run -d windows
```

1. Find a project with a generated pack and no Workshop ID.
2. Confirm the row now shows: input field (URL or ID), play-icon launcher button, save icon, and the checklist below.
3. Paste a full Workshop URL, save, and confirm the ID persists.

- [ ] **Step 6: Commit**

```bash
git add lib/features/steam_publish/widgets/steam_publish_action_cell.dart test/features/steam_publish/widgets/steam_publish_action_cell_test.dart
git commit -m "feat: guide Workshop publish with launcher button, URL parse, checklist"
```

---

# Phase 4 — Next step CTA

## Task 9: `NextStepCta` widget

**Spec:** decision 3.

**Files:**
- Create: `lib/widgets/workflow/next_step_cta.dart`
- Create: `test/widgets/workflow/next_step_cta_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/widgets/workflow/next_step_cta_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/widgets/workflow/next_step_cta.dart';

void main() {
  testWidgets('renders label and invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NextStepCta(
            label: 'Compile this pack',
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    expect(find.text('Next: Compile this pack'), findsOneWidget);
    await tester.tap(find.byType(NextStepCta));
    expect(tapped, isTrue);
  });

  testWidgets('renders disabled when onTap is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NextStepCta(label: 'Compile this pack', onTap: null),
        ),
      ),
    );
    final gesture = tester.widget<GestureDetector>(
        find.descendant(
            of: find.byType(NextStepCta),
            matching: find.byType(GestureDetector)));
    expect(gesture.onTap, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
C:/src/flutter/bin/flutter test test/widgets/workflow/next_step_cta_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement the widget**

```dart
// lib/widgets/workflow/next_step_cta.dart
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Compact accent card surfaced at the end of a workflow screen to nudge the
/// user toward the next pipeline step. Reads "Next: <label>" and routes via
/// [onTap]. Disabled when [onTap] is `null`.
class NextStepCta extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData icon;

  const NextStepCta({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = FluentIcons.arrow_right_24_regular,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final disabled = onTap == null;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: disabled ? tokens.panel2 : tokens.accentBg,
            border: Border.all(
              color: disabled ? tokens.border : tokens.accent,
            ),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: disabled ? tokens.textFaint : tokens.accent,
              ),
              const SizedBox(width: 8),
              Text(
                'Next: $label',
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: disabled ? tokens.textFaint : tokens.accent,
                  fontWeight: FontWeight.w600,
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

- [ ] **Step 4: Run the test to verify it passes**

```bash
C:/src/flutter/bin/flutter test test/widgets/workflow/next_step_cta_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/workflow/next_step_cta.dart test/widgets/workflow/next_step_cta_test.dart
git commit -m "feat: add NextStepCta widget for workflow hand-offs"
```

---

## Task 10: Integrate `NextStepCta` on the Pack Compilation Editor

**Spec:** decision 3.

**Files:**
- Read: `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart`
- Modify: same file — surface the CTA when a compile has succeeded (the output pack file exists).

- [ ] **Step 1: Read the editor screen and locate the post-compile state**

Use the Read tool on `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart`. Locate the state variable / provider that indicates "compilation finished successfully" (likely a `PhaseState` / `status` enum field or a flag set in the notifier on success). If a single scalar is not available, surface the CTA when both: (a) an output pack file path is set, and (b) the last progress phase was `completed`.

- [ ] **Step 2: Insert the CTA in the success branch**

In the same area that today shows the "Compilation finished" success banner or toast, add a `NextStepCta` rendered below the banner:

```dart
import 'package:twmt/widgets/workflow/next_step_cta.dart';
// ...
NextStepCta(
  label: 'Publish on Steam Workshop',
  icon: FluentIcons.cloud_arrow_up_24_regular,
  onTap: () => context.goSteamPublish(),
),
```

Place it inside the same `Column` / `SingleChildScrollView` that hosts the success block. If the editor uses the wizard's `DynamicZonePanel`, add the CTA to the `done` sub-view.

- [ ] **Step 3: Add a widget test**

Create or extend the editor test to assert that after a successful compile the CTA is present and tapping it pushes the route `/publishing/steam`.

- [ ] **Step 4: Run the test**

```bash
C:/src/flutter/bin/flutter test test/features/pack_compilation/
```

Expected: all pack-compilation tests PASS.

- [ ] **Step 5: Smoke-check**

```bash
C:/src/flutter/bin/flutter run -d windows
```

Compile a small pack end-to-end. After success, confirm the CTA appears and routes correctly.

- [ ] **Step 6: Commit**

```bash
git add lib/features/pack_compilation/ test/features/pack_compilation/
git commit -m "feat: show Next-step CTA on successful pack compilation"
```

---

## Task 11: Integrate `NextStepCta` on the Translation Editor

**Spec:** decision 3.

**Files:**
- Read: `lib/features/translation_editor/screens/translation_editor_screen.dart`
- Modify: same file — surface the CTA when the language's progress reaches 100 % (or when all visible units have a non-empty translation).

Translation "done-ness" is a softer concept than compile success. The CTA should appear only when the current language shows 100 % progress in its `projectLanguage.progressPercent` (or equivalent). For an ambiguous case (e.g. 99.x %), keep the CTA hidden to avoid false positives.

- [ ] **Step 1: Read the screen and locate the progress provider**

Use the Read tool on `lib/features/translation_editor/screens/translation_editor_screen.dart` and identify the provider that exposes current-language progress. If none is directly available, compute it locally from the visible units.

- [ ] **Step 2: Insert the CTA in the toolbar trailing area or footer**

If the toolbar has a `trailing` slot, add:

```dart
if (progress >= 1.0)
  NextStepCta(
    label: 'Compile this pack',
    icon: FluentIcons.box_multiple_24_regular,
    onTap: () => context.goPackCompilation(),
  ),
```

Otherwise place the CTA at the bottom of the screen above the status bar.

- [ ] **Step 3: Test**

Add a widget test that pumps the editor with a fully-translated language and asserts the CTA is present and tappable.

```bash
C:/src/flutter/bin/flutter test test/features/translation_editor/
```

- [ ] **Step 4: Smoke-check**

```bash
C:/src/flutter/bin/flutter run -d windows
```

Open a language that is 100 % translated. Confirm the CTA is visible and routes to Pack Compilation. Open an incomplete language and confirm the CTA is hidden.

- [ ] **Step 5: Commit**

```bash
git add lib/features/translation_editor/ test/features/translation_editor/
git commit -m "feat: show Next-step CTA when a translation reaches 100%"
```

---

# Verification after all phases

- [ ] **Run the full test suite**

```bash
C:/src/flutter/bin/flutter test
```

Expected: full suite PASS. Fix any regressions before considering the plan complete.

- [ ] **Build-runner sanity check**

```bash
C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs
```

Expected: no new generated-file drift.

- [ ] **Desktop launch sanity check**

```bash
C:/src/flutter/bin/flutter run -d windows
```

Manually exercise:
1. Home → empty-state shows 5 steps (in a freshly-installed / no-projects game).
2. Sidebar has 4 groups: Workflow, Work, Resources, System.
3. `Publish` shows the onboarding card on first visit.
4. Dismissing with "Don't show again" persists across restart.
5. `Settings → Reset onboarding hints` re-enables the card.
6. Project with a pack but no Workshop ID: input accepts a full URL, launcher button opens Steam, checklist text visible.
7. Compile a pack: Next CTA → Steam Workshop.
8. Complete a translation: Next CTA → Pack Compilation.

- [ ] **Final commit / PR (caller decides)**

After the verification run is clean, either squash-merge the feature branch or open a PR per the repository's workflow. No CLAUDE.md changes needed.
