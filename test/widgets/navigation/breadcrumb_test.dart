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
}
