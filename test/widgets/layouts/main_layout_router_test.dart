import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/layouts/main_layout_router.dart';
import 'package:twmt/widgets/navigation/breadcrumb.dart';
import 'package:twmt/widgets/navigation/navigation_sidebar.dart';

/// Builds a minimal app with a [ShellRoute] wrapping [MainLayoutRouter] so we
/// can exercise breadcrumb visibility and navigation guards. Dummy screens
/// are injected for each route under test.
Widget _wrap(
  String path, {
  bool translationInProgress = false,
}) {
  final router = GoRouter(
    initialLocation: path,
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainLayoutRouter(child: child),
        routes: [
          GoRoute(
            path: '/work/home',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('home'))),
          ),
          GoRoute(
            path: '/work/projects/:projectId/editor/:languageId',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('editor'))),
          ),
          GoRoute(
            path: '/publishing/steam/single',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('single'))),
          ),
          GoRoute(
            path: '/publishing/steam/batch',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('batch'))),
          ),
          GoRoute(
            path: '/resources/glossary',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('glossary'))),
          ),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      if (translationInProgress)
        translationInProgressProvider.overrideWithValue(true),
    ],
    child: MaterialApp.router(
      theme: AppTheme.atelierDarkTheme,
      routerConfig: router,
    ),
  );
}

/// Drains horizontal-overflow exceptions emitted by sidebar children that
/// render wider than the 250px sidebar in tests. Same known issue documented
/// in `navigation_sidebar_test.dart` — `SidebarUpdateChecker` and
/// `GameSelectorDropdown`.
void _drainOverflowExceptions(WidgetTester tester) {
  while (true) {
    final e = tester.takeException();
    if (e == null) return;
    final msg = e.toString();
    final isOverflow = msg.contains('A RenderFlex overflowed');
    final mentionsOffender = msg.contains('SidebarUpdateChecker') ||
        msg.contains('GameSelectorDropdown') ||
        msg.contains('sidebar_update_checker.dart') ||
        msg.contains('game_selector_dropdown.dart');
    if (isOverflow && mentionsOffender) {
      continue;
    }
    if (isOverflow &&
        !msg.contains('The relevant error-causing widget was')) {
      continue;
    }
    if (msg.startsWith('Multiple exceptions')) {
      continue;
    }
    throw e;
  }
}

void main() {
  setUp(() {
    // Large viewport so the sidebar ListView lays out every group.
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

  testWidgets('hides Breadcrumb on editor route', (tester) async {
    await tester.pumpWidget(
      _wrap('/work/projects/550e8400-e29b-41d4-a716-446655440000/editor/fr-FR'),
    );
    await tester.pumpAndSettle();
    _drainOverflowExceptions(tester);

    expect(find.byType(Breadcrumb), findsNothing);
  });

  testWidgets('hides Breadcrumb on /publishing/steam/single', (tester) async {
    await tester.pumpWidget(_wrap('/publishing/steam/single'));
    await tester.pumpAndSettle();
    _drainOverflowExceptions(tester);

    expect(find.byType(Breadcrumb), findsNothing);
  });

  testWidgets('hides Breadcrumb on /publishing/steam/batch', (tester) async {
    await tester.pumpWidget(_wrap('/publishing/steam/batch'));
    await tester.pumpAndSettle();
    _drainOverflowExceptions(tester);

    expect(find.byType(Breadcrumb), findsNothing);
  });

  testWidgets('hides Breadcrumb on AppRoutes.home', (tester) async {
    await tester.pumpWidget(_wrap(AppRoutes.home));
    await tester.pumpAndSettle();
    _drainOverflowExceptions(tester);

    expect(find.byType(Breadcrumb), findsNothing);
  });

  testWidgets('shows Breadcrumb on /resources/glossary', (tester) async {
    await tester.pumpWidget(_wrap('/resources/glossary'));
    await tester.pumpAndSettle();
    _drainOverflowExceptions(tester);

    expect(find.byType(Breadcrumb), findsOneWidget);
  });

  testWidgets(
    'blocks navigation and shows toast when translation is in progress',
    (tester) async {
      await tester.pumpWidget(
        _wrap('/work/home', translationInProgress: true),
      );
      await tester.pumpAndSettle();
      _drainOverflowExceptions(tester);

      // Sanity: the sidebar is mounted so tapping a nav tile reaches the
      // MainLayoutRouter guard.
      expect(find.byType(NavigationSidebar), findsOneWidget);

      // Tap "Glossary" in the sidebar. Because the guard should block
      // navigation, we stay on /work/home and a warning toast appears.
      await tester.tap(find.text('Glossary').first);
      await tester.pump();
      _drainOverflowExceptions(tester);

      // Toast renders the warning message.
      expect(
        find.text('Translation in progress. Stop the translation first.'),
        findsOneWidget,
      );

      // The router did not navigate away from home — the home body is still
      // on-screen while the glossary body is not.
      expect(find.text('home'), findsOneWidget);
      expect(find.text('glossary'), findsNothing);

      // FluentToast schedules a 4s auto-dismiss via Future.delayed; advance
      // past it so no pending timers remain when the test tears down.
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
