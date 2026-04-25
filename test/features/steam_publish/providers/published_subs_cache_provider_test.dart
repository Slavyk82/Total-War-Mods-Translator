import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/steam_publish/providers/published_subs_cache_provider.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/compilation_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_mod_info.dart';

class _MockProjectRepository extends Mock implements ProjectRepository {}

class _MockCompilationRepository extends Mock implements CompilationRepository {}

class _MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

class _MockWorkshopApiService extends Mock implements IWorkshopApiService {}

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

GameInstallation _installation({String id = 'install-wh3'}) =>
    GameInstallation(
      id: id,
      gameCode: 'wh3',
      gameName: 'WH3',
      createdAt: 0,
      updatedAt: 0,
    );

Project _project({
  required String id,
  String? publishedSteamId,
}) =>
    Project(
      id: id,
      name: id,
      gameInstallationId: 'install-wh3',
      createdAt: 0,
      updatedAt: 0,
      publishedSteamId: publishedSteamId,
      publishedAt: publishedSteamId != null ? 1700000000 : null,
    );

Compilation _compilation({
  required String id,
  String? publishedSteamId,
}) =>
    Compilation(
      id: id,
      name: 'C-$id',
      prefix: '!',
      packName: 'pack-$id',
      gameInstallationId: 'install-wh3',
      createdAt: 0,
      updatedAt: 0,
      publishedSteamId: publishedSteamId,
      publishedAt: publishedSteamId != null ? 1700000000 : null,
    );

WorkshopModInfo _modInfo({
  required String id,
  required int subs,
}) =>
    WorkshopModInfo(
      workshopId: id,
      title: 'Mod $id',
      workshopUrl: 'https://example/$id',
      subscriptions: subs,
      appId: 1142710,
    );

ProviderContainer _makeContainer({
  required ProjectRepository projectRepo,
  required CompilationRepository compilationRepo,
  required GameInstallationRepository gameInstallationRepo,
  required IWorkshopApiService workshopApi,
  ConfiguredGame? selectedGame = _gameWh3,
}) {
  final container = ProviderContainer(
    overrides: [
      projectRepositoryProvider.overrideWithValue(projectRepo),
      compilationRepositoryProvider.overrideWithValue(compilationRepo),
      gameInstallationRepositoryProvider.overrideWithValue(gameInstallationRepo),
      workshopApiServiceProvider.overrideWithValue(workshopApi),
      selectedGameProvider.overrideWith(() => _FakeSelectedGame(selectedGame)),
    ],
  );
  return container;
}

void main() {
  group('publishedSubsCacheProvider', () {
    test('starts empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(publishedSubsCacheProvider), isEmpty);
    });

    test('refreshFromWorkshop populates cache with subscriber counts from API',
        () async {
      final projectRepo = _MockProjectRepository();
      final compilationRepo = _MockCompilationRepository();
      final gameInstallRepo = _MockGameInstallationRepository();
      final workshopApi = _MockWorkshopApiService();

      when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
        (_) async =>
            Ok<GameInstallation, TWMTDatabaseException>(_installation()),
      );
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([
          _project(id: 'p1', publishedSteamId: '111'),
          _project(id: 'p2', publishedSteamId: '222'),
          _project(id: 'p3'), // unpublished — must not be queried
        ]),
      );
      when(() => compilationRepo.getByGameInstallation('install-wh3'))
          .thenAnswer(
        (_) async => Ok<List<Compilation>, TWMTDatabaseException>([
          _compilation(id: 'c1', publishedSteamId: '333'),
        ]),
      );
      when(() => workshopApi.getMultipleModInfo(
            workshopIds: any(named: 'workshopIds'),
            appId: any(named: 'appId'),
          )).thenAnswer(
        (_) async => Ok<List<WorkshopModInfo>, SteamServiceException>([
          _modInfo(id: '111', subs: 1234),
          _modInfo(id: '222', subs: 50),
          _modInfo(id: '333', subs: 9999),
        ]),
      );

      final container = _makeContainer(
        projectRepo: projectRepo,
        compilationRepo: compilationRepo,
        gameInstallationRepo: gameInstallRepo,
        workshopApi: workshopApi,
      );
      addTearDown(container.dispose);

      await container
          .read(publishedSubsCacheProvider.notifier)
          .refreshFromWorkshop();

      final state = container.read(publishedSubsCacheProvider);
      expect(state, {'111': 1234, '222': 50, '333': 9999});

      final captured = verify(() => workshopApi.getMultipleModInfo(
            workshopIds: captureAny(named: 'workshopIds'),
            appId: 1142710,
          )).captured.single as List<String>;
      expect(captured.toSet(), {'111', '222', '333'});
    });

    test('refreshFromWorkshop leaves prior state untouched on API failure',
        () async {
      final projectRepo = _MockProjectRepository();
      final compilationRepo = _MockCompilationRepository();
      final gameInstallRepo = _MockGameInstallationRepository();
      final workshopApi = _MockWorkshopApiService();

      when(() => gameInstallRepo.getByGameCode('wh3')).thenAnswer(
        (_) async =>
            Ok<GameInstallation, TWMTDatabaseException>(_installation()),
      );
      when(() => projectRepo.getByGameInstallation('install-wh3')).thenAnswer(
        (_) async => Ok<List<Project>, TWMTDatabaseException>([
          _project(id: 'p1', publishedSteamId: '111'),
        ]),
      );
      when(() => compilationRepo.getByGameInstallation('install-wh3'))
          .thenAnswer(
        (_) async => Ok<List<Compilation>, TWMTDatabaseException>(const []),
      );

      var callCount = 0;
      when(() => workshopApi.getMultipleModInfo(
            workshopIds: any(named: 'workshopIds'),
            appId: any(named: 'appId'),
          )).thenAnswer((_) async {
        callCount += 1;
        if (callCount == 1) {
          return Ok<List<WorkshopModInfo>, SteamServiceException>([
            _modInfo(id: '111', subs: 999),
          ]);
        }
        return Err<List<WorkshopModInfo>, SteamServiceException>(
          const WorkshopApiException('boom'),
        );
      });

      final container = _makeContainer(
        projectRepo: projectRepo,
        compilationRepo: compilationRepo,
        gameInstallationRepo: gameInstallRepo,
        workshopApi: workshopApi,
      );
      addTearDown(container.dispose);

      // First call — succeeds, populates cache.
      await container
          .read(publishedSubsCacheProvider.notifier)
          .refreshFromWorkshop();
      expect(container.read(publishedSubsCacheProvider), {'111': 999});

      // Second call — API fails. Cache must not be cleared.
      await container
          .read(publishedSubsCacheProvider.notifier)
          .refreshFromWorkshop();
      expect(container.read(publishedSubsCacheProvider), {'111': 999});
    });
  });
}
