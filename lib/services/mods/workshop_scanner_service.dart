import 'dart:async';
import 'dart:io';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/models/domain/mod_scan_result.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/repositories/mod_scan_cache_repository.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/mods/mod_update_analysis_service.dart';
import 'package:twmt/services/mods/utils/workshop_mod_processor.dart';
import 'package:twmt/services/mods/pack_file_scanner.dart';
import 'package:twmt/services/mods/detected_mod_builder.dart';
import 'package:twmt/services/mods/project_analysis_handler.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';
import 'package:twmt/i18n/strings.g.dart';

/// Service for scanning Steam Workshop folders and discovering mods.
///
/// Orchestrates the mod scanning process:
/// 1. Validates game installation and Workshop path
/// 2. Scans Workshop directories for pack files with localization content
/// 3. Fetches metadata from Steam Workshop API
/// 4. Analyzes changes for imported projects
/// 5. Returns list of detected mods with their status
class WorkshopScannerService {
  final ProjectRepository _projectRepository;
  final GameInstallationRepository _gameInstallationRepository;
  final WorkshopModRepository _workshopModRepository;
  final WorkshopModProcessor _workshopModProcessor;
  final PackFileScanner _packFileScanner;
  final DetectedModBuilder _detectedModBuilder;
  final IRpfmService _rpfmService;
  final ILoggingService _logger;

  /// Stream controller for scan progress logs
  final StreamController<ScanLogMessage> _scanLogController =
      StreamController<ScanLogMessage>.broadcast();

  /// Stream of scan log messages for UI consumption
  Stream<ScanLogMessage> get scanLogStream => _scanLogController.stream;

  /// Emit a log message to the scan log stream
  void _emitLog(String message, [ScanLogLevel level = ScanLogLevel.info]) {
    if (!_scanLogController.isClosed) {
      _scanLogController.add(ScanLogMessage(message: message, level: level));
    }
  }

  /// Dispose resources
  void dispose() {
    _scanLogController.close();
  }

  WorkshopScannerService({
    required ProjectRepository projectRepository,
    required GameInstallationRepository gameInstallationRepository,
    required WorkshopModRepository workshopModRepository,
    required ModScanCacheRepository modScanCacheRepository,
    required ModUpdateAnalysisCacheRepository analysisCacheRepository,
    required IWorkshopApiService workshopApiService,
    required IRpfmService rpfmService,
    required ModUpdateAnalysisService modUpdateAnalysisService,
    ILoggingService? logger,
  })  : _projectRepository = projectRepository,
        _gameInstallationRepository = gameInstallationRepository,
        _workshopModRepository = workshopModRepository,
        _rpfmService = rpfmService,
        _workshopModProcessor = WorkshopModProcessor(
          workshopModRepository: workshopModRepository,
          workshopApiService: workshopApiService,
          logger: logger,
        ),
        _packFileScanner = PackFileScanner(
          modScanCacheRepository: modScanCacheRepository,
          rpfmService: rpfmService,
          logger: logger,
        ),
        _detectedModBuilder = DetectedModBuilder(
          workshopModRepository: workshopModRepository,
          analysisCacheRepository: analysisCacheRepository,
          projectRepository: projectRepository,
          analysisHandler: ProjectAnalysisHandler(
            projectRepository: projectRepository,
            analysisCacheRepository: analysisCacheRepository,
            modUpdateAnalysisService: modUpdateAnalysisService,
            logger: logger,
          ),
          logger: logger,
        ),
        _logger = logger ?? ServiceLocator.get<ILoggingService>();

  /// Scan Workshop folder for a game and return detected mods without creating projects.
  ///
  /// Returns [ModScanResult] containing the list of mods and whether translation
  /// statistics changed (units added or statuses reset to pending).
  Future<Result<ModScanResult, ServiceException>> scanMods(
    String gameCode,
  ) async {
    try {
      _logger.info('Scanning Workshop folder for game: $gameCode');
      _emitLog(t.mods.scanLogs.startingScan(gameCode: gameCode));

      // Fail fast if RPFM-CLI is missing or has an incompatible version: a
      // scan without RPFM cannot detect localization files and would silently
      // return zero mods, leaving the user without an explanation.
      final rpfmAvailable = await _rpfmService.isRpfmAvailable();
      if (!rpfmAvailable) {
        _logger.error(
            'RPFM-CLI is not available. Update its path in Settings → '
            'Folders → RPFM, or download it from there.');
        _emitLog(t.mods.scanLogs.rpfmNotAvailable, ScanLogLevel.error);
        return const Err(RpfmNotFoundException(
          'RPFM-CLI is not available. Please update the path in Settings.',
        ));
      }

      // Get game installation from database
      final gameInstallationResult =
          await _gameInstallationRepository.getByGameCode(gameCode);

      if (gameInstallationResult is Err) {
        final error = gameInstallationResult.error;
        _logger.error(
            'Game installation not found for $gameCode: ${error.message}');
        _emitLog(
            t.mods.scanLogs.gameInstallationNotFound(message: error.message),
            ScanLogLevel.error);
        throw ServiceException(
          'Game installation not found: ${error.message}',
          error: error,
        );
      }

      final gameInstallation = gameInstallationResult.value;

      // Check if Workshop path is configured
      if (!gameInstallation.hasWorkshopPath) {
        _logger.debug('No Workshop path configured for $gameCode');
        _emitLog(t.mods.scanLogs.noWorkshopPath, ScanLogLevel.warning);
        return const Ok(ModScanResult.empty);
      }

      final workshopPath = gameInstallation.steamWorkshopPath!;
      final gameWorkshopDir = Directory(workshopPath);
      _emitLog(t.mods.scanLogs.scanningPath(path: workshopPath));

      if (!await gameWorkshopDir.exists()) {
        _logger.debug('Workshop folder does not exist: $workshopPath');
        _emitLog(t.mods.scanLogs.workshopFolderMissing, ScanLogLevel.warning);
        return const Ok(ModScanResult.empty);
      }

      // Get existing projects to mark which mods are already imported
      _emitLog(t.mods.scanLogs.loadingProjects);
      final existingWorkshopIds = await _getExistingWorkshopIds();

      // Scan Workshop folder for mod directories
      _emitLog(t.mods.scanLogs.listingDirectories);
      final modDirs = await gameWorkshopDir
          .list()
          .where((entity) => entity is Directory)
          .cast<Directory>()
          .toList();

      _logger.info('Found ${modDirs.length} Workshop items');
      _emitLog(t.mods.scanLogs.foundItems(count: modDirs.length));

      // Phase 1: Collect pack file info and check cache
      _emitLog(t.mods.scanLogs.scanningPackFiles);
      final modDataList = await _packFileScanner.collectModData(
        modDirs,
        emitLog: _emitLog,
      );
      _emitLog(t.mods.scanLogs.foundLocalizedMods(count: modDataList.length));

      // Phase 1.5: Get cached workshop mods to track previous timeUpdated values
      final workshopIds = modDataList.map((m) => m.workshopId).toList();
      final cachedModsMap = await _getCachedWorkshopMods(workshopIds);

      // Phase 1.6: Get hidden workshop IDs
      final hiddenWorkshopIds = await _getHiddenWorkshopIds();

      // Phase 2: Batch fetch Steam Workshop data (will update cache)
      _emitLog(t.mods.scanLogs.fetchingMetadata);
      final workshopModsMap = await _fetchWorkshopData(
        workshopIds,
        gameInstallation.steamAppId,
      );
      _emitLog(
          t.mods.scanLogs.retrievedMetadata(count: workshopModsMap.length));

      // Phase 3: Build DetectedMod list with cached timestamps for comparison
      _emitLog(t.mods.scanLogs.analyzingUpdates);
      final buildResult = await _detectedModBuilder.buildDetectedMods(
        modDataList: modDataList,
        workshopModsMap: workshopModsMap,
        cachedModsMap: cachedModsMap,
        existingWorkshopIds: existingWorkshopIds,
        hiddenWorkshopIds: hiddenWorkshopIds,
        emitLog: _emitLog,
      );

      _logger.info('Scan complete: ${buildResult.mods.length} translatable mods');
      _emitLog(t.mods.scanLogs.scanComplete(count: buildResult.mods.length));
      if (buildResult.translationStatsChanged) {
        _logger.info('Translation statistics changed during scan');
        _emitLog(t.mods.scanLogs.statsUpdated);
      }
      return Ok(buildResult);
    } catch (e, stackTrace) {
      _logger.error('Failed to scan Workshop folder: $e', stackTrace);
      _emitLog(t.mods.scanLogs.scanFailed(error: '$e'), ScanLogLevel.error);
      return Err(ServiceException(
        'Failed to scan Workshop folder: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Get cached workshop mods from database before fetching new data.
  /// This allows us to compare previous timestamps with new ones.
  Future<Map<String, WorkshopMod>> _getCachedWorkshopMods(
    List<String> workshopIds,
  ) async {
    if (workshopIds.isEmpty) {
      return {};
    }

    final result = await _workshopModRepository.getByWorkshopIds(workshopIds);
    if (result is Err) {
      _logger
          .warning('Failed to get cached workshop mods: ${result.error.message}');
      return {};
    }

    final cachedMods = result.value;
    return {for (final mod in cachedMods) mod.workshopId: mod};
  }

  /// Get set of hidden workshop IDs.
  Future<Set<String>> _getHiddenWorkshopIds() async {
    final result = await _workshopModRepository.getHiddenWorkshopIds();
    if (result is Err) {
      _logger
          .warning('Failed to get hidden workshop IDs: ${result.error.message}');
      return {};
    }
    return result.value;
  }

  /// Get map of existing Steam Workshop IDs to projects.
  Future<Map<String, Project>> _getExistingWorkshopIds() async {
    final existingProjectsResult = await _projectRepository.getAll();
    final existingProjects = existingProjectsResult is Ok
        ? existingProjectsResult.value
        : <Project>[];

    final existingWorkshopIds = <String, Project>{};
    for (final project in existingProjects) {
      if (project.modSteamId != null && project.modSteamId!.isNotEmpty) {
        existingWorkshopIds[project.modSteamId!] = project;
      }
    }
    return existingWorkshopIds;
  }

  /// Fetch Workshop mod data from Steam API.
  Future<Map<String, WorkshopMod>> _fetchWorkshopData(
    List<String> workshopIds,
    String? steamAppId,
  ) async {
    if (steamAppId == null || workshopIds.isEmpty) {
      return {};
    }

    final appId = int.tryParse(steamAppId);
    if (appId == null) {
      return {};
    }

    return _workshopModProcessor.fetchAndProcessMods(
      workshopIds: workshopIds,
      appId: appId,
    );
  }
}
