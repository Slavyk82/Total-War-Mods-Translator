import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/home/providers/action_grid_providers.dart';
import 'package:twmt/features/home/providers/workflow_providers.dart';
import 'package:twmt/features/home/widgets/workflow_ribbon.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/cards/workflow_card.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
    // Give the ribbon a wide enough viewport so the four cards fit without
    // horizontal overflow (default test surface is only 800x600).
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

  testWidgets('renders 4 workflow cards', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const WorkflowRibbon(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        modsDiscoveredCountProvider.overrideWith((ref) async => 187),
        modsWithUpdatesCountProvider.overrideWith((ref) async => 5),
        activeProjectsCountProvider.overrideWith((ref) async => 24),
        projectsToReviewCountProvider.overrideWith((ref) async => 2),
        projectsReadyToCompileCountProvider.overrideWith((ref) async => 3),
        packsAwaitingPublishCountProvider.overrideWith((ref) async => 1),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.byType(WorkflowCard), findsNWidgets(4));
    expect(find.text('Detect'), findsOneWidget);
    expect(find.text('Translate'), findsOneWidget);
    // `Compile` and `Publish` appear both as the card title and as the CTA
    // label when those steps are `current`, so match at least once.
    expect(find.text('Compile'), findsAtLeastNWidgets(1));
    expect(find.text('Publish'), findsAtLeastNWidgets(1));
  });

  testWidgets('step 1 is done when mods > 0, step 2 is current',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const WorkflowRibbon(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        modsDiscoveredCountProvider.overrideWith((ref) async => 187),
        modsWithUpdatesCountProvider.overrideWith((ref) async => 0),
        activeProjectsCountProvider.overrideWith((ref) async => 24),
        projectsToReviewCountProvider.overrideWith((ref) async => 0),
        projectsReadyToCompileCountProvider.overrideWith((ref) async => 0),
        packsAwaitingPublishCountProvider.overrideWith((ref) async => 0),
      ],
    ));
    await tester.pumpAndSettle();
    // Card 1 has state done (check mark rendered)
    expect(find.text('✓'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // step 2 number
  });
}
