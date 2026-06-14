// Coverage for the providers DEFINED in pack_compilation_providers.dart
// (the compilation list/details, current-game resolution, filtered project
// lists, BBCode generation, and small state holders). The re-exported
// compilation editor notifier and conflict providers are tested elsewhere.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/pack_compilation/providers/pack_compilation_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/project_statistics.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/repositories/compilation_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

class _MockCompilationRepository extends Mock
    implements CompilationRepository {}

class _MockProjectRepository extends Mock implements ProjectRepository {}

class _MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

class _MockLanguageRepository extends Mock implements LanguageRepository {}

class _MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

class _MockTranslationVersionRepository extends Mock
    implements TranslationVersionRepository {}

/// Fake [SelectedGame] notifier returning a fixed game (or null). The codegen
/// AsyncNotifier must be overridden with a notifier factory, not a closure.
class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._game);
  final ConfiguredGame? _game;
  @override
  Future<ConfiguredGame?> build() async => _game;
}

const _dbErr = TWMTDatabaseException('boom');

GameInstallation _game({String id = 'install-wh3', String code = 'wh3'}) =>
    GameInstallation(
      id: id,
      gameCode: code,
      gameName: 'Total War: WARHAMMER III',
      installationPath: r'C:\games\wh3',
      createdAt: 0,
      updatedAt: 0,
    );

Compilation _compilation({
  String id = 'comp-1',
  String gameInstallationId = 'install-wh3',
  String? languageId = 'lang-fr',
}) =>
    Compilation(
      id: id,
      name: 'Comp $id',
      prefix: '!!!_fr_compilation_twmt_',
      packName: 'my_pack',
      gameInstallationId: gameInstallationId,
      languageId: languageId,
      createdAt: 0,
      updatedAt: 0,
    );

Language _language({String id = 'lang-fr', String code = 'fr'}) => Language(
      id: id,
      code: code,
      name: 'French',
      nativeName: 'Français',
    );

Project _project({
  String id = 'proj-1',
  String name = 'P1',
  String? modSteamId,
}) =>
    Project(
      id: id,
      name: name,
      modSteamId: modSteamId,
      gameInstallationId: 'install-wh3',
      createdAt: 0,
      updatedAt: 0,
    );

ProjectLanguage _projectLanguage({String id = 'pl-1'}) => ProjectLanguage(
      id: id,
      projectId: 'proj-1',
      languageId: 'lang-fr',
      createdAt: 0,
      updatedAt: 0,
    );

ProjectStatistics _stats({
  int total = 10,
  int translated = 4,
  int validated = 2,
}) =>
    ProjectStatistics(
      totalCount: total,
      translatedCount: translated,
      pendingCount: 0,
      validatedCount: validated,
      errorCount: 0,
    );

void main() {
  late _MockCompilationRepository compilationRepo;
  late _MockProjectRepository projectRepo;
  late _MockGameInstallationRepository gameRepo;
  late _MockLanguageRepository languageRepo;
  late _MockProjectLanguageRepository projectLangRepo;
  late _MockTranslationVersionRepository versionRepo;

  setUp(() {
    compilationRepo = _MockCompilationRepository();
    projectRepo = _MockProjectRepository();
    gameRepo = _MockGameInstallationRepository();
    languageRepo = _MockLanguageRepository();
    projectLangRepo = _MockProjectLanguageRepository();
    versionRepo = _MockTranslationVersionRepository();
  });

  /// Build a container with all leaf repos overridden plus an optional
  /// selected game. Repos are injected so the providers never touch GetIt.
  ProviderContainer makeContainer({ConfiguredGame? selectedGame}) {
    final container = ProviderContainer(overrides: [
      compilationRepositoryProvider.overrideWithValue(compilationRepo),
      projectRepositoryProvider.overrideWithValue(projectRepo),
      gameInstallationRepositoryProvider.overrideWithValue(gameRepo),
      languageRepositoryProvider.overrideWithValue(languageRepo),
      projectLanguageRepositoryProvider.overrideWithValue(projectLangRepo),
      translationVersionRepositoryProvider.overrideWithValue(versionRepo),
      selectedGameProvider.overrideWith(() => _FakeSelectedGame(selectedGame)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  const wh3Game = ConfiguredGame(code: 'wh3', name: 'WH3', path: r'C:\wh3');

  group('currentGameInstallationProvider', () {
    test('returns null when no game is selected', () async {
      final container = makeContainer(selectedGame: null);
      final result =
          await container.read(currentGameInstallationProvider.future);
      expect(result, isNull);
      verifyNever(() => gameRepo.getByGameCode(any()));
    });

    test('returns null when the repo lookup errors', () async {
      when(() => gameRepo.getByGameCode('wh3')).thenAnswer(
        (_) async =>
            const Err<GameInstallation, TWMTDatabaseException>(_dbErr),
      );
      final container = makeContainer(selectedGame: wh3Game);
      final result =
          await container.read(currentGameInstallationProvider.future);
      expect(result, isNull);
    });

    test('returns the installation on success', () async {
      when(() => gameRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(_game()),
      );
      final container = makeContainer(selectedGame: wh3Game);
      final result =
          await container.read(currentGameInstallationProvider.future);
      expect(result?.id, 'install-wh3');
    });
  });

  group('compilationsWithDetailsProvider', () {
    test('returns empty list when no game installation resolves', () async {
      final container = makeContainer(selectedGame: null);
      final result =
          await container.read(compilationsWithDetailsProvider.future);
      expect(result, isEmpty);
    });

    test('throws when the compilation query errors', () async {
      when(() => gameRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(_game()),
      );
      when(() => compilationRepo.getByGameInstallation('install-wh3'))
          .thenAnswer(
        (_) async =>
            const Err<List<Compilation>, TWMTDatabaseException>(_dbErr),
      );
      final container = makeContainer(selectedGame: wh3Game);
      // Awaiting a known-throwing `.future` can race container disposal, so
      // listen and assert the AsyncValue settles into an error instead.
      container.listen(
        compilationsWithDetailsProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await pumpEventQueue();
      expect(container.read(compilationsWithDetailsProvider).hasError, isTrue);
    });

    test('maps compilations with resolved game, language and projects',
        () async {
      when(() => gameRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(_game()),
      );
      when(() => compilationRepo.getByGameInstallation('install-wh3'))
          .thenAnswer(
        (_) async => Ok<List<Compilation>, TWMTDatabaseException>(
          [_compilation()],
        ),
      );
      when(() => gameRepo.getById('install-wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(_game()),
      );
      when(() => languageRepo.getById('lang-fr')).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(_language()),
      );
      when(() => compilationRepo.getProjectIds('comp-1')).thenAnswer(
        (_) async =>
            Ok<List<String>, TWMTDatabaseException>(['proj-1', 'proj-2']),
      );
      when(() => projectRepo.getById('proj-1')).thenAnswer(
        (_) async => Ok<Project, TWMTDatabaseException>(_project(id: 'proj-1')),
      );
      // proj-2 fails to load -> excluded from projects list.
      when(() => projectRepo.getById('proj-2')).thenAnswer(
        (_) async => const Err<Project, TWMTDatabaseException>(_dbErr),
      );

      final container = makeContainer(selectedGame: wh3Game);
      final result =
          await container.read(compilationsWithDetailsProvider.future);

      expect(result, hasLength(1));
      final details = result.single;
      expect(details.gameInstallation?.id, 'install-wh3');
      expect(details.language?.code, 'fr');
      expect(details.projects.map((p) => p.id), ['proj-1']);
      expect(details.projectCount, 1);
    });

    test('tolerates missing game, null language id and project-id error',
        () async {
      when(() => gameRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(_game()),
      );
      when(() => compilationRepo.getByGameInstallation('install-wh3'))
          .thenAnswer(
        (_) async => Ok<List<Compilation>, TWMTDatabaseException>(
          [_compilation(languageId: null)],
        ),
      );
      // game lookup for the row fails -> gameInstallation stays null.
      when(() => gameRepo.getById('install-wh3')).thenAnswer(
        (_) async => const Err<GameInstallation, TWMTDatabaseException>(_dbErr),
      );
      // project ids lookup fails -> empty project list.
      when(() => compilationRepo.getProjectIds('comp-1')).thenAnswer(
        (_) async => const Err<List<String>, TWMTDatabaseException>(_dbErr),
      );

      final container = makeContainer(selectedGame: wh3Game);
      final result =
          await container.read(compilationsWithDetailsProvider.future);

      expect(result, hasLength(1));
      final details = result.single;
      expect(details.gameInstallation, isNull);
      expect(details.language, isNull);
      expect(details.projects, isEmpty);
      expect(details.projectCount, 0);
      verifyNever(() => languageRepo.getById(any()));
    });

    test('language lookup error leaves language null', () async {
      when(() => gameRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(_game()),
      );
      when(() => compilationRepo.getByGameInstallation('install-wh3'))
          .thenAnswer(
        (_) async =>
            Ok<List<Compilation>, TWMTDatabaseException>([_compilation()]),
      );
      when(() => gameRepo.getById('install-wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(_game()),
      );
      when(() => languageRepo.getById('lang-fr')).thenAnswer(
        (_) async => const Err<Language, TWMTDatabaseException>(_dbErr),
      );
      when(() => compilationRepo.getProjectIds('comp-1')).thenAnswer(
        (_) async => Ok<List<String>, TWMTDatabaseException>(const []),
      );

      final container = makeContainer(selectedGame: wh3Game);
      final result =
          await container.read(compilationsWithDetailsProvider.future);
      expect(result.single.language, isNull);
    });
  });

  group('projectsWithTranslationProvider', () {
    test('returns empty list when params lack ids', () async {
      final container = makeContainer();
      final result = await container.read(
        projectsWithTranslationProvider(const ProjectFilterParams()).future,
      );
      expect(result, isEmpty);
      verifyNever(() => projectRepo.getByGameInstallation(any()));
    });

    test('throws when the project query errors', () async {
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => const Err<List<Project>, TWMTDatabaseException>(_dbErr),
      );
      final container = makeContainer();
      const params = ProjectFilterParams(
        gameInstallationId: 'install-wh3',
        languageId: 'lang-fr',
      );
      container.listen(
        projectsWithTranslationProvider(params),
        (_, _) {},
        fireImmediately: true,
      );
      await pumpEventQueue();
      expect(
        container.read(projectsWithTranslationProvider(params)).hasError,
        isTrue,
      );
    });

    test('throws when checking project language errors', () async {
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([_project()]),
      );
      when(() => projectLangRepo.findByProjectAndLanguage('proj-1', 'lang-fr'))
          .thenAnswer(
        (_) async =>
            const Err<ProjectLanguage?, TWMTDatabaseException>(_dbErr),
      );
      final container = makeContainer();
      const params = ProjectFilterParams(
        gameInstallationId: 'install-wh3',
        languageId: 'lang-fr',
      );
      container.listen(
        projectsWithTranslationProvider(params),
        (_, _) {},
        fireImmediately: true,
      );
      await pumpEventQueue();
      expect(
        container.read(projectsWithTranslationProvider(params)).hasError,
        isTrue,
      );
    });

    test('skips projects without a translation in the language', () async {
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([_project()]),
      );
      when(() => projectLangRepo.findByProjectAndLanguage('proj-1', 'lang-fr'))
          .thenAnswer(
        (_) async => const Ok<ProjectLanguage?, TWMTDatabaseException>(null),
      );
      final container = makeContainer();
      final result = await container.read(
        projectsWithTranslationProvider(
          const ProjectFilterParams(
            gameInstallationId: 'install-wh3',
            languageId: 'lang-fr',
          ),
        ).future,
      );
      expect(result, isEmpty);
      verifyNever(() => versionRepo.getLanguageStatistics(any()));
    });

    test('includes project with combined translated count from stats',
        () async {
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([_project()]),
      );
      when(() => projectLangRepo.findByProjectAndLanguage('proj-1', 'lang-fr'))
          .thenAnswer(
        (_) async =>
            Ok<ProjectLanguage?, TWMTDatabaseException>(_projectLanguage()),
      );
      when(() => versionRepo.getLanguageStatistics('pl-1')).thenAnswer(
        (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(_stats()),
      );
      final container = makeContainer();
      final result = await container.read(
        projectsWithTranslationProvider(
          const ProjectFilterParams(
            gameInstallationId: 'install-wh3',
            languageId: 'lang-fr',
          ),
        ).future,
      );
      expect(result, hasLength(1));
      expect(result.single.totalUnits, 10);
      // translated + validated = 4 + 2.
      expect(result.single.translatedUnits, 6);
    });

    test('falls back to empty stats when statistics lookup errors', () async {
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([_project()]),
      );
      when(() => projectLangRepo.findByProjectAndLanguage('proj-1', 'lang-fr'))
          .thenAnswer(
        (_) async =>
            Ok<ProjectLanguage?, TWMTDatabaseException>(_projectLanguage()),
      );
      when(() => versionRepo.getLanguageStatistics('pl-1')).thenAnswer(
        (_) async =>
            const Err<ProjectStatistics, TWMTDatabaseException>(_dbErr),
      );
      final container = makeContainer();
      final result = await container.read(
        projectsWithTranslationProvider(
          const ProjectFilterParams(
            gameInstallationId: 'install-wh3',
            languageId: 'lang-fr',
          ),
        ).future,
      );
      expect(result.single.totalUnits, 0);
      expect(result.single.translatedUnits, 0);
    });
  });

  group('filteredProjects', () {
    const params = ProjectFilterParams(
      gameInstallationId: 'install-wh3',
      languageId: 'lang-fr',
    );

    /// Override the underlying list provider so filteredProjects sees a fixed
    /// set without exercising the DB-backed path again.
    ProviderContainer withProjects(List<ProjectWithTranslationInfo> items) {
      final container = ProviderContainer(overrides: [
        projectsWithTranslationProvider(params)
            .overrideWith((ref) async => items),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    final pA =
        ProjectWithTranslationInfo(project: _project(id: 'a', name: 'Alpha'));
    final pB =
        ProjectWithTranslationInfo(project: _project(id: 'b', name: 'Beta'));

    test('returns loading while the source list is loading', () {
      final container = ProviderContainer(overrides: [
        projectsWithTranslationProvider(params)
            .overrideWith((ref) => Completer<List<ProjectWithTranslationInfo>>()
                .future),
      ]);
      addTearDown(container.dispose);
      final value = container.read(filteredProjectsProvider(params));
      expect(value.isLoading, isTrue);
    });

    test('returns all projects with no filter and onlySelected off', () async {
      final container = withProjects([pA, pB]);
      await container.read(projectsWithTranslationProvider(params).future);
      final value = container.read(filteredProjectsProvider(params));
      expect(value.value, hasLength(2));
    });

    test('applies the text filter case-insensitively', () async {
      final container = withProjects([pA, pB]);
      container.read(projectFilterProvider.notifier).setFilter('  ALPHA ');
      await container.read(projectsWithTranslationProvider(params).future);
      final value = container.read(filteredProjectsProvider(params));
      expect(value.value!.map((p) => p.id), ['a']);
    });

    test('restricts to selected projects when the toggle is on', () async {
      final container = withProjects([pA, pB]);
      container.read(showOnlySelectedProjectsProvider.notifier).state = true;
      container
          .read(compilationEditorProvider.notifier)
          .toggleProject('b');
      await container.read(projectsWithTranslationProvider(params).future);
      final value = container.read(filteredProjectsProvider(params));
      expect(value.value!.map((p) => p.id), ['b']);
    });
  });

  group('compilationInProgressProvider', () {
    test('mirrors the editor isCompiling flag', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(compilationInProgressProvider), isFalse);
    });
  });

  group('ProjectFilter notifier', () {
    test('setFilter and clear update state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(projectFilterProvider), '');
      container.read(projectFilterProvider.notifier).setFilter('abc');
      expect(container.read(projectFilterProvider), 'abc');
      container.read(projectFilterProvider.notifier).clear();
      expect(container.read(projectFilterProvider), '');
    });
  });

  group('compilationBBCodeProvider', () {
    test('returns empty string when no projects are selected', () async {
      final container = makeContainer();
      final result = await container.read(compilationBBCodeProvider.future);
      expect(result, isEmpty);
      verifyNever(() => projectRepo.getById(any()));
    });

    test('builds url lines only for projects with a steam id', () async {
      final container = makeContainer();
      container.read(compilationEditorProvider.notifier)
        ..toggleProject('with-steam')
        ..toggleProject('no-steam')
        ..toggleProject('missing');

      when(() => projectRepo.getById('with-steam')).thenAnswer(
        (_) async => Ok<Project, TWMTDatabaseException>(
          _project(id: 'with-steam', name: 'Mod A', modSteamId: '12345'),
        ),
      );
      when(() => projectRepo.getById('no-steam')).thenAnswer(
        (_) async => Ok<Project, TWMTDatabaseException>(
          _project(id: 'no-steam', name: 'Mod B'),
        ),
      );
      when(() => projectRepo.getById('missing')).thenAnswer(
        (_) async => const Err<Project, TWMTDatabaseException>(_dbErr),
      );

      final result = await container.read(compilationBBCodeProvider.future);
      expect(
        result,
        '[url=https://steamcommunity.com/sharedfiles/filedetails/?id=12345]Mod A[/url]',
      );
    });
  });

  group('deleteCompilation', () {
    testWidgets('returns true on success and false on error',
        (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            compilationRepositoryProvider.overrideWithValue(compilationRepo),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const SizedBox();
            },
          ),
        ),
      );

      when(() => compilationRepo.delete('ok')).thenAnswer(
        (_) async => const Ok<void, TWMTDatabaseException>(null),
      );
      when(() => compilationRepo.delete('bad')).thenAnswer(
        (_) async => const Err<void, TWMTDatabaseException>(_dbErr),
      );

      expect(await deleteCompilation(capturedRef, 'ok'), isTrue);
      expect(await deleteCompilation(capturedRef, 'bad'), isFalse);
    });
  });
}
