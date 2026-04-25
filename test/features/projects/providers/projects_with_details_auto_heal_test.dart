// Provider test covering the auto-heal side-effect inside
// `ProjectsWithDetailsNotifier._computeOne`: when a project has the persistent
// `has_mod_update_impact` flag set but is already fully translated with no
// pending reviews and no pending mod-update analysis changes, the notifier
// must call `clearModUpdateImpact` on the repository and return a Project
// instance with the flag reset to `false` — so the status pill on the card
// stays consistent with the "Needs Update" filter predicate.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/project_statistics.dart';
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

import '../../../helpers/test_bootstrap.dart';

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

Project _project({required bool hasModUpdateImpact}) {
  return Project(
    id: 'p1',
    name: 'Alpha',
    gameInstallationId: 'install-wh3',
    createdAt: 0,
    updatedAt: 0,
    hasModUpdateImpact: hasModUpdateImpact,
  );
}

ProjectLanguage _projectLanguage() {
  return ProjectLanguage(
    id: 'pl-fr',
    projectId: 'p1',
    languageId: 'lang-fr',
    progressPercent: 100.0,
    createdAt: 0,
    updatedAt: 0,
  );
}

ProviderContainer _makeContainer({
  required ProjectRepository projectRepo,
  required ProjectLanguageRepository projectLanguageRepo,
  required LanguageRepository languageRepo,
  required GameInstallationRepository gameInstallationRepo,
  required TranslationVersionRepository versionRepo,
  required WorkshopModRepository workshopModRepo,
  required ExportHistoryRepository exportHistoryRepo,
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
    selectedGameProvider.overrideWith(() => _FakeSelectedGame(_game)),
  ]);
}

void _stubCommonRepos({
  required _MockGameInstallationRepository gameInstallationRepo,
  required _MockLanguageRepository languageRepo,
  required _MockProjectLanguageRepository projectLanguageRepo,
  required _MockWorkshopModRepository workshopModRepo,
  required _MockExportHistoryRepository exportHistoryRepo,
  required _MockTranslationVersionRepository versionRepo,
  required ProjectStatistics stats,
}) {
  when(() => gameInstallationRepo.getByGameCode('wh3')).thenAnswer(
    (_) async => Ok<GameInstallation, TWMTDatabaseException>(_installation()),
  );
  when(() => gameInstallationRepo.getAll()).thenAnswer(
    (_) async => Ok<List<GameInstallation>, TWMTDatabaseException>(
      [_installation()],
    ),
  );
  when(() => languageRepo.getAll()).thenAnswer(
    (_) async => Ok<List<Language>, TWMTDatabaseException>(
      const [
        Language(
          id: 'lang-fr',
          code: 'fr',
          name: 'French',
          nativeName: 'Français',
        ),
      ],
    ),
  );
  when(() => projectLanguageRepo.getByProject('p1')).thenAnswer(
    (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>(
      [_projectLanguage()],
    ),
  );
  when(() => versionRepo.getLanguageStatistics('pl-fr')).thenAnswer(
    (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(stats),
  );
  when(() => exportHistoryRepo.getLastPackExportByProject('p1'))
      .thenAnswer((_) async => null);
}

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  group('ProjectsWithDetailsNotifier auto-heal of hasModUpdateImpact', () {
    test(
      'clears the DB flag and mirrors the reset in the returned Project '
      'when the project is fully translated with no reviews pending',
      () async {
        final projectRepo = _MockProjectRepository();
        final projectLanguageRepo = _MockProjectLanguageRepository();
        final languageRepo = _MockLanguageRepository();
        final gameInstallationRepo = _MockGameInstallationRepository();
        final versionRepo = _MockTranslationVersionRepository();
        final workshopModRepo = _MockWorkshopModRepository();
        final exportHistoryRepo = _MockExportHistoryRepository();

        when(() => projectRepo.getModTranslationsByInstallation('install-wh3'))
            .thenAnswer((_) async => Ok<List<Project>, TWMTDatabaseException>(
                  [_project(hasModUpdateImpact: true)],
                ));
        when(() => projectRepo.clearModUpdateImpact('p1')).thenAnswer(
          (_) async => const Ok<void, TWMTDatabaseException>(null),
        );

        _stubCommonRepos(
          gameInstallationRepo: gameInstallationRepo,
          languageRepo: languageRepo,
          projectLanguageRepo: projectLanguageRepo,
          workshopModRepo: workshopModRepo,
          exportHistoryRepo: exportHistoryRepo,
          versionRepo: versionRepo,
          stats: const ProjectStatistics(
            totalCount: 10,
            translatedCount: 10,
            pendingCount: 0,
            validatedCount: 0,
            errorCount: 0,
          ),
        );

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

        final projects =
            await container.read(projectsWithDetailsProvider.future);

        expect(projects, hasLength(1));
        expect(projects.single.project.hasModUpdateImpact, isFalse,
            reason: 'Returned project should mirror the cleared DB flag.');
        expect(projects.single.hasUpdates, isFalse,
            reason: 'Project should drop out of the "Needs Update" filter.');
        verify(() => projectRepo.clearModUpdateImpact('p1')).called(1);
      },
    );

    test(
      'does NOT clear the flag when `needs_review` units still remain',
      () async {
        final projectRepo = _MockProjectRepository();
        final projectLanguageRepo = _MockProjectLanguageRepository();
        final languageRepo = _MockLanguageRepository();
        final gameInstallationRepo = _MockGameInstallationRepository();
        final versionRepo = _MockTranslationVersionRepository();
        final workshopModRepo = _MockWorkshopModRepository();
        final exportHistoryRepo = _MockExportHistoryRepository();

        when(() => projectRepo.getModTranslationsByInstallation('install-wh3'))
            .thenAnswer((_) async => Ok<List<Project>, TWMTDatabaseException>(
                  [_project(hasModUpdateImpact: true)],
                ));

        _stubCommonRepos(
          gameInstallationRepo: gameInstallationRepo,
          languageRepo: languageRepo,
          projectLanguageRepo: projectLanguageRepo,
          workshopModRepo: workshopModRepo,
          exportHistoryRepo: exportHistoryRepo,
          versionRepo: versionRepo,
          stats: const ProjectStatistics(
            totalCount: 10,
            translatedCount: 10,
            pendingCount: 0,
            validatedCount: 0,
            errorCount: 2, // still has needs_review units
          ),
        );

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

        final projects =
            await container.read(projectsWithDetailsProvider.future);

        expect(projects.single.project.hasModUpdateImpact, isTrue);
        expect(projects.single.hasUpdates, isTrue,
            reason: 'Still has reviews pending → stays in Needs Update.');
        verifyNever(() => projectRepo.clearModUpdateImpact(any()));
      },
    );

    test('does NOT clear the flag when translation is incomplete', () async {
      final projectRepo = _MockProjectRepository();
      final projectLanguageRepo = _MockProjectLanguageRepository();
      final languageRepo = _MockLanguageRepository();
      final gameInstallationRepo = _MockGameInstallationRepository();
      final versionRepo = _MockTranslationVersionRepository();
      final workshopModRepo = _MockWorkshopModRepository();
      final exportHistoryRepo = _MockExportHistoryRepository();

      when(() => projectRepo.getModTranslationsByInstallation('install-wh3'))
          .thenAnswer((_) async => Ok<List<Project>, TWMTDatabaseException>(
                [_project(hasModUpdateImpact: true)],
              ));

      _stubCommonRepos(
        gameInstallationRepo: gameInstallationRepo,
        languageRepo: languageRepo,
        projectLanguageRepo: projectLanguageRepo,
        workshopModRepo: workshopModRepo,
        exportHistoryRepo: exportHistoryRepo,
        versionRepo: versionRepo,
        stats: const ProjectStatistics(
          totalCount: 10,
          translatedCount: 6, // not yet complete
          pendingCount: 4,
          validatedCount: 0,
          errorCount: 0,
        ),
      );

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

      final projects =
          await container.read(projectsWithDetailsProvider.future);

      expect(projects.single.project.hasModUpdateImpact, isTrue);
      verifyNever(() => projectRepo.clearModUpdateImpact(any()));
    });

    test(
      'does NOT clear the flag when the project has no languages configured',
      () async {
        final projectRepo = _MockProjectRepository();
        final projectLanguageRepo = _MockProjectLanguageRepository();
        final languageRepo = _MockLanguageRepository();
        final gameInstallationRepo = _MockGameInstallationRepository();
        final versionRepo = _MockTranslationVersionRepository();
        final workshopModRepo = _MockWorkshopModRepository();
        final exportHistoryRepo = _MockExportHistoryRepository();

        when(() => projectRepo.getModTranslationsByInstallation('install-wh3'))
            .thenAnswer((_) async => Ok<List<Project>, TWMTDatabaseException>(
                  [_project(hasModUpdateImpact: true)],
                ));

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
          (_) async => Ok<List<Language>, TWMTDatabaseException>(const []),
        );
        when(() => projectLanguageRepo.getByProject('p1')).thenAnswer(
          (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>(const []),
        );
        when(() => exportHistoryRepo.getLastPackExportByProject('p1'))
            .thenAnswer((_) async => null);

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

        final projects =
            await container.read(projectsWithDetailsProvider.future);

        expect(projects.single.project.hasModUpdateImpact, isTrue,
            reason: 'Empty-language projects must not be auto-cleared.');
        verifyNever(() => projectRepo.clearModUpdateImpact(any()));
      },
    );
  });
}
