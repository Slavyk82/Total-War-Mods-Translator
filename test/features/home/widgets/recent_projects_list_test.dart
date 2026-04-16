import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/home/models/next_project_action.dart';
import 'package:twmt/features/home/models/project_with_next_action.dart';
import 'package:twmt/features/home/providers/home_providers.dart';
import 'package:twmt/features/home/widgets/recent_projects_list.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Minimal Project fixture. Mirrors the `_project` helper used by the
/// recent-projects provider test (Task 10) — only the fields the widget
/// reads (`id`, `name`) carry test-facing data; everything else uses the
/// defaults required by the Project constructor.
Project _project(String id, String name) => Project(
      id: id,
      name: name,
      gameInstallationId: 'install-test',
      createdAt: 0,
      updatedAt: 0,
    );

ProjectWithNextAction _pwa(String name, NextProjectAction a, int pct) =>
    ProjectWithNextAction(
      project: _project('id-$name', name),
      action: a,
      translatedPct: pct,
    );

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
    // Ensure a desktop-class viewport so the 4-row list never reports a
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

  testWidgets('renders N rows with names and next-action badges',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const RecentProjectsList(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        recentProjectsProvider.overrideWith((ref) async => [
              _pwa('Tribes', NextProjectAction.readyToCompile, 100),
              _pwa('TechTree', NextProjectAction.continueWork, 72),
              _pwa('Godslayer', NextProjectAction.toReview, 45),
              _pwa('OvN', NextProjectAction.translate, 0),
            ]),
      ],
    ));
    await tester.pumpAndSettle();

    // 4 rows rendered via the dedicated key.
    expect(find.byKey(const Key('RecentProjectsRow')), findsNWidgets(4));

    // Project names.
    expect(find.text('Tribes'), findsOneWidget);
    expect(find.text('TechTree'), findsOneWidget);
    expect(find.text('Godslayer'), findsOneWidget);
    expect(find.text('OvN'), findsOneWidget);

    // Next-action badge labels.
    expect(find.text('Ready to compile'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('To review'), findsOneWidget);
    expect(find.text('Translate'), findsOneWidget);
  });

  testWidgets('renders nothing when list empty', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const RecentProjectsList(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        recentProjectsProvider.overrideWith((ref) async => const []),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('RecentProjectsRow')), findsNothing);
  });
}
