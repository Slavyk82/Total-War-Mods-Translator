import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_mod_info.dart';
import 'package:twmt/services/steam/workshop_metadata_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockApi extends Mock implements IWorkshopApiService {}

class _MockRepo extends Mock implements WorkshopModRepository {}

WorkshopModInfo _info(String id, {String title = 'Mod'}) => WorkshopModInfo(
      workshopId: id,
      title: title,
      workshopUrl: 'https://x/$id',
      appId: 1142710,
      timeUpdated: 100,
    );

WorkshopMod _mod(String id, {int? createdAt}) => WorkshopMod(
      id: 'pk-$id',
      workshopId: id,
      title: 'Old',
      appId: 1142710,
      workshopUrl: 'u',
      createdAt: createdAt ?? 1,
      updatedAt: 1,
    );

// API uses SteamServiceException; the repository uses TWMTDatabaseException.
Ok<T, SteamServiceException> _aok<T>(T v) => Ok(v);
Err<T, SteamServiceException> _aerr<T>(String m) =>
    Err(SteamServiceException(m, code: 'TEST'));
Ok<T, TWMTDatabaseException> _rok<T>(T v) => Ok(v);
Err<T, TWMTDatabaseException> _rerr<T>(String m) => Err(TWMTDatabaseException(m));

void main() {
  setUpAll(() => registerFallbackValue(_mod('f')));

  late _MockApi api;
  late _MockRepo repo;
  late WorkshopMetadataService service;

  setUp(() {
    api = _MockApi();
    repo = _MockRepo();
    service = WorkshopMetadataService(
        apiService: api, repository: repo, logger: FakeLogger());
  });

  group('fetchAndStore', () {
    test('errors when the API call fails', () async {
      when(() => api.getModInfo(
              workshopId: any(named: 'workshopId'), appId: any(named: 'appId')))
          .thenAnswer((_) async => _aerr<WorkshopModInfo>('api down'));

      final r = await service.fetchAndStore(workshopId: '1', appId: 1142710);
      expect(r.isErr, isTrue);
    });

    test('reuses the existing id/createdAt and upserts', () async {
      when(() => api.getModInfo(
              workshopId: any(named: 'workshopId'), appId: any(named: 'appId')))
          .thenAnswer((_) async => _aok(_info('1', title: 'New Title')));
      when(() => repo.getByWorkshopId('1'))
          .thenAnswer((_) async => _rok(_mod('1', createdAt: 42)));
      when(() => repo.upsert(any())).thenAnswer((_) async => _rok(_mod('1')));

      final r = await service.fetchAndStore(workshopId: '1', appId: 1142710);

      expect(r.isOk, isTrue);
      final saved = verify(() => repo.upsert(captureAny())).captured.single
          as WorkshopMod;
      expect(saved.id, 'pk-1'); // reused
      expect(saved.createdAt, 42); // preserved
      expect(saved.title, 'New Title');
    });

    test('propagates a database upsert failure', () async {
      when(() => api.getModInfo(
              workshopId: any(named: 'workshopId'), appId: any(named: 'appId')))
          .thenAnswer((_) async => _aok(_info('1')));
      when(() => repo.getByWorkshopId('1'))
          .thenAnswer((_) async => _rerr<WorkshopMod>('none'));
      when(() => repo.upsert(any())).thenAnswer((_) async => _rerr<WorkshopMod>('db'));

      final r = await service.fetchAndStore(workshopId: '1', appId: 1142710);
      expect(r.isErr, isTrue);
    });
  });

  group('fetchAndStoreBatch', () {
    test('returns empty for an empty list', () async {
      expect((await service.fetchAndStoreBatch(workshopIds: [], appId: 1)).unwrap(),
          isEmpty);
    });

    test('rejects more than 100 ids', () async {
      final ids = List.generate(101, (i) => '$i');
      expect((await service.fetchAndStoreBatch(workshopIds: ids, appId: 1)).isErr,
          isTrue);
    });

    test('upserts the fetched mods in batch', () async {
      when(() => api.getMultipleModInfo(
              workshopIds: any(named: 'workshopIds'), appId: any(named: 'appId')))
          .thenAnswer((_) async => _aok([_info('1'), _info('2')]));
      when(() => repo.getByWorkshopIds(any()))
          .thenAnswer((_) async => _rok(<WorkshopMod>[]));
      when(() => repo.upsertBatch(any()))
          .thenAnswer((_) async => _rok(<WorkshopMod>[_mod('1'), _mod('2')]));

      final r = await service.fetchAndStoreBatch(
          workshopIds: ['1', '2'], appId: 1142710);

      expect(r.unwrap(), hasLength(2));
      verify(() => repo.upsertBatch(any())).called(1);
    });
  });

  group('checkAndUpdateMods', () {
    test('returns the ids the API flags as updated', () async {
      when(() => repo.getByWorkshopIds(any()))
          .thenAnswer((_) async => _rok([_mod('1'), _mod('2')]));
      when(() => api.checkForUpdates(
            modsWithTimestamps: any(named: 'modsWithTimestamps'),
            appId: any(named: 'appId'),
          )).thenAnswer((_) async => _aok({'1': true, '2': false}));
      when(() => api.getMultipleModInfo(
              workshopIds: any(named: 'workshopIds'), appId: any(named: 'appId')))
          .thenAnswer((_) async => _aok([_info('1')]));
      when(() => repo.upsertBatch(any()))
          .thenAnswer((_) async => _rok(<WorkshopMod>[_mod('1')]));

      final r = await service.checkAndUpdateMods(
          workshopIds: ['1', '2'], appId: 1142710);

      expect(r.unwrap(), ['1']);
    });

    test('propagates a local lookup failure', () async {
      when(() => repo.getByWorkshopIds(any()))
          .thenAnswer((_) async => _rerr<List<WorkshopMod>>('db'));

      final r = await service.checkAndUpdateMods(
          workshopIds: ['1'], appId: 1142710);
      expect(r.isErr, isTrue);
    });
  });

  group('simple getters', () {
    test('getModMetadata maps an error result', () async {
      when(() => repo.getByWorkshopId('1'))
          .thenAnswer((_) async => _rerr<WorkshopMod>('gone'));
      expect((await service.getModMetadata(workshopId: '1')).isErr, isTrue);
    });

    test('modExistsOnSteam delegates to the API', () async {
      when(() => api.modExists(
              workshopId: any(named: 'workshopId'), appId: any(named: 'appId')))
          .thenAnswer((_) async => _aok(true));
      expect((await service.modExistsOnSteam(workshopId: '1', appId: 1)).unwrap(),
          isTrue);
    });

    test('getModsByApp delegates to the repository', () async {
      when(() => repo.getByAppId(1142710))
          .thenAnswer((_) async => _rok([_mod('1')]));
      expect((await service.getModsByApp(appId: 1142710)).unwrap(), hasLength(1));
    });
  });
}
