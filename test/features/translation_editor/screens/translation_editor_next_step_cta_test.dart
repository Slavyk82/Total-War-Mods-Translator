// Task 11 (workflow-improvements): when a translation language reaches 100%
// completion, the editor screen surfaces a NextStepCta routing to Pack
// Compilation. These tests pin the CTA to the full-progress branch and assert
// it stays hidden when progress is below 100%.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/providers/translation_settings_provider.dart';
import 'package:twmt/features/translation_editor/screens/translation_editor_screen.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/workflow/next_step_cta.dart';

import '../../../helpers/test_helpers.dart';

const _projectId = 'p-1';
const _languageId = 'fr';

EditorStats _stats(double completionPercentage, {int total = 100}) {
  final translated = (total * (completionPercentage / 100)).round();
  return EditorStats(
    totalUnits: total,
    pendingCount: total - translated,
    translatedCount: translated,
    needsReviewCount: 0,
    completionPercentage: completionPercentage,
  );
}

/// Minimal TranslationSettingsNotifier stub so the editor's initState
/// post-frame callback can reset the skip-TM flag without touching storage.
class _StubSettingsNotifier extends TranslationSettingsNotifier {
  @override
  TranslationSettings build() => const TranslationSettings(
        unitsPerBatch: 0,
        parallelBatches: 5,
        skipTranslationMemory: false,
      );

  @override
  void setSkipTranslationMemory(bool value) {}

  @override
  Future<void> updateSettings({int? unitsPerBatch, int? parallelBatches}) async {}

  @override
  Future<TranslationSettings> ensureLoaded() async => state;
}

Widget _wrap({required EditorStats stats, GoRouter? router}) {
  final rc = router ??
      GoRouter(
        initialLocation: '/editor',
        routes: [
          GoRoute(
            path: '/editor',
            builder: (_, _) => const TranslationEditorScreen(
              projectId: _projectId,
              languageId: _languageId,
            ),
          ),
          GoRoute(
            path: '/publishing/pack',
            builder: (_, _) => const Scaffold(body: Text('PACK_COMPILATION')),
          ),
        ],
      );
  return ProviderScope(
    overrides: [
      currentProjectProvider(_projectId).overrideWith(
        (ref) async => Project(
          id: _projectId,
          name: 'Test Project',
          gameInstallationId: 'gi-1',
          projectType: 'mod',
          createdAt: 0,
          updatedAt: 0,
        ),
      ),
      currentLanguageProvider(_languageId).overrideWith(
        (ref) async => const Language(
          id: _languageId,
          code: 'fr',
          name: 'French',
          nativeName: 'Francais',
        ),
      ),
      translationRowsProvider(_projectId, _languageId).overrideWith(
        (ref) async => <TranslationRow>[],
      ),
      editorStatsProvider(_projectId, _languageId).overrideWith(
        (ref) async => stats,
      ),
      translationSettingsProvider.overrideWith(() => _StubSettingsNotifier()),
    ],
    child: MaterialApp.router(
      theme: AppTheme.atelierDarkTheme,
      routerConfig: rc,
    ),
  );
}

void main() {
  setUp(() async {
    await setupMockServices();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1920, 1080);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
    await tearDownMockServices();
  });

  testWidgets('shows Next-step CTA when language is 100% translated',
      (tester) async {
    await tester.pumpWidget(_wrap(stats: _stats(100.0)));
    await tester.pumpAndSettle();

    expect(find.byType(NextStepCta), findsOneWidget);
    expect(find.text('Next: Compile this pack'), findsOneWidget);
  });

  testWidgets('hides Next-step CTA when language is 99% translated',
      (tester) async {
    await tester.pumpWidget(_wrap(stats: _stats(99.0)));
    await tester.pumpAndSettle();

    expect(find.byType(NextStepCta), findsNothing);
  });

  testWidgets('hides Next-step CTA while stats are loading', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentProjectProvider(_projectId).overrideWith(
          (ref) async => Project(
            id: _projectId,
            name: 'Test Project',
            gameInstallationId: 'gi-1',
            projectType: 'mod',
            createdAt: 0,
            updatedAt: 0,
          ),
        ),
        currentLanguageProvider(_languageId).overrideWith(
          (ref) async => const Language(
            id: _languageId,
            code: 'fr',
            name: 'French',
            nativeName: 'Francais',
          ),
        ),
        translationRowsProvider(_projectId, _languageId).overrideWith(
          (ref) async => <TranslationRow>[],
        ),
        // Never-completing future keeps the stats provider in loading state.
        editorStatsProvider(_projectId, _languageId).overrideWith(
          (ref) => Future<EditorStats>.delayed(const Duration(minutes: 5)),
        ),
        translationSettingsProvider.overrideWith(() => _StubSettingsNotifier()),
      ],
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: const TranslationEditorScreen(
          projectId: _projectId,
          languageId: _languageId,
        ),
      ),
    ));
    // Pump once so initState + first build run, without awaiting the
    // pending stats future.
    await tester.pump();

    expect(find.byType(NextStepCta), findsNothing);
  });

  testWidgets('tapping the CTA navigates to /publishing/pack', (tester) async {
    final router = GoRouter(
      initialLocation: '/editor',
      routes: [
        GoRoute(
          path: '/editor',
          builder: (_, _) => const TranslationEditorScreen(
            projectId: _projectId,
            languageId: _languageId,
          ),
        ),
        GoRoute(
          path: '/publishing/pack',
          builder: (_, _) => const Scaffold(body: Text('PACK_COMPILATION')),
        ),
      ],
    );

    await tester.pumpWidget(_wrap(stats: _stats(100.0), router: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NextStepCta));
    await tester.pumpAndSettle();

    expect(find.text('PACK_COMPILATION'), findsOneWidget);
  });
}
