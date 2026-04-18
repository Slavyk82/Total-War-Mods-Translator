import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
import 'package:twmt/features/translation_editor/providers/translation_settings_provider.dart';
import 'package:twmt/features/translation_editor/screens/translation_editor_screen.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  const projectId = 'p';
  const languageId = 'fr';

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

  Widget build({List<Override> extraOverrides = const []}) {
    return ProviderScope(
      overrides: [
        currentProjectProvider(projectId).overrideWith(
          (ref) async => Project(
            id: projectId,
            name: 'Test Project',
            gameInstallationId: 'g',
            projectType: 'mod',
            createdAt: DateTime.now().millisecondsSinceEpoch,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
        currentLanguageProvider(languageId).overrideWith(
          (ref) async => const Language(
            id: languageId,
            code: 'fr',
            name: 'French',
            nativeName: 'Francais',
          ),
        ),
        translationRowsProvider(projectId, languageId)
            .overrideWith((ref) async => <TranslationRow>[]),
        editorStatsProvider(projectId, languageId).overrideWith(
          (ref) async => const EditorStats(
            totalUnits: 100,
            pendingCount: 50,
            translatedCount: 40,
            needsReviewCount: 10,
            completionPercentage: 40.0,
          ),
        ),
        translationSettingsProvider.overrideWith(
          () => _Settings(),
        ),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: const SizedBox(
          width: 1920,
          height: 1080,
          child: TranslationEditorScreen(
            projectId: projectId,
            languageId: languageId,
          ),
        ),
      ),
    );
  }

  testWidgets('renders FilterToolbar with STATUS and TM SOURCE groups',
      (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byType(FilterToolbar), findsOneWidget);
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.text('TM SOURCE'), findsOneWidget);

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Translated'), findsOneWidget);
    expect(find.text('Needs review'), findsOneWidget);
    expect(find.text('Exact match'), findsOneWidget);
    expect(find.text('Fuzzy match'), findsOneWidget);
    expect(find.text('LLM'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('tapping Pending pill toggles editorFilterProvider.statusFilters',
      (tester) async {
    final container = ProviderContainer(overrides: [
      editorStatsProvider(projectId, languageId).overrideWith(
        (ref) async => const EditorStats(
          totalUnits: 100,
          pendingCount: 50,
          translatedCount: 40,
          needsReviewCount: 10,
          completionPercentage: 40.0,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    // Tap the Pending pill.
    await tester.tap(find.widgetWithText(FilterPill, 'Pending'));
    await tester.pumpAndSettle();

    // Read the provider from the screen's scope via any ProviderScope.
    final element = tester.element(find.byType(TranslationEditorScreen));
    final innerContainer =
        ProviderScope.containerOf(element, listen: false);
    expect(
      innerContainer.read(editorFilterProvider).statusFilters,
      contains(TranslationVersionStatus.pending),
    );
  });
}

class _Settings extends TranslationSettingsNotifier {
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
