import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
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

  testWidgets('renders FilterToolbar with STATE group only',
      (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byType(FilterToolbar), findsOneWidget);
    expect(find.text('STATE'), findsOneWidget);
    expect(find.text('TM SOURCE'), findsNothing);

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Translated'), findsOneWidget);
    expect(find.text('Needs review'), findsOneWidget);
  });

  testWidgets('tapping Pending pill toggles editorFilterProvider.statusFilter',
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
      innerContainer.read(editorFilterProvider).statusFilter,
      TranslationVersionStatus.pending,
    );
  });

  testWidgets(
      'hides SEVERITY pill group when needsReview is not the statusFilter',
      (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(find.text('SEVERITY'), findsNothing);
  });

  testWidgets(
      'shows SEVERITY pill group with counts when needsReview is selected',
      (tester) async {
    await tester.pumpWidget(build(extraOverrides: [
      visibleSeverityCountsProvider(projectId, languageId).overrideWith(
        (_) async => (errors: 3, warnings: 7),
      ),
    ]));
    await tester.pumpAndSettle();

    // Flip the filter state via the running provider scope.
    final element = tester.element(find.byType(TranslationEditorScreen));
    final container = ProviderScope.containerOf(element, listen: false);
    container
        .read(editorFilterProvider.notifier)
        .setStatusFilter(TranslationVersionStatus.needsReview);
    await tester.pumpAndSettle();

    expect(find.text('SEVERITY'), findsOneWidget);
    expect(find.widgetWithText(FilterPill, 'Errors'), findsOneWidget);
    expect(find.widgetWithText(FilterPill, 'Warnings'), findsOneWidget);
    // Scope the count assertions to the FilterPill widgets — the sidebar's
    // step badge renders "3" too, so a bare find.text('3') matches twice.
    expect(find.widgetWithText(FilterPill, '3'), findsOneWidget); // error count
    expect(find.widgetWithText(FilterPill, '7'), findsOneWidget); // warning count
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
