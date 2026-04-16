import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/home/providers/action_grid_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_statistics.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../../../helpers/test_bootstrap.dart';

class _MockProjectRepository extends Mock implements ProjectRepository {}

class _MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

class _MockTranslationVersionRepository extends Mock
    implements TranslationVersionRepository {}

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
}) =>
    Project(
      id: id,
      name: 'P-$id',
      gameInstallationId: gameInstallationId,
      createdAt: 0,
      updatedAt: 0,
    );

ProjectStatistics _stats({int errorCount = 0}) => ProjectStatistics(
      totalCount: 10,
      translatedCount: 10 - errorCount,
      pendingCount: 0,
      validatedCount: 0,
      errorCount: errorCount,
    );

ProviderContainer _makeContainer({
  required ProjectRepository projectRepo,
  required GameInstallationRepository gameInstallationRepo,
  required TranslationVersionRepository versionRepo,
  ConfiguredGame? selectedGame = _gameWh3,
}) {
  return ProviderContainer(
    overrides: [
      projectRepositoryProvider.overrideWithValue(projectRepo),
      gameInstallationRepositoryProvider.overrideWithValue(gameInstallationRepo),
      translationVersionRepositoryProvider.overrideWithValue(versionRepo),
      selectedGameProvider.overrideWith(() => _FakeSelectedGame(selectedGame)),
    ],
  );
}

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  group('projectsToReviewCountProvider', () {
    test('returns 0 when no project has needs-review units', () async {
      final projectRepo = _MockProjectRepository();
      final gameInstallRepo = _MockGameInstallationRepository();
      final versionRepo = _MockTranslationVersionRepository();

      when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(
          _installation(),
        ),
      );
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([
          _project(id: 'a'),
          _project(id: 'b'),
        ]),
      );
      when(() => versionRepo.getProjectStatistics(any())).thenAnswer(
        (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(_stats()),
      );

      final container = _makeContainer(
        projectRepo: projectRepo,
        gameInstallationRepo: gameInstallRepo,
        versionRepo: versionRepo,
      );
      addTearDown(container.dispose);

      expect(await container.read(projectsToReviewCountProvider.future), 0);
    });

    test('counts projects whose stats report errorCount > 0', () async {
      final projectRepo = _MockProjectRepository();
      final gameInstallRepo = _MockGameInstallationRepository();
      final versionRepo = _MockTranslationVersionRepository();

      when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok<GameInstallation, TWMTDatabaseException>(
          _installation(),
        ),
      );
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([
          _project(id: 'clean'),
          _project(id: 'needs-review-1'),
          _project(id: 'needs-review-2'),
        ]),
      );
      when(() => versionRepo.getProjectStatistics('clean')).thenAnswer(
        (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(_stats()),
      );
      when(() => versionRepo.getProjectStatistics('needs-review-1'))
          .thenAnswer(
        (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(
          _stats(errorCount: 3),
        ),
      );
      when(() => versionRepo.getProjectStatistics('needs-review-2'))
          .thenAnswer(
        (_) async => Ok<ProjectStatistics, TWMTDatabaseException>(
          _stats(errorCount: 1),
        ),
      );

      final container = _makeContainer(
        projectRepo: projectRepo,
        gameInstallationRepo: gameInstallRepo,
        versionRepo: versionRepo,
      );
      addTearDown(container.dispose);

      expect(await container.read(projectsToReviewCountProvider.future), 2);
    });
  });
}
