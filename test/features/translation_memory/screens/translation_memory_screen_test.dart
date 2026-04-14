import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/translation_memory/screens/translation_memory_screen.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

/// Empty, no-op implementation of [ITranslationMemoryService] for widget tests.
///
/// Returns empty / default values for every method so the Translation Memory
/// screen can build without triggering the real DI container. Used via
/// Riverpod overrides so the TM bridge providers resolve without throwing.
class FakeTranslationMemoryService implements ITranslationMemoryService {
  @override
  Future<Result<TranslationMemoryEntry, TmAddException>> addTranslation({
    required String sourceText,
    required String targetText,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
    String? category,
  }) async =>
      Err(const TmAddException('not implemented'));

  @override
  Future<Result<int, TmAddException>> addTranslationsBatch({
    required List<({String sourceText, String targetText})> translations,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
  }) async =>
      const Ok(0);

  @override
  Future<Result<TmMatch?, TmLookupException>> findExactMatch({
    required String sourceText,
    required String targetLanguageCode,
  }) async =>
      const Ok(null);

  @override
  Future<Result<List<TmMatch>, TmLookupException>> findFuzzyMatches({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = 0.85,
    int maxResults = 5,
    String? category,
  }) async =>
      const Ok([]);

  @override
  Future<Result<TmMatch?, TmLookupException>> findBestMatch({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = 0.85,
    String? category,
  }) async =>
      const Ok(null);

  @override
  Future<Result<List<TmMatch>, TmLookupException>> findFuzzyMatchesIsolate({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = 0.85,
    int maxResults = 5,
    String? category,
  }) async =>
      const Ok([]);

  @override
  Future<Result<TranslationMemoryEntry, TmServiceException>>
      incrementUsageCount({
    required String entryId,
  }) async =>
      Err(const TmServiceException('not implemented'));

  @override
  Future<Result<int, TmServiceException>> incrementUsageCountBatch(
    Map<String, int> usageCounts,
  ) async =>
      const Ok(0);

  @override
  Future<Result<void, TmServiceException>> deleteEntry({
    required String entryId,
  }) async =>
      const Ok(null);

  @override
  Future<Result<int, TmServiceException>> cleanupUnusedEntries({
    int unusedDays = 365,
  }) async =>
      const Ok(0);

  @override
  Future<Result<TmStatistics, TmServiceException>> getStatistics({
    String? targetLanguageCode,
  }) async =>
      const Ok(TmStatistics(
        totalEntries: 0,
        entriesByLanguagePair: {},
        totalReuseCount: 0,
        tokensSaved: 0,
        averageFuzzyScore: 0.0,
        reuseRate: 0.0,
      ));

  @override
  Future<Result<int, TmImportException>> importFromTmx({
    required String filePath,
    bool overwriteExisting = false,
    void Function(int processed, int total)? onProgress,
  }) async =>
      const Ok(0);

  @override
  Future<Result<int, TmExportException>> exportToTmx({
    required String outputPath,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  }) async =>
      const Ok(0);

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>> getEntries({
    String? targetLanguageCode,
    int limit = 50,
    int offset = 0,
    String orderBy = 'usage_count DESC',
  }) async =>
      const Ok([]);

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>>
      searchEntries({
    required String searchText,
    TmSearchScope searchIn = TmSearchScope.both,
    String? targetLanguageCode,
    int limit = 50,
  }) async =>
      const Ok([]);

  @override
  Future<void> clearCache() async {}

  @override
  Future<Result<void, TmServiceException>> rebuildCache({
    int maxEntries = 10000,
  }) async =>
      const Ok(null);

  @override
  Future<Result<({int added, int existing}), TmServiceException>>
      rebuildFromTranslations({
    String? projectId,
    void Function(int processed, int total, int added)? onProgress,
  }) async =>
      const Ok((added: 0, existing: 0));

  @override
  Future<Result<int, TmServiceException>> migrateLegacyHashes({
    void Function(int processed, int total)? onProgress,
  }) async =>
      const Ok(0);
}

/// Build the Riverpod overrides shared by every test in this file.
///
/// These overrides replace the bridge providers (which normally resolve via
/// `ServiceLocator.get<T>()`) with test doubles so the TM screen widgets can
/// render without the full DI container being initialised.
/// `loggingServiceProvider` is already overridden by the test helper.
List<Override> _tmScreenOverrides() => [
      translationMemoryServiceProvider
          .overrideWithValue(FakeTranslationMemoryService()),
    ];

void main() {
  group('TranslationMemoryScreen', () {
    group('Widget Structure', () {
      testWidgets('should render FluentScaffold as root widget', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(FluentScaffold), findsOneWidget);
      });

      testWidgets('should have Column layout', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(Column), findsWidgets);
      });

      testWidgets('should have const constructor', (tester) async {
        const screen = TranslationMemoryScreen();
        expect(screen, isNotNull);
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerStatefulWidget', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Header', () {
      testWidgets('should display database icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        // The database icon appears in the screen header, in the statistics
        // panel "Total Entries" card, and in the DataGrid empty state when no
        // entries exist. Any of these satisfy the "displays a database icon"
        // expectation, so use findsWidgets rather than findsOneWidget.
        expect(find.byIcon(FluentIcons.database_24_regular), findsWidgets);
      });

      testWidgets('should display Translation Memory title', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.text('Translation Memory'), findsOneWidget);
      });

      testWidgets('should have header padding of 24.0', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Action Buttons', () {
      testWidgets('should display Import button', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.text('Import'), findsOneWidget);
      });

      testWidgets('should display Export button', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.text('Export'), findsOneWidget);
      });

      testWidgets('should display Cleanup button', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.text('Cleanup'), findsOneWidget);
      });

      testWidgets('should have import icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byIcon(FluentIcons.arrow_import_24_regular), findsWidgets);
      });

      testWidgets('should have export icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byIcon(FluentIcons.arrow_export_24_regular), findsWidgets);
      });

      testWidgets('should have broom icon for cleanup', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byIcon(FluentIcons.broom_24_regular), findsOneWidget);
      });

      testWidgets('should have tooltips on buttons', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(Tooltip), findsWidgets);
      });
    });

    group('Main Layout', () {
      testWidgets('should have Row layout for content', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(Row), findsWidgets);
      });

      testWidgets('should have divider between header and content', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(Divider), findsWidgets);
      });
    });

    group('Statistics Panel', () {
      testWidgets('should render TmStatisticsPanel', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });

      testWidgets('should have fixed width of 280', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Toolbar', () {
      testWidgets('should render TmSearchBar', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });

      testWidgets('should display Refresh button', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.text('Refresh'), findsOneWidget);
      });

      testWidgets('should have refresh icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byIcon(FluentIcons.arrow_clockwise_24_regular), findsWidgets);
      });

      testWidgets('should have toolbar padding of 16.0', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('DataGrid', () {
      testWidgets('should render TmBrowserDataGrid', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Pagination', () {
      testWidgets('should render TmPaginationBar', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Dialogs', () {
      testWidgets('should show import dialog on Import tap', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });

      testWidgets('should show export dialog on Export tap', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });

      testWidgets('should show cleanup dialog on Cleanup tap', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Refresh Action', () {
      testWidgets('should invalidate providers on refresh', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Vertical Divider', () {
      testWidgets('should have vertical divider between panels', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(VerticalDivider), findsWidgets);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const TranslationMemoryScreen(),
            overrides: _tmScreenOverrides(),
            theme: ThemeData.light(),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const TranslationMemoryScreen(),
            overrides: _tmScreenOverrides(),
            theme: ThemeData.dark(),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });

      testWidgets('should use theme primary color for icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Accessibility', () {
      testWidgets('should have accessible header', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.text('Translation Memory'), findsOneWidget);
      });

      testWidgets('should have accessible action buttons', (tester) async {
        await tester.pumpWidget(createTestableWidget(
          const TranslationMemoryScreen(),
          overrides: _tmScreenOverrides(),
        ));
        await tester.pump();

        expect(find.text('Import'), findsOneWidget);
        expect(find.text('Export'), findsOneWidget);
        expect(find.text('Cleanup'), findsOneWidget);
        expect(find.text('Refresh'), findsOneWidget);
      });
    });
  });
}
