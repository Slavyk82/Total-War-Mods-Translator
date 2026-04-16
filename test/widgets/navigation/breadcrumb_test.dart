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
        builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/sources/mods',
        builder: (_, _) => const Scaffold(body: Breadcrumb()),
      ),
      GoRoute(
        path: '/work/projects/:projectId',
        builder: (_, _) => const Scaffold(body: Breadcrumb()),
      ),
      GoRoute(
        path: '/work/projects/:projectId/editor/:languageId',
        builder: (_, _) => const Scaffold(body: Breadcrumb()),
      ),
      GoRoute(
        path: '/publishing/steam/batch',
        builder: (_, _) => const Scaffold(body: Breadcrumb()),
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

  testWidgets('renders static Steam \u203a Batch chain', (tester) async {
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
          builder: (_, _) => const Scaffold(body: Breadcrumb()),
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

  testWidgets('tapping a group crumb navigates to the group default item', (tester) async {
    String? tapped;
    final router = GoRouter(
      initialLocation: '/work/projects',
      routes: [
        GoRoute(
          path: '/work/projects',
          builder: (_, _) => Scaffold(body: Breadcrumb(
            onCrumbTap: (ctx, p) => tapped = p,
          )),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      theme: AppTheme.atelierDarkTheme,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work'));
    await tester.pump();
    expect(tapped, '/work/home', reason: 'group crumb should redirect to first item');
  });

  testWidgets('intermediate non-item crumb is not clickable', (tester) async {
    // Path /work/projects/<uuid>/editor has "editor" as a leaf, but that path
    // alone is not a valid route (requires /editor/:languageId). Tapping must
    // not invoke onCrumbTap.
    var tapCount = 0;
    final router = GoRouter(
      initialLocation: '/work/projects/550e8400-e29b-41d4-a716-446655440000/editor/fr-FR',
      routes: [
        GoRoute(
          path: '/work/projects/:projectId/editor/:languageId',
          builder: (_, _) => Scaffold(body: Breadcrumb(
            onCrumbTap: (ctx, p) => tapCount++,
          )),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      theme: AppTheme.atelierDarkTheme,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
    // "Editor" is a non-last crumb but its accumulated path is invalid.
    await tester.tap(find.text('Editor'), warnIfMissed: false);
    await tester.pump();
    expect(tapCount, 0, reason: 'intermediate non-item crumb should not be clickable');
  });

  testWidgets('item crumb navigates to its accumulated path', (tester) async {
    String? tapped;
    final router = GoRouter(
      initialLocation: '/work/projects/550e8400-e29b-41d4-a716-446655440000',
      routes: [
        GoRoute(
          path: '/work/projects/:projectId',
          builder: (_, _) => Scaffold(body: Breadcrumb(
            onCrumbTap: (ctx, p) => tapped = p,
          )),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      theme: AppTheme.atelierDarkTheme,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects'));
    await tester.pump();
    expect(tapped, '/work/projects', reason: 'item crumb navigates to item route');
  });
}
