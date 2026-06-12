// Complementary provider tests for `lib/providers/projects_data_providers.dart`.
//
// The auto-heal branch of `ProjectsWithDetailsNotifier._computeOne` is already
// covered by
// `test/features/projects/providers/projects_with_details_auto_heal_test.dart`.
// This file covers the *rest* of the file: the two plain data models
// (`ProjectWithDetails`, `ProjectLanguageWithInfo`), the
// `TranslationStatsVersionNotifier`, and the notifier's load / refresh /
// filtering / non-auto-heal `_computeOne` branches.
//
// The mock setup (override list, mock classes, model factories) mirrors the
// auto-heal template so the two files stay consistent.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/project_statistics.dart';
import 'package:twmt/providers/projects_data_providers.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/export_history_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/mods/mod_update_analysis_service.dart';

import '../helpers/test_bootstrap.dart';

class _MockProjectRepository extends Mock implements ProjectRepository {}

class _MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

class _MockLanguageRepository extends Mock implements LanguageRepository {}

class _MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

class _MockTranslationVersionRepository extends Mock
    implements TranslationVersionRepository {}

class _MockWorkshopModRepository extends Mock
    implements WorkshopModRepository {}

class _MockExportHistoryRepository extends Mock
    implements ExportHistoryRepository {}

class _MockModUpdateAnalysisService extends Mock
    implements ModUpdateAnalysisService {}

class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);
  final ConfiguredGame? _value;
  @override
  Future<ConfiguredGame?> build() async => _value;
}

const _game = ConfiguredGame(
  code: 'wh3',
  name: 'Total War: WARHAMMER III',
  path: 'C:/games/wh3',
);

GameInstallation _installation() {
  return GameInstallation(
    id: 'install-wh3',
    gameCode: 'wh3',
    gameName: 'WH3',
    createdAt: 0,
    updatedAt: 0,
  );
}

/// Build a project with sane defaults. `hasSourceFile`/`modSteamId` left null so
/// the timestamp-comparison / update-analysis branch of `_computeOne` is not
/// triggered (those require real filesystem stat calls).
Project _project({
  String id = 'p1',
  String name = 'Alpha',
  bool hasModUpdateImpact = false,
}) {
  return Project(
    id: id,
    name: name,
    gameInstallationId: 'install-wh3',
    createdAt: 0,
    updatedAt: 0,
    hasModUpdateImpact: hasModUpdateImpact,
  );
}

ProjectLanguage _projectLanguage({
  String id = 'pl-fr',
  String projectId = 'p1',
  String languageId = 'lang-fr',
}) {
  return ProjectLanguage(
    id: id,
    projectId: projectId,
    languageId: languageId,
    progressPercent: 100.0,
    createdAt: 0,
    updatedAt: 0,
  );
}

const _fr = Language(
  id: 'lang-fr',
  code: 'fr',
  name: 'French',
  nativeName: 'Français',
);

ProviderContainer _makeContainer({
  required ProjectRepository projectRepo,
  required ProjectLanguageRepository projectLanguageRepo,
  required LanguageRepository languageRepo,
  required GameInstallationRepository gameInstallationRepo,
  required TranslationVersionRepository versionRepo,
  required WorkshopModRepository workshopModRepo,
  required ExportHistoryRepository exportHistoryRepo,
  ConfiguredGame? selectedGame = _game,
}) {
  return ProviderContainer(overrides: [
    projectRepositoryProvider.overrideWithValue(projectRepo),
    projectLanguageRepositoryProvider.overrideWithValue(projectLanguageRepo),
    languageRepositoryProvider.overrideWithValue(languageRepo),
    gameInstallationRepositoryProvider.overrideWithValue(gameInstallationRepo),
    translationVersionRepositoryProvider.overrideWithValue(versionRepo),
    workshopModRepositoryProvider.overrideWithValue(workshopModRepo),
    exportHistoryRepositoryProvider.overrideWithValue(exportHistoryRepo),
    modUpdateAnalysisServiceProvider
        .overrideWithValue(_MockModUpdateAnalysisService()),
    selectedGameProvider.overrideWith(() => _FakeSelectedGame(selectedGame)),
  ]);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_project());
  });

  setUp(() async => TestBootstrap.registerFakes());

  // --------------------------------------------------------------------------
  // ProjectWithDetails model
  // --------------------------------------------------------------------------
  group('ProjectWithDetails', () {
    ProjectLanguageWithInfo lang({
      required int total,
      required int translated,
      int needsReview = 0,
    }) {
      return ProjectLanguageWithInfo(
        projectLanguage: _projectLanguage(),
        language: _fr,
        totalUnits: total,
        translatedUnits: translated,
        needsReviewUnits: needsReview,
      );
    }

    test('overallProgress is 0 when there are no languages', () {
      final d = ProjectWithDetails(project: _project(), languages: const []);
      expect(d.overallProgress, 0.0);
      expect(d.isFullyTranslated, isFalse);
      expect(d.hasAtLeastOneCompleteLanguage, isFalse);
      expect(d.hasNeedsReviewUnits, isFalse);
    });

    test('overallProgress averages per-language progress', () {
      final d = ProjectWithDetails(
        project: _project(),
        languages: [
          lang(total: 10, translated: 10), // 100%
          lang(total: 10, translated: 0), // 0%
        ],
      );
      expect(d.overallProgress, 50.0);
    });

    test('isFullyTranslated / hasAtLeastOneCompleteLanguage derive from langs',
        () {
      final partial = ProjectWithDetails(
        project: _project(),
        languages: [
          lang(total: 10, translated: 10),
          lang(total: 10, translated: 5),
        ],
      );
      expect(partial.isFullyTranslated, isFalse);
      expect(partial.hasAtLeastOneCompleteLanguage, isTrue);

      final full = ProjectWithDetails(
        project: _project(),
        languages: [lang(total: 10, translated: 10)],
      );
      expect(full.isFullyTranslated, isTrue);
    });

    test('hasNeedsReviewUnits is true when any language has review units', () {
      final d = ProjectWithDetails(
        project: _project(),
        languages: [lang(total: 10, translated: 10, needsReview: 3)],
      );
      expect(d.hasNeedsReviewUnits, isTrue);
    });

    test('hasUpdates is true when updateAnalysis has pending changes', () {
      final d = ProjectWithDetails(
        project: _project(),
        languages: const [],
        updateAnalysis: const ModUpdateAnalysis(
          newUnitsCount: 2,
          removedUnitsCount: 0,
          modifiedUnitsCount: 0,
          totalPackUnits: 0,
          totalProjectUnits: 0,
        ),
      );
      expect(d.hasUpdates, isTrue);
    });

    test(
        'hasUpdates is true for impacted project that is not fully translated',
        () {
      final d = ProjectWithDetails(
        project: _project(hasModUpdateImpact: true),
        languages: [lang(total: 10, translated: 5)],
      );
      expect(d.hasUpdates, isTrue);
    });

    test(
        'hasUpdates is false for impacted project that is complete with no '
        'reviews', () {
      final d = ProjectWithDetails(
        project: _project(hasModUpdateImpact: true),
        languages: [lang(total: 10, translated: 10)],
      );
      expect(d.hasUpdates, isFalse);
    });

    test('hasUpdates is false when not impacted and no pending analysis', () {
      final d = ProjectWithDetails(
        project: _project(hasModUpdateImpact: false),
        languages: [lang(total: 10, translated: 5)],
      );
      expect(d.hasUpdates, isFalse);
    });

    test('hasBeenExported reflects presence of lastPackExport', () {
      final without =
          ProjectWithDetails(project: _project(), languages: const []);
      expect(without.hasBeenExported, isFalse);

      final export = ExportHistory(
        id: 'e1',
        projectId: 'p1',
        languages: '["fr"]',
        format: ExportFormat.pack,
        validatedOnly: false,
        outputPath: 'C:/out.pack',
        entryCount: 5,
        exportedAt: 1000,
      );
      final with_ = ProjectWithDetails(
        project: _project(),
        languages: const [],
        lastPackExport: export,
      );
      expect(with_.hasBeenExported, isTrue);
    });

    test('isModifiedSinceLastExport compares updatedAt against checkpoint', () {
      final export = ExportHistory(
        id: 'e1',
        projectId: 'p1',
        languages: '["fr"]',
        format: ExportFormat.pack,
        validatedOnly: false,
        outputPath: 'C:/out.pack',
        entryCount: 5,
        exportedAt: 1000,
      );

      // No export -> false.
      expect(
        ProjectWithDetails(project: _project(), languages: const [])
            .isModifiedSinceLastExport,
        isFalse,
      );

      // updatedAt within the 60s margin of the export -> not modified.
      final notModified = ProjectWithDetails(
        project: Project(
          id: 'p1',
          name: 'Alpha',
          gameInstallationId: 'install-wh3',
          createdAt: 0,
          updatedAt: 1030,
        ),
        languages: const [],
        lastPackExport: export,
      );
      expect(notModified.isModifiedSinceLastExport, isFalse);

      // updatedAt well beyond the margin -> modified.
      final modified = ProjectWithDetails(
        project: Project(
          id: 'p1',
          name: 'Alpha',
          gameInstallationId: 'install-wh3',
          createdAt: 0,
          updatedAt: 2000,
        ),
        languages: const [],
        lastPackExport: export,
      );
      expect(modified.isModifiedSinceLastExport, isTrue);
    });

    test('hasSteamPublishWorkflow true via modSteamId or publishedSteamId', () {
      final plain =
          ProjectWithDetails(project: _project(), languages: const []);
      expect(plain.hasSteamPublishWorkflow, isFalse);

      final viaMod = ProjectWithDetails(
        project: Project(
          id: 'p1',
          name: 'Alpha',
          gameInstallationId: 'install-wh3',
          createdAt: 0,
          updatedAt: 0,
          modSteamId: '12345',
        ),
        languages: const [],
      );
      expect(viaMod.hasSteamPublishWorkflow, isTrue);

      final viaPublished = ProjectWithDetails(
        project: Project(
          id: 'p1',
          name: 'Alpha',
          gameInstallationId: 'install-wh3',
          createdAt: 0,
          updatedAt: 0,
          publishedSteamId: '99999',
        ),
        languages: const [],
      );
      expect(viaPublished.hasSteamPublishWorkflow, isTrue);
    });

    test('isPackPublishedOnSteam requires export, publishedSteamId and time',
        () {
      final export = ExportHistory(
        id: 'e1',
        projectId: 'p1',
        languages: '["fr"]',
        format: ExportFormat.pack,
        validatedOnly: false,
        outputPath: 'C:/out.pack',
        entryCount: 5,
        exportedAt: 1000,
      );

      // No export at all.
      expect(
        ProjectWithDetails(project: _project(), languages: const [])
            .isPackPublishedOnSteam,
        isFalse,
      );

      // Export present but no published id.
      expect(
        ProjectWithDetails(
          project: _project(),
          languages: const [],
          lastPackExport: export,
        ).isPackPublishedOnSteam,
        isFalse,
      );

      // Published after the export -> live on Steam.
      final live = ProjectWithDetails(
        project: Project(
          id: 'p1',
          name: 'Alpha',
          gameInstallationId: 'install-wh3',
          createdAt: 0,
          updatedAt: 0,
          publishedSteamId: '99999',
          publishedAt: 2000,
        ),
        languages: const [],
        lastPackExport: export,
      );
      expect(live.isPackPublishedOnSteam, isTrue);

      // Published before the export -> stale (local pack newer than Steam).
      final stale = ProjectWithDetails(
        project: Project(
          id: 'p1',
          name: 'Alpha',
          gameInstallationId: 'install-wh3',
          createdAt: 0,
          updatedAt: 0,
          publishedSteamId: '99999',
          publishedAt: 500,
        ),
        languages: const [],
        lastPackExport: export,
      );
      expect(stale.isPackPublishedOnSteam, isFalse);
    });
  });

  // --------------------------------------------------------------------------
  // ProjectLanguageWithInfo model
  // --------------------------------------------------------------------------
  group('ProjectLanguageWithInfo', () {
    test('progressPercent is 0 when there are no units', () {
      final info = ProjectLanguageWithInfo(projectLanguage: _projectLanguage());
      expect(info.progressPercent, 0.0);
      expect(info.isComplete, isFalse);
    });

    test('progressPercent reflects translated/total ratio', () {
      final info = ProjectLanguageWithInfo(
        projectLanguage: _projectLanguage(),
        totalUnits: 4,
        translatedUnits: 1,
      );
      expect(info.progressPercent, 25.0);
      expect(info.isComplete, isFalse);
    });

    test('isComplete is true only when translated >= total (>0)', () {
      final complete = ProjectLanguageWithInfo(
        projectLanguage: _projectLanguage(),
        totalUnits: 5,
        translatedUnits: 5,
      );
      expect(complete.isComplete, isTrue);
      expect(complete.progressPercent, 100.0);
    });
  });

  // --------------------------------------------------------------------------
  // TranslationStatsVersionNotifier
  // --------------------------------------------------------------------------
  group('TranslationStatsVersionNotifier', () {
    test('build() returns 0 and increment() bumps the value', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(translationStatsVersionProvider), 0);

      container.read(translationStatsVersionProvider.notifier).increment();
      expect(container.read(translationStatsVersionProvider), 1);

      container.read(translationStatsVersionProvider.notifier).increment();
      expect(container.read(translationStatsVersionProvider), 2);
    });
  });

  // --------------------------------------------------------------------------
  // ProjectsWithDetailsNotifier — build / _loadAll
  // --------------------------------------------------------------------------
  group('ProjectsWithDetailsNotifier build/_loadAll', () {
    late _MockProjectRepository projectRepo;
    late _MockProjectLanguageRepository projectLanguageRepo;
    late _MockLanguageRepository languageRepo;
    late _MockGameInstallationRepository gameInstallationRepo;
    late _MockTranslationVersionRepository versionRepo;
    late _MockWorkshopModRepository workshopModRepo;
    late _MockExportHistoryRepository exportHistoryRepo;

    setUp(() {
      projectRepo = _MockProjectRepository();
      projectLanguageRepo = _MockProjectLanguageRepository();
      languageRepo = _MockLanguageRepository();
      gameInstallationRepo = _MockGameInstallationRepository();
      versionRepo = _MockTranslationVersionRepository();
      workshopModRepo = _MockWorkshopModRepository();
      exportHistoryRepo = _MockExportHistoryRepository();

      // Lookup-map stubs shared by every load path.
      when(() => gameInstallationRepo.getByGameCode('wh3')).thenAnswer(
        (_) async =>
            Ok<GameInstallation, TWMTDatabaseException>(_installation()),
      );
      when(() => gameInstallationRepo.getAll()).thenAnswer(
        (_) async => Ok<List<GameInstallation>, TWMTDatabaseException>(
          [_installation()],
        ),
      );
      when(() => languageRepo.getAll()).thenAnswer(
        (_) async =>
            Ok<List<Language>, TWMTDatabaseException>(const [_fr]),
      );
    });

    ProviderContainer build({ConfiguredGame? selectedGame = _game}) {
      final container = _makeContainer(
        projectRepo: projectRepo,
        projectLanguageRepo: projectLanguageRepo,
        languageRepo: languageRepo,
        gameInstallationRepo: gameInstallationRepo,
        versionRepo: versionRepo,
        workshopModRepo: workshopModRepo,
        exportHistoryRepo: exportHistoryRepo,
        selectedGame: selectedGame,
      );
      addTearDown(container.dispose);
      return container;
    }

    test('returns empty list when no game is selected', () async {
      final container = build(selectedGame: null);
      final result =
          await container.read(projectsWithDetailsProvider.future);
      expect(result, isEmpty);
      // Should short-circuit before touching the project repo.
      verifyNever(() => projectRepo.getModTranslationsByInstallation(any()));
    });

    test('returns empty list when game installation lookup errors', () async {
      when(() => gameInstallationRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Err<GameInstallation, TWMTDatabaseException>(
          const TWMTDatabaseException('not found'),
        ),
      );
      final container = build();
      final result =
          await container.read(projectsWithDetailsProvider.future);
      expect(result, isEmpty);
      verifyNever(() => projectRepo.getModTranslationsByInstallation(any()));
    });

    test('returns empty list when there are no projects', () async {
      when(() => projectRepo.getModTranslationsByInstallation('install-wh3'))
          .thenAnswer((_) async =>
              Ok<List<Project>, TWMTDatabaseException>(const []));
      final container = build();
      final result =
          await container.read(projectsWithDetailsProvider.future);
      expect(result, isEmpty);
    });

    test('surfaces an error (AsyncError) when the project query fails',
        () async {
      when(() => projectRepo.getModTranslationsByInstallation('install-wh3'))
          .thenAnswer((_) async => Err<List<Project>, TWMTDatabaseException>(
                const TWMTDatabaseException('boom'),
              ));
      final container = build();
      // Reading .future of an AsyncNotifier that errors on the first microtask
      // hangs ("disposed during loading"); assert via the AsyncValue instead.
      container.listen(projectsWithDetailsProvider, (_, _) {});
      await pumpEventQueue();
      final state = container.read(projectsWithDetailsProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<Exception>());
    });

    test('maps multiple projects to ProjectWithDetails preserving order',
        () async {
      when(() => projectRepo.getModTranslationsByInstallation('install-wh3'))
          .thenAnswer((_) async => Ok<List<Project>, TWMTDatabaseException>([
                _project(id: 'p1', name: 'Alpha'),
                _project(id: 'p2', name: 'Beta'),
              ]));

      // No languages configured for either project => simplest _computeOne path
      // (no stats lookups, no auto-heal because languages list is empty).
      when(() => projectLanguageRepo.getByProject(any())).thenAnswer(
        (_) async =>
            Ok<List<ProjectLanguage>, TWMTDatabaseException>(const []),
      );
      when(() => exportHistoryRepo.getLastPackExportByProject(any()))
          .thenAnswer((_) async => null);

      final container = build();
      final result =
          await container.read(projectsWithDetailsProvider.future);

      expect(result, hasLength(2));
      expect(result[0].project.id, 'p1');
      expect(result[1].project.id, 'p2');
      expect(result[0].languages, isEmpty);
      expect(result[0].gameInstallation, isNotNull);
    });

    test(
        'project WITHOUT mod-update-impact flag: incomplete + pending reviews '
        'never triggers clearModUpdateImpact', () async {
      when(() => projectRepo.getModTranslationsByInstallation('install-wh3'))
          .thenAnswer((_) async => Ok<List<Project>, TWMTDatabaseException>([
                _project(hasModUpdateImpact: false),
              ]));
      when(() => projectLanguageRepo.getByProject('p1')).thenAnswer(
        (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>(
          [_projectLanguage()],
        ),
      );
      when(() => versionRepo.getLanguageStatistics('pl-fr')).thenAnswer(
        (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(
          const ProjectStatistics(
            totalCount: 10,
            translatedCount: 6, // incomplete
            pendingCount: 4,
            validatedCount: 0,
            errorCount: 2, // pending reviews
          ),
        ),
      );
      when(() => exportHistoryRepo.getLastPackExportByProject('p1'))
          .thenAnswer((_) async => null);

      final container = build();
      final result =
          await container.read(projectsWithDetailsProvider.future);

      final details = result.single;
      expect(details.project.hasModUpdateImpact, isFalse);
      expect(details.isFullyTranslated, isFalse);
      expect(details.hasNeedsReviewUnits, isTrue);
      expect(details.languages.single.needsReviewUnits, 2);
      expect(details.hasUpdates, isFalse,
          reason: 'No impact flag and no pending analysis.');
      verifyNever(() => projectRepo.clearModUpdateImpact(any()));
    });

    test('falls back to empty stats when getLanguageStatistics errors',
        () async {
      when(() => projectRepo.getModTranslationsByInstallation('install-wh3'))
          .thenAnswer((_) async => Ok<List<Project>, TWMTDatabaseException>([
                _project(),
              ]));
      when(() => projectLanguageRepo.getByProject('p1')).thenAnswer(
        (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>(
          [_projectLanguage()],
        ),
      );
      when(() => versionRepo.getLanguageStatistics('pl-fr')).thenAnswer(
        (_) async => Err<ProjectStatistics, TWMTDatabaseException>(
          const TWMTDatabaseException('stats failed'),
        ),
      );
      when(() => exportHistoryRepo.getLastPackExportByProject('p1'))
          .thenAnswer((_) async => null);

      final container = build();
      final result =
          await container.read(projectsWithDetailsProvider.future);

      final lang = result.single.languages.single;
      expect(lang.totalUnits, 0);
      expect(lang.translatedUnits, 0);
      expect(lang.isComplete, isFalse);
    });

    test('handles a project-languages lookup error as zero languages',
        () async {
      when(() => projectRepo.getModTranslationsByInstallation('install-wh3'))
          .thenAnswer((_) async => Ok<List<Project>, TWMTDatabaseException>([
                _project(),
              ]));
      when(() => projectLanguageRepo.getByProject('p1')).thenAnswer(
        (_) async => Err<List<ProjectLanguage>, TWMTDatabaseException>(
          const TWMTDatabaseException('lang lookup failed'),
        ),
      );
      when(() => exportHistoryRepo.getLastPackExportByProject('p1'))
          .thenAnswer((_) async => null);

      final container = build();
      final result =
          await container.read(projectsWithDetailsProvider.future);

      expect(result.single.languages, isEmpty);
    });
  });

  // --------------------------------------------------------------------------
  // ProjectsWithDetailsNotifier — refreshProject / removeProject
  // --------------------------------------------------------------------------
  group('ProjectsWithDetailsNotifier refreshProject/removeProject', () {
    late _MockProjectRepository projectRepo;
    late _MockProjectLanguageRepository projectLanguageRepo;
    late _MockLanguageRepository languageRepo;
    late _MockGameInstallationRepository gameInstallationRepo;
    late _MockTranslationVersionRepository versionRepo;
    late _MockWorkshopModRepository workshopModRepo;
    late _MockExportHistoryRepository exportHistoryRepo;

    setUp(() {
      projectRepo = _MockProjectRepository();
      projectLanguageRepo = _MockProjectLanguageRepository();
      languageRepo = _MockLanguageRepository();
      gameInstallationRepo = _MockGameInstallationRepository();
      versionRepo = _MockTranslationVersionRepository();
      workshopModRepo = _MockWorkshopModRepository();
      exportHistoryRepo = _MockExportHistoryRepository();

      when(() => gameInstallationRepo.getByGameCode('wh3')).thenAnswer(
        (_) async =>
            Ok<GameInstallation, TWMTDatabaseException>(_installation()),
      );
      when(() => gameInstallationRepo.getAll()).thenAnswer(
        (_) async => Ok<List<GameInstallation>, TWMTDatabaseException>(
          [_installation()],
        ),
      );
      when(() => languageRepo.getAll()).thenAnswer(
        (_) async => Ok<List<Language>, TWMTDatabaseException>(const [_fr]),
      );
      // Initial load: two projects with no languages (simple path).
      when(() => projectRepo.getModTranslationsByInstallation('install-wh3'))
          .thenAnswer((_) async => Ok<List<Project>, TWMTDatabaseException>([
                _project(id: 'p1', name: 'Alpha'),
                _project(id: 'p2', name: 'Beta'),
              ]));
      when(() => projectLanguageRepo.getByProject(any())).thenAnswer(
        (_) async =>
            Ok<List<ProjectLanguage>, TWMTDatabaseException>(const []),
      );
      when(() => exportHistoryRepo.getLastPackExportByProject(any()))
          .thenAnswer((_) async => null);
    });

    ProviderContainer build() {
      final container = _makeContainer(
        projectRepo: projectRepo,
        projectLanguageRepo: projectLanguageRepo,
        languageRepo: languageRepo,
        gameInstallationRepo: gameInstallationRepo,
        versionRepo: versionRepo,
        workshopModRepo: workshopModRepo,
        exportHistoryRepo: exportHistoryRepo,
      );
      addTearDown(container.dispose);
      return container;
    }

    test('updates a single project entry in place', () async {
      final container = build();
      await container.read(projectsWithDetailsProvider.future);

      // getById returns a renamed p1.
      when(() => projectRepo.getById('p1')).thenAnswer(
        (_) async => Ok<Project, TWMTDatabaseException>(
          _project(id: 'p1', name: 'Alpha Renamed'),
        ),
      );

      await container
          .read(projectsWithDetailsProvider.notifier)
          .refreshProject('p1');

      final state = container.read(projectsWithDetailsProvider).value!;
      expect(state, hasLength(2));
      expect(state.firstWhere((p) => p.project.id == 'p1').project.name,
          'Alpha Renamed');
      // p2 untouched.
      expect(state.firstWhere((p) => p.project.id == 'p2').project.name,
          'Beta');
    });

    test('removes the project from the list when getById errors (not found)',
        () async {
      final container = build();
      await container.read(projectsWithDetailsProvider.future);

      when(() => projectRepo.getById('p1')).thenAnswer(
        (_) async => Err<Project, TWMTDatabaseException>(
          const TWMTDatabaseException('gone'),
        ),
      );

      await container
          .read(projectsWithDetailsProvider.notifier)
          .refreshProject('p1');

      final state = container.read(projectsWithDetailsProvider).value!;
      expect(state.map((p) => p.project.id), ['p2']);
    });

    test('removeProject drops the project without touching repos', () async {
      final container = build();
      await container.read(projectsWithDetailsProvider.future);

      container
          .read(projectsWithDetailsProvider.notifier)
          .removeProject('p2');

      final state = container.read(projectsWithDetailsProvider).value!;
      expect(state.map((p) => p.project.id), ['p1']);
    });
  });

  // NOTE: `_findModImage` / `_findModImageInDir` and the source-file/Steam
  // timestamp-comparison branch of `_computeOne` are intentionally NOT covered:
  // they call `File`/`Directory` against the real filesystem (and `File.stat`),
  // which is non-deterministic in a pure unit test. They are best exercised by
  // integration tests with a temp-dir fixture.
}
