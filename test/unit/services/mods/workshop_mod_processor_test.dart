import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/mods/utils/workshop_mod_processor.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_mod_info.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockApi extends Mock implements IWorkshopApiService {}

class _MockRepo extends Mock implements WorkshopModRepository {}

WorkshopModInfo _info(String id, {String title = 'Mod'}) => WorkshopModInfo(
      workshopId: id,
      title: title,
      workshopUrl: 'u/$id',
      appId: 1142710,
      timeUpdated: 200,
    );

WorkshopMod _mod(String id, {String title = 'Mod'}) => WorkshopMod(
      id: 'pk-$id',
      workshopId: id,
      title: title,
      appId: 1142710,
      workshopUrl: 'u/$id',
      timeUpdated: 100,
      createdAt: 1,
      updatedAt: 1,
    );

Ok<T, SteamServiceException> _aok<T>(T v) => Ok(v);
Err<T, SteamServiceException> _aerr<T>(String m) =>
    Err(SteamServiceException(m, code: 'X'));
Ok<T, TWMTDatabaseException> _rok<T>(T v) => Ok(v);
Err<T, TWMTDatabaseException> _rerr<T>(String m) => Err(TWMTDatabaseException(m));

void main() {
  setUpAll(() => registerFallbackValue(_mod('f')));

  late _MockApi api;
  late _MockRepo repo;
  late WorkshopModProcessor processor;

  setUp(() {
    api = _MockApi();
    repo = _MockRepo();
    processor = WorkshopModProcessor(
        workshopModRepository: repo, workshopApiService: api, logger: FakeLogger());
    when(() => repo.upsert(any())).thenAnswer((_) async => _rok(_mod('x')));
    when(() => repo.updateLastChecked(any(), any()))
        .thenAnswer((_) async => const Ok(null));
  });

  test('returns an empty map for no workshop ids', () async {
    expect(await processor.fetchAndProcessMods(workshopIds: [], appId: 1),
        isEmpty);
  });

  test('returns empty when the Steam API batch fails', () async {
    when(() => api.getMultipleModInfo(
            workshopIds: any(named: 'workshopIds'), appId: any(named: 'appId')))
        .thenAnswer((_) async => _aerr<List<WorkshopModInfo>>('api down'));

    expect(
      await processor.fetchAndProcessMods(workshopIds: ['1'], appId: 1142710),
      isEmpty,
    );
  });

  test('a new mod is upserted and returned with the fresh API timestamp',
      () async {
    when(() => api.getMultipleModInfo(
            workshopIds: any(named: 'workshopIds'), appId: any(named: 'appId')))
        .thenAnswer((_) async => _aok([_info('1')]));
    when(() => repo.getByWorkshopId('1'))
        .thenAnswer((_) async => _rerr<WorkshopMod>('absent'));

    final map = await processor.fetchAndProcessMods(
        workshopIds: ['1'], appId: 1142710);

    expect(map.containsKey('1'), isTrue);
    expect(map['1']!.timeUpdated, 200); // fresh API value
    verify(() => repo.upsert(any())).called(1);
  });

  test('an unchanged existing mod only bumps lastChecked (no upsert)',
      () async {
    when(() => api.getMultipleModInfo(
            workshopIds: any(named: 'workshopIds'), appId: any(named: 'appId')))
        .thenAnswer((_) async => _aok([_info('1', title: 'Same')]));
    when(() => repo.getByWorkshopId('1'))
        .thenAnswer((_) async => _rok(_mod('1', title: 'Same')));

    await processor.fetchAndProcessMods(workshopIds: ['1'], appId: 1142710);

    verify(() => repo.updateLastChecked('1', any())).called(1);
    verifyNever(() => repo.upsert(any()));
  });

  test('a changed existing mod is upserted', () async {
    when(() => api.getMultipleModInfo(
            workshopIds: any(named: 'workshopIds'), appId: any(named: 'appId')))
        .thenAnswer((_) async => _aok([_info('1', title: 'New Title')]));
    when(() => repo.getByWorkshopId('1'))
        .thenAnswer((_) async => _rok(_mod('1', title: 'Old Title')));

    await processor.fetchAndProcessMods(workshopIds: ['1'], appId: 1142710);

    verify(() => repo.upsert(any())).called(1);
  });
}
