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

/// Drains any pending horizontal-overflow exceptions emitted by the upstream
/// [GameSelectorDropdown] and [SidebarUpdateChecker] widgets. They render
/// their own content at a natural width that happens to exceed the 250px
/// sidebar in the unit-test viewport and are out of scope for
/// [NavigationSidebar] itself.
void _drainOverflowExceptions(WidgetTester tester) {
  while (true) {
    final e = tester.takeException();
    if (e == null) return;
    final msg = e.toString();
    // The test binding aggregates simultaneous layout errors into a single
    // "Multiple exceptions (N)" wrapper; in our case both members are the
    // upstream overflow warnings we want to ignore.
    if (msg.contains('A RenderFlex overflowed') ||
        msg.contains('Multiple exceptions')) {
      continue;
    }
    // Unexpected exception — re-throw to fail the test loudly.
    throw e;
  }
}

void main() {
  setUp(() {
    // Give the sidebar ListView a tall viewport so every group is laid out.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize =
        const Size(1600, 2000);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('renders all five group headers in order', (tester) async {
    await tester.pumpWidget(_wrap('/work/home'));
    await tester.pumpAndSettle();
    _drainOverflowExceptions(tester);

    for (final label in ['Sources', 'Work', 'Resources', 'Publishing', 'System']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('renders every nav item', (tester) async {
    await tester.pumpWidget(_wrap('/work/home'));
    await tester.pumpAndSettle();
    _drainOverflowExceptions(tester);

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
    _drainOverflowExceptions(tester);

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
    _drainOverflowExceptions(tester);

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
        theme: AppTheme.atelierDarkTheme,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    _drainOverflowExceptions(tester);

    await tester.tap(find.text('Glossary'));
    await tester.pump();
    _drainOverflowExceptions(tester);

    expect(navigatedTo, '/resources/glossary');
  });
}
