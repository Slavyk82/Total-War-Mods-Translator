import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/repositories/export_history_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/export_orchestrator_service.dart';
import 'package:twmt/services/file/file_import_export_service.dart';
import 'package:twmt/services/file/i_loc_file_service.dart';
import 'package:twmt/services/file/i_pack_image_generator_service.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockLocFileService extends Mock implements ILocFileService {}

class _MockRpfmService extends Mock implements IRpfmService {}

class _MockProjectRepository extends Mock implements ProjectRepository {}

class _MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

class _MockExportHistoryRepository extends Mock
    implements ExportHistoryRepository {}

class _MockSettingsService extends Mock implements SettingsService {}

class _FakeFileImportExportService extends Fake
    implements FileImportExportService {}

class _FakeTmxService extends Fake implements TmxService {}

class _FakePackImageGenerator extends Fake
    implements IPackImageGeneratorService {}

class _FakeProjectLanguageRepository extends Fake
    implements ProjectLanguageRepository {}

class _FakeTranslationUnitRepository extends Fake
    implements TranslationUnitRepository {}

class _FakeTranslationVersionRepository extends Fake
    implements TranslationVersionRepository {}

void main() {
  const projectId = 'proj-1';
  const gameInstallationId = 'game-1';
  const previousPackContent = 'previous good pack';
  const newPackContent = 'new pack content';

  late Directory tempRoot;
  late String gameDataPath;
  late String finalPackPath;
  late String sourceTsvPath;

  late _MockLocFileService locFileService;
  late _MockRpfmService rpfmService;
  late _MockProjectRepository projectRepository;
  late _MockGameInstallationRepository gameInstallationRepository;
  late _MockExportHistoryRepository exportHistoryRepository;
  late _MockSettingsService settingsService;
  late ExportOrchestratorService orchestrator;

  setUpAll(() {
    registerFallbackValue(ExportHistory(
      id: 'fallback',
      projectId: 'fallback',
      languages: '["fr"]',
      format: ExportFormat.pack,
      validatedOnly: false,
      outputPath: 'fallback',
      fileSize: 0,
      entryCount: 0,
      exportedAt: 0,
    ));
  });

  setUp(() async {
    tempRoot =
        await Directory.systemTemp.createTemp('twmt_export_orch_test_');

    final installationPath = path.join(tempRoot.path, 'install');
    gameDataPath = path.join(installationPath, 'data');
    await Directory(gameDataPath).create(recursive: true);

    // Pack prefix '!!!', language 'fr', source mod 'coolmod.pack'
    // -> '!!!_fr_twmt_coolmod.pack' (see PackExportUtils.buildPackFileName).
    finalPackPath = path.join(gameDataPath, '!!!_fr_twmt_coolmod.pack');

    // Real TSV file the orchestrator copies into its input temp directory.
    sourceTsvPath = path.join(tempRoot.path, 'src', 'generated.tsv');
    final sourceTsv = File(sourceTsvPath);
    await sourceTsv.create(recursive: true);
    await sourceTsv.writeAsString('key\ttext\n#meta\nfoo\tbar\n');

    locFileService = _MockLocFileService();
    rpfmService = _MockRpfmService();
    projectRepository = _MockProjectRepository();
    gameInstallationRepository = _MockGameInstallationRepository();
    exportHistoryRepository = _MockExportHistoryRepository();
    settingsService = _MockSettingsService();

    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<SettingsService>(settingsService);

    when(() => settingsService.getPackPrefix()).thenAnswer((_) async => '!!!');

    when(() => projectRepository.getById(projectId)).thenAnswer(
      (_) async => Ok(Project(
        id: projectId,
        name: 'Cool Mod Translation',
        gameInstallationId: gameInstallationId,
        sourceFilePath: path.join('C:', 'mods', 'coolmod.pack'),
        createdAt: 0,
        updatedAt: 0,
      )),
    );

    when(() => gameInstallationRepository.getById(gameInstallationId))
        .thenAnswer(
      (_) async => Ok(GameInstallation(
        id: gameInstallationId,
        gameCode: 'wh3',
        gameName: 'Total War: WARHAMMER III',
        installationPath: installationPath,
        createdAt: 0,
        updatedAt: 0,
      )),
    );

    when(() => exportHistoryRepository.ensureTableExists())
        .thenAnswer((_) async {});
    when(() => exportHistoryRepository.insert(any())).thenAnswer(
      (inv) async => Ok(inv.positionalArguments.first as ExportHistory),
    );

    when(() => locFileService.generateLocFilesGroupedBySource(
          projectId: any(named: 'projectId'),
          languageCode: any(named: 'languageCode'),
          validatedOnly: any(named: 'validatedOnly'),
          prefix: any(named: 'prefix'),
        )).thenAnswer(
      (_) async => Ok([
        GeneratedLocFile(
          tsvPath: sourceTsvPath,
          internalPath: 'text/db/coolmod__.loc',
        ),
      ]),
    );

    when(() => locFileService.countExportableTranslations(
          projectId: any(named: 'projectId'),
          languageCode: any(named: 'languageCode'),
          validatedOnly: any(named: 'validatedOnly'),
        )).thenAnswer((_) async => const Ok(3));

    orchestrator = ExportOrchestratorService(
      locFileService: locFileService,
      rpfmService: rpfmService,
      fileImportExportService: _FakeFileImportExportService(),
      tmxService: _FakeTmxService(),
      packImageGenerator: _FakePackImageGenerator(),
      exportHistoryRepository: exportHistoryRepository,
      gameInstallationRepository: gameInstallationRepository,
      projectRepository: projectRepository,
      projectLanguageRepository: _FakeProjectLanguageRepository(),
      translationUnitRepository: _FakeTranslationUnitRepository(),
      translationVersionRepository: _FakeTranslationVersionRepository(),
      logger: FakeLogger(),
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
    try {
      await tempRoot.delete(recursive: true);
    } catch (_) {}
  });

  /// Stubs IRpfmService.createPack with [body] receiving the output pack
  /// path the orchestrator asked for.
  void stubCreatePack(
    Future<Result<String, RpfmServiceException>> Function(String outputPath)
        body,
  ) {
    when(() => rpfmService.createPack(
          inputDirectory: any(named: 'inputDirectory'),
          outputPackPath: any(named: 'outputPackPath'),
          languageCode: any(named: 'languageCode'),
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((inv) {
      final outputPath = inv.namedArguments[#outputPackPath] as String;
      return body(outputPath);
    });
  }

  /// Simulates the previous good pack still sitting in the game data folder.
  Future<File> seedPreviousGoodPack() async {
    final file = File(finalPackPath);
    await file.writeAsString(previousPackContent, flush: true);
    return file;
  }

  List<String> dataDirFileNames() => Directory(gameDataPath)
      .listSync()
      .whereType<File>()
      .map((f) => path.basename(f.path))
      .toList();

  Future<Result<ExportResult, dynamic>> runExport() {
    return orchestrator.exportToPack(
      projectId: projectId,
      languageCodes: const ['fr'],
      outputPath: 'exports', // Dummy, mirrors the real callers.
      validatedOnly: false,
      generatePackImage: false,
    );
  }

  group('exportToPack atomic pack replacement', () {
    test(
        'success: final pack is at the destination, no temp file is left '
        'behind, and ExportResult.outputPath is the final path', () async {
      await seedPreviousGoodPack();

      String? requestedOutputPath;
      stubCreatePack((outputPath) async {
        requestedOutputPath = outputPath;
        await File(outputPath).writeAsString(newPackContent, flush: true);
        return Ok(outputPath);
      });

      final result = await runExport();

      expect(result.isOk, isTrue, reason: 'Unexpected error: $result');
      expect(result.unwrap().outputPath, finalPackPath,
          reason: 'Callers must keep seeing the final pack path');
      expect(await File(finalPackPath).readAsString(), newPackContent,
          reason: 'The new pack must replace the previous one on success');
      expect(dataDirFileNames(), [path.basename(finalPackPath)],
          reason: 'No temporary pack file may remain after a successful '
              'export');

      expect(requestedOutputPath, isNotNull);
      expect(requestedOutputPath, isNot(finalPackPath),
          reason: 'createPack must build at a temporary path, never directly '
              'at the destination');
      expect(path.dirname(requestedOutputPath!), gameDataPath,
          reason: 'The temp pack must be built next to the destination so '
              'the final rename stays on the same volume (atomic)');
    });

    test(
        'failure during pack creation: the previous good pack at the '
        'destination is untouched and no temp file is left behind', () async {
      final previousPack = await seedPreviousGoodPack();

      // Faithful emulation of RpfmPackOperationsMixin.createPack on a
      // 'pack add' failure: 'pack create' clobbers whatever file exists at
      // the requested output path, then the cleanup deletes the partial
      // pack before the Err is returned.
      stubCreatePack((outputPath) async {
        final partial = File(outputPath);
        await partial.writeAsString('partial pack', flush: true);
        await partial.delete();
        return Err(const RpfmPackingException(
          'Failed to add TSV file to pack: schema mismatch',
        ));
      });

      final result = await runExport();

      expect(result.isErr, isTrue);
      expect(previousPack.existsSync(), isTrue,
          reason: 'A failed export must never destroy the previous good '
              'pack already deployed in the game data directory');
      expect(await previousPack.readAsString(), previousPackContent);
      expect(dataDirFileNames(), [path.basename(finalPackPath)],
          reason: 'No temporary pack file may remain after a failed export');
    });

    test(
        'failure where createPack leaves its partial output behind: the '
        'orchestrator deletes the temp pack and the previous good pack '
        'survives', () async {
      final previousPack = await seedPreviousGoodPack();

      // Degenerate failure mode (e.g. cleanup itself failed inside RPFM):
      // the partial file is left at the requested output path.
      stubCreatePack((outputPath) async {
        await File(outputPath).writeAsString('partial pack', flush: true);
        return Err(const RpfmPackingException('rpfm crashed'));
      });

      final result = await runExport();

      expect(result.isErr, isTrue);
      expect(await previousPack.readAsString(), previousPackContent,
          reason: 'The destination must keep the previous good pack');
      expect(dataDirFileNames(), [path.basename(finalPackPath)],
          reason: 'The orchestrator must clean up the temp pack even when '
              'createPack failed to remove its own partial output');
    });
  });
}
