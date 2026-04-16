import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/providers/tm_reuse_stats_provider.dart';
import 'package:twmt/features/translation_editor/widgets/editor_status_bar.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1920, 1080);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('renders four metrics + encoding when stats are loaded', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const Scaffold(
        body: EditorStatusBar(projectId: 'p', languageId: 'fr'),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        editorStatsProvider('p', 'fr').overrideWith((_) async => const EditorStats(
              totalUnits: 4540,
              pendingCount: 1240,
              translatedCount: 3268,
              needsReviewCount: 32,
              completionPercentage: 72.0,
            )),
        tmReuseStatsProvider('p', 'fr').overrideWith((_) async => const TmReuseStats(
              translatedCount: 3268,
              reusedCount: 2672,
              reusePercentage: 81.8,
            )),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('4540 units'), findsOneWidget);
    expect(find.textContaining('3268 translated'), findsOneWidget);
    expect(find.textContaining('72'), findsAtLeast(1));
    expect(find.text('32 need review'), findsOneWidget);
    expect(find.textContaining('TM 82'), findsOneWidget); // rounded
    expect(find.text('UTF-8 · CRLF'), findsOneWidget);
  });

  testWidgets('shows skeleton when loading', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const Scaffold(
        body: EditorStatusBar(projectId: 'p', languageId: 'fr'),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        // Use never-completing futures (Completer.future) instead of
        // `Future.delayed` so the test does not leak a pending timer that
        // would trip the framework's invariant check on teardown.
        editorStatsProvider('p', 'fr').overrideWith((_) => Completer<EditorStats>().future),
        tmReuseStatsProvider('p', 'fr').overrideWith((_) => Completer<TmReuseStats>().future),
      ],
    ));
    await tester.pump(); // 1 frame, providers still loading

    expect(find.text('· · ·'), findsAtLeast(1));
    expect(find.text('UTF-8 · CRLF'), findsOneWidget);
  });

  testWidgets('renders nothing left side when stats error', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const Scaffold(
        body: EditorStatusBar(projectId: 'p', languageId: 'fr'),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        editorStatsProvider('p', 'fr').overrideWith((_) async => throw Exception('boom')),
        tmReuseStatsProvider('p', 'fr').overrideWith((_) async => TmReuseStats.empty()),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('units'), findsNothing);
    expect(find.text('UTF-8 · CRLF'), findsOneWidget);
  });
}
