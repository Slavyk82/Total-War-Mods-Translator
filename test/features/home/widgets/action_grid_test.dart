import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/home/providers/action_grid_providers.dart';
import 'package:twmt/features/home/providers/workflow_providers.dart';
import 'package:twmt/features/home/widgets/action_grid.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/cards/action_card.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
    // Give the grid a wide enough viewport so the four cards fit without
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

  testWidgets('renders 4 action cards with correct values', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const ActionGrid(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        projectsToReviewCountProvider.overrideWith((ref) async => 2),
        projectsReadyToCompileCountProvider.overrideWith((ref) async => 3),
        modsWithUpdatesCountProvider.overrideWith((ref) async => 5),
        packsAwaitingPublishCountProvider.overrideWith((ref) async => 1),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ActionCard), findsNWidgets(4));
    expect(find.text('To review'.toUpperCase()), findsOneWidget);
    expect(find.text('Ready to compile'.toUpperCase()), findsOneWidget);
    expect(find.text('Mod updates'.toUpperCase()), findsOneWidget);
    expect(find.text('Ready to publish'.toUpperCase()), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });
}
