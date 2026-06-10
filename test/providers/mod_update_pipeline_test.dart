import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/mod_update_analysis_cache.dart';
import 'package:twmt/models/domain/mod_version.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/mods/mod_update_provider.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';
import 'package:twmt/repositories/mod_version_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/mods/mod_update_analysis_service.dart';
import 'package:twmt/services/steam/i_steamcmd_service.dart';
import 'package:twmt/services/steam/models/steamcmd_download_result.dart';

import '../helpers/fakes/fake_logger.dart';

// Regression tests for the "Update mod" flow (ModUpdateQueue._updateProject).
//
// The post-download step used to insert a PLACEHOLDER ModVersion (`// TODO:
// Implement change detection logic`) with unitsAdded/Modified/Deleted all 0
// and never invoked ModUpdateAnalysisService: the user saw "completed" while
// the downloaded pack's new keys, modified source texts and removed keys were
// never applied to the database. The flow must run the real analysis pipeline
// and persist a ModVersion carrying the real change counts.

class _MockSteamCmdService extends Mock implements ISteamCmdService {}

class _MockModVersionRepository extends Mock implements ModVersionRepository {}

class _MockProjectRepository extends Mock implements ProjectRepository {}

class _MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

class _MockModUpdateAnalysisService extends Mock
    implements ModUpdateAnalysisService {}

class _MockAnalysisCacheRepository extends Mock
    implements ModUpdateAnalysisCacheRepository {}

class _FakeModVersion extends Fake implements ModVersion {}

class _FakeAnalysisCache extends Fake implements ModUpdateAnalysisCache {}

class _FakeAnalysis extends Fake implements ModUpdateAnalysis {}

void main() {
  const projectId = 'proj-1';
  const workshopId = '123456789';

  late _MockSteamCmdService steamService;
  late _MockModVersionRepository versionRepo;
  late _MockProjectRepository projectRepo;
  late _MockGameInstallationRepository gameRepo;
  late _MockModUpdateAnalysisService analysisService;
  late _MockAnalysisCacheRepository cacheRepo;
  late Directory downloadDir;
  late ProviderContainer container;

  final project = Project(
    id: projectId,
    name: 'Test mod',
    gameInstallationId: 'gi-1',
    modSteamId: workshopId,
    sourceLanguageCode: 'en',
    createdAt: 0,
    updatedAt: 0,
  );
  final gameInstallation = GameInstallation(
    id: 'gi-1',
    gameCode: 'wh3',
    gameName: 'WH3',
    steamAppId: '1142710',
    createdAt: 0,
    updatedAt: 0,
  );

  setUpAll(() {
    registerFallbackValue(_FakeModVersion());
    registerFallbackValue(_FakeAnalysisCache());
    registerFallbackValue(_FakeAnalysis());
  });

  setUp(() async {
    steamService = _MockSteamCmdService();
    versionRepo = _MockModVersionRepository();
    projectRepo = _MockProjectRepository();
    gameRepo = _MockGameInstallationRepository();
    analysisService = _MockModUpdateAnalysisService();
    cacheRepo = _MockAnalysisCacheRepository();
    downloadDir = await Directory.systemTemp.createTemp('twmt_mod_update_test');

    when(() => steamService.progressStream)
        .thenAnswer((_) => const Stream<double>.empty());
    when(() => steamService.downloadMod(
          workshopId: any(named: 'workshopId'),
          appId: any(named: 'appId'),
          forceUpdate: any(named: 'forceUpdate'),
        )).thenAnswer((_) async => Ok(SteamCmdDownloadResult(
          workshopId: workshopId,
          appId: 1142710,
          downloadPath: downloadDir.path,
          sizeBytes: 1024,
          durationMs: 10,
          timestamp: DateTime(2026, 6, 9),
          wasUpdate: true,
        )));

    when(() => projectRepo.getById(projectId))
        .thenAnswer((_) async => Ok(project));
    when(() => projectRepo.setModUpdateImpact(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => gameRepo.getById('gi-1'))
        .thenAnswer((_) async => Ok(gameInstallation));

    when(() => versionRepo.insert(any())).thenAnswer((inv) async =>
        Ok(inv.positionalArguments.first as ModVersion));
    when(() => versionRepo.markAsCurrent(any())).thenAnswer((inv) async => Ok(
        ModVersion(
            id: inv.positionalArguments.first as String,
            projectId: projectId,
            versionString: 'v',
            detectedAt: 0)));

    when(() => cacheRepo.getByProjectAndPath(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => cacheRepo.upsert(any())).thenAnswer((inv) async =>
        Ok(inv.positionalArguments.first as ModUpdateAnalysisCache));

    container = ProviderContainer(overrides: [
      steamCmdServiceProvider.overrideWithValue(steamService),
      modVersionRepositoryProvider.overrideWithValue(versionRepo),
      projectRepositoryProvider.overrideWithValue(projectRepo),
      gameInstallationRepositoryProvider.overrideWithValue(gameRepo),
      modUpdateAnalysisServiceProvider.overrideWithValue(analysisService),
      modUpdateAnalysisCacheRepositoryProvider.overrideWithValue(cacheRepo),
      loggingServiceProvider.overrideWithValue(FakeLogger()),
    ]);
    addTearDown(container.dispose);
    addTearDown(() => downloadDir.delete(recursive: true));
  });

  Future<void> runUpdate() async {
    // The provider is autoDispose: keep it alive for the whole update, like
    // the dialog watching it in production. Without a listener the notifier
    // is disposed mid-update and every ref.read/state write short-circuits.
    final subscription = container.listen(modUpdateQueueProvider, (_, _) {});
    addTearDown(subscription.close);
    final notifier = container.read(modUpdateQueueProvider.notifier);
    notifier.addToQueue(project);
    await notifier.startUpdates();
  }

  group('ModUpdateQueue update pipeline', () {
    test(
        'runs real change detection on the downloaded pack and persists a '
        'ModVersion with the real change counts', () async {
      // The downloaded mod directory contains one .pack file.
      final packFile = File(p.join(downloadDir.path, 'cool_mod.pack'));
      await packFile.writeAsString('PFH5 fake pack content');

      const analysis = ModUpdateAnalysis(
        newUnitsCount: 3,
        removedUnitsCount: 1,
        modifiedUnitsCount: 2,
        totalPackUnits: 50,
        totalProjectUnits: 48,
      );
      when(() => analysisService.analyzeChanges(
            projectId: projectId,
            packFilePath: any(named: 'packFilePath'),
          )).thenAnswer((_) async => const Ok(analysis));
      when(() => analysisService.addNewUnits(
            projectId: any(named: 'projectId'),
            analysis: any(named: 'analysis'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => const Ok(3));
      when(() => analysisService.applyModifiedSourceTexts(
            projectId: any(named: 'projectId'),
            analysis: any(named: 'analysis'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => const Ok(ModUpdateApplyResult(
            sourceTextsUpdated: 2,
            translationsReset: 2,
          )));
      when(() => analysisService.markRemovedUnitsObsolete(
            projectId: any(named: 'projectId'),
            analysis: any(named: 'analysis'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => const Ok(1));

      await runUpdate();

      // The real analysis pipeline ran against the downloaded .pack file.
      final captured = verify(() => analysisService.analyzeChanges(
            projectId: projectId,
            packFilePath: captureAny(named: 'packFilePath'),
          )).captured;
      expect(captured.single, packFile.path,
          reason: 'change detection must analyze the downloaded pack');

      // The persisted ModVersion carries the REAL change counts, not 0/0/0.
      final inserted = verify(() => versionRepo.insert(captureAny()))
          .captured
          .cast<ModVersion>();
      expect(inserted, hasLength(1));
      expect(inserted.single.unitsAdded, 3);
      expect(inserted.single.unitsModified, 2);
      expect(inserted.single.unitsDeleted, 1);

      final state = container.read(modUpdateQueueProvider);
      expect(state[projectId]!.status, ModUpdateStatus.completed);
      expect(state[projectId]!.newVersion, isNotNull);
    });

    test('fails (not "completed") when the download contains no .pack file',
        () async {
      // Empty download dir — nothing to analyze. Reporting success here would
      // be the old placeholder behaviour (success with nothing applied).
      await runUpdate();

      final state = container.read(modUpdateQueueProvider);
      expect(state[projectId]!.status, ModUpdateStatus.failed,
          reason: 'no pack file → the update cannot have been applied');
      verifyNever(() => versionRepo.insert(any()));
    });
  });

  group('ModUpdateQueue background continuation (Hide mid-download)', () {
    // The dialog's 'Hide' button pops the ONLY watcher of this autoDispose
    // notifier while updates run. startUpdates must hold a keep-alive link so
    // the remaining queued mods still update in the background; without it the
    // notifier is disposed mid-loop and the run dies with an unhandled
    // UnmountedRefException, silently abandoning every remaining mod.
    test(
        'remaining queued mods still update after the last listener is '
        'removed mid-download', () async {
      final packFile = File(p.join(downloadDir.path, 'cool_mod.pack'));
      await packFile.writeAsString('PFH5 fake pack content');

      const project2Id = 'proj-2';
      final project2 = Project(
        id: project2Id,
        name: 'Second mod',
        gameInstallationId: 'gi-1',
        modSteamId: '987654321',
        sourceLanguageCode: 'en',
        createdAt: 0,
        updatedAt: 0,
      );
      when(() => projectRepo.getById(project2Id))
          .thenAnswer((_) async => Ok(project2));

      const analysis = ModUpdateAnalysis(
        newUnitsCount: 1,
        removedUnitsCount: 0,
        modifiedUnitsCount: 0,
        totalPackUnits: 10,
        totalProjectUnits: 9,
      );
      when(() => analysisService.analyzeChanges(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
          )).thenAnswer((_) async => const Ok(analysis));
      when(() => analysisService.addNewUnits(
            projectId: any(named: 'projectId'),
            analysis: any(named: 'analysis'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => const Ok(1));
      when(() => analysisService.applyModifiedSourceTexts(
            projectId: any(named: 'projectId'),
            analysis: any(named: 'analysis'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => const Ok(ModUpdateApplyResult(
            sourceTextsUpdated: 0,
            translationsReset: 0,
          )));
      when(() => analysisService.markRemovedUnitsObsolete(
            projectId: any(named: 'projectId'),
            analysis: any(named: 'analysis'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => const Ok(0));

      // Hold the first download until the test has removed the listener, so
      // the dispose happens while mod #1 is mid-download.
      final firstDownloadStarted = Completer<void>();
      final releaseFirstDownload = Completer<void>();
      var downloadCalls = 0;
      when(() => steamService.downloadMod(
            workshopId: any(named: 'workshopId'),
            appId: any(named: 'appId'),
            forceUpdate: any(named: 'forceUpdate'),
          )).thenAnswer((invocation) async {
        downloadCalls++;
        if (downloadCalls == 1) {
          firstDownloadStarted.complete();
          await releaseFirstDownload.future;
        }
        return Ok(SteamCmdDownloadResult(
          workshopId:
              invocation.namedArguments[#workshopId] as String,
          appId: 1142710,
          downloadPath: downloadDir.path,
          sizeBytes: 1024,
          durationMs: 10,
          timestamp: DateTime(2026, 6, 9),
          wasUpdate: true,
        ));
      });

      // The dialog watching the provider.
      final subscription = container.listen(modUpdateQueueProvider, (_, _) {});
      final notifier = container.read(modUpdateQueueProvider.notifier);
      notifier.addMultipleToQueue([project, project2]);

      // Fire-and-forget, exactly like the production call site
      // (whats_new_dialog). Captured here only to assert it doesn't throw.
      final updates = notifier.startUpdates();

      await firstDownloadStarted.future;

      // User presses 'Hide': the dialog pops, removing the last listener.
      subscription.close();
      // Flush the autoDispose scheduler so the disposal (if any) happens now.
      await container.pump();

      releaseFirstDownload.complete();

      // Must complete without an UnmountedRefException.
      await updates;

      expect(downloadCalls, 2,
          reason: 'the second queued mod must still download in background');
      final inserted = verify(() => versionRepo.insert(captureAny()))
          .captured
          .cast<ModVersion>();
      expect(
        inserted.map((v) => v.projectId),
        containsAll([projectId, project2Id]),
        reason: 'both mods must persist their new version despite Hide',
      );
    });
  });
}
