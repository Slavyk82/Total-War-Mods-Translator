// Screen tests for the migrated Projects screen (Plan 5a · Task 2).
//
// The pre-existing tests that asserted a FluentScaffold root and Fluent header
// were replaced when the screen moved to the FilterToolbar + ListRow archetype.
// These tests exercise the new chrome and row archetype.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/screens/projects_screen.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_row.dart';

import '../../../helpers/fakes/fake_logger.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

Project _project(String id, String name) => Project(
      id: id,
      name: name,
      gameInstallationId: 'install-1',
      createdAt: 0,
      updatedAt: 0,
    );

ProjectWithDetails _details(String id, String name) => ProjectWithDetails(
      project: _project(id, name),
      languages: const [],
    );

List<Override> _populatedOverrides() => [
      paginatedProjectsProvider.overrideWith((_) async => [
            _details('p1', 'Project Alpha'),
            _details('p2', 'Project Bravo'),
            _details('p3', 'Project Charlie'),
          ]),
      allLanguagesProvider.overrideWith((_) async => const <Language>[]),
    ];

List<Override> _emptyOverrides() => [
      paginatedProjectsProvider
          .overrideWith((_) async => const <ProjectWithDetails>[]),
      allLanguagesProvider.overrideWith((_) async => const <Language>[]),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('ProjectsScreen shows FilterToolbar and ListRows',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const ProjectsScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(FilterToolbar), findsOneWidget);
    expect(find.byType(ListRow), findsNWidgets(3));
    expect(find.text('Project Alpha'), findsOneWidget);
    expect(find.text('Project Bravo'), findsOneWidget);
    expect(find.text('Project Charlie'), findsOneWidget);
  });

  testWidgets('ProjectsScreen empty state when no projects', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const ProjectsScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _emptyOverrides(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ListRow), findsNothing);
    expect(find.textContaining('No projects'), findsOneWidget);
  });

  testWidgets('Tapping a row triggers navigation callback', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Build a minimal router pairing the Projects screen with a dummy detail
    // screen so we can observe that `context.go(AppRoutes.projectDetail(...))`
    // triggered by the row tap actually pushes the expected URL.
    final router = GoRouter(
      initialLocation: AppRoutes.projects,
      routes: [
        GoRoute(
          path: AppRoutes.projects,
          builder: (_, _) => const ProjectsScreen(),
        ),
        GoRoute(
          path: '${AppRoutes.projects}/:projectId',
          builder: (_, state) => Scaffold(
            body: Center(
              child: Text(
                'detail:${state.pathParameters[AppRoutes.projectIdParam]}',
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        loggingServiceProvider.overrideWithValue(FakeLogger()),
        ..._populatedOverrides(),
      ],
      child: MaterialApp.router(
        theme: AppTheme.atelierDarkTheme,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();

    // Sanity: on the Projects screen, detail marker is absent.
    expect(find.text('Project Alpha'), findsOneWidget);
    expect(find.text('detail:p1'), findsNothing);

    // Tap the first row (Project Alpha) and let the router settle.
    await tester.tap(find.text('Project Alpha'));
    await tester.pumpAndSettle();

    // The dummy detail route received the expected project id, proving the
    // row's onTap called `context.go(AppRoutes.projectDetail('p1'))`.
    expect(find.text('detail:p1'), findsOneWidget);
  });
}
