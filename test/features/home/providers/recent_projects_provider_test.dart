import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/home/models/next_project_action.dart';
import 'package:twmt/features/home/providers/home_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_statistics.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
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

GameInstallation _installation({String id = 'install-wh3'}) => GameInstallation(
      id: id,
      gameCode: 'wh3',
      gameName: 'WH3',
      createdAt: 0,
      updatedAt: 0,
    );

Project _project({
  required String id,
  String gameInstallationId = 'install-wh3',
  int updatedAt = 1000,
}) =>
    Project(
      id: id,
      name: 'P-$id',
      gameInstallationId: gameInstallationId,
      createdAt: 0,
      updatedAt: updatedAt,
    );

ProjectStatistics _stats({
  int totalCount = 10,
  required int translatedCount,
  int errorCount = 0,
}) =>
    ProjectStatistics(
      totalCount: totalCount,
      translatedCount: translatedCount,
      pendingCount: totalCount - translatedCount,
      validatedCount: 0,
      errorCount: errorCount,
    );

ExportHistory _packExport({required String projectId}) => ExportHistory(
      id: 'eh-$projectId',
      projectId: projectId,
      languages: '[]',
      format: ExportFormat.pack,
      validatedOnly: false,
      outputPath: 'out.pack',
      entryCount: 0,
      exportedAt: 10,
    );

ProviderContainer _makeContainer({
  required ProjectRepository projectRepo,
  required GameInstallationRepository gameInstallationRepo,
  required TranslationVersionRepository versionRepo,
  required ExportHistoryRepository exportHistoryRepo,
  ConfiguredGame? selectedGame = _gameWh3,
}) {
  final overrides = <Override>[
    projectRepositoryProvider.overrideWithValue(projectRepo),
    gameInstallationRepositoryProvider.overrideWithValue(gameInstallationRepo),
    translationVersionRepositoryProvider.overrideWithValue(versionRepo),
    exportHistoryRepositoryProvider.overrideWithValue(exportHistoryRepo),
    selectedGameProvider.overrideWith(() => _FakeSelectedGame(selectedGame)),
  ];
  return ProviderContainer(overrides: overrides);
}

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  test('returns empty list when no projects exist (no game selected)',
      () async {
    final projectRepo = _MockProjectRepository();
    final gameInstallRepo = _MockGameInstallationRepository();
    final versionRepo = _MockTranslationVersionRepository();
    final exportHistoryRepo = _MockExportHistoryRepository();

    when(() => projectRepo.getAll()).thenAnswer(
      (_) async =>
          Ok<List<Project>, TWMTDatabaseException>(const <Project>[]),
    );

    final container = _makeContainer(
      projectRepo: projectRepo,
      gameInstallationRepo: gameInstallRepo,
      versionRepo: versionRepo,
      exportHistoryRepo: exportHistoryRepo,
      selectedGame: null,
    );
    addTearDown(container.dispose);

    final result = await container.read(recentProjectsProvider.future);
    expect(result, isEmpty);
  });

  test('classifies a project with errorCount > 0 as toReview', () async {
    final projectRepo = _MockProjectRepository();
    final gameInstallRepo = _MockGameInstallationRepository();
    final versionRepo = _MockTranslationVersionRepository();
    final exportHistoryRepo = _MockExportHistoryRepository();

    when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
      (_) async => Ok<GameInstallation, TWMTDatabaseException>(
        _installation(),
      ),
    );
    when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
      (_) async => Ok<List<Project>, TWMTDatabaseException>([
        _project(id: 'needs-review', updatedAt: 2000),
      ]),
    );
    when(() => versionRepo.getProjectStatistics('needs-review')).thenAnswer(
      (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(
        _stats(totalCount: 10, translatedCount: 10, errorCount: 3),
      ),
    );
    when(() => exportHistoryRepo.getLastPackExportByProject('needs-review'))
        .thenAnswer((_) async => null);

    final container = _makeContainer(
      projectRepo: projectRepo,
      gameInstallationRepo: gameInstallRepo,
      versionRepo: versionRepo,
      exportHistoryRepo: exportHistoryRepo,
    );
    addTearDown(container.dispose);

    final result = await container.read(recentProjectsProvider.future);
    expect(result, hasLength(1));
    expect(result.first.action, NextProjectAction.toReview);
    expect(result.first.project.id, 'needs-review');
  });

  test('classifies a 0%-translated project as translate', () async {
    final projectRepo = _MockProjectRepository();
    final gameInstallRepo = _MockGameInstallationRepository();
    final versionRepo = _MockTranslationVersionRepository();
    final exportHistoryRepo = _MockExportHistoryRepository();

    when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
      (_) async => Ok<GameInstallation, TWMTDatabaseException>(
        _installation(),
      ),
    );
    when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
      (_) async => Ok<List<Project>, TWMTDatabaseException>([
        _project(id: 'fresh'),
      ]),
    );
    when(() => versionRepo.getProjectStatistics('fresh')).thenAnswer(
      (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(
        _stats(totalCount: 10, translatedCount: 0),
      ),
    );
    when(() => exportHistoryRepo.getLastPackExportByProject('fresh'))
        .thenAnswer((_) async => null);

    final container = _makeContainer(
      projectRepo: projectRepo,
      gameInstallationRepo: gameInstallRepo,
      versionRepo: versionRepo,
      exportHistoryRepo: exportHistoryRepo,
    );
    addTearDown(container.dispose);

    final result = await container.read(recentProjectsProvider.future);
    expect(result, hasLength(1));
    expect(result.first.action, NextProjectAction.translate);
    expect(result.first.translatedPct, 0);
  });

  test('classifies a 100%-translated project with no pack as readyToCompile',
      () async {
    final projectRepo = _MockProjectRepository();
    final gameInstallRepo = _MockGameInstallationRepository();
    final versionRepo = _MockTranslationVersionRepository();
    final exportHistoryRepo = _MockExportHistoryRepository();

    when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
      (_) async => Ok<GameInstallation, TWMTDatabaseException>(
        _installation(),
      ),
    );
    when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
      (_) async => Ok<List<Project>, TWMTDatabaseException>([
        _project(id: 'ready'),
      ]),
    );
    when(() => versionRepo.getProjectStatistics('ready')).thenAnswer(
      (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(
        _stats(totalCount: 10, translatedCount: 10),
      ),
    );
    when(() => exportHistoryRepo.getLastPackExportByProject('ready'))
        .thenAnswer((_) async => null);

    final container = _makeContainer(
      projectRepo: projectRepo,
      gameInstallationRepo: gameInstallRepo,
      versionRepo: versionRepo,
      exportHistoryRepo: exportHistoryRepo,
    );
    addTearDown(container.dispose);

    final result = await container.read(recentProjectsProvider.future);
    expect(result, hasLength(1));
    expect(result.first.action, NextProjectAction.readyToCompile);
    expect(result.first.translatedPct, 100);
  });

  test('classifies a 100%-translated project with a pack as continueWork',
      () async {
    final projectRepo = _MockProjectRepository();
    final gameInstallRepo = _MockGameInstallationRepository();
    final versionRepo = _MockTranslationVersionRepository();
    final exportHistoryRepo = _MockExportHistoryRepository();

    when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
      (_) async => Ok<GameInstallation, TWMTDatabaseException>(
        _installation(),
      ),
    );
    when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
      (_) async => Ok<List<Project>, TWMTDatabaseException>([
        _project(id: 'packed'),
      ]),
    );
    when(() => versionRepo.getProjectStatistics('packed')).thenAnswer(
      (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(
        _stats(totalCount: 10, translatedCount: 10),
      ),
    );
    when(() => exportHistoryRepo.getLastPackExportByProject('packed'))
        .thenAnswer((_) async => _packExport(projectId: 'packed'));

    final container = _makeContainer(
      projectRepo: projectRepo,
      gameInstallationRepo: gameInstallRepo,
      versionRepo: versionRepo,
      exportHistoryRepo: exportHistoryRepo,
    );
    addTearDown(container.dispose);

    final result = await container.read(recentProjectsProvider.future);
    expect(result, hasLength(1));
    expect(result.first.action, NextProjectAction.continueWork);
  });

  test('classifies a mid-progress project (50%) as continueWork', () async {
    final projectRepo = _MockProjectRepository();
    final gameInstallRepo = _MockGameInstallationRepository();
    final versionRepo = _MockTranslationVersionRepository();
    final exportHistoryRepo = _MockExportHistoryRepository();

    when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
      (_) async => Ok<GameInstallation, TWMTDatabaseException>(
        _installation(),
      ),
    );
    when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
      (_) async => Ok<List<Project>, TWMTDatabaseException>([
        _project(id: 'half'),
      ]),
    );
    when(() => versionRepo.getProjectStatistics('half')).thenAnswer(
      (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(
        _stats(totalCount: 10, translatedCount: 5),
      ),
    );
    when(() => exportHistoryRepo.getLastPackExportByProject('half'))
        .thenAnswer((_) async => null);

    final container = _makeContainer(
      projectRepo: projectRepo,
      gameInstallationRepo: gameInstallRepo,
      versionRepo: versionRepo,
      exportHistoryRepo: exportHistoryRepo,
    );
    addTearDown(container.dispose);

    final result = await container.read(recentProjectsProvider.future);
    expect(result, hasLength(1));
    expect(result.first.action, NextProjectAction.continueWork);
    expect(result.first.translatedPct, 50);
  });

  test(
      'sorts by updatedAt desc, takes top 5, and filters by selected game '
      'installation', () async {
    final projectRepo = _MockProjectRepository();
    final gameInstallRepo = _MockGameInstallationRepository();
    final versionRepo = _MockTranslationVersionRepository();
    final exportHistoryRepo = _MockExportHistoryRepository();

    when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
      (_) async => Ok<GameInstallation, TWMTDatabaseException>(
        _installation(),
      ),
    );
    // 6 projects, only 5 should come back, ordered by updatedAt desc.
    when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
      (_) async => Ok<List<Project>, TWMTDatabaseException>([
        _project(id: 'p1', updatedAt: 100),
        _project(id: 'p2', updatedAt: 600),
        _project(id: 'p3', updatedAt: 500),
        _project(id: 'p4', updatedAt: 400),
        _project(id: 'p5', updatedAt: 300),
        _project(id: 'p6', updatedAt: 200),
      ]),
    );
    when(() => versionRepo.getProjectStatistics(any())).thenAnswer(
      (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(
        _stats(totalCount: 10, translatedCount: 5),
      ),
    );
    when(() => exportHistoryRepo.getLastPackExportByProject(any()))
        .thenAnswer((_) async => null);

    final container = _makeContainer(
      projectRepo: projectRepo,
      gameInstallationRepo: gameInstallRepo,
      versionRepo: versionRepo,
      exportHistoryRepo: exportHistoryRepo,
    );
    addTearDown(container.dispose);

    final result = await container.read(recentProjectsProvider.future);
    expect(result, hasLength(5));
    expect(
      result.map((e) => e.project.id).toList(),
      ['p2', 'p3', 'p4', 'p5', 'p6'],
    );
    // getAll must not be hit when a game is selected.
    verifyNever(() => projectRepo.getAll());
    verify(() => projectRepo.getByGameInstallation('install-wh3')).called(1);
  });
}
