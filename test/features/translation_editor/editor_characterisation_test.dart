import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/database/database_service.dart';

import '../../helpers/mock_logging_service.dart';

/// Characterisation tests for the Translation Editor feature.
///
/// These tests lock in the current observable behaviour of the providers,
/// filtering / selection logic, and navigation guard consumer prior to the
/// Phase 4 editor fragmentation refactor (Tasks 2-4). Any deviation in
/// behaviour during fragmentation should trip these assertions.
///
/// Scope: provider-level regression net.
/// - Avoids deep widget-tree rendering (screen tests already cover that).
/// - Uses an in-memory sqflite instance to exercise the real repositories
///   rather than mocking them, so query semantics (ORDER BY, JOIN, filters)
///   are part of the contract.
void main() {
  const projectId = 'project-test';
  const languageId = 'language-test';
  const projectLanguageId = 'pl-test';

  late Database db;
  late TranslationUnitRepository unitRepository;
  late TranslationVersionRepository versionRepository;
  late ProjectLanguageRepository projectLanguageRepository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Minimal schema required by TranslationUnitRepository.getTranslationRowsJoined
    // and TranslationVersionRepository.acceptBatch (small-batch path, no triggers).
    await db.execute('''
      CREATE TABLE translation_units (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        key TEXT NOT NULL,
        source_text TEXT NOT NULL,
        context TEXT,
        notes TEXT,
        source_loc_file TEXT,
        is_obsolete INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE translation_versions (
        id TEXT PRIMARY KEY,
        unit_id TEXT NOT NULL,
        project_language_id TEXT NOT NULL,
        translated_text TEXT,
        is_manually_edited INTEGER DEFAULT 0,
        status TEXT DEFAULT 'pending',
        translation_source TEXT,
        validation_issues TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE project_languages (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        language_id TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        progress_percent REAL DEFAULT 0.0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    DatabaseService.setTestDatabase(db);

    unitRepository = TranslationUnitRepository();
    versionRepository = TranslationVersionRepository();
    projectLanguageRepository = ProjectLanguageRepository();

    await _seedFixture(
      db: db,
      unitRepository: unitRepository,
      projectLanguageRepository: projectLanguageRepository,
      projectId: projectId,
      languageId: languageId,
      projectLanguageId: projectLanguageId,
    );
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  /// Builds a `ProviderContainer` wired to the seeded in-memory database.
  /// Overrides the editor-local repository providers so every downstream
  /// `ref.watch(...)` resolves to the real repositories under test.
  ProviderContainer buildContainer() {
    return ProviderContainer(
      overrides: [
        loggingServiceProvider.overrideWithValue(NoopLoggingService()),
        translationUnitRepositoryProvider.overrideWith((ref) => unitRepository),
        translationVersionRepositoryProvider
            .overrideWith((ref) => versionRepository),
        projectLanguageRepositoryProvider
            .overrideWith((ref) => projectLanguageRepository),
      ],
    );
  }

  group('translationRowsProvider', () {
    test(
        'resolves to all seeded units ordered by key ASC '
        '(case 1: grid loads N rows)', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final rows = await container
          .read(translationRowsProvider(projectId, languageId).future);

      expect(rows, hasLength(3));
      expect(
        rows.map((r) => r.key).toList(),
        equals(<String>['key.alpha', 'key.bravo', 'key.charlie']),
      );
    });
  });

  group('filteredTranslationRowsProvider', () {
    test(
        'narrows to translated rows when status filter is set '
        '(case 2a: status filter)', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      // Hold listeners on both providers: editorFilter is auto-disposed
      // between reads (losing the set filters) and filteredTranslationRows
      // needs a live listener across its async build. Only then apply the
      // filter and resolve.
      final filterSub = container.listen(editorFilterProvider, (_, _) {});
      addTearDown(filterSub.close);
      container
          .read(editorFilterProvider.notifier)
          .setStatusFilters({TranslationVersionStatus.translated});
      final sub = container.listen(
        filteredTranslationRowsProvider(projectId, languageId),
        (_, _) {},
      );
      addTearDown(sub.close);

      final filtered = await container
          .read(filteredTranslationRowsProvider(projectId, languageId).future);

      expect(filtered, hasLength(1));
      expect(filtered.single.key, equals('key.bravo'));
      expect(
        filtered.single.status,
        equals(TranslationVersionStatus.translated),
      );
    });

    test(
        'returns all rows when no filters are active '
        '(case 2b: cleared filter returns full set)', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final filterSub = container.listen(editorFilterProvider, (_, _) {});
      addTearDown(filterSub.close);
      final sub = container.listen(
        filteredTranslationRowsProvider(projectId, languageId),
        (_, _) {},
      );
      addTearDown(sub.close);

      // Default filter state has no active filters -> full set.
      final all = await container
          .read(filteredTranslationRowsProvider(projectId, languageId).future);
      expect(all, hasLength(3));

      // Explicit clear is an identity operation on the default state.
      container.read(editorFilterProvider.notifier).clearFilters();
      expect(
        container.read(editorFilterProvider).hasActiveFilters,
        isFalse,
      );
    });

    /// Each sub-test spins up a fresh container, holds a subscription on
    /// `editorFilterProvider` (which is auto-disposed between reads and
    /// would otherwise forget the query), applies the query, then reads
    /// the filtered provider with an active listener to avoid mid-rebuild
    /// disposal under Riverpod 3's one-shot `.future` semantics.
    Future<List<TranslationRow>> resolveWithQuery(String query) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      final filterSub = container.listen(editorFilterProvider, (_, _) {});
      addTearDown(filterSub.close);
      container.read(editorFilterProvider.notifier).setSearchQuery(query);
      final sub = container.listen(
        filteredTranslationRowsProvider(projectId, languageId),
        (_, _) {},
      );
      addTearDown(sub.close);
      return container.read(
        filteredTranslationRowsProvider(projectId, languageId).future,
      );
    }

    test('search query matches a unit key (case 3a)', () async {
      final filtered = await resolveWithQuery('alpha');
      expect(filtered, hasLength(1));
      expect(filtered.single.key, equals('key.alpha'));
    });

    test('search query matches source text (case 3b)', () async {
      final filtered = await resolveWithQuery('second source');
      expect(filtered, hasLength(1));
      expect(filtered.single.key, equals('key.bravo'));
    });

    test('search query matches translated text (case 3c)', () async {
      final filtered = await resolveWithQuery('manual draft');
      expect(filtered, hasLength(1));
      expect(filtered.single.key, equals('key.charlie'));
    });
  });

  group('editorSelectionProvider + batch mark-reviewed action', () {
    test(
        'toggling selection on two rows and invoking the bulk-accept '
        'entry point updates the selected versions to translated '
        '(case 4: selection + batch action)', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final rows = await container
          .read(translationRowsProvider(projectId, languageId).future);

      final alpha = rows.firstWhere((r) => r.key == 'key.alpha');
      final charlie = rows.firstWhere((r) => r.key == 'key.charlie');

      // Toggle selection on two of three rows.
      container
          .read(editorSelectionProvider.notifier)
          .toggleSelection(alpha.unit.id);
      container
          .read(editorSelectionProvider.notifier)
          .toggleSelection(charlie.unit.id);

      final selection = container.read(editorSelectionProvider);
      expect(selection.selectedCount, equals(2));
      expect(selection.isSelected(alpha.unit.id), isTrue);
      expect(selection.isSelected(charlie.unit.id), isTrue);

      // Resolve selected version IDs from the current rows, then invoke
      // the same repository entry point used by the editor's bulk-accept
      // action (`editor_actions_validation.dart::_handleBulkAcceptTranslation`).
      final selectedVersionIds = rows
          .where((r) => selection.isSelected(r.unit.id))
          .map((r) => r.version.id)
          .toList();

      final repoResult = await versionRepository.acceptBatch(selectedVersionIds);
      expect(repoResult.isOk, isTrue);
      expect(repoResult.unwrap(), equals(2));

      // Assert both selected rows are now `translated` in the database.
      final alphaAfter = await versionRepository.getById(alpha.version.id);
      final charlieAfter = await versionRepository.getById(charlie.version.id);
      expect(alphaAfter.isOk, isTrue);
      expect(charlieAfter.isOk, isTrue);
      expect(
        alphaAfter.unwrap().status,
        equals(TranslationVersionStatus.translated),
      );
      expect(
        charlieAfter.unwrap().status,
        equals(TranslationVersionStatus.translated),
      );
      expect(alphaAfter.unwrap().validationIssues, isNull);
      expect(charlieAfter.unwrap().validationIssues, isNull);

      // The unselected row should be untouched.
      final bravo = rows.firstWhere((r) => r.key == 'key.bravo');
      final bravoAfter = await versionRepository.getById(bravo.version.id);
      expect(
        bravoAfter.unwrap().status,
        equals(TranslationVersionStatus.translated),
      );
    });
  });

  group('selectedLlmModelProvider', () {
    test(
        'retains its value while any listener on the container exists '
        '(case 5: keepAlive semantics)', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      container
          .read(selectedLlmModelProvider.notifier)
          .setModel('foo-model-id');

      expect(container.read(selectedLlmModelProvider), equals('foo-model-id'));

      // In Riverpod 3, @Riverpod(keepAlive: true) prevents the state from
      // being disposed when the last listener drops. Allow the scheduler to
      // run a frame with no listeners and ensure the state survives.
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(selectedLlmModelProvider),
        equals('foo-model-id'),
        reason: 'keepAlive: true must preserve state across dispose windows',
      );

      // Also confirm that the clear() notifier method resets the state.
      container.read(selectedLlmModelProvider.notifier).clear();
      expect(container.read(selectedLlmModelProvider), isNull);
    });
  });

  group('translationInProgressProvider', () {
    test(
        'is consumed by the navigation guard and its state flips '
        'observably (case 6: navigation block signal)', () {
      final container = buildContainer();
      addTearDown(container.dispose);

      // Default state must be false so the guard in
      // `lib/widgets/layouts/main_layout_router.dart::_canNavigate` allows
      // navigation.
      expect(container.read(translationInProgressProvider), isFalse);

      // Flipping to true is the exact signal the guard reads to block
      // navigation (and show the "Translation in progress" warning toast).
      container
          .read(translationInProgressProvider.notifier)
          .setInProgress(true);
      expect(container.read(translationInProgressProvider), isTrue);

      // The provider is keepAlive: true, so disposing all widget listeners
      // should not reset the state mid-translation.
      container
          .read(translationInProgressProvider.notifier)
          .setInProgress(false);
      expect(container.read(translationInProgressProvider), isFalse);
    });

    testWidgets(
        'a consumer reading translationInProgressProvider sees the flipped '
        'value (widget-level contract with the navigation guard)',
        (tester) async {
      late bool observed;
      final scope = ProviderScope(
        overrides: [
          loggingServiceProvider.overrideWithValue(NoopLoggingService()),
          translationInProgressProvider.overrideWith(() => _AlwaysInProgress()),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              observed = ref.watch(translationInProgressProvider);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(scope);
      await tester.pump();

      expect(
        observed,
        isTrue,
        reason:
            'The navigation guard and any other consumer must observe the '
            'in-progress flag via translationInProgressProvider.',
      );
    });
  });
}

/// Fixture: 1 project + 1 target language + 3 translation units + 3 versions.
/// Status mix: pending / translated / needsReview.
Future<void> _seedFixture({
  required Database db,
  required TranslationUnitRepository unitRepository,
  required ProjectLanguageRepository projectLanguageRepository,
  required String projectId,
  required String languageId,
  required String projectLanguageId,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // project_language row that joins the project and the target language.
  await projectLanguageRepository.insert(
    ProjectLanguage(
      id: projectLanguageId,
      projectId: projectId,
      languageId: languageId,
      createdAt: now,
      updatedAt: now,
    ),
  );

  // Three translation units with deliberately different keys (to validate
  // ORDER BY key ASC) and distinct source texts (for search-query cases).
  final units = <TranslationUnit>[
    TranslationUnit(
      id: 'unit-alpha',
      projectId: projectId,
      key: 'key.alpha',
      sourceText: 'First source string',
      createdAt: now,
      updatedAt: now,
    ),
    TranslationUnit(
      id: 'unit-bravo',
      projectId: projectId,
      key: 'key.bravo',
      sourceText: 'Second source text',
      createdAt: now,
      updatedAt: now,
    ),
    TranslationUnit(
      id: 'unit-charlie',
      projectId: projectId,
      key: 'key.charlie',
      sourceText: 'Third source content',
      createdAt: now,
      updatedAt: now,
    ),
  ];
  for (final unit in units) {
    await unitRepository.insert(unit);
  }

  // Matching versions: pending / translated / needsReview.
  // Version IDs are deterministic for assertion stability.
  await db.insert('translation_versions', {
    'id': 'version-alpha',
    'unit_id': 'unit-alpha',
    'project_language_id': projectLanguageId,
    'translated_text': null,
    'is_manually_edited': 0,
    'status': 'pending',
    'translation_source': 'unknown',
    'validation_issues': null,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('translation_versions', {
    'id': 'version-bravo',
    'unit_id': 'unit-bravo',
    'project_language_id': projectLanguageId,
    'translated_text': 'Deuxieme texte source',
    'is_manually_edited': 0,
    'status': 'translated',
    'translation_source': 'llm',
    'validation_issues': null,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('translation_versions', {
    'id': 'version-charlie',
    'unit_id': 'unit-charlie',
    'project_language_id': projectLanguageId,
    'translated_text': 'Manual draft with issues',
    'is_manually_edited': 1,
    'status': 'needs_review',
    'translation_source': 'manual',
    'validation_issues': '[{type: whitespace, severity: warning, '
        'description: trailing space}]',
    'created_at': now,
    'updated_at': now,
  });
}

/// Notifier fake that always reports a translation as in progress. Exists so
/// test case 6 can verify the consumer-side contract without having to drive
/// the real translation pipeline.
class _AlwaysInProgress extends TranslationInProgress {
  @override
  bool build() => true;
}
