# Clickable crumbs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every non-edge segment of the detail/wizard toolbar crumb clickable (navigating to its route), render the current segment in bold, and keep in-progress operation guards in effect on crumb taps.

**Architecture:** Introduce a typed `CrumbSegment(label, route?)` and change `DetailScreenToolbar` from `StatelessWidget` to `ConsumerWidget`, replacing its single `String crumb` with `List<CrumbSegment> crumbs`. Extract the existing in-progress-operation guard from `MainLayoutRouter` into a shared helper `canNavigateNow(BuildContext, WidgetRef)` used both by the sidebar navigation path and by crumb taps. Migrate the 5 feature screens (6 files, since workshop screens have empty-state + regular variants) from the string crumb to the typed list.

**Tech Stack:** Flutter, Riverpod (generator-style via `*.g.dart`), go_router, FluentUI system icons.

---

## File Structure

- **Create:** `lib/config/router/navigation_guard.dart` — top-level `canNavigateNow(BuildContext, WidgetRef)` helper that reads `translationInProgressProvider` + `compilationInProgressProvider` and emits the same toast as today.
- **Create:** `test/config/router/navigation_guard_test.dart` — unit tests for the helper.
- **Create:** `lib/widgets/detail/crumb_segment.dart` — `CrumbSegment` value type (colocated in `detail/` to stay close to its consumer).
- **Modify:** `lib/widgets/detail/detail_screen_toolbar.dart` — `ConsumerWidget`, new `crumbs: List<CrumbSegment>` API, renders segments + separator + hover underline + bold-last + tap-with-guard.
- **Modify:** `test/widgets/detail/detail_screen_toolbar_test.dart` — rewrite for the new API (first task-local tests use old API, final task migrates all).
- **Modify:** `lib/widgets/layouts/main_layout_router.dart` — remove private `_canNavigate`, call shared helper.
- **Modify (6 screens):**
  - `lib/features/projects/screens/project_detail_screen.dart`
  - `lib/features/translation_editor/screens/translation_editor_screen.dart`
  - `lib/features/glossary/screens/glossary_screen.dart`
  - `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart`
  - `lib/features/steam_publish/screens/workshop_publish_screen.dart` (2 `DetailScreenToolbar` sites)
  - `lib/features/steam_publish/screens/batch_workshop_publish_screen.dart` (2 sites)
- **Modify tests that assert on the crumb string:**
  - `test/features/translation_editor/screens/translation_editor_screen_test.dart` (line 263 uses `textContaining('Work › Projects › Test Project › Spanish')`).
- The existing steam_publish tests rely on `textContaining('No pack')` / `textContaining('No items')` — those still match individual segment Text widgets and stay as-is.

---

## Task 1: Extract navigation guard helper

**Files:**
- Create: `lib/config/router/navigation_guard.dart`
- Create: `test/config/router/navigation_guard_test.dart`
- Modify: `lib/widgets/layouts/main_layout_router.dart`

- [ ] **Step 1: Write the failing guard unit test**

Create `test/config/router/navigation_guard_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/config/router/navigation_guard.dart';
import 'package:twmt/features/pack_compilation/providers/pack_compilation_providers.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';

void main() {
  Widget host(WidgetRef Function(WidgetRef) capture) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (ctx, ref, _) {
            capture(ref);
            return const SizedBox();
          }),
        ),
      ),
    );
  }

  testWidgets('returns true when no operation is in progress', (t) async {
    late WidgetRef captured;
    await t.pumpWidget(host((ref) => captured = ref));
    await t.pumpAndSettle();
    // `captured` was set by the Consumer builder during pump.
    expect(
      canNavigateNow(captured.context, captured),
      isTrue,
    );
  });

  testWidgets('returns false when translation is in progress', (t) async {
    late WidgetRef captured;
    await t.pumpWidget(ProviderScope(
      overrides: [
        translationInProgressProvider.overrideWith((ref) => true),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (ctx, ref, _) {
            captured = ref;
            return const SizedBox();
          }),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(
      canNavigateNow(captured.context, captured),
      isFalse,
    );
  });

  testWidgets('returns false when compilation is in progress', (t) async {
    late WidgetRef captured;
    await t.pumpWidget(ProviderScope(
      overrides: [
        compilationInProgressProvider.overrideWith((ref) => true),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (ctx, ref, _) {
            captured = ref;
            return const SizedBox();
          }),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(
      canNavigateNow(captured.context, captured),
      isFalse,
    );
  });
}
```

Note: `WidgetRef.context` exists via `ref.context` — the helper accepts a separate `BuildContext` so callers can pass `context` explicitly (clearer intent when the helper emits a toast tied to the current widget tree).

If `overrideWith` doesn't match the exact provider signature of `translationInProgressProvider` / `compilationInProgressProvider`, inspect their declarations (look at `lib/features/translation_editor/providers/editor_providers.dart` and `lib/features/pack_compilation/providers/pack_compilation_providers.dart`) and use the appropriate override form (`overrideWith` for Notifier-based, or direct assignment for state providers). Do not guess — read the provider declarations first.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/config/router/navigation_guard_test.dart`
Expected: FAIL — `navigation_guard.dart` does not exist / `canNavigateNow` undefined.

- [ ] **Step 3: Create the helper**

Create `lib/config/router/navigation_guard.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/pack_compilation/providers/pack_compilation_providers.dart';
import '../../features/translation_editor/providers/editor_providers.dart';
import '../../widgets/fluent/fluent_widgets.dart';

/// Returns `true` if it is safe to navigate away from the current screen.
///
/// When a translation or pack compilation is in progress, this emits the
/// matching warning toast on [context] and returns `false`. Callers should
/// short-circuit their navigation on a `false` result.
///
/// Shared between the sidebar ([MainLayoutRouter]) and the detail-screen
/// crumb tap handler.
bool canNavigateNow(BuildContext context, WidgetRef ref) {
  if (ref.read(translationInProgressProvider)) {
    FluentToast.warning(
      context,
      'Translation in progress. Stop the translation first.',
    );
    return false;
  }
  if (ref.read(compilationInProgressProvider)) {
    FluentToast.warning(
      context,
      'Pack generation in progress. Stop the generation first.',
    );
    return false;
  }
  return true;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/config/router/navigation_guard_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Refactor `MainLayoutRouter` to use the helper**

In `lib/widgets/layouts/main_layout_router.dart`:

- Remove the private `_canNavigate` method and its duplicate toast logic.
- Remove the now-unused imports of `../fluent/fluent_widgets.dart`, editor_providers, pack_compilation_providers.
- Add `import '../../config/router/navigation_guard.dart';`.
- Replace `if (_canNavigate(context, ref)) context.go(p);` with
  `if (canNavigateNow(context, ref)) context.go(p);`.

The file shrinks to:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/navigation_guard.dart';
import '../navigation/navigation_sidebar.dart';
import 'fluent_scaffold.dart';

/// Shell layout: sidebar + active screen.
///
/// Each screen renders its own toolbar/header; the in-progress-operation guard
/// is shared with crumb taps via [canNavigateNow].
class MainLayoutRouter extends ConsumerWidget {
  const MainLayoutRouter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FluentScaffold(
      body: Row(
        children: [
          NavigationSidebar(
            onNavigate: (p) {
              if (canNavigateNow(context, ref)) context.go(p);
            },
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Run the full test suite to confirm no regression**

Run: `flutter test`
Expected: PASS (same count as before + 3 new navigation_guard tests).

- [ ] **Step 7: Commit**

```bash
git add lib/config/router/navigation_guard.dart \
        test/config/router/navigation_guard_test.dart \
        lib/widgets/layouts/main_layout_router.dart
git commit -m "refactor: extract in-progress navigation guard into shared helper"
```

---

## Task 2: Introduce `CrumbSegment` + new `DetailScreenToolbar` API (additive)

**Files:**
- Create: `lib/widgets/detail/crumb_segment.dart`
- Modify: `lib/widgets/detail/detail_screen_toolbar.dart`
- Test: `test/widgets/detail/detail_screen_toolbar_test.dart` (add new-API tests alongside existing ones)

- [ ] **Step 1: Create the `CrumbSegment` type**

Create `lib/widgets/detail/crumb_segment.dart`:

```dart
/// One segment of a detail-screen crumb trail.
///
/// [route] is the absolute path to navigate to when the segment is tapped.
/// When `null`, the segment is rendered as plain text (non-clickable). By
/// convention, the first and last segments of a crumb list have `route: null`.
class CrumbSegment {
  final String label;
  final String? route;

  const CrumbSegment(this.label, {this.route});
}
```

- [ ] **Step 2: Write failing tests for the new `crumbs:` API**

At the top of `test/widgets/detail/detail_screen_toolbar_test.dart`, keep the existing `wrap(child)` helper. Replace its body with a `ProviderScope`-wrapping version (the widget is about to become a `ConsumerWidget`):

```dart
Widget wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      ),
    );
```

Append the following new test group at the bottom of the `main()` body (the existing `crumb: 'X'` tests stay; the final task (9) deletes them):

```dart
group('crumbs API (new)', () {
  testWidgets('renders each segment with "›" separators between them',
      (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumbs: const [
        CrumbSegment('Work'),
        CrumbSegment('Projects', route: '/work/projects'),
        CrumbSegment('Foo'),
      ],
      onBack: () {},
    )));
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Foo'), findsOneWidget);
    // Two separators for three segments.
    expect(find.text('›'), findsNWidgets(2));
  });

  testWidgets('last segment is bold and uses tokens.text', (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumbs: const [
        CrumbSegment('Work'),
        CrumbSegment('Projects', route: '/work/projects'),
        CrumbSegment('Foo'),
      ],
      onBack: () {},
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final last = t.widget<Text>(find.text('Foo'));
    expect(last.style?.fontWeight, FontWeight.w600);
    expect(last.style?.color, tokens.text);
  });

  testWidgets('first segment is non-clickable (no MouseRegion.click)',
      (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumbs: const [
        CrumbSegment('Work'),
        CrumbSegment('Projects', route: '/work/projects'),
        CrumbSegment('Foo'),
      ],
      onBack: () {},
    )));
    // The "Work" segment has no GestureDetector ancestor.
    expect(
      find.ancestor(
        of: find.text('Work'),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });

  testWidgets('middle clickable segment has a GestureDetector ancestor',
      (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumbs: const [
        CrumbSegment('Work'),
        CrumbSegment('Projects', route: '/work/projects'),
        CrumbSegment('Foo'),
      ],
      onBack: () {},
    )));
    expect(
      find.ancestor(
        of: find.text('Projects'),
        matching: find.byType(GestureDetector),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tap on middle segment navigates via go_router', (t) async {
    final router = GoRouter(
      initialLocation: '/work/projects/42',
      routes: [
        GoRoute(
          path: '/work/projects/42',
          builder: (_, __) => Scaffold(
            body: DetailScreenToolbar(
              crumbs: const [
                CrumbSegment('Work'),
                CrumbSegment('Projects', route: '/work/projects'),
                CrumbSegment('Foo'),
              ],
              onBack: () {},
            ),
          ),
        ),
        GoRoute(
          path: '/work/projects',
          builder: (_, __) =>
              const Scaffold(body: Text('PROJECTS_LIST_PAGE')),
        ),
      ],
    );
    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(
        theme: AppTheme.atelierDarkTheme,
        routerConfig: router,
      ),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text('Projects'));
    await t.pumpAndSettle();

    expect(find.text('PROJECTS_LIST_PAGE'), findsOneWidget);
  });

  testWidgets(
    'tap is suppressed when translation is in progress',
    (t) async {
      var navigated = false;
      final router = GoRouter(
        initialLocation: '/a',
        routes: [
          GoRoute(
            path: '/a',
            builder: (_, __) => Scaffold(
              body: DetailScreenToolbar(
                crumbs: const [
                  CrumbSegment('Work'),
                  CrumbSegment('Projects', route: '/b'),
                  CrumbSegment('Foo'),
                ],
                onBack: () {},
              ),
            ),
          ),
          GoRoute(
            path: '/b',
            builder: (_, __) {
              navigated = true;
              return const Scaffold(body: Text('B'));
            },
          ),
        ],
      );
      await t.pumpWidget(ProviderScope(
        overrides: [
          translationInProgressProvider.overrideWith((ref) => true),
        ],
        child: MaterialApp.router(
          theme: AppTheme.atelierDarkTheme,
          routerConfig: router,
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('Projects'));
      await t.pumpAndSettle();
      expect(navigated, isFalse);
    },
  );
});
```

Add the required imports at the top of the test file:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/widgets/detail/crumb_segment.dart';
```

(Keep the existing imports.)

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/widgets/detail/detail_screen_toolbar_test.dart`
Expected: old tests PASS (still using `crumb: String`), new-group tests FAIL (parameter `crumbs` not recognised on `DetailScreenToolbar`).

- [ ] **Step 4: Implement the new `DetailScreenToolbar`**

Rewrite `lib/widgets/detail/detail_screen_toolbar.dart` to:

1. Convert to `ConsumerWidget` (needs `ref` for the navigation guard).
2. Keep `crumb: String?` as a deprecated fallback. Add `crumbs: List<CrumbSegment>?`. Require exactly one to be non-null via an `assert`.
3. Render the `crumbs` path when present; otherwise render the legacy `crumb` Text.
4. Rendering details for `crumbs`:
   - `Row` wrapping a `DefaultTextStyle` whose base style is `tokens.fontMono` 12px letterSpacing 0.5 `tokens.textDim`.
   - `Expanded` around the whole row so ellipsis still works at the far right.
   - Interleave segments with a separator `Text('›', style: … tokens.textFaint …)` with 6px horizontal gaps on each side.
   - Each `CrumbSegment` is rendered by a small private `_CrumbLabel` widget.
   - First segment (`index == 0`) and last segment (`index == crumbs.length - 1`): non-clickable. The last uses `tokens.text` + `FontWeight.w600`; the first uses default dim style.
   - Middle segments: clickable when `segment.route != null` (by our call-site convention all middle segments will have a route; defensive check anyway).
5. `_CrumbLabel` (StatefulWidget) handles hover:
   - `MouseRegion(cursor: clickable ? SystemMouseCursors.click : SystemMouseCursors.basic, onEnter: …, onExit: …)`.
   - Wraps a `GestureDetector(onTap: …)` when clickable.
   - Renders a `Text` whose `style.decoration` is `TextDecoration.underline` on hover, `TextDecoration.none` otherwise.
6. Tap handler: call `canNavigateNow(context, ref)`; if true, `context.go(segment.route!)`.

Here is the full replacement file:

```dart
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/navigation_guard.dart';
import '../../theme/twmt_theme_tokens.dart';
import '../lists/small_icon_button.dart';
import 'crumb_segment.dart';

/// Detail-screen top toolbar (§7.2 / §7.5).
///
/// 48px fixed height with a back button, a crumb trail, and optional trailing
/// widgets. The crumb trail renders each [CrumbSegment]: the first and last
/// segments are plain text (last in bold, marking the current screen); any
/// middle segment with a non-null `route` is clickable and navigates via
/// [GoRouter] after passing the [canNavigateNow] guard.
class DetailScreenToolbar extends ConsumerWidget {
  final List<CrumbSegment>? crumbs;

  /// Legacy single-string API. Deprecated; kept temporarily so the migration
  /// of individual feature screens can be staged commit by commit. Will be
  /// removed in the final task of this plan.
  final String? crumb;

  final VoidCallback onBack;
  final List<Widget> trailing;

  const DetailScreenToolbar({
    super.key,
    this.crumbs,
    this.crumb,
    required this.onBack,
    this.trailing = const [],
  }) : assert(
          (crumbs == null) != (crumb == null),
          'DetailScreenToolbar requires exactly one of `crumbs` or `crumb`.',
        );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          SmallIconButton(
            icon: FluentIcons.arrow_left_24_regular,
            tooltip: 'Back',
            onTap: onBack,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: crumbs != null
                ? _CrumbTrail(crumbs: crumbs!)
                : Text(
                    crumb!,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.fontMono.copyWith(
                      fontSize: 12,
                      color: tokens.textDim,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: 12),
            ...trailing,
          ],
        ],
      ),
    );
  }
}

class _CrumbTrail extends ConsumerWidget {
  final List<CrumbSegment> crumbs;
  const _CrumbTrail({required this.crumbs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final baseStyle = tokens.fontMono.copyWith(
      fontSize: 12,
      color: tokens.textDim,
      letterSpacing: 0.5,
    );
    final sep = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text('›', style: baseStyle.copyWith(color: tokens.textFaint)),
    );

    final children = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      if (i > 0) children.add(sep);
      final s = crumbs[i];
      final isFirst = i == 0;
      final isLast = i == crumbs.length - 1;
      children.add(_CrumbLabel(
        segment: s,
        isFirst: isFirst,
        isLast: isLast,
        baseStyle: baseStyle,
        currentStyle: baseStyle.copyWith(
          color: tokens.text,
          fontWeight: FontWeight.w600,
        ),
        onTap: (isFirst || isLast || s.route == null)
            ? null
            : () {
                if (canNavigateNow(context, ref)) {
                  context.go(s.route!);
                }
              },
      ));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _CrumbLabel extends StatefulWidget {
  final CrumbSegment segment;
  final bool isFirst;
  final bool isLast;
  final TextStyle baseStyle;
  final TextStyle currentStyle;
  final VoidCallback? onTap;

  const _CrumbLabel({
    required this.segment,
    required this.isFirst,
    required this.isLast,
    required this.baseStyle,
    required this.currentStyle,
    required this.onTap,
  });

  @override
  State<_CrumbLabel> createState() => _CrumbLabelState();
}

class _CrumbLabelState extends State<_CrumbLabel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final clickable = widget.onTap != null;
    final style = widget.isLast ? widget.currentStyle : widget.baseStyle;
    final effective = clickable && _hovered
        ? style.copyWith(decoration: TextDecoration.underline)
        : style;

    final label = Text(
      widget.segment.label,
      style: effective,
      overflow: TextOverflow.ellipsis,
    );

    if (!clickable) return label;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: label,
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/widgets/detail/detail_screen_toolbar_test.dart`
Expected: all tests PASS (existing `crumb:` tests + new `crumbs:` tests).

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: PASS — no other tests broken (the old `crumb:` API is still supported).

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/detail/crumb_segment.dart \
        lib/widgets/detail/detail_screen_toolbar.dart \
        test/widgets/detail/detail_screen_toolbar_test.dart
git commit -m "feat: add clickable CrumbSegment API to DetailScreenToolbar"
```

---

## Task 3: Migrate `project_detail_screen.dart`

**Files:**
- Modify: `lib/features/projects/screens/project_detail_screen.dart:246-250`

- [ ] **Step 1: Replace the `crumb:` call with `crumbs:`**

In `lib/features/projects/screens/project_detail_screen.dart`, add the import:

```dart
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/widgets/detail/crumb_segment.dart';
```

(Check the existing imports — `AppRoutes` may already be imported. If not, add it.)

Replace:

```dart
DetailScreenToolbar(
  crumb:
      'Work › Projects › ${p.name}',
  onBack: onBack,
),
```

with:

```dart
DetailScreenToolbar(
  crumbs: [
    const CrumbSegment('Work'),
    const CrumbSegment('Projects', route: AppRoutes.projects),
    CrumbSegment(p.name),
  ],
  onBack: onBack,
),
```

- [ ] **Step 2: Run related tests**

Run: `flutter test test/features/projects/`
Expected: PASS (project screen tests don't assert on the crumb string).

- [ ] **Step 3: Commit**

```bash
git add lib/features/projects/screens/project_detail_screen.dart
git commit -m "refactor: use CrumbSegment list in project detail toolbar"
```

---

## Task 4: Migrate `translation_editor_screen.dart`

**Files:**
- Modify: `lib/features/translation_editor/screens/translation_editor_screen.dart:84-93`
- Modify: `test/features/translation_editor/screens/translation_editor_screen_test.dart:255-267`

- [ ] **Step 1: Update the screen**

Add imports (if not already present):

```dart
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/widgets/detail/crumb_segment.dart';
```

Replace:

```dart
DetailScreenToolbar(
  crumb: 'Work › Projects › $projectName › $languageName',
  onBack: () { … },
),
```

with:

```dart
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
  onBack: () { … },  // keep existing onBack body unchanged
),
```

- [ ] **Step 2: Update the failing widget test**

In `test/features/translation_editor/screens/translation_editor_screen_test.dart`, replace the single `textContaining` assertion (line 263) with per-segment checks:

```dart
expect(find.byType(DetailScreenToolbar), findsOneWidget);
expect(find.text('Work'), findsOneWidget);
expect(find.text('Projects'), findsOneWidget);
expect(find.text('Test Project'), findsOneWidget);
expect(find.text('Spanish'), findsOneWidget);
// Three separators between four segments.
expect(find.text('›'), findsNWidgets(3));
expect(find.byTooltip('Back'), findsOneWidget);
```

- [ ] **Step 3: Run the updated test**

Run: `flutter test test/features/translation_editor/screens/translation_editor_screen_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/features/translation_editor/screens/translation_editor_screen.dart \
        test/features/translation_editor/screens/translation_editor_screen_test.dart
git commit -m "refactor: use CrumbSegment list in translation editor toolbar"
```

---

## Task 5: Migrate `glossary_screen.dart`

**Files:**
- Modify: `lib/features/glossary/screens/glossary_screen.dart:235-239`

- [ ] **Step 1: Update the screen**

Add imports (if missing):

```dart
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/widgets/detail/crumb_segment.dart';
```

Replace:

```dart
DetailScreenToolbar(
  crumb: 'Resources › Glossary › ${glossary.name}',
  onBack: () =>
      ref.read(selectedGlossaryProvider.notifier).clear(),
),
```

with:

```dart
DetailScreenToolbar(
  crumbs: [
    const CrumbSegment('Resources'),
    const CrumbSegment('Glossary', route: AppRoutes.glossary),
    CrumbSegment(glossary.name),
  ],
  onBack: () =>
      ref.read(selectedGlossaryProvider.notifier).clear(),
),
```

- [ ] **Step 2: Run related tests**

Run: `flutter test test/features/glossary/`
Expected: PASS (or "no tests found" — both acceptable).

Also run: `flutter test`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/features/glossary/screens/glossary_screen.dart
git commit -m "refactor: use CrumbSegment list in glossary detail toolbar"
```

---

## Task 6: Migrate `pack_compilation_editor_screen.dart` (normalize separator)

**Files:**
- Modify: `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart:167-172`

Note: current crumb uses `>` (ASCII). New segments use `›` (U+203A) from the toolbar separator — this normalization is automatic since the separator is now controlled by `DetailScreenToolbar`.

- [ ] **Step 1: Update the screen**

Add imports (if missing):

```dart
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/widgets/detail/crumb_segment.dart';
```

Replace:

```dart
toolbar: DetailScreenToolbar(
  crumb: state.isEditing
      ? 'Publishing > Pack compilation > ${state.name.isEmpty ? "Untitled" : state.name}'
      : 'Publishing > Pack compilation > New',
  onBack: _handleBack,
),
```

with:

```dart
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
```

- [ ] **Step 2: Run related tests**

Run: `flutter test test/features/pack_compilation/`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart
git commit -m "refactor: use CrumbSegment list in pack compilation editor toolbar"
```

---

## Task 7: Migrate `workshop_publish_screen.dart` (both call sites)

**Files:**
- Modify: `lib/features/steam_publish/screens/workshop_publish_screen.dart:325-330` (empty-state) and `:387-390` (main)

- [ ] **Step 1: Update the screen**

Add imports (if missing):

```dart
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/widgets/detail/crumb_segment.dart';
```

Replace the empty-state toolbar:

```dart
DetailScreenToolbar(
  crumb: 'Publishing > Steam Workshop > No pack staged',
  onBack: () { if (context.canPop()) context.pop(); },
),
```

with:

```dart
DetailScreenToolbar(
  crumbs: const [
    CrumbSegment('Publishing'),
    CrumbSegment('Steam Workshop', route: AppRoutes.steamPublish),
    CrumbSegment('No pack staged'),
  ],
  onBack: () { if (context.canPop()) context.pop(); },
),
```

Replace the main toolbar:

```dart
toolbar: DetailScreenToolbar(
  crumb:
      'Publishing > Steam Workshop > ${_projectName()}',
  onBack: _handleBack,
  trailing: [ … ],
),
```

with:

```dart
toolbar: DetailScreenToolbar(
  crumbs: [
    const CrumbSegment('Publishing'),
    const CrumbSegment('Steam Workshop', route: AppRoutes.steamPublish),
    CrumbSegment(_projectName()),
  ],
  onBack: _handleBack,
  trailing: [ … ],  // keep trailing content unchanged
),
```

- [ ] **Step 2: Run related tests**

Run: `flutter test test/features/steam_publish/screens/workshop_publish_screen_test.dart`
Expected: PASS (existing assertion `textContaining('No pack')` still matches the "No pack staged" segment).

- [ ] **Step 3: Commit**

```bash
git add lib/features/steam_publish/screens/workshop_publish_screen.dart
git commit -m "refactor: use CrumbSegment list in workshop publish toolbar"
```

---

## Task 8: Migrate `batch_workshop_publish_screen.dart` (both call sites)

**Files:**
- Modify: `lib/features/steam_publish/screens/batch_workshop_publish_screen.dart:183-188` (empty-state) and `:235-239` (main)

- [ ] **Step 1: Update the screen**

Add imports (if missing):

```dart
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/widgets/detail/crumb_segment.dart';
```

Replace the empty-state toolbar:

```dart
DetailScreenToolbar(
  crumb: 'Publishing > Steam Workshop > No items staged',
  onBack: () { if (context.canPop()) context.pop(); },
),
```

with:

```dart
DetailScreenToolbar(
  crumbs: const [
    CrumbSegment('Publishing'),
    CrumbSegment('Steam Workshop', route: AppRoutes.steamPublish),
    CrumbSegment('No items staged'),
  ],
  onBack: () { if (context.canPop()) context.pop(); },
),
```

Replace the main toolbar:

```dart
toolbar: DetailScreenToolbar(
  crumb:
      'Publishing > Steam Workshop > Batch (${items.length} packs)',
  onBack: _handleBack,
),
```

with:

```dart
toolbar: DetailScreenToolbar(
  crumbs: [
    const CrumbSegment('Publishing'),
    const CrumbSegment('Steam Workshop', route: AppRoutes.steamPublish),
    CrumbSegment('Batch (${items.length} packs)'),
  ],
  onBack: _handleBack,
),
```

- [ ] **Step 2: Run related tests**

Run: `flutter test test/features/steam_publish/screens/batch_workshop_publish_screen_test.dart`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/features/steam_publish/screens/batch_workshop_publish_screen.dart
git commit -m "refactor: use CrumbSegment list in batch workshop publish toolbar"
```

---

## Task 9: Remove legacy `crumb: String` parameter

**Files:**
- Modify: `lib/widgets/detail/detail_screen_toolbar.dart`
- Modify: `test/widgets/detail/detail_screen_toolbar_test.dart`

At this point, no callers remain using `crumb: String`. Verify and then remove.

- [ ] **Step 1: Verify no remaining callers**

Run a search for the legacy API:

Run: `rg -n "crumb:\s*'" lib/`
Expected: no matches (only `crumbs:` remain).

If any match appears, stop and migrate that call site first before proceeding.

- [ ] **Step 2: Remove the legacy code path from `DetailScreenToolbar`**

In `lib/widgets/detail/detail_screen_toolbar.dart`:

- Remove the `final String? crumb;` field and its constructor parameter.
- Make `crumbs` required and non-nullable:

```dart
final List<CrumbSegment> crumbs;

const DetailScreenToolbar({
  super.key,
  required this.crumbs,
  required this.onBack,
  this.trailing = const [],
});
```

- Remove the `assert` checking `crumbs` vs `crumb`.
- Simplify `build`: the `Expanded` child becomes `_CrumbTrail(crumbs: crumbs)` unconditionally.

- [ ] **Step 3: Delete the legacy tests in the toolbar test file**

Remove the four tests that use `crumb: 'X'` / `crumb: 'Work › Projects › Foo'`:

- `renders crumb and back icon`
- `back icon tap fires onBack`
- `renders trailing widgets` — rewrite to use `crumbs: const [CrumbSegment('X')]`.
- `toolbar height is 48` — rewrite to use `crumbs: const [CrumbSegment('X')]`.
- `crumb uses font-mono 12px textDim` — delete; the new API's "renders each segment with separators" test already covers per-segment style, and the "last segment bold" test covers the current-segment style. A single-segment run makes the "last = current" assumption explicit, so add a new test:

```dart
testWidgets('single-segment crumb renders the only segment as current bold',
    (t) async {
  await t.pumpWidget(wrap(DetailScreenToolbar(
    crumbs: const [CrumbSegment('Solo')],
    onBack: () {},
  )));
  final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
  final text = t.widget<Text>(find.text('Solo'));
  expect(text.style?.fontSize, 12);
  expect(text.style?.color, tokens.text);
  expect(text.style?.fontWeight, FontWeight.w600);
  // No separators for a single segment.
  expect(find.text('›'), findsNothing);
});
```

Rewrite the back-icon / trailing / height tests to use `crumbs: const [CrumbSegment('X')]` instead of `crumb: 'X'`.

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: PASS across the whole suite.

- [ ] **Step 5: Run the app and smoke-check each screen**

Since this is UI, run the app and verify visually:

```bash
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows
```

Walk through and check the crumb on each screen:
- Open a project → project detail shows `Work › Projects › <name>`. "Projects" clickable → back to projects list. "Work" and `<name>` not clickable.
- Open a language → translation editor shows `Work › Projects › <proj> › <lang>`. "Projects" and `<proj>` clickable; `<lang>` bold.
- Open a glossary → `Resources › Glossary › <name>`. "Glossary" clickable.
- Open pack compilation editor → `Publishing › Pack compilation › New|<name>`. "Pack compilation" clickable.
- Open Steam Workshop publish → `Publishing › Steam Workshop › <proj>|No pack staged`. "Steam Workshop" clickable.
- Hover behavior: pointer cursor + underline on middle segments; plain text on first/last.
- Start a translation, then click a middle crumb → toast "Translation in progress", no navigation.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/detail/detail_screen_toolbar.dart \
        test/widgets/detail/detail_screen_toolbar_test.dart
git commit -m "refactor: drop legacy crumb string API from DetailScreenToolbar"
```

---

## Post-implementation checklist

- [ ] `flutter test` passes.
- [ ] `flutter analyze` passes (no new warnings).
- [ ] Manual smoke test on Windows (Task 9, Step 5) confirms clickable behaviour, hover underline, bold current segment, and in-progress guard.
- [ ] 9 commits landed, each compiling and green on its own.
