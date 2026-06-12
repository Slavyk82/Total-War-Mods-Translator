import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/mod_scan_cache.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/scan_log_message.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/mod_scan_cache_repository.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/mods/mod_update_analysis_service.dart';
import 'package:twmt/services/mods/workshop_scanner_service.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';

import '../../helpers/noop_logger.dart';

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

class MockWorkshopModRepository extends Mock
    implements WorkshopModRepository {}

class MockModScanCacheRepository extends Mock
    implements ModScanCacheRepository {}

class MockAnalysisCacheRepository extends Mock
    implements ModUpdateAnalysisCacheRepository {}

class MockWorkshopApiService extends Mock implements IWorkshopApiService {}

class MockRpfmService extends Mock implements IRpfmService {}

class MockModUpdateAnalysisService extends Mock
    implements ModUpdateAnalysisService {}

GameInstallation _install({
  String? steamWorkshopPath,
  String? steamAppId = '1142710',
}) {
  return GameInstallation(
    id: 'gi1',
    gameCode: 'wh3',
    gameName: 'WH3',
    installationPath: r'C:\Games\wh3',
    steamWorkshopPath: steamWorkshopPath,
    steamAppId: steamAppId,
    createdAt: 1,
    updatedAt: 1,
  );
}

void main() {
  late MockProjectRepository projectRepo;
  late MockGameInstallationRepository gameRepo;
  late MockWorkshopModRepository workshopRepo;
  late MockModScanCacheRepository scanCacheRepo;
  late MockAnalysisCacheRepository analysisCacheRepo;
  late MockWorkshopApiService apiService;
  late MockRpfmService rpfm;
  late MockModUpdateAnalysisService analysisService;
  late WorkshopScannerService service;
  late Directory tempRoot;

  setUp(() async {
    projectRepo = MockProjectRepository();
    gameRepo = MockGameInstallationRepository();
    workshopRepo = MockWorkshopModRepository();
    scanCacheRepo = MockModScanCacheRepository();
    analysisCacheRepo = MockAnalysisCacheRepository();
    apiService = MockWorkshopApiService();
    rpfm = MockRpfmService();
    analysisService = MockModUpdateAnalysisService();
    tempRoot = await Directory.systemTemp.createTemp('ws_scan_test_');

    service = WorkshopScannerService(
      projectRepository: projectRepo,
      gameInstallationRepository: gameRepo,
      workshopModRepository: workshopRepo,
      modScanCacheRepository: scanCacheRepo,
      analysisCacheRepository: analysisCacheRepo,
      workshopApiService: apiService,
      rpfmService: rpfm,
      modUpdateAnalysisService: analysisService,
      logger: NoopLogger(),
    );

    // Common defaults; individual tests override what they need.
    when(() => rpfm.isRpfmAvailable()).thenAnswer((_) async => true);
    when(() => projectRepo.getAll())
        .thenAnswer((_) async => const Ok(<Project>[]));
    when(() => workshopRepo.getHiddenWorkshopIds())
        .thenAnswer((_) async => const Ok(<String>{}));
    when(() => workshopRepo.getByWorkshopIds(any()))
        .thenAnswer((_) async => const Ok(<WorkshopMod>[]));
    when(() => scanCacheRepo.getByPackFilePaths(any()))
        .thenAnswer((_) async => const Ok(<String, ModScanCache>{}));
    when(() => scanCacheRepo.upsertBatch(any()))
        .thenAnswer((_) async => const Ok(<ModScanCache>[]));
  });

  tearDown(() async {
    service.dispose();
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  group('early returns', () {
    test('fails fast when RPFM is unavailable', () async {
      when(() => rpfm.isRpfmAvailable()).thenAnswer((_) async => false);

      final result = await service.scanMods('wh3');

      expect(result, isA<Err>());
      expect((result as Err).error, isA<RpfmNotFoundException>());
      verifyNever(() => gameRepo.getByGameCode(any()));
    });

    test('errors when the game installation is not found', () async {
      when(() => gameRepo.getByGameCode('wh3'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('absent')));

      final result = await service.scanMods('wh3');

      expect(result, isA<Err>());
      expect((result as Err).error.message,
          contains('Game installation not found'));
    });

    test('returns empty when no workshop path is configured', () async {
      when(() => gameRepo.getByGameCode('wh3'))
          .thenAnswer((_) async => Ok(_install(steamWorkshopPath: null)));

      final result = await service.scanMods('wh3');

      expect((result as Ok).value.mods, isEmpty);
    });

    test('returns empty when the workshop folder does not exist', () async {
      when(() => gameRepo.getByGameCode('wh3')).thenAnswer(
        (_) async => Ok(_install(
          steamWorkshopPath: '${tempRoot.path}/does_not_exist',
        )),
      );

      final result = await service.scanMods('wh3');

      expect((result as Ok).value.mods, isEmpty);
    });
  });

  group('full scan', () {
    test('scans an empty workshop folder and returns no mods', () async {
      final wsDir = Directory('${tempRoot.path}/workshop')..createSync();
      when(() => gameRepo.getByGameCode('wh3'))
          .thenAnswer((_) async => Ok(_install(steamWorkshopPath: wsDir.path)));

      final result = await service.scanMods('wh3');

      expect(result, isA<Ok>());
      expect((result as Ok).value.mods, isEmpty);
      // No pack files -> workshop-id cache is never queried.
      verifyNever(() => workshopRepo.getByWorkshopIds(any()));
    });

    test('detects a localized mod and emits scan progress logs', () async {
      final wsDir = Directory('${tempRoot.path}/workshop')..createSync();
      final modDir = Directory('${wsDir.path}/123')..createSync();
      File('${modDir.path}/mod.pack').writeAsStringSync('PACK');

      // steamAppId null -> Steam metadata fetch is skipped, keeping the test
      // focused on the scanner's own orchestration.
      when(() => gameRepo.getByGameCode('wh3')).thenAnswer(
        (_) async =>
            Ok(_install(steamWorkshopPath: wsDir.path, steamAppId: null)),
      );
      when(() => rpfm.listPackContents(any()))
          .thenAnswer((_) async => const Ok(['text/db/foo.loc']));
      // Workshop metadata absent -> DetectedModBuilder falls back to cache.
      when(() => workshopRepo.getByWorkshopId('123'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('absent')));
      // A project with a different workshop id exercises the existing-id loop.
      when(() => projectRepo.getAll()).thenAnswer(
        (_) async => Ok([
          Project(
            id: 'p1',
            name: 'Other',
            modSteamId: '999',
            gameInstallationId: 'gi1',
            createdAt: 1,
            updatedAt: 1,
          ),
        ]),
      );

      final logs = <ScanLogMessage>[];
      final sub = service.scanLogStream.listen(logs.add);

      final result = await service.scanMods('wh3');

      expect(result, isA<Ok>());
      expect((result as Ok).value.mods, hasLength(1));
      expect(result.value.mods.single.workshopId, '123');
      await sub.cancel();
      expect(logs, isNotEmpty);
    });

    test('tolerates failures fetching cached workshop mods and hidden ids',
        () async {
      final wsDir = Directory('${tempRoot.path}/workshop')..createSync();
      final modDir = Directory('${wsDir.path}/123')..createSync();
      File('${modDir.path}/mod.pack').writeAsStringSync('PACK');

      when(() => gameRepo.getByGameCode('wh3')).thenAnswer(
        (_) async =>
            Ok(_install(steamWorkshopPath: wsDir.path, steamAppId: null)),
      );
      when(() => rpfm.listPackContents(any()))
          .thenAnswer((_) async => const Ok(['x.loc']));
      when(() => workshopRepo.getByWorkshopId('123'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('absent')));
      // Both helper repo calls fail -> service degrades gracefully.
      when(() => workshopRepo.getByWorkshopIds(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('cache fail')));
      when(() => workshopRepo.getHiddenWorkshopIds())
          .thenAnswer((_) async => Err(TWMTDatabaseException('hidden fail')));

      final result = await service.scanMods('wh3');

      expect(result, isA<Ok>());
      expect((result as Ok).value.mods, hasLength(1));
    });

    test('wraps an unexpected error in a ServiceException', () async {
      final wsDir = Directory('${tempRoot.path}/workshop')..createSync();
      when(() => gameRepo.getByGameCode('wh3'))
          .thenAnswer((_) async => Ok(_install(steamWorkshopPath: wsDir.path)));
      when(() => projectRepo.getAll()).thenThrow(Exception('kaboom'));

      final result = await service.scanMods('wh3');

      expect(result, isA<Err>());
      expect((result as Err).error.message,
          contains('Failed to scan Workshop folder'));
    });
  });

  test('dispose closes the scan log stream', () async {
    final done = expectLater(service.scanLogStream, emitsDone);
    service.dispose();
    await done;
  });
}
