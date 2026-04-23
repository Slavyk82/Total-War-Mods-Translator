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

  testWidgets('renders 3 workflow cards', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const WorkflowRibbon(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        modsDiscoveredCountProvider.overrideWith((ref) async => 187),
        modsWithUpdatesCountProvider.overrideWith((ref) async => 5),
        activeProjectsCountProvider.overrideWith((ref) async => 24),
        projectsToReviewCountProvider.overrideWith((ref) async => 2),
        packsAwaitingPublishCountProvider.overrideWith((ref) async => 1),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.byType(WorkflowCard), findsNWidgets(3));
    expect(find.text('Detect'), findsOneWidget);
    expect(find.text('Translate'), findsOneWidget);
    expect(find.text('Compile'), findsNothing);
    // `Publish` appears both as the card title and as the CTA label when the
    // step is `current`, so match at least once.
    expect(find.text('Publish'), findsAtLeastNWidgets(1));
  });

  testWidgets('all 3 cards render in current state with step numbers',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const WorkflowRibbon(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        modsDiscoveredCountProvider.overrideWith((ref) async => 187),
        modsWithUpdatesCountProvider.overrideWith((ref) async => 0),
        activeProjectsCountProvider.overrideWith((ref) async => 24),
        projectsToReviewCountProvider.overrideWith((ref) async => 0),
        packsAwaitingPublishCountProvider.overrideWith((ref) async => 0),
      ],
    ));
    await tester.pumpAndSettle();
    // No checkmark: the `done` visual state is no longer used.
    expect(find.text('✓'), findsNothing);
    // Every card now shows its step number in the badge.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
