import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/activity/models/activity_event.dart';
import 'package:twmt/features/activity/providers/activity_providers.dart';
import 'package:twmt/features/home/widgets/activity_feed_panel.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Minimal ActivityEvent fixture. Only the fields the widget actually reads
/// (`type`, `timestamp`, `payload`) carry test-facing data; id/projectId/
/// gameCode use the constructor-required defaults spelled out in the spec.
ActivityEvent _evt(
  ActivityEventType type,
  Map<String, dynamic> payload, {
  DateTime? when,
}) =>
    ActivityEvent(
      id: 1,
      type: type,
      timestamp: when ?? DateTime.now(),
      projectId: null,
      gameCode: 'wh3',
      payload: payload,
    );

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
    // Ensure a desktop-class viewport so the panel never reports a
    // horizontal overflow on the default 800x600 test surface.
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

  testWidgets('renders rows for each event', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const ActivityFeedPanel(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        activityFeedProvider.overrideWith((ref) async => [
              _evt(
                ActivityEventType.translationBatchCompleted,
                {'count': 124, 'method': 'llm', 'projectName': 'TechTree'},
              ),
              _evt(
                ActivityEventType.packCompiled,
                {'projectName': 'Tribes', 'packFileName': 'x.pack'},
              ),
            ]),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('TechTree'), findsOneWidget);
    expect(find.textContaining('Tribes'), findsOneWidget);
  });

  testWidgets('empty placeholder when no events', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const ActivityFeedPanel(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        activityFeedProvider.overrideWith((ref) async => const []),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('No recent activity'), findsOneWidget);
  });
}
