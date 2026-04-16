import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/home/providers/workflow_providers.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_statistics.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/compilation_repository.dart';
import 'package:twmt/repositories/export_history_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../../../helpers/test_bootstrap.dart';

class _MockProjectRepository extends Mock implements ProjectRepository {}

class _MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

class _MockTranslationVersionRepository extends Mock
    implements TranslationVersionRepository {}

class _MockCompilationRepository extends Mock implements CompilationRepository {
}

class _MockExportHistoryRepository extends Mock
    implements ExportHistoryRepository {}

/// Test double for [SelectedGame] that short-circuits settings-service access.
class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);

  final ConfiguredGame? _value;

  @override
  Future<ConfiguredGame?> build() async => _value;
}

const _gameWh3 = ConfiguredGame(
  code: 'wh3',
  name: 'Total War: WARHAMMER III',
  path: 'C:/games/wh3',
);

GameInstallation _installation({
  String id = 'install-wh3',
  String gameCode = 'wh3',
}) {
  return GameInstallation(
    id: id,
    gameCode: gameCode,
    gameName: 'WH3',
    createdAt: 0,
    updatedAt: 0,
  );
}

Project _project({
  String id = 'p1',
  String name = 'P1',
  String gameInstallationId = 'install-wh3',
  int updatedAt = 1000,
}) {
  return Project(
    id: id,
    name: name,
    gameInstallationId: gameInstallationId,
    createdAt: 0,
    updatedAt: updatedAt,
  );
}

ExportHistory _packExport({required String projectId}) {
  return ExportHistory(
    id: 'eh-$projectId',
    projectId: projectId,
    languages: '[]',
    format: ExportFormat.pack,
    validatedOnly: false,
    outputPath: 'out.pack',
    entryCount: 0,
    exportedAt: 10,
  );
}

Compilation _compilation({
  required String id,
  String gameInstallationId = 'install-wh3',
  int? lastGeneratedAt,
  int? publishedAt,
}) {
  return Compilation(
    id: id,
    name: 'C-$id',
    prefix: '!',
    packName: 'pack-$id',
    gameInstallationId: gameInstallationId,
    lastGeneratedAt: lastGeneratedAt,
    publishedAt: publishedAt,
    createdAt: 0,
    updatedAt: 0,
  );
}

ProviderContainer _makeContainer({
  required ProjectRepository projectRepo,
  required GameInstallationRepository gameInstallationRepo,
  TranslationVersionRepository? versionRepo,
  ExportHistoryRepository? exportHistoryRepo,
  CompilationRepository? compilationRepo,
  ConfiguredGame? selectedGame = _gameWh3,
  Future<int> Function()? totalModsCountOverride,
  Future<int> Function()? needsUpdateModsCountOverride,
}) {
  final overrides = <Override>[
    projectRepositoryProvider.overrideWithValue(projectRepo),
    gameInstallationRepositoryProvider.overrideWithValue(gameInstallationRepo),
    selectedGameProvider.overrideWith(() => _FakeSelectedGame(selectedGame)),
    if (versionRepo != null)
      translationVersionRepositoryProvider.overrideWithValue(versionRepo),
    if (exportHistoryRepo != null)
      exportHistoryRepositoryProvider.overrideWithValue(exportHistoryRepo),
    if (compilationRepo != null)
      compilationRepositoryProvider.overrideWithValue(compilationRepo),
    if (totalModsCountOverride != null)
      totalModsCountProvider.overrideWith((ref) => totalModsCountOverride()),
    if (needsUpdateModsCountOverride != null)
      needsUpdateModsCountProvider.overrideWith(
        (ref) => needsUpdateModsCountOverride(),
      ),
  ];
  final container = ProviderContainer(overrides: overrides);
  return container;
}

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  group('modsDiscoveredCountProvider', () {
    test('forwards totalModsCountProvider value', () async {
      final projectRepo = _MockProjectRepository();
      final gameInstallRepo = _MockGameInstallationRepository();

      final container = _makeContainer(
        projectRepo: projectRepo,
        gameInstallationRepo: gameInstallRepo,
        selectedGame: null,
        totalModsCountOverride: () async => 42,
      );
      addTearDown(container.dispose);

      expect(await container.read(modsDiscoveredCountProvider.future), 42);
    });
  });

  group('modsWithUpdatesCountProvider', () {
    test('forwards needsUpdateModsCountProvider value', () async {
      final projectRepo = _MockProjectRepository();
      final gameInstallRepo = _MockGameInstallationRepository();

      final container = _makeContainer(
        projectRepo: projectRepo,
        gameInstallationRepo: gameInstallRepo,
        selectedGame: null,
        needsUpdateModsCountOverride: () async => 7,
      );
      addTearDown(container.dispose);

      expect(await container.read(modsWithUpdatesCountProvider.future), 7);
    });
  });

  group('activeProjectsCountProvider', () {
    test('counts projects attached to the selected game installation',
        () async {
      final projectRepo = _MockProjectRepository();
      final gameInstallRepo = _MockGameInstallationRepository();

      when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(
          _installation(id: 'install-wh3'),
        ),
      );
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([
          _project(id: 'p1'),
          _project(id: 'p2'),
          _project(id: 'p3'),
        ]),
      );

      final container = _makeContainer(
        projectRepo: projectRepo,
        gameInstallationRepo: gameInstallRepo,
      );
      addTearDown(container.dispose);

      expect(await container.read(activeProjectsCountProvider.future), 3);
      verify(() => projectRepo.getByGameInstallation('install-wh3')).called(1);
      verifyNever(() => projectRepo.getAll());
    });

    test('falls back to getAll() when no game is selected', () async {
      final projectRepo = _MockProjectRepository();
      final gameInstallRepo = _MockGameInstallationRepository();

      when(() => projectRepo.getAll()).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>(
          [_project(id: 'p1'), _project(id: 'p2')],
        ),
      );

      final container = _makeContainer(
        projectRepo: projectRepo,
        gameInstallationRepo: gameInstallRepo,
        selectedGame: null,
      );
      addTearDown(container.dispose);

      expect(await container.read(activeProjectsCountProvider.future), 2);
    });
  });

  group('projectsReadyToCompileCountProvider', () {
    test(
        'counts only projects that are 100% translated AND have no pack export',
        () async {
      final projectRepo = _MockProjectRepository();
      final gameInstallRepo = _MockGameInstallationRepository();
      final versionRepo = _MockTranslationVersionRepository();
      final exportHistoryRepo = _MockExportHistoryRepository();

      when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(
          _installation(id: 'install-wh3'),
        ),
      );
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([
          _project(id: 'ready'),      // 100% translated, no pack → counts
          _project(id: 'has-pack'),   // 100% translated, pack exists → skipped
          _project(id: 'half-done'),  // 50% translated → skipped
        ]),
      );

      // Project stats: translated/total.
      when(() => versionRepo.getProjectStatistics('ready')).thenAnswer(
        (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(
          const ProjectStatistics(
            totalCount: 10,
            translatedCount: 10,
            pendingCount: 0,
            validatedCount: 0,
            errorCount: 0,
          ),
        ),
      );
      when(() => versionRepo.getProjectStatistics('has-pack')).thenAnswer(
        (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(
          const ProjectStatistics(
            totalCount: 10,
            translatedCount: 10,
            pendingCount: 0,
            validatedCount: 0,
            errorCount: 0,
          ),
        ),
      );
      when(() => versionRepo.getProjectStatistics('half-done')).thenAnswer(
        (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(
          const ProjectStatistics(
            totalCount: 10,
            translatedCount: 5,
            pendingCount: 5,
            validatedCount: 0,
            errorCount: 0,
          ),
        ),
      );

      // Export history: only 'has-pack' has a pack exported.
      when(() => exportHistoryRepo.getLastPackExportByProject('ready'))
          .thenAnswer((_) async => null);
      when(() => exportHistoryRepo.getLastPackExportByProject('has-pack'))
          .thenAnswer((_) async => _packExport(projectId: 'has-pack'));
      // 'half-done' is short-circuited before reaching the export check.

      final container = _makeContainer(
        projectRepo: projectRepo,
        gameInstallationRepo: gameInstallRepo,
        versionRepo: versionRepo,
        exportHistoryRepo: exportHistoryRepo,
      );
      addTearDown(container.dispose);

      expect(
        await container.read(projectsReadyToCompileCountProvider.future),
        1,
      );
    });
  });

  group('packsAwaitingPublishCountProvider', () {
    test(
        'counts compilations generated after (or without) their last publish, '
        'filtered by installation', () async {
      final projectRepo = _MockProjectRepository();
      final gameInstallRepo = _MockGameInstallationRepository();
      final compilationRepo = _MockCompilationRepository();

      when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(
          _installation(id: 'install-wh3'),
        ),
      );
      when(() => compilationRepo.getAll()).thenAnswer(
        (_) async => Ok<List<Compilation>, TWMTDatabaseException>([
          // Matches game, generated, never published → counted.
          _compilation(
            id: 'c-never-published',
            gameInstallationId: 'install-wh3',
            lastGeneratedAt: 100,
          ),
          // Matches game, regenerated after publish → counted.
          _compilation(
            id: 'c-regenerated',
            gameInstallationId: 'install-wh3',
            lastGeneratedAt: 200,
            publishedAt: 150,
          ),
          // Matches game, published after last generation → skipped.
          _compilation(
            id: 'c-already-published',
            gameInstallationId: 'install-wh3',
            lastGeneratedAt: 100,
            publishedAt: 200,
          ),
          // Matches game, never generated → skipped.
          _compilation(
            id: 'c-never-generated',
            gameInstallationId: 'install-wh3',
            lastGeneratedAt: null,
            publishedAt: null,
          ),
          // Different installation → skipped even when otherwise qualifying.
          _compilation(
            id: 'c-other-game',
            gameInstallationId: 'install-other',
            lastGeneratedAt: 100,
            publishedAt: null,
          ),
        ]),
      );

      final container = _makeContainer(
        projectRepo: projectRepo,
        gameInstallationRepo: gameInstallRepo,
        compilationRepo: compilationRepo,
      );
      addTearDown(container.dispose);

      expect(
        await container.read(packsAwaitingPublishCountProvider.future),
        2,
      );
    });
  });
}
