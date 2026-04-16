import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/activity/models/activity_event.dart';
import 'package:twmt/features/activity/providers/activity_providers.dart';
import 'package:twmt/features/home/models/next_project_action.dart';
import 'package:twmt/features/home/models/project_with_next_action.dart';
import 'package:twmt/features/home/providers/action_grid_providers.dart';
import 'package:twmt/features/home/providers/home_providers.dart';
import 'package:twmt/features/home/providers/home_status_provider.dart';
import 'package:twmt/features/home/providers/workflow_providers.dart';
import 'package:twmt/features/home/screens/home_screen.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Minimal Project fixture mirroring the pattern from Task 16's
/// `recent_projects_list_test.dart` — only the fields read by the widgets
/// (`id`, `name`) carry test-facing data; everything else uses defaults.
Project _fixtureProject(String id, String name) => Project(
      id: id,
      name: name,
      gameInstallationId: 'install-test',
      createdAt: 0,
      updatedAt: 0,
    );

ProjectWithNextAction _pwa(String name, NextProjectAction action, int pct) =>
    ProjectWithNextAction(
      project: _fixtureProject('id-$name', name),
      action: action,
      translatedPct: pct,
    );

/// Fixed-in-the-past timestamp so the activity feed's relative formatter
/// always lands in the stable `YYYY-MM-DD` branch, immune to "N min ago" /
/// "yesterday" drift between runs.
final _fixedActivityTs = DateTime.utc(2024, 1, 1, 12, 0);

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
    // Desktop-class viewport so the full dashboard (workflow ribbon +
    // recent/activity columns) renders without overflow at 1920x1080.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize =
        const Size(1920, 1080);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  // Populated dashboard overrides: non-zero counts across the board, a
  // couple of recent projects, and a single fixed-timestamp activity row.
  final populatedOverrides = <Override>[
    modsDiscoveredCountProvider.overrideWith((ref) async => 187),
    modsWithUpdatesCountProvider.overrideWith((ref) async => 5),
    activeProjectsCountProvider.overrideWith((ref) async => 24),
    projectsToReviewCountProvider.overrideWith((ref) async => 2),
    projectsReadyToCompileCountProvider.overrideWith((ref) async => 3),
    packsAwaitingPublishCountProvider.overrideWith((ref) async => 1),
    homeStatusProvider.overrideWith(
      (ref) async => const HomeStatus(HomeStatusKind.needsAttention, 2),
    ),
    recentProjectsProvider.overrideWith((ref) async => [
          _pwa('Tribes of the North', NextProjectAction.readyToCompile, 100),
          _pwa('TechTree Overhaul', NextProjectAction.continueWork, 72),
        ]),
    activityFeedProvider.overrideWith((ref) async => [
          ActivityEvent(
            id: 1,
            type: ActivityEventType.packCompiled,
            timestamp: _fixedActivityTs,
            projectId: null,
            gameCode: 'warhammer_3',
            payload: const {
              'projectName': 'Tribes of the North',
              'packFileName': 'tribes.pack',
            },
          ),
        ]),
  ];

  // Empty dashboard overrides: no active projects → EmptyStateGuide renders,
  // zero counts, and empty recent/activity lists. Re-declared in full (not
  // spread from the populated list) to avoid registering duplicate overrides
  // for the same provider, which Riverpod resolves in an undefined order.
  final emptyOverrides = <Override>[
    modsDiscoveredCountProvider.overrideWith((ref) async => 0),
    modsWithUpdatesCountProvider.overrideWith((ref) async => 0),
    activeProjectsCountProvider.overrideWith((ref) async => 0),
    projectsToReviewCountProvider.overrideWith((ref) async => 0),
    projectsReadyToCompileCountProvider.overrideWith((ref) async => 0),
    packsAwaitingPublishCountProvider.overrideWith((ref) async => 0),
    homeStatusProvider.overrideWith(
      (ref) async => const HomeStatus(HomeStatusKind.allCaughtUp, 0),
    ),
    recentProjectsProvider.overrideWith((ref) async => const []),
    activityFeedProvider.overrideWith((ref) async => const []),
  ];

  Future<void> pumpUnder(
    WidgetTester tester,
    ThemeData theme,
    List<Override> overrides,
  ) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const HomeScreen(),
      theme: theme,
      overrides: overrides,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('home dashboard atelier', (tester) async {
    await pumpUnder(tester, AppTheme.atelierDarkTheme, populatedOverrides);
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('../goldens/home_dashboard_atelier.png'),
    );
  });

  testWidgets('home dashboard forge', (tester) async {
    await pumpUnder(tester, AppTheme.forgeDarkTheme, populatedOverrides);
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('../goldens/home_dashboard_forge.png'),
    );
  });

  testWidgets('home empty atelier', (tester) async {
    await pumpUnder(tester, AppTheme.atelierDarkTheme, emptyOverrides);
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('../goldens/home_empty_atelier.png'),
    );
  });

  testWidgets('home empty forge', (tester) async {
    await pumpUnder(tester, AppTheme.forgeDarkTheme, emptyOverrides);
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('../goldens/home_empty_forge.png'),
    );
  });
}
