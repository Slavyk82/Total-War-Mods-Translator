import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/mod_update_analysis_cache.dart';
import 'package:twmt/models/domain/mod_update_status.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/models/domain/scan_log_message.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/mods/detected_mod_builder.dart';
import 'package:twmt/services/mods/project_analysis_handler.dart'
    hide ScanLogEmitter;
import 'package:twmt/services/mods/utils/workshop_scan_models.dart';

import '../../helpers/noop_logger.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockWorkshopModRepository extends Mock implements WorkshopModRepository {}

class MockAnalysisCacheRepository extends Mock
    implements ModUpdateAnalysisCacheRepository {}

class MockProjectAnalysisHandler extends Mock
    implements ProjectAnalysisHandler {}

class MockProjectRepository extends Mock implements ProjectRepository {}

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

ModLocalData _localData({
  String workshopId = '111',
  String packFileName = 'my_mod',
  String? modImagePath,
  bool hasLocFiles = false,
  int fileLastModified = 1000,
  String path = r'C:\mods\my_mod.pack',
}) {
  return ModLocalData(
    workshopId: workshopId,
    packFile: File(path),
    packFileName: packFileName,
    modImagePath: modImagePath,
    hasLocFiles: hasLocFiles,
    fileLastModified: fileLastModified,
  );
}

WorkshopMod _workshopMod({
  String workshopId = '111',
  String title = 'Steam Title',
  int? timeUpdated = 1000,
  int? subscriptions = 42,
}) {
  return WorkshopMod(
    id: 'wm-$workshopId',
    workshopId: workshopId,
    title: title,
    appId: 1142710,
    workshopUrl: 'https://example/$workshopId',
    timeUpdated: timeUpdated,
    subscriptions: subscriptions,
    createdAt: 0,
    updatedAt: 0,
  );
}

Project _project({
  String id = 'p1',
  String name = 'Project',
  String workshopId = '111',
  String? storedModTitle,
}) {
  return Project(
    id: id,
    name: name,
    modSteamId: workshopId,
    gameInstallationId: 'g1',
    createdAt: 1,
    updatedAt: 1,
    metadata: storedModTitle == null
        ? null
        : ProjectMetadata(modTitle: storedModTitle).toJsonString(),
  );
}

ModUpdateAnalysis _analysis({
  int newUnits = 0,
  int modifiedUnits = 0,
  int removedUnits = 0,
}) {
  return ModUpdateAnalysis(
    newUnitsCount: newUnits,
    removedUnitsCount: removedUnits,
    modifiedUnitsCount: modifiedUnits,
    totalPackUnits: 100,
    totalProjectUnits: 100,
  );
}

ModUpdateAnalysisCache _cache({
  String projectId = 'p1',
  String packFilePath = r'C:\mods\my_mod.pack',
  int fileLastModified = 1000,
  int newUnits = 0,
  int modifiedUnits = 0,
  int removedUnits = 0,
}) {
  return ModUpdateAnalysisCache(
    id: 'cache1',
    projectId: projectId,
    packFilePath: packFilePath,
    fileLastModified: fileLastModified,
    newUnitsCount: newUnits,
    removedUnitsCount: removedUnits,
    modifiedUnitsCount: modifiedUnits,
    totalPackUnits: 100,
    totalProjectUnits: 100,
    analyzedAt: 0,
  );
}

void main() {
  late MockWorkshopModRepository workshopRepo;
  late MockAnalysisCacheRepository cacheRepo;
  late MockProjectAnalysisHandler analysisHandler;
  late MockProjectRepository projectRepo;
  late DetectedModBuilder builder;

  setUpAll(() {
    registerFallbackValue(_project());
  });

  setUp(() {
    workshopRepo = MockWorkshopModRepository();
    cacheRepo = MockAnalysisCacheRepository();
    analysisHandler = MockProjectAnalysisHandler();
    projectRepo = MockProjectRepository();
    builder = DetectedModBuilder(
      workshopModRepository: workshopRepo,
      analysisCacheRepository: cacheRepo,
      analysisHandler: analysisHandler,
      projectRepository: projectRepo,
      logger: NoopLogger(),
    );
  });

  Future<ModScanResultLike> build({
    required List<ModLocalData> modDataList,
    Map<String, WorkshopMod> workshopModsMap = const {},
    Map<String, WorkshopMod> cachedModsMap = const {},
    Map<String, Project> existingWorkshopIds = const {},
    Set<String> hiddenWorkshopIds = const {},
    ScanLogEmitter? emitLog,
  }) async {
    final result = await builder.buildDetectedMods(
      modDataList: modDataList,
      workshopModsMap: workshopModsMap,
      cachedModsMap: cachedModsMap,
      existingWorkshopIds: existingWorkshopIds,
      hiddenWorkshopIds: hiddenWorkshopIds,
      emitLog: emitLog,
    );
    return ModScanResultLike(result.mods, result.translationStatsChanged);
  }

  group('buildDetectedMods - workshop metadata enrichment', () {
    test('uses Workshop title and metadata when present', () async {
      final result = await build(
        modDataList: [_localData(modImagePath: r'C:\img.png')],
        workshopModsMap: {'111': _workshopMod(title: 'Steam Title')},
      );

      expect(result.mods, hasLength(1));
      final mod = result.mods.single;
      expect(mod.name, 'Steam Title');
      expect(mod.metadata?.modTitle, 'Steam Title');
      expect(mod.metadata?.modSubscribers, 42);
      expect(mod.imageUrl, r'C:\img.png');
      expect(mod.timeUpdated, 1000);
      expect(mod.updateStatus, ModUpdateStatus.upToDate);
      expect(result.translationStatsChanged, isFalse);
    });

    test('cleans the pack file name when no Workshop data and falls back to '
        'cache repo Err with an image', () async {
      when(() => workshopRepo.getByWorkshopId(any())).thenAnswer(
        (_) async => Err(TWMTDatabaseException('not found')),
      );

      final result = await build(
        modDataList: [
          _localData(packFileName: 'my_awesome-mod', modImagePath: r'C:\i.png'),
        ],
      );

      final mod = result.mods.single;
      // _cleanModName: underscores/hyphens -> spaces, title-cased.
      expect(mod.name, 'My Awesome Mod');
      expect(mod.metadata?.modTitle, 'My Awesome Mod');
      expect(mod.imageUrl, r'C:\i.png');
    });

    test('returns null metadata when no Workshop data, cache Err and no image',
        () async {
      when(() => workshopRepo.getByWorkshopId(any())).thenAnswer(
        (_) async => Err(TWMTDatabaseException('not found')),
      );

      final result = await build(modDataList: [_localData()]);

      final mod = result.mods.single;
      expect(mod.metadata, isNull);
      expect(mod.name, 'My Mod');
    });

    test('falls back to DB cache (Ok) metadata when batch fetch missing',
        () async {
      when(() => workshopRepo.getByWorkshopId('111')).thenAnswer(
        (_) async => Ok(_workshopMod(title: 'Cached Title', subscriptions: 7)),
      );

      final result = await build(
        modDataList: [_localData(modImagePath: r'C:\c.png')],
        cachedModsMap: {'111': _workshopMod(timeUpdated: 1000)},
      );

      final mod = result.mods.single;
      expect(mod.name, 'Cached Title');
      expect(mod.metadata?.modSubscribers, 7);
      // timeUpdated falls back to the cached value when API fetch failed.
      expect(mod.timeUpdated, 1000);
    });
  });

  group('buildDetectedMods - update status', () {
    test('marks needsDownload when Steam is newer than local file', () async {
      final result = await build(
        modDataList: [_localData(fileLastModified: 500)],
        workshopModsMap: {'111': _workshopMod(timeUpdated: 1000)},
      );

      expect(result.mods.single.updateStatus, ModUpdateStatus.needsDownload);
    });

    test('marks hidden mods', () async {
      final result = await build(
        modDataList: [_localData()],
        workshopModsMap: {'111': _workshopMod()},
        hiddenWorkshopIds: {'111'},
      );

      expect(result.mods.single.isHidden, isTrue);
    });
  });

  group('buildDetectedMods - analysis on new Steam update', () {
    test('runs analysis, emits stats change and does NOT sync timeUpdated '
        'when changes are found', () async {
      final project = _project(storedModTitle: 'Steam Title');
      when(() => cacheRepo.getByProjectAndPath(any(), any()))
          .thenAnswer((_) async => Ok(null));
      when(() => analysisHandler.analyzeProjectChanges(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
            workshopId: any(named: 'workshopId'),
            fileLastModified: any(named: 'fileLastModified'),
            emitLog: any(named: 'emitLog'),
          )).thenAnswer(
        (_) async => ProjectAnalysisResult(
          analysis: _analysis(newUnits: 3),
          statsChanged: true,
        ),
      );

      final logs = <String>[];
      final result = await build(
        modDataList: [_localData(fileLastModified: 2000)],
        workshopModsMap: {'111': _workshopMod(timeUpdated: 1500)},
        cachedModsMap: {'111': _workshopMod(timeUpdated: 1000)},
        existingWorkshopIds: {'111': project},
        emitLog: (msg, [level = ScanLogLevel.info]) => logs.add(msg),
      );

      expect(result.translationStatsChanged, isTrue);
      expect(result.mods.single.updateStatus, ModUpdateStatus.hasChanges);
      expect(logs, isNotEmpty);
      verifyNever(() => workshopRepo.updateTimeUpdated(any(), any()));
    });

    test('syncs timeUpdated when analysis finds no changes', () async {
      final project = _project();
      when(() => cacheRepo.getByProjectAndPath(any(), any()))
          .thenAnswer((_) async => Ok(null));
      when(() => analysisHandler.analyzeProjectChanges(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
            workshopId: any(named: 'workshopId'),
            fileLastModified: any(named: 'fileLastModified'),
            emitLog: any(named: 'emitLog'),
          )).thenAnswer((_) async => const ProjectAnalysisResult());
      when(() => workshopRepo.updateTimeUpdated(any(), any()))
          .thenAnswer((_) async => const Ok(null));

      await build(
        modDataList: [_localData(fileLastModified: 2000)],
        workshopModsMap: {'111': _workshopMod(timeUpdated: 1500)},
        cachedModsMap: {'111': _workshopMod(timeUpdated: 1000)},
        existingWorkshopIds: {'111': project},
      );

      verify(() => workshopRepo.updateTimeUpdated('111', 1500)).called(1);
    });

    test('runs fresh analysis when analysis cache is invalid even without a '
        'new Steam update', () async {
      final project = _project();
      // Stale cache (different fileLastModified) -> analysisCacheInvalid.
      when(() => cacheRepo.getByProjectAndPath(any(), any()))
          .thenAnswer((_) async => Ok(_cache(fileLastModified: 1)));
      when(() => analysisHandler.analyzeProjectChanges(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
            workshopId: any(named: 'workshopId'),
            fileLastModified: any(named: 'fileLastModified'),
            emitLog: any(named: 'emitLog'),
          )).thenAnswer(
        (_) async => ProjectAnalysisResult(analysis: _analysis(newUnits: 1)),
      );

      await build(
        modDataList: [_localData(fileLastModified: 1000)],
        workshopModsMap: {'111': _workshopMod(timeUpdated: 1000)},
        cachedModsMap: {'111': _workshopMod(timeUpdated: 1000)},
        existingWorkshopIds: {'111': project},
      );

      verify(() => analysisHandler.analyzeProjectChanges(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
            workshopId: any(named: 'workshopId'),
            fileLastModified: any(named: 'fileLastModified'),
            emitLog: any(named: 'emitLog'),
          )).called(1);
    });
  });

  group('buildDetectedMods - cached analysis reuse', () {
    test('uses valid cached analysis with changes without re-running analysis',
        () async {
      final project = _project();
      when(() => cacheRepo.getByProjectAndPath(any(), any())).thenAnswer(
        (_) async => Ok(_cache(fileLastModified: 1000, newUnits: 5)),
      );

      final result = await build(
        modDataList: [_localData(fileLastModified: 1000)],
        workshopModsMap: {'111': _workshopMod(timeUpdated: 1000)},
        cachedModsMap: {'111': _workshopMod(timeUpdated: 1000)},
        existingWorkshopIds: {'111': project},
      );

      expect(result.mods.single.updateStatus, ModUpdateStatus.hasChanges);
      expect(result.mods.single.updateAnalysis?.newUnitsCount, 5);
      verifyNever(() => analysisHandler.analyzeProjectChanges(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
            workshopId: any(named: 'workshopId'),
            fileLastModified: any(named: 'fileLastModified'),
            emitLog: any(named: 'emitLog'),
          ));
    });
  });

  group('buildDetectedMods - timestamp sync without project', () {
    test('syncs timeUpdated when no project imported but timestamps differ',
        () async {
      when(() => workshopRepo.updateTimeUpdated(any(), any()))
          .thenAnswer((_) async => const Ok(null));

      await build(
        modDataList: [_localData(fileLastModified: 2000)],
        workshopModsMap: {'111': _workshopMod(timeUpdated: 1500)},
        cachedModsMap: {'111': _workshopMod(timeUpdated: 1000)},
      );

      verify(() => workshopRepo.updateTimeUpdated('111', 1500)).called(1);
    });
  });

  group('buildDetectedMods - project title sync', () {
    test('updates project when Workshop title changed', () async {
      final project = _project(storedModTitle: 'Old Title');
      when(() => cacheRepo.getByProjectAndPath(any(), any()))
          .thenAnswer((_) async => Ok(_cache(fileLastModified: 1000)));
      when(() => projectRepo.update(any()))
          .thenAnswer((invocation) async => Ok(_project()));

      final logs = <String>[];
      await build(
        modDataList: [_localData(fileLastModified: 1000)],
        workshopModsMap: {'111': _workshopMod(title: 'New Title')},
        cachedModsMap: {'111': _workshopMod(timeUpdated: 1000)},
        existingWorkshopIds: {'111': project},
        emitLog: (msg, [level = ScanLogLevel.info]) => logs.add(msg),
      );

      final captured =
          verify(() => projectRepo.update(captureAny())).captured.single
              as Project;
      expect(captured.name, 'New Title');
      expect(captured.parsedMetadata?.modTitle, 'New Title');
      expect(logs, isNotEmpty);
    });

    test('does not update project when stored title matches', () async {
      final project = _project(storedModTitle: 'Same Title');
      when(() => cacheRepo.getByProjectAndPath(any(), any()))
          .thenAnswer((_) async => Ok(_cache(fileLastModified: 1000)));

      await build(
        modDataList: [_localData(fileLastModified: 1000)],
        workshopModsMap: {'111': _workshopMod(title: 'Same Title')},
        cachedModsMap: {'111': _workshopMod(timeUpdated: 1000)},
        existingWorkshopIds: {'111': project},
      );

      verifyNever(() => projectRepo.update(any()));
    });

    test('swallows repository error during title update', () async {
      final project = _project(storedModTitle: 'Old Title');
      when(() => cacheRepo.getByProjectAndPath(any(), any()))
          .thenAnswer((_) async => Ok(_cache(fileLastModified: 1000)));
      when(() => projectRepo.update(any()))
          .thenThrow(Exception('db down'));

      // Should not rethrow; the mod is still produced.
      final result = await build(
        modDataList: [_localData(fileLastModified: 1000)],
        workshopModsMap: {'111': _workshopMod(title: 'New Title')},
        cachedModsMap: {'111': _workshopMod(timeUpdated: 1000)},
        existingWorkshopIds: {'111': project},
      );

      expect(result.mods, hasLength(1));
    });
  });

  test('returns an empty result for an empty mod list', () async {
    final result = await build(modDataList: const []);
    expect(result.mods, isEmpty);
    expect(result.translationStatsChanged, isFalse);
  });
}

/// Small holder mirroring [ModScanResult] fields for readable assertions.
class ModScanResultLike {
  ModScanResultLike(this.mods, this.translationStatsChanged);
  final List<DetectedMod> mods;
  final bool translationStatsChanged;
}
