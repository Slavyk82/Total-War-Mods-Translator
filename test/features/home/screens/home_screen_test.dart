import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/activity/providers/activity_providers.dart';
import 'package:twmt/features/home/providers/action_grid_providers.dart';
import 'package:twmt/features/home/providers/home_providers.dart';
import 'package:twmt/features/home/providers/home_status_provider.dart';
import 'package:twmt/features/home/providers/workflow_providers.dart';
import 'package:twmt/features/home/screens/home_screen.dart';
import 'package:twmt/features/home/widgets/empty_state_guide.dart';
import 'package:twmt/features/home/widgets/recent_projects_list.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
    // Ensure the viewport is wide enough for the full dashboard (workflow
    // ribbon + recent/activity columns) without triggering overflow.
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

  // Shared overrides that don't depend on the active-projects count.
  // The per-test override list injects the right `activeProjectsCountProvider`
  // value explicitly so we never register duplicate overrides for the same
  // provider (Riverpod resolves duplicates in an order we don't want to rely on).
  final baseOverrides = [
    modsDiscoveredCountProvider.overrideWith((ref) async => 187),
    modsWithUpdatesCountProvider.overrideWith((ref) async => 5),
    projectsToReviewCountProvider.overrideWith((ref) async => 2),
    projectsReadyToCompileCountProvider.overrideWith((ref) async => 3),
    packsAwaitingPublishCountProvider.overrideWith((ref) async => 1),
    homeStatusProvider.overrideWith(
      (ref) async => const HomeStatus(HomeStatusKind.needsAttention, 2),
    ),
    recentProjectsProvider.overrideWith((ref) async => const []),
    activityFeedProvider.overrideWith((ref) async => const []),
  ];

  testWidgets('renders full dashboard when projects > 0', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const HomeScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        activeProjectsCountProvider.overrideWith((ref) async => 24),
        ...baseOverrides,
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Workflow'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.byType(EmptyStateGuide), findsNothing);
    expect(find.byType(RecentProjectsList), findsOneWidget);
  });

  testWidgets('renders empty state when projects == 0', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const HomeScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        activeProjectsCountProvider.overrideWith((ref) async => 0),
        ...baseOverrides,
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyStateGuide), findsOneWidget);
    expect(find.byType(RecentProjectsList), findsNothing);
  });
}
