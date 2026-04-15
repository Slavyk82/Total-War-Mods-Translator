# UI Navigation Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the navigation layer of the Flutter Desktop app (TWMT) into five named sidebar groups, nested URL paths, and a reusable breadcrumb widget — with zero visual change inside existing screens.

**Architecture:** A single shared `NavigationTree` const data structure feeds both the new `NavigationSidebar` (sidebar rendering) and the new `Breadcrumb` widget (path → label resolution). Route paths move from flat (`/mods`, `/projects`) to nested (`/sources/mods`, `/work/projects`). `GoRouter.redirect` keeps legacy URLs working during the transition. `MainLayoutRouter` swaps the legacy sidebar and inline breadcrumb for the new widgets. All colours consume `context.tokens` exclusively.

**Tech Stack:** Flutter 3.x, Riverpod (codegen), `go_router`, `fluentui_system_icons`, `flutter_test`. Flutter SDK at `C:/src/flutter/bin`. Code generation via `dart run build_runner build --delete-conflicting-outputs`.

**Design spec:** [`docs/superpowers/specs/2026-04-16-ui-navigation-design.md`](../specs/2026-04-16-ui-navigation-design.md)

**Working directory:** `.worktrees/ui-navigation/` (branch `feat/ui-navigation`, created from `main`).

**Baseline tests:** 1165 passing / 30 pre-existing failures (do not regress; do not fix the 30 in this plan).

---

## File map

### Created
- `lib/config/router/navigation_tree.dart` — data (groups/items)
- `lib/config/router/navigation_tree_resolver.dart` — pure helper (path → group/item, segment → label)
- `lib/widgets/navigation/breadcrumb.dart` — new reusable breadcrumb widget
- `lib/widgets/navigation/navigation_sidebar.dart` — new 5-group sidebar widget
- `test/config/router/navigation_tree_resolver_test.dart`
- `test/widgets/navigation/breadcrumb_test.dart`
- `test/widgets/navigation/navigation_sidebar_test.dart`
- `test/config/router/app_router_test.dart`

### Modified
- `lib/config/router/app_router.dart` — new route table, legacy redirects, new `AppRoutes` constants
- `lib/widgets/layouts/main_layout_router.dart` — swap legacy sidebar/breadcrumb for new widgets, remove inline code
- Every file that hardcodes an old path literal — migrated to `AppRoutes.*` (Task 5 enumerates them)

### Deleted
- `lib/widgets/navigation_sidebar_router.dart`
- `lib/widgets/navigation_sidebar.dart` (legacy index-based, already unused in router)

### Unchanged
- `lib/widgets/game_selector_dropdown.dart` — reused as-is
- `lib/widgets/sidebar_update_checker.dart` — reused as-is
- All screen widgets (`lib/features/*/screens/*.dart`) — untouched content

---

## Commands cheat sheet

Run from `.worktrees/ui-navigation/`:

- Tests, single file: `C:/src/flutter/bin/flutter test test/<path>.dart`
- Tests, all: `C:/src/flutter/bin/flutter test`
- Codegen: `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs`
- Analyze: `C:/src/flutter/bin/dart analyze`
- Run app (smoke): `C:/src/flutter/bin/flutter run -d windows`

---

## Task 1: NavigationTree data + resolver (pure, no Flutter imports)

**Files:**
- Create: `lib/config/router/navigation_tree.dart`
- Create: `lib/config/router/navigation_tree_resolver.dart`
- Create: `test/config/router/navigation_tree_resolver_test.dart`

**Context for the engineer:** These two files contain zero Flutter widget code. `navigation_tree.dart` declares the static 5-group × 10-items structure. `navigation_tree_resolver.dart` exposes two pure functions used by the sidebar (to highlight the active item) and by the breadcrumb (to turn URL segments into display labels). Both use `IconData` from the `fluentui_system_icons` package — that package is a leaf dependency, safe to import here.

### Step 1.1: Write the failing resolver tests

- [ ] Create `test/config/router/navigation_tree_resolver_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/config/router/navigation_tree.dart';
import 'package:twmt/config/router/navigation_tree_resolver.dart';

void main() {
  group('NavigationTreeResolver.findActive', () {
    test('exact top-level match resolves to its item and group', () {
      final result = NavigationTreeResolver.findActive('/sources/mods');
      expect(result.group?.label, 'Sources');
      expect(result.item?.label, 'Mods');
    });

    test('sub-route resolves to parent item (longest-prefix match)', () {
      final result = NavigationTreeResolver.findActive(
        '/work/projects/abc-123/editor/fr-FR',
      );
      expect(result.group?.label, 'Work');
      expect(result.item?.label, 'Projects');
    });

    test('unknown path returns null group and item', () {
      final result = NavigationTreeResolver.findActive('/nowhere');
      expect(result.group, isNull);
      expect(result.item, isNull);
    });

    test('empty path returns null', () {
      final result = NavigationTreeResolver.findActive('');
      expect(result.group, isNull);
      expect(result.item, isNull);
    });

    test('every item in the tree is findable by its exact route', () {
      for (final group in navigationTree) {
        for (final item in group.items) {
          final result = NavigationTreeResolver.findActive(item.route);
          expect(result.item?.label, item.label,
              reason: 'route=${item.route}');
          expect(result.group?.label, group.label,
              reason: 'route=${item.route}');
        }
      }
    });
  });

  group('NavigationTreeResolver.labelForSegment', () {
    test('group segments resolve to group labels', () {
      expect(NavigationTreeResolver.labelForSegment('sources'), 'Sources');
      expect(NavigationTreeResolver.labelForSegment('work'), 'Work');
      expect(NavigationTreeResolver.labelForSegment('resources'), 'Resources');
      expect(NavigationTreeResolver.labelForSegment('publishing'), 'Publishing');
      expect(NavigationTreeResolver.labelForSegment('system'), 'System');
    });

    test('item segments resolve to item labels', () {
      expect(NavigationTreeResolver.labelForSegment('mods'), 'Mods');
      expect(NavigationTreeResolver.labelForSegment('game-files'), 'Game Files');
      expect(NavigationTreeResolver.labelForSegment('projects'), 'Projects');
      expect(NavigationTreeResolver.labelForSegment('home'), 'Home');
      expect(NavigationTreeResolver.labelForSegment('glossary'), 'Glossary');
      expect(NavigationTreeResolver.labelForSegment('tm'), 'Translation Memory');
      expect(NavigationTreeResolver.labelForSegment('pack'), 'Pack Compilation');
      expect(NavigationTreeResolver.labelForSegment('steam'), 'Steam Workshop');
      expect(NavigationTreeResolver.labelForSegment('settings'), 'Settings');
      expect(NavigationTreeResolver.labelForSegment('help'), 'Help');
    });

    test('leaf segments resolve to their labels', () {
      expect(NavigationTreeResolver.labelForSegment('editor'), 'Editor');
      expect(NavigationTreeResolver.labelForSegment('single'), 'Single');
      expect(NavigationTreeResolver.labelForSegment('batch'), 'Batch');
      expect(NavigationTreeResolver.labelForSegment('batch-export'), 'Batch Export');
    });

    test('unknown segment returns null', () {
      expect(NavigationTreeResolver.labelForSegment('unknown'), isNull);
      expect(NavigationTreeResolver.labelForSegment(''), isNull);
    });
  });
}
```

### Step 1.2: Run the tests — expect failure

Run: `C:/src/flutter/bin/flutter test test/config/router/navigation_tree_resolver_test.dart`
Expected: compilation failure — `navigation_tree.dart` and `navigation_tree_resolver.dart` do not exist yet.

### Step 1.3: Create `navigation_tree.dart`

- [ ] Create `lib/config/router/navigation_tree.dart`:

```dart
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';

/// Immutable group of sidebar nav items.
class NavGroup {
  const NavGroup(this.label, this.items);

  final String label;
  final List<NavItem> items;
}

/// Immutable sidebar nav item.
class NavItem {
  const NavItem({
    required this.label,
    required this.route,
    required this.icon,
    required this.selectedIcon,
  });

  /// Display label (English, EN-only per parent spec §11).
  final String label;

  /// Absolute route path this item navigates to (use [AppRoutes] constants).
  final String route;

  /// Outline icon for the inactive state.
  final IconData icon;

  /// Filled icon for the active state.
  final IconData selectedIcon;
}

/// Single source of truth for the sidebar structure and breadcrumb label
/// resolution. Mutating this list is a user-facing change — update spec first.
const List<NavGroup> navigationTree = [
  NavGroup('Sources', [
    NavItem(
      label: 'Mods',
      route: '/sources/mods',
      icon: FluentIcons.cube_24_regular,
      selectedIcon: FluentIcons.cube_24_filled,
    ),
    NavItem(
      label: 'Game Files',
      route: '/sources/game-files',
      icon: FluentIcons.globe_24_regular,
      selectedIcon: FluentIcons.globe_24_filled,
    ),
  ]),
  NavGroup('Work', [
    NavItem(
      label: 'Home',
      route: '/work/home',
      icon: FluentIcons.home_24_regular,
      selectedIcon: FluentIcons.home_24_filled,
    ),
    NavItem(
      label: 'Projects',
      route: '/work/projects',
      icon: FluentIcons.folder_24_regular,
      selectedIcon: FluentIcons.folder_24_filled,
    ),
  ]),
  NavGroup('Resources', [
    NavItem(
      label: 'Glossary',
      route: '/resources/glossary',
      icon: FluentIcons.book_24_regular,
      selectedIcon: FluentIcons.book_24_filled,
    ),
    NavItem(
      label: 'Translation Memory',
      route: '/resources/tm',
      icon: FluentIcons.database_24_regular,
      selectedIcon: FluentIcons.database_24_filled,
    ),
  ]),
  NavGroup('Publishing', [
    NavItem(
      label: 'Pack Compilation',
      route: '/publishing/pack',
      icon: FluentIcons.box_multiple_24_regular,
      selectedIcon: FluentIcons.box_multiple_24_filled,
    ),
    NavItem(
      label: 'Steam Workshop',
      route: '/publishing/steam',
      icon: FluentIcons.cloud_arrow_up_24_regular,
      selectedIcon: FluentIcons.cloud_arrow_up_24_filled,
    ),
  ]),
  NavGroup('System', [
    NavItem(
      label: 'Settings',
      route: '/system/settings',
      icon: FluentIcons.settings_24_regular,
      selectedIcon: FluentIcons.settings_24_filled,
    ),
    NavItem(
      label: 'Help',
      route: '/system/help',
      icon: FluentIcons.question_circle_24_regular,
      selectedIcon: FluentIcons.question_circle_24_filled,
    ),
  ]),
];
```

### Step 1.4: Create `navigation_tree_resolver.dart`

- [ ] Create `lib/config/router/navigation_tree_resolver.dart`:

```dart
import 'navigation_tree.dart';

/// Result of a tree lookup for the current route path.
class NavigationActive {
  const NavigationActive(this.group, this.item);
  final NavGroup? group;
  final NavItem? item;
}

/// Pure helpers for navigation label/active-state resolution.
/// Shared between sidebar highlight and breadcrumb label lookup.
class NavigationTreeResolver {
  const NavigationTreeResolver._();

  /// Returns the active group and item for the given URL [path], using
  /// longest-prefix `startsWith` matching across every item in [navigationTree].
  ///
  /// Returns [NavigationActive] with null fields when nothing matches.
  static NavigationActive findActive(String path) {
    if (path.isEmpty) {
      return const NavigationActive(null, null);
    }

    NavGroup? bestGroup;
    NavItem? bestItem;
    int bestLength = -1;

    for (final group in navigationTree) {
      for (final item in group.items) {
        final route = item.route;
        final matches = path == route || path.startsWith('$route/');
        if (matches && route.length > bestLength) {
          bestLength = route.length;
          bestGroup = group;
          bestItem = item;
        }
      }
    }

    return NavigationActive(bestGroup, bestItem);
  }

  /// Returns the display label for a single URL [segment], or `null` if the
  /// segment is unknown (dynamic id, unsupported leaf, etc.). Used by the
  /// breadcrumb to render static segments.
  static String? labelForSegment(String segment) {
    return _segmentLabels[segment];
  }
}

const Map<String, String> _segmentLabels = {
  // Group segments
  'sources': 'Sources',
  'work': 'Work',
  'resources': 'Resources',
  'publishing': 'Publishing',
  'system': 'System',
  // Item segments
  'mods': 'Mods',
  'game-files': 'Game Files',
  'home': 'Home',
  'projects': 'Projects',
  'glossary': 'Glossary',
  'tm': 'Translation Memory',
  'pack': 'Pack Compilation',
  'steam': 'Steam Workshop',
  'settings': 'Settings',
  'help': 'Help',
  // Leaf segments
  'editor': 'Editor',
  'single': 'Single',
  'batch': 'Batch',
  'batch-export': 'Batch Export',
};
```

### Step 1.5: Run the tests — expect pass

Run: `C:/src/flutter/bin/flutter test test/config/router/navigation_tree_resolver_test.dart`
Expected: all tests pass (about 10 tests).

### Step 1.6: Commit

```bash
git add lib/config/router/navigation_tree.dart lib/config/router/navigation_tree_resolver.dart test/config/router/navigation_tree_resolver_test.dart
git commit -m "feat: add NavigationTree data and resolver helpers"
```

---

## Task 2: Breadcrumb widget

**Files:**
- Create: `lib/widgets/navigation/breadcrumb.dart`
- Create: `test/widgets/navigation/breadcrumb_test.dart`

**Context:** The widget renders `Home › Group › Item [› sub-segments]` from the current `GoRouterState.of(context).uri.path`. Static segments resolve via `NavigationTreeResolver.labelForSegment`. UUIDs are skipped (same rule as the legacy inline breadcrumb). All colours via `context.tokens`. Consumed later (Task 6) by `MainLayoutRouter`.

**Token reference:** `context.tokens` exposes `textPrimary`, `textMid`, `textDim`, `border`, `panel`, `panel2`, `accent`, etc. See `lib/theme/twmt_theme_tokens.dart` for the full list.

### Step 2.1: Write the failing widget tests

- [ ] Create `test/widgets/navigation/breadcrumb_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/navigation/breadcrumb.dart';

Widget _wrap(String path) {
  final router = GoRouter(
    initialLocation: path,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/sources/mods',
        builder: (_, __) => const Scaffold(body: Breadcrumb()),
      ),
      GoRoute(
        path: '/work/projects/:projectId',
        builder: (_, __) => const Scaffold(body: Breadcrumb()),
      ),
      GoRoute(
        path: '/work/projects/:projectId/editor/:languageId',
        builder: (_, __) => const Scaffold(body: Breadcrumb()),
      ),
      GoRoute(
        path: '/publishing/steam/batch',
        builder: (_, __) => const Scaffold(body: Breadcrumb()),
      ),
    ],
  );
  return MaterialApp.router(
    theme: AppTheme.atelierDarkTheme,
    routerConfig: router,
  );
}

void main() {
  testWidgets('renders "Sources" and "Mods" for /sources/mods', (tester) async {
    await tester.pumpWidget(_wrap('/sources/mods'));
    await tester.pumpAndSettle();

    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Mods'), findsOneWidget);
  });

  testWidgets('skips UUID segments', (tester) async {
    await tester.pumpWidget(_wrap('/work/projects/550e8400-e29b-41d4-a716-446655440000'));
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.textContaining('550e8400'), findsNothing);
  });

  testWidgets('renders deep path with leaf segment', (tester) async {
    await tester.pumpWidget(
      _wrap('/work/projects/550e8400-e29b-41d4-a716-446655440000/editor/fr-FR'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
  });

  testWidgets('renders static Steam › Batch chain', (tester) async {
    await tester.pumpWidget(_wrap('/publishing/steam/batch'));
    await tester.pumpAndSettle();

    expect(find.text('Publishing'), findsOneWidget);
    expect(find.text('Steam Workshop'), findsOneWidget);
    expect(find.text('Batch'), findsOneWidget);
  });

  testWidgets('unknown segments are hidden gracefully', (tester) async {
    final router = GoRouter(
      initialLocation: '/sources/mods/unknown-leaf',
      routes: [
        GoRoute(
          path: '/sources/mods/unknown-leaf',
          builder: (_, __) => const Scaffold(body: Breadcrumb()),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      theme: AppTheme.atelierDarkTheme,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();

    // Known segments still render.
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Mods'), findsOneWidget);
    // Unknown segment falls back to raw text.
    expect(find.text('unknown-leaf'), findsOneWidget);
  });
}
```

### Step 2.2: Run the tests — expect failure

Run: `C:/src/flutter/bin/flutter test test/widgets/navigation/breadcrumb_test.dart`
Expected: compilation failure — `breadcrumb.dart` does not exist.

### Step 2.3: Create the Breadcrumb widget

- [ ] Create `lib/widgets/navigation/breadcrumb.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/navigation_tree_resolver.dart';
import '../../theme/twmt_theme_tokens.dart';

/// Reusable breadcrumb widget driven by the current [GoRouter] path.
///
/// Segments are resolved via [NavigationTreeResolver.labelForSegment]. UUID
/// segments (e.g. project ids) are skipped. Unknown non-UUID segments fall
/// back to the raw segment text in a muted mono style.
class Breadcrumb extends StatelessWidget {
  const Breadcrumb({super.key});

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final crumbs = _buildCrumbs(path);
    if (crumbs.isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(
          bottom: BorderSide(color: tokens.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < crumbs.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  FluentIcons.chevron_right_24_regular,
                  size: 14,
                  color: tokens.textDim,
                ),
              ),
            _BreadcrumbSegment(
              crumb: crumbs[i],
              isLast: i == crumbs.length - 1,
            ),
          ],
        ],
      ),
    );
  }

  List<_Crumb> _buildCrumbs(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final crumbs = <_Crumb>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (_uuidPattern.hasMatch(segment)) continue;
      final label = NavigationTreeResolver.labelForSegment(segment);
      crumbs.add(_Crumb(
        rawSegment: segment,
        label: label ?? segment,
        isKnown: label != null,
      ));
    }
    return crumbs;
  }
}

class _Crumb {
  const _Crumb({
    required this.rawSegment,
    required this.label,
    required this.isKnown,
  });

  final String rawSegment;
  final String label;
  final bool isKnown;
}

class _BreadcrumbSegment extends StatelessWidget {
  const _BreadcrumbSegment({required this.crumb, required this.isLast});

  final _Crumb crumb;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final baseStyle = crumb.isKnown
        ? tokens.fontBody
        : tokens.fontMono; // unknown segments render in mono for signal
    final style = baseStyle.copyWith(
      fontSize: 13,
      color: isLast
          ? tokens.text
          : (crumb.isKnown ? tokens.textMid : tokens.textDim),
      fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(crumb.label, style: style),
    );
  }
}
```

**Token cheat sheet** (from `lib/theme/twmt_theme_tokens.dart`): `bg`, `panel`, `panel2`, `border`, `text`, `textMid`, `textDim`, `textFaint`, `accent`, `accentFg`, `accentBg`, `ok`/`okBg`, `warn`/`warnBg`, `err`/`errBg`, `llm`/`llmBg`, `rowSelected`. **Typography tokens are `TextStyle` objects** (`fontBody`, `fontDisplay`, `fontMono`), not family name strings — merge with `.copyWith(...)` rather than setting `fontFamily:` manually.

### Step 2.4: Run the tests — expect pass

Run: `C:/src/flutter/bin/flutter test test/widgets/navigation/breadcrumb_test.dart`
Expected: all 5 tests pass.

### Step 2.5: Commit

```bash
git add lib/widgets/navigation/breadcrumb.dart test/widgets/navigation/breadcrumb_test.dart
git commit -m "feat: add reusable Breadcrumb widget"
```

---

## Task 3: NavigationSidebar widget

**Files:**
- Create: `lib/widgets/navigation/navigation_sidebar.dart`
- Create: `test/widgets/navigation/navigation_sidebar_test.dart`

**Context:** Replaces `NavigationSidebarRouter`. Renders five groups from `navigationTree`, with `GameSelectorDropdown` on top and `SidebarUpdateChecker` pinned at the bottom. Preserves the brand header with icon + "TWMT" title + theme-mode cycle button. Active item detection via `NavigationTreeResolver.findActive`. Accepts the same `onNavigate` callback as the legacy widget (used by `MainLayoutRouter` to gate navigation during translations/compilations).

### Step 3.1: Write the failing widget tests

- [ ] Create `test/widgets/navigation/navigation_sidebar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/navigation/navigation_sidebar.dart';

Widget _wrap(String path) {
  final router = GoRouter(
    initialLocation: path,
    routes: [
      for (final p in const [
        '/sources/mods',
        '/sources/game-files',
        '/work/home',
        '/work/projects',
        '/work/projects/:projectId',
        '/resources/glossary',
        '/resources/tm',
        '/publishing/pack',
        '/publishing/steam',
        '/system/settings',
        '/system/help',
      ])
        GoRoute(
          path: p,
          builder: (_, __) => const Scaffold(
            body: Row(children: [NavigationSidebar()]),
          ),
        ),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      theme: AppTheme.atelierDarkTheme,
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('renders all five group headers in order', (tester) async {
    await tester.pumpWidget(_wrap('/work/home'));
    await tester.pumpAndSettle();

    for (final label in ['Sources', 'Work', 'Resources', 'Publishing', 'System']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('renders every nav item', (tester) async {
    await tester.pumpWidget(_wrap('/work/home'));
    await tester.pumpAndSettle();

    for (final label in [
      'Mods', 'Game Files', 'Home', 'Projects',
      'Glossary', 'Translation Memory',
      'Pack Compilation', 'Steam Workshop',
      'Settings', 'Help',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('highlights active item for top-level path', (tester) async {
    await tester.pumpWidget(_wrap('/resources/glossary'));
    await tester.pumpAndSettle();

    // The active tile must expose a tracked semantic: we tag it with key
    // NavigationSidebar.activeItemKey.
    expect(find.byKey(NavigationSidebar.activeItemKey), findsOneWidget);
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(NavigationSidebar.activeItemKey),
        matching: find.byType(Text),
      ),
    );
    expect(text.data, 'Glossary');
  });

  testWidgets('highlights parent item for sub-route', (tester) async {
    await tester.pumpWidget(_wrap('/work/projects/abc-123'));
    await tester.pumpAndSettle();

    expect(find.byKey(NavigationSidebar.activeItemKey), findsOneWidget);
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(NavigationSidebar.activeItemKey),
        matching: find.byType(Text),
      ),
    );
    expect(text.data, 'Projects');
  });

  testWidgets('tapping a nav item fires onNavigate with target route',
      (tester) async {
    String? navigatedTo;
    final router = GoRouter(
      initialLocation: '/work/home',
      routes: [
        GoRoute(
          path: '/work/home',
          builder: (_, __) => Scaffold(
            body: Row(children: [
              NavigationSidebar(onNavigate: (p) => navigatedTo = p),
            ]),
          ),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(
        theme: AppTheme.atelierTheme,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Glossary'));
    await tester.pump();

    expect(navigatedTo, '/resources/glossary');
  });
}
```

### Step 3.2: Run the tests — expect failure

Run: `C:/src/flutter/bin/flutter test test/widgets/navigation/navigation_sidebar_test.dart`
Expected: compilation failure — `navigation_sidebar.dart` does not exist.

### Step 3.3: Create the widget

- [ ] Create `lib/widgets/navigation/navigation_sidebar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/navigation_tree.dart';
import '../../config/router/navigation_tree_resolver.dart';
import '../../providers/theme_provider.dart';
import '../../theme/twmt_theme_tokens.dart';
import '../game_selector_dropdown.dart';
import '../sidebar_update_checker.dart';

/// Five-group sidebar. Reads the current [GoRouter] path to highlight the
/// active item (longest-prefix match). Pass [onNavigate] to intercept taps
/// (e.g. to block navigation during in-progress translations).
class NavigationSidebar extends ConsumerWidget {
  const NavigationSidebar({super.key, this.onNavigate});

  /// Callback invoked with the target route on tap. If null, the widget
  /// defaults to `context.go(route)`.
  final void Function(String route)? onNavigate;

  /// Widget key attached to the currently-active item, for tests.
  static const Key activeItemKey = ValueKey('nav-sidebar-active-item');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final active = NavigationTreeResolver.findActive(path);
    final tokens = context.tokens;

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(right: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BrandHeader(),
          Divider(height: 1, color: tokens.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: GameSelectorDropdown(),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < navigationTree.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _GroupHeader(label: navigationTree[i].label),
                  for (final item in navigationTree[i].items)
                    _NavItemTile(
                      item: item,
                      isActive: active.item?.route == item.route,
                      onTap: () => _dispatch(context, item.route),
                    ),
                ],
              ],
            ),
          ),
          const SidebarUpdateChecker(),
        ],
      ),
    );
  }

  void _dispatch(BuildContext context, String route) {
    if (onNavigate != null) {
      onNavigate!(route);
    } else {
      context.go(route);
    }
  }
}

class _BrandHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final themeModeAsync = ref.watch(themeProvider);
    final themeMode = themeModeAsync.maybeWhen(
      data: (m) => m,
      orElse: () => ThemeMode.system,
    );
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Image.asset('assets/twmt_icon.png', width: 32, height: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'TWMT',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold, color: tokens.text),
            ),
          ),
          _ThemeModeButton(
            mode: themeMode,
            onPressed: () => ref.read(themeProvider.notifier).cycleTheme(),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: tokens.fontMono.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: tokens.textDim,
        ),
      ),
    );
  }
}

class _NavItemTile extends StatefulWidget {
  const _NavItemTile({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_NavItemTile> createState() => _NavItemTileState();
}

class _NavItemTileState extends State<_NavItemTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bg = widget.isActive
        ? tokens.accentBg
        : (_hover ? tokens.panel2 : Colors.transparent);
    final fg = widget.isActive ? tokens.accent : tokens.text;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: widget.isActive
                  ? Border(left: BorderSide(color: tokens.accent, width: 2))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  widget.isActive ? widget.item.selectedIcon : widget.item.icon,
                  size: 20,
                  color: fg,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    key: widget.isActive ? NavigationSidebar.activeItemKey : null,
                    style: TextStyle(
                      color: fg,
                      fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeModeButton extends StatefulWidget {
  const _ThemeModeButton({required this.mode, required this.onPressed});

  final ThemeMode mode;
  final VoidCallback onPressed;

  @override
  State<_ThemeModeButton> createState() => _ThemeModeButtonState();
}

class _ThemeModeButtonState extends State<_ThemeModeButton> {
  bool _hover = false;

  IconData get _icon {
    switch (widget.mode) {
      case ThemeMode.system:
        return Icons.desktop_windows_outlined;
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: 'Theme: ${widget.mode.name} (click to cycle)',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _hover ? tokens.panel2 : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(_icon, size: 18, color: tokens.accent),
          ),
        ),
      ),
    );
  }
}
```

**Token names verified against** `lib/theme/twmt_theme_tokens.dart`: the fields `panel`, `panel2`, `border`, `text`, `textMid`, `textDim`, `accent`, `accentBg`, and the `TextStyle` field `fontMono` all exist exactly as used above.

### Step 3.4: Run the tests — expect pass

Run: `C:/src/flutter/bin/flutter test test/widgets/navigation/navigation_sidebar_test.dart`
Expected: all 5 tests pass.

### Step 3.5: Commit

```bash
git add lib/widgets/navigation/navigation_sidebar.dart test/widgets/navigation/navigation_sidebar_test.dart
git commit -m "feat: add 5-group NavigationSidebar widget"
```

---

## Task 4: New AppRoutes, router, legacy redirects

**Files:**
- Modify: `lib/config/router/app_router.dart`
- Create: `test/config/router/app_router_test.dart`

**Context:** Rename every constant in `AppRoutes` to its new nested path, add the `rootRedirect` constant, add a `legacyRedirects` map, wire `GoRouter.redirect` to apply them, and update every `GoRoute.path` in the route tree to the new path. Note `GoRoute` children use *relative* paths (no leading `/`), so only the top-level paths need updating.

### Step 4.1: Write the failing router tests

- [ ] Create `test/config/router/app_router_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';

/// Minimal router used only to exercise the redirect logic. Uses the real
/// `legacyRedirects` + `rootRedirect` from [AppRoutes] but dummy screens.
GoRouter _buildTestRouter({required String initial}) {
  return GoRouter(
    initialLocation: initial,
    redirect: (context, state) => appRouterRedirect(state.uri.path),
    routes: [
      for (final path in [
        AppRoutes.home,
        AppRoutes.mods,
        AppRoutes.gameFiles,
        AppRoutes.projects,
        AppRoutes.batchPackExport,
        AppRoutes.glossary,
        AppRoutes.translationMemory,
        AppRoutes.packCompilation,
        AppRoutes.steamPublish,
        AppRoutes.steamPublishSingle,
        AppRoutes.steamPublishBatch,
        AppRoutes.settings,
        AppRoutes.help,
      ])
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Text('at:$path')),
        ),
      GoRoute(
        path: '${AppRoutes.projects}/:projectId',
        builder: (_, s) =>
            Scaffold(body: Text('project:${s.pathParameters['projectId']}')),
      ),
      GoRoute(
        path: '${AppRoutes.projects}/:projectId/editor/:languageId',
        builder: (_, s) => Scaffold(
          body: Text(
            'editor:${s.pathParameters['projectId']}/${s.pathParameters['languageId']}',
          ),
        ),
      ),
    ],
  );
}

void main() {
  group('AppRoutes nested paths', () {
    test('home is /work/home', () {
      expect(AppRoutes.home, '/work/home');
    });
    test('mods is /sources/mods', () {
      expect(AppRoutes.mods, '/sources/mods');
    });
    test('gameFiles is /sources/game-files', () {
      expect(AppRoutes.gameFiles, '/sources/game-files');
    });
    test('projects is /work/projects', () {
      expect(AppRoutes.projects, '/work/projects');
    });
    test('projectDetail composes /work/projects/<id>', () {
      expect(AppRoutes.projectDetail('abc'), '/work/projects/abc');
    });
    test('translationEditor composes /work/projects/<id>/editor/<lang>', () {
      expect(
        AppRoutes.translationEditor('abc', 'fr-FR'),
        '/work/projects/abc/editor/fr-FR',
      );
    });
    test('batchPackExport is /work/projects/batch-export', () {
      expect(AppRoutes.batchPackExport, '/work/projects/batch-export');
    });
    test('glossary is /resources/glossary', () {
      expect(AppRoutes.glossary, '/resources/glossary');
    });
    test('translationMemory is /resources/tm', () {
      expect(AppRoutes.translationMemory, '/resources/tm');
    });
    test('packCompilation is /publishing/pack', () {
      expect(AppRoutes.packCompilation, '/publishing/pack');
    });
    test('steamPublish is /publishing/steam', () {
      expect(AppRoutes.steamPublish, '/publishing/steam');
    });
    test('steamPublishSingle is /publishing/steam/single', () {
      expect(AppRoutes.steamPublishSingle, '/publishing/steam/single');
    });
    test('settings is /system/settings', () {
      expect(AppRoutes.settings, '/system/settings');
    });
    test('help is /system/help', () {
      expect(AppRoutes.help, '/system/help');
    });
    test('rootRedirect is /work/home', () {
      expect(AppRoutes.rootRedirect, '/work/home');
    });
  });

  group('appRouterRedirect', () {
    test('root / redirects to /work/home', () {
      expect(appRouterRedirect('/'), '/work/home');
    });
    test('legacy /mods redirects to /sources/mods', () {
      expect(appRouterRedirect('/mods'), '/sources/mods');
    });
    test('legacy /game-translation redirects to /sources/game-files', () {
      expect(appRouterRedirect('/game-translation'), '/sources/game-files');
    });
    test('legacy /projects redirects to /work/projects', () {
      expect(appRouterRedirect('/projects'), '/work/projects');
    });
    test('legacy nested /projects/<id> redirects to /work/projects/<id>', () {
      expect(
        appRouterRedirect('/projects/abc-123'),
        '/work/projects/abc-123',
      );
    });
    test('legacy deep /projects/<id>/editor/<lang> redirects correctly', () {
      expect(
        appRouterRedirect('/projects/abc-123/editor/fr-FR'),
        '/work/projects/abc-123/editor/fr-FR',
      );
    });
    test('legacy /glossary redirects to /resources/glossary', () {
      expect(appRouterRedirect('/glossary'), '/resources/glossary');
    });
    test('legacy /translation-memory redirects to /resources/tm', () {
      expect(appRouterRedirect('/translation-memory'), '/resources/tm');
    });
    test('legacy /pack-compilation redirects to /publishing/pack', () {
      expect(appRouterRedirect('/pack-compilation'), '/publishing/pack');
    });
    test('legacy /steam-publish redirects to /publishing/steam', () {
      expect(appRouterRedirect('/steam-publish'), '/publishing/steam');
    });
    test('legacy /steam-publish/batch redirects correctly', () {
      expect(
        appRouterRedirect('/steam-publish/batch'),
        '/publishing/steam/batch',
      );
    });
    test('legacy /settings redirects to /system/settings', () {
      expect(appRouterRedirect('/settings'), '/system/settings');
    });
    test('legacy /help redirects to /system/help', () {
      expect(appRouterRedirect('/help'), '/system/help');
    });
    test('new-path input returns null (no redirect)', () {
      expect(appRouterRedirect('/sources/mods'), isNull);
      expect(appRouterRedirect('/work/projects/abc'), isNull);
      expect(appRouterRedirect('/system/settings'), isNull);
    });
    test('unknown path returns null (no redirect, falls through to errorBuilder)', () {
      expect(appRouterRedirect('/nowhere'), isNull);
    });
  });

  group('GoRouter integration', () {
    testWidgets('/ navigates to /work/home', (tester) async {
      final router = _buildTestRouter(initial: '/');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('at:/work/home'), findsOneWidget);
    });

    testWidgets('/mods navigates to /sources/mods screen', (tester) async {
      final router = _buildTestRouter(initial: '/mods');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('at:/sources/mods'), findsOneWidget);
    });

    testWidgets('/projects/abc navigates to /work/projects/abc', (tester) async {
      final router = _buildTestRouter(initial: '/projects/abc-123');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('project:abc-123'), findsOneWidget);
    });
  });
}
```

### Step 4.2: Run the tests — expect failure

Run: `C:/src/flutter/bin/flutter test test/config/router/app_router_test.dart`
Expected: compilation failures on `AppRoutes.gameFiles`, `AppRoutes.rootRedirect`, `appRouterRedirect`, and mismatched constants.

### Step 4.3: Rewrite `AppRoutes` + add redirect helper

- [ ] Open `lib/config/router/app_router.dart`. Replace the whole `AppRoutes` class (lines 35–63) with:

```dart
/// Route path constants.
///
/// Paths are nested by sidebar group (Sources, Work, Resources, Publishing,
/// System) — see `NavigationTree`. Use `legacyRedirects` to map pre-restructure
/// URLs onto the new ones.
class AppRoutes {
  // Root
  static const String rootRedirect = '/work/home';

  // Sources
  static const String mods = '/sources/mods';
  static const String gameFiles = '/sources/game-files';

  // Work
  static const String home = '/work/home';
  static const String projects = '/work/projects';
  static const String batchPackExport = '/work/projects/batch-export';

  // Resources
  static const String glossary = '/resources/glossary';
  static const String translationMemory = '/resources/tm';

  // Publishing
  static const String packCompilation = '/publishing/pack';
  static const String steamPublish = '/publishing/steam';
  static const String steamPublishSingle = '/publishing/steam/single';
  static const String steamPublishBatch = '/publishing/steam/batch';

  // System
  static const String settings = '/system/settings';
  static const String settingsGeneral = '/system/settings/general';
  static const String settingsLlm = '/system/settings/llm';
  static const String help = '/system/help';

  // Detail / parameterised routes
  static String projectDetail(String projectId) => '$projects/$projectId';
  static String translationEditor(String projectId, String languageId) =>
      '$projects/$projectId/editor/$languageId';

  // Path parameter names
  static const String projectIdParam = 'projectId';
  static const String languageIdParam = 'languageId';
}

/// Legacy URL → new URL map. Longest match wins (handled by
/// [appRouterRedirect]). Retained for one cycle to absorb any path that may
/// have been persisted by the app (Windows shortcuts, cached state).
const Map<String, String> legacyRedirects = {
  '/': '/work/home',
  '/mods': '/sources/mods',
  '/game-translation': '/sources/game-files',
  '/projects': '/work/projects',
  '/glossary': '/resources/glossary',
  '/translation-memory': '/resources/tm',
  '/pack-compilation': '/publishing/pack',
  '/steam-publish': '/publishing/steam',
  '/settings': '/system/settings',
  '/help': '/system/help',
};

/// Pure redirect function. Returns the new path or `null` if no redirect
/// applies. Matches the longest legacy prefix so
/// `/projects/abc/editor/fr` → `/work/projects/abc/editor/fr`.
String? appRouterRedirect(String path) {
  if (path == '/') return legacyRedirects['/'];

  String? bestMatch;
  int bestLen = 0;
  legacyRedirects.forEach((legacy, newPrefix) {
    if (legacy == '/') return; // handled above
    if (path == legacy || path.startsWith('$legacy/')) {
      if (legacy.length > bestLen) {
        bestLen = legacy.length;
        final tail = path.substring(legacy.length);
        bestMatch = '$newPrefix$tail';
      }
    }
  });
  return bestMatch;
}
```

### Step 4.4: Update `GoRouter` config

- [ ] In the same file, inside `goRouterProvider`:
  - Change `initialLocation: AppRoutes.home` → `initialLocation: AppRoutes.rootRedirect`.
  - Add immediately after `debugLogDiagnostics: true,`:
    ```dart
    redirect: (context, state) => appRouterRedirect(state.uri.path),
    ```
  - Update each top-level `GoRoute.path` in the `routes:` list to the new value (the `AppRoutes.*` constants update their values automatically — no textual change needed since the references already use the constants).
  - The child routes (`batch-export`, `:projectId`, `editor/:languageId`, `single`, `batch`) keep their relative paths — no change.

### Step 4.5: Update the extension methods

- [ ] Replace the `GoRouterExtensions` extension at the bottom of `lib/config/router/app_router.dart` with (adds `goGameFiles`):

```dart
extension GoRouterExtensions on BuildContext {
  void goHome() => go(AppRoutes.home);
  void goMods() => go(AppRoutes.mods);
  void goGameFiles() => go(AppRoutes.gameFiles);
  void goProjects() => go(AppRoutes.projects);
  void goGlossary() => go(AppRoutes.glossary);
  void goTranslationMemory() => go(AppRoutes.translationMemory);
  void goPackCompilation() => go(AppRoutes.packCompilation);
  void goBatchPackExport() => go(AppRoutes.batchPackExport);
  void goSteamPublish() => go(AppRoutes.steamPublish);
  void goWorkshopPublishSingle() => go(AppRoutes.steamPublishSingle);
  void goWorkshopPublishBatch() => go(AppRoutes.steamPublishBatch);
  void goSettings() => go(AppRoutes.settings);
  void goHelp() => go(AppRoutes.help);

  void goProjectDetail(String projectId) => go(AppRoutes.projectDetail(projectId));
  void goTranslationEditor(String projectId, String languageId) =>
      go(AppRoutes.translationEditor(projectId, languageId));
}
```

Drop the old `goGameTranslation()` helper — its call sites (if any) get migrated in Task 5 to `goGameFiles()`.

### Step 4.6: Run the router tests — expect pass

Run: `C:/src/flutter/bin/flutter test test/config/router/app_router_test.dart`
Expected: all tests pass.

### Step 4.7: Check nothing else broke yet

Run: `C:/src/flutter/bin/dart analyze lib/config/`
Expected: zero analyzer issues in `lib/config/`. (Other files that reference the old constant names are migrated in Task 5; analyzer will still flag them — that is expected and acceptable at this step as long as analyze runs only on `lib/config/`.)

### Step 4.8: Commit

```bash
git add lib/config/router/app_router.dart test/config/router/app_router_test.dart
git commit -m "feat: nest route paths into 5 groups with legacy redirects"
```

---

## Task 5: Migrate string literals + removed-constant references

**Files modified:** every `.dart` file in `lib/` and `test/` that references:
- The removed constant `AppRoutes.gameTranslation` → `AppRoutes.gameFiles`.
- The removed extension `context.goGameTranslation()` → `context.goGameFiles()`.
- A hardcoded legacy path literal that should be a constant.

**Context:** After Task 4, only `AppRoutes.*` constant *values* changed. Every reference that goes through a constant is already correct. This task fixes (a) references to the removed `gameTranslation` name, (b) any string literal that hardcodes a legacy path instead of going through `AppRoutes`.

### Step 5.1: Find every stale reference

- [ ] Run (from worktree root):

```bash
C:/src/flutter/bin/dart analyze lib/ test/ 2>&1 | grep -E "(gameTranslation|goGameTranslation)" | head -50
```

- [ ] And find hardcoded literals:

```bash
grep -rnE "'/(mods|projects|game-translation|glossary|translation-memory|pack-compilation|steam-publish|settings|help)(/|'|\")" lib/ test/ | grep -v "AppRoutes\." | grep -v "navigation_tree.dart" | grep -v "app_router.dart" | grep -v "navigation_tree_resolver.dart"
```

The grep excludes the files that legitimately own those literals (data + redirect map).

### Step 5.2: Migrate every hit

- [ ] For each file surfaced by the greps above, apply the appropriate transformation:

| Old | New |
|---|---|
| `AppRoutes.gameTranslation` | `AppRoutes.gameFiles` |
| `.goGameTranslation()` | `.goGameFiles()` |
| `'/mods'` as a literal | `AppRoutes.mods` (add import if missing) |
| `'/game-translation'` | `AppRoutes.gameFiles` |
| `'/projects'` | `AppRoutes.projects` |
| `'/glossary'` | `AppRoutes.glossary` |
| `'/translation-memory'` | `AppRoutes.translationMemory` |
| `'/pack-compilation'` | `AppRoutes.packCompilation` |
| `'/steam-publish'` | `AppRoutes.steamPublish` |
| `'/settings'` | `AppRoutes.settings` |
| `'/help'` | `AppRoutes.help` |

**Special case — translation blockers**: `main_layout_router.dart` has legacy literal comparisons like `location == '/steam-publish/single'` inside `_buildBreadcrumbs`. Task 6 rewrites that whole method, so these particular literals can be left alone until Task 6 and removed there. Skip them if they appear in the grep.

### Step 5.3: Re-run analyzer

Run: `C:/src/flutter/bin/dart analyze lib/ test/`
Expected: zero references to `gameTranslation` / `goGameTranslation`; no "undefined getter / method" errors.

### Step 5.4: Re-run the full test suite

Run: `C:/src/flutter/bin/flutter test`
Expected: **1165 + (new tests from Tasks 1–4) passing / 30 pre-existing failing**. No new failures beyond the documented baseline.

### Step 5.5: Commit

```bash
git add -A lib/ test/
git commit -m "refactor: migrate route literals to AppRoutes constants"
```

---

## Task 6: Wire new widgets in MainLayoutRouter, delete legacy, manual smoke test

**Files:**
- Modify: `lib/widgets/layouts/main_layout_router.dart`
- Delete: `lib/widgets/navigation_sidebar_router.dart`
- Delete: `lib/widgets/navigation_sidebar.dart` (legacy index-based)

### Step 6.1: Rewrite `MainLayoutRouter`

- [ ] Replace the entire contents of `lib/widgets/layouts/main_layout_router.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../fluent/fluent_widgets.dart';
import '../navigation/breadcrumb.dart';
import '../navigation/navigation_sidebar.dart';
import 'fluent_scaffold.dart';
import '../../features/translation_editor/providers/editor_providers.dart';
import '../../features/pack_compilation/providers/pack_compilation_providers.dart';

/// Shell layout: sidebar + global breadcrumb + active screen.
///
/// This plan keeps the breadcrumb rendered at the shell level. Plans 3-5
/// move it into each screen's toolbar, at which point the [Breadcrumb]
/// line below is removed.
class MainLayoutRouter extends ConsumerWidget {
  const MainLayoutRouter({super.key, required this.child});

  final Widget child;

  bool _canNavigate(BuildContext context, WidgetRef ref) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final hideBreadcrumb = _shouldHideBreadcrumb(path);

    return FluentScaffold(
      body: Column(
        children: [
          if (!hideBreadcrumb) const Breadcrumb(),
          Expanded(
            child: Row(
              children: [
                NavigationSidebar(
                  onNavigate: (p) {
                    if (_canNavigate(context, ref)) context.go(p);
                  },
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Editor and single-publish screens render their own header and would
  /// double-up with the shell breadcrumb.
  bool _shouldHideBreadcrumb(String path) {
    if (path.contains('/editor/')) return true;
    if (path == '/publishing/steam/single') return true;
    if (path == '/publishing/steam/batch') return true;
    return false;
  }
}
```

### Step 6.2: Delete legacy files

- [ ] Run:

```bash
git rm lib/widgets/navigation_sidebar_router.dart lib/widgets/navigation_sidebar.dart
```

### Step 6.3: Analyze

Run: `C:/src/flutter/bin/dart analyze lib/ test/`
Expected: zero errors. No dangling references to the deleted files.

### Step 6.4: Run the full test suite

Run: `C:/src/flutter/bin/flutter test`
Expected: 1165 + new tests passing, 30 pre-existing failing, no new regressions.

### Step 6.5: Manual smoke test on Windows

- [ ] Start the app:

```bash
C:/src/flutter/bin/flutter run -d windows
```

Verify, clicking each sidebar item in order:

| Action | Expected URL | Expected screen |
|---|---|---|
| App boot | `/work/home` | Home |
| Click Mods | `/sources/mods` | Mods screen |
| Click Game Files | `/sources/game-files` | Game Translation screen |
| Click Home | `/work/home` | Home |
| Click Projects | `/work/projects` | Projects list |
| Open a project | `/work/projects/<uuid>` | Project detail |
| Open a language editor | `/work/projects/<uuid>/editor/<lang>` | Editor (no breadcrumb) |
| Click Glossary | `/resources/glossary` | Glossary |
| Click Translation Memory | `/resources/tm` | TM |
| Click Pack Compilation | `/publishing/pack` | Pack screen |
| Click Steam Workshop | `/publishing/steam` | Steam list |
| Click Settings | `/system/settings` | Settings |
| Click Help | `/system/help` | Help |

Verify the breadcrumb reads `Sources › Mods`, `Work › Projects`, etc. — never a raw segment, never empty on a nested path.

Verify the sidebar highlights the correct group's item on each click (left accent border + accent text).

### Step 6.6: Commit

```bash
git add lib/widgets/layouts/main_layout_router.dart
git commit -m "feat: wire new NavigationSidebar and Breadcrumb in MainLayoutRouter"
```

### Step 6.7: Final analyzer + tests sweep

Run: `C:/src/flutter/bin/dart analyze`
Expected: zero issues.

Run: `C:/src/flutter/bin/flutter test`
Expected: baseline + new tests pass, 30 pre-existing failures unchanged.

---

## Acceptance checklist

- [ ] `navigation_tree.dart` + `navigation_tree_resolver.dart` exist with 5 groups × 10 items.
- [ ] `Breadcrumb` widget renders `Group › Item [› Leaf]` for every route.
- [ ] `NavigationSidebar` shows 5 grouped sections + game switcher + update checker.
- [ ] All new route paths (`/sources/*`, `/work/*`, `/resources/*`, `/publishing/*`, `/system/*`) resolve to their expected screen.
- [ ] All 10 legacy paths redirect cleanly (including nested `/projects/<id>/editor/<lang>`).
- [ ] `lib/widgets/navigation_sidebar*.dart` legacy files are deleted.
- [ ] `dart analyze` — zero issues.
- [ ] `flutter test` — new tests pass, baseline 30 failures unchanged, no new failures.
- [ ] Manual smoke on Windows — every sidebar item navigates, breadcrumb renders correctly, editor and publish sub-screens hide the shell breadcrumb.

---

## Rollback notes

Everything ships on `feat/ui-navigation`. If the branch is abandoned, drop the worktree with `git worktree remove .worktrees/ui-navigation` — no migrations, no DB schema change, no persisted user state touches the new paths since legacy redirects keep the app functional.
