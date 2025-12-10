import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/models/domain/mod_scan_cache.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/mod_update_analysis_cache.dart';
import 'package:twmt/models/domain/mod_update_status.dart';
import 'package:twmt/models/domain/mod_scan_result.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/repositories/mod_scan_cache_repository.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/utils/rpfm_output_parser.dart';
import 'package:twmt/services/mods/mod_update_analysis_service.dart';
import 'package:twmt/services/mods/utils/workshop_scan_models.dart';
import 'package:twmt/services/mods/utils/mod_image_finder.dart';
import 'package:twmt/services/mods/utils/workshop_mod_processor.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';

/// Result of analyzing a project for changes.
class _AnalysisResult {
  final ModUpdateAnalysis? analysis;
  final bool statsChanged;

  const _AnalysisResult({this.analysis, this.statsChanged = false});
}

/// Service for scanning Steam Workshop folders and discovering mods.
class WorkshopScannerService {
  final ProjectRepository _projectRepository;
  final GameInstallationRepository _gameInstallationRepository;
  final WorkshopModRepository _workshopModRepository;
  final ModScanCacheRepository _modScanCacheRepository;
  final ModUpdateAnalysisCacheRepository _analysisCacheRepository;
  final IRpfmService _rpfmService;
  final ModUpdateAnalysisService _modUpdateAnalysisService;
  final WorkshopModProcessor _workshopModProcessor;
  final LoggingService _logger = LoggingService.instance;
  final Uuid _uuid = const Uuid();

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
  })  : _projectRepository = projectRepository,
        _gameInstallationRepository = gameInstallationRepository,
        _workshopModRepository = workshopModRepository,
        _modScanCacheRepository = modScanCacheRepository,
        _analysisCacheRepository = analysisCacheRepository,
        _rpfmService = rpfmService,
        _modUpdateAnalysisService = modUpdateAnalysisService,
        _workshopModProcessor = WorkshopModProcessor(
          workshopModRepository: workshopModRepository,
          workshopApiService: workshopApiService,
        );

  /// Scan Workshop folder for a game and return detected mods without creating projects.
  ///
  /// Returns [ModScanResult] containing the list of mods and whether translation
  /// statistics changed (units added or statuses reset to pending).
  Future<Result<ModScanResult, ServiceException>> scanMods(
    String gameCode,
  ) async {
    try {
      _logger.info('Scanning Workshop folder for game: $gameCode');
      _emitLog('Starting scan for game: $gameCode');

      // Get game installation from database
      final gameInstallationResult =
          await _gameInstallationRepository.getByGameCode(gameCode);

      if (gameInstallationResult is Err) {
        final error = gameInstallationResult.error;
        _logger.error('Game installation not found for $gameCode: ${error.message}');
        _emitLog('Game installation not found: ${error.message}', ScanLogLevel.error);
        throw ServiceException(
          'Game installation not found: ${error.message}',
          error: error,
        );
      }

      final gameInstallation = gameInstallationResult.value;

      // Check if Workshop path is configured
      if (!gameInstallation.hasWorkshopPath) {
        _logger.debug('No Workshop path configured for $gameCode');
        _emitLog('No Workshop path configured', ScanLogLevel.warning);
        return const Ok(ModScanResult.empty);
      }

      final workshopPath = gameInstallation.steamWorkshopPath!;
      final gameWorkshopDir = Directory(workshopPath);
      _emitLog('Scanning: $workshopPath');

      if (!await gameWorkshopDir.exists()) {
        _logger.debug('Workshop folder does not exist: $workshopPath');
        _emitLog('Workshop folder does not exist', ScanLogLevel.warning);
        return const Ok(ModScanResult.empty);
      }

      // Get existing projects to mark which mods are already imported
      _emitLog('Loading existing projects...');
      final existingWorkshopIds = await _getExistingWorkshopIds();

      // Scan Workshop folder for mod directories
      _emitLog('Listing Workshop directories...');
      final modDirs = await gameWorkshopDir
          .list()
          .where((entity) => entity is Directory)
          .cast<Directory>()
          .toList();

      _logger.info('Found ${modDirs.length} Workshop items');
      _emitLog('Found ${modDirs.length} Workshop items');

      // Phase 1: Collect pack file info and check cache
      _emitLog('Scanning pack files for localization data...');
      final modDataList = await _collectModData(modDirs);
      _emitLog('Found ${modDataList.length} mods with localization files');

      // Phase 1.5: Get cached workshop mods to track previous timeUpdated values
      final workshopIds = modDataList.map((m) => m.workshopId).toList();
      final cachedModsMap = await _getCachedWorkshopMods(workshopIds);
      
      // Phase 1.6: Get hidden workshop IDs
      final hiddenWorkshopIds = await _getHiddenWorkshopIds();

      // Phase 2: Batch fetch Steam Workshop data (will update cache)
      _emitLog('Fetching Steam Workshop metadata...');
      final workshopModsMap = await _fetchWorkshopData(
        modDataList,
        gameInstallation.steamAppId,
      );
      _emitLog('Retrieved data for ${workshopModsMap.length} mods from Steam');

      // Phase 3: Build DetectedMod list with cached timestamps for comparison
      _emitLog('Analyzing mod updates...');
      final buildResult = await _buildDetectedMods(
        modDataList,
        workshopModsMap,
        cachedModsMap,
        existingWorkshopIds,
        hiddenWorkshopIds,
      );

      _logger.info('Scan complete: ${buildResult.mods.length} translatable mods');
      _emitLog('Scan complete: ${buildResult.mods.length} translatable mods');
      if (buildResult.translationStatsChanged) {
        _logger.info('Translation statistics changed during scan');
        _emitLog('Translation statistics updated');
      }
      return Ok(buildResult);
    } catch (e, stackTrace) {
      _logger.error('Failed to scan Workshop folder: $e', stackTrace);
      _emitLog('Scan failed: $e', ScanLogLevel.error);
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
      _logger.warning('Failed to get cached workshop mods: ${result.error.message}');
      return {};
    }

    final cachedMods = result.value;
    return {for (final mod in cachedMods) mod.workshopId: mod};
  }

  /// Get set of hidden workshop IDs.
  Future<Set<String>> _getHiddenWorkshopIds() async {
    final result = await _workshopModRepository.getHiddenWorkshopIds();
    if (result is Err) {
      _logger.warning('Failed to get hidden workshop IDs: ${result.error.message}');
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

  /// Collect local mod data from workshop directories.
  Future<List<ModLocalData>> _collectModData(List<Directory> modDirs) async {
    final rpfmAvailable = await _rpfmService.isRpfmAvailable();
    if (!rpfmAvailable) {
      _logger.warning('RPFM-CLI not available, cannot filter mods by loc files');
    }

    // First pass: collect all valid pack files
    final packFileInfos = await _collectPackFileInfos(modDirs);
    _logger.debug('Found ${packFileInfos.length} pack files to check');

    // Fetch cache entries for all pack files in batch
    final packFilePaths = packFileInfos.map((info) => info.packFile.path).toList();
    final cacheResult = await _modScanCacheRepository.getByPackFilePaths(packFilePaths);
    final cacheMap = cacheResult.isOk
        ? cacheResult.value
        : <String, ModScanCache>{};

    // Second pass: check cache and scan if necessary
    return _processPackFiles(packFileInfos, cacheMap, rpfmAvailable);
  }

  /// Collect pack file information from mod directories.
  Future<List<PackFileInfo>> _collectPackFileInfos(List<Directory> modDirs) async {
    final packFileInfos = <PackFileInfo>[];

    for (final modDir in modDirs) {
      final workshopId = path.basename(modDir.path);

      // Skip if not a valid Workshop ID (numeric)
      if (!_isValidWorkshopId(workshopId)) {
        continue;
      }

      // Look for .pack files in the mod directory
      final packFiles = await modDir
          .list()
          .where((entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.pack'))
          .cast<File>()
          .toList();

      if (packFiles.isEmpty) {
        _logger.debug('No .pack files found in $workshopId, skipping');
        continue;
      }

      // Use the first .pack file found
      final packFile = packFiles.first;
      final packFileName = path.basenameWithoutExtension(packFile.path);

      // Get file last modified time
      final fileStat = await packFile.stat();
      final fileLastModified = fileStat.modified.millisecondsSinceEpoch ~/ 1000;

      packFileInfos.add(PackFileInfo(
        workshopId: workshopId,
        modDir: modDir,
        packFile: packFile,
        packFileName: packFileName,
        fileLastModified: fileLastModified,
      ));
    }

    return packFileInfos;
  }

  /// Process pack files, checking cache and scanning for loc files.
  Future<List<ModLocalData>> _processPackFiles(
    List<PackFileInfo> packFileInfos,
    Map<String, ModScanCache> cacheMap,
    bool rpfmAvailable,
  ) async {
    final modDataList = <ModLocalData>[];
    final cacheUpdates = <ModScanCache>[];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    int cacheHits = 0, cacheMisses = 0, cacheSkipped = 0;
    int processed = 0;
    final total = packFileInfos.length;

    for (final info in packFileInfos) {
      processed++;
      final cacheEntry = cacheMap[info.packFile.path];
      bool hasLocFiles = false;

      // Check if we have a valid cache entry
      if (cacheEntry != null && cacheEntry.isValidFor(info.fileLastModified)) {
        hasLocFiles = cacheEntry.hasLocFiles;
        cacheHits++;

        if (!hasLocFiles) {
          cacheSkipped++;
          _logger.debug('Cache hit (no loc files): ${info.workshopId}');
          continue;
        }
      } else if (rpfmAvailable) {
        // Cache miss or invalidated - need to scan
        cacheMisses++;
        _emitLog('[$processed/$total] Scanning: ${info.packFileName}.pack');
        hasLocFiles = await _scanPackForLocFiles(info);

        // Update cache with scan result
        cacheUpdates.add(ModScanCache(
          id: cacheEntry?.id ?? _uuid.v4(),
          packFilePath: info.packFile.path,
          fileLastModified: info.fileLastModified,
          hasLocFiles: hasLocFiles,
          scannedAt: now,
        ));

        if (!hasLocFiles) {
          continue;
        }
      } else {
        // RPFM not available and no cache - skip
        continue;
      }

      // Find mod image
      final modImagePath = await ModImageFinder.findModImage(info.modDir, info.packFileName);

      modDataList.add(ModLocalData(
        workshopId: info.workshopId,
        packFile: info.packFile,
        packFileName: info.packFileName,
        modImagePath: modImagePath,
        hasLocFiles: hasLocFiles,
        fileLastModified: info.fileLastModified,
      ));
    }

    // Batch update cache entries
    if (cacheUpdates.isNotEmpty) {
      await _modScanCacheRepository.upsertBatch(cacheUpdates);
    }

    _logger.debug('Cache: hits=$cacheHits, misses=$cacheMisses, skipped=$cacheSkipped');
    if (cacheMisses > 0) {
      _emitLog('Cache: $cacheHits hits, $cacheMisses scans, $cacheSkipped skipped');
    }
    return modDataList;
  }

  /// Scan a pack file to check if it contains localization files.
  Future<bool> _scanPackForLocFiles(PackFileInfo info) async {
    final listResult = await _rpfmService.listPackContents(info.packFile.path);
    return listResult.when(
      ok: (files) {
        final locFiles = RpfmOutputParser.filterLocalizationFiles(files);
        final hasLocFiles = locFiles.isNotEmpty;
        if (!hasLocFiles) {
          _logger.debug(
              'No loc files in ${info.workshopId} (${info.packFileName}), skipping');
        }
        return hasLocFiles;
      },
      err: (error) {
        _logger.warning(
            'Failed to list pack contents for ${info.workshopId}: ${error.message}');
        return false;
      },
    );
  }

  /// Fetch Workshop mod data from Steam API.
  Future<Map<String, WorkshopMod>> _fetchWorkshopData(
    List<ModLocalData> modDataList,
    String? steamAppId,
  ) async {
    if (steamAppId == null || modDataList.isEmpty) {
      return {};
    }

    final appId = int.tryParse(steamAppId);
    if (appId == null) {
      return {};
    }

    final workshopIds = modDataList.map((m) => m.workshopId).toList();
    return _workshopModProcessor.fetchAndProcessMods(
      workshopIds: workshopIds,
      appId: appId,
    );
  }

  /// Build list of DetectedMod from collected data.
  ///
  /// [cachedModsMap] contains the workshop mods from database BEFORE the API fetch,
  /// allowing us to detect when Steam has a newer version by comparing timestamps.
  ///
  /// Returns [ModScanResult] with the mods list and whether translation stats changed.
  Future<ModScanResult> _buildDetectedMods(
    List<ModLocalData> modDataList,
    Map<String, WorkshopMod> workshopModsMap,
    Map<String, WorkshopMod> cachedModsMap,
    Map<String, Project> existingWorkshopIds,
    Set<String> hiddenWorkshopIds,
  ) async {
    final detectedMods = <DetectedMod>[];
    bool translationStatsChanged = false;

    for (final modData in modDataList) {
      final workshopId = modData.workshopId;
      String modTitle = _cleanModName(modData.packFileName);
      ProjectMetadata? metadata;
      int? timeUpdated;
      int? cachedTimeUpdated;

      // Get cached mod to compare timestamps
      final cachedMod = cachedModsMap[workshopId];
      cachedTimeUpdated = cachedMod?.timeUpdated;

      // Try to get Workshop data from batch fetch
      final workshopMod = workshopModsMap[workshopId];

      if (workshopMod != null) {
        modTitle = workshopMod.title;
        timeUpdated = workshopMod.timeUpdated;
        metadata = ProjectMetadata(
          modTitle: workshopMod.title,
          modImageUrl: modData.modImagePath,
          modSubscribers: workshopMod.subscriptions,
        );
      } else {
        // Fall back to database cache if batch fetch failed
        metadata = await _getMetadataFromCache(workshopId, modData, modTitle);
        if (metadata != null) {
          modTitle = metadata.modTitle ?? modTitle;
        }
        // Use cached timeUpdated if API fetch failed
        timeUpdated = cachedTimeUpdated;
      }

      // Check if mod is already imported
      final existingProject = existingWorkshopIds[workshopId];

      // Determine if we should analyze changes:
      // Only analyze if:
      // 1. Project is imported
      // 2. Local file is up to date (not needing download)
      // 3. Steam has a NEW update (timestamp differs from cache)
      //    OR analysis cache is missing/invalidated (file was re-downloaded)
      final localFileUpToDate = timeUpdated == null ||
          modData.fileLastModified >= timeUpdated;
      final hasNewSteamUpdate = cachedTimeUpdated != null &&
          timeUpdated != null &&
          timeUpdated != cachedTimeUpdated;

      // Check if we have a valid cached analysis with changes
      // This is used to continue showing changes even after timeUpdated is synced
      ModUpdateAnalysisCache? validCachedAnalysis;
      bool analysisCacheInvalid = false;

      if (existingProject != null && localFileUpToDate) {
        final cacheResult = await _analysisCacheRepository.getByProjectAndPath(
          existingProject.id,
          modData.packFile.path,
        );
        if (cacheResult.isOk) {
          final cachedAnalysis = cacheResult.value;
          if (cachedAnalysis != null &&
              cachedAnalysis.isValidFor(modData.fileLastModified)) {
            validCachedAnalysis = cachedAnalysis;
          } else {
            analysisCacheInvalid = true;
          }
        } else {
          analysisCacheInvalid = true;
        }
      }

      ModUpdateAnalysis? updateAnalysis;

      // If we have a new Steam update or cache is invalid, perform fresh analysis
      if (existingProject != null && localFileUpToDate && (hasNewSteamUpdate || analysisCacheInvalid)) {
        if (hasNewSteamUpdate) {
          _logger.info('New Steam update detected for $workshopId, analyzing changes...');
          _emitLog('Update detected: $modTitle - analyzing changes...');
        } else {
          _logger.info('Analysis cache invalidated for $workshopId (file re-downloaded), analyzing changes...');
          _emitLog('Re-analyzing: $modTitle');
        }
        final analysisResult = await _analyzeProjectChanges(
          existingProject.id,
          modData.packFile.path,
          workshopId,
          modData.fileLastModified,
        );
        updateAnalysis = analysisResult.analysis;
        if (analysisResult.statsChanged) {
          translationStatsChanged = true;
        }
        if (updateAnalysis != null && updateAnalysis.hasChanges) {
          _emitLog('  → ${updateAnalysis.newUnitsCount} new, ${updateAnalysis.modifiedUnitsCount} modified, ${updateAnalysis.removedUnitsCount} removed');
        }

        // Only sync timeUpdated AFTER analysis if there are NO changes
        // If there are changes, we wait until they are dismissed by the user
        if (updateAnalysis == null || !updateAnalysis.hasChanges) {
          if (hasNewSteamUpdate) {
            _logger.debug('Syncing timeUpdated for $workshopId (no changes): $cachedTimeUpdated -> $timeUpdated');
            await _workshopModRepository.updateTimeUpdated(workshopId, timeUpdated);
          }
        }
      } else if (validCachedAnalysis != null && validCachedAnalysis.hasChanges) {
        // Use cached analysis that still has unprocessed changes
        // This allows showing changes even after timeUpdated was synced
        _logger.debug('Using cached analysis with changes for $workshopId');
        updateAnalysis = validCachedAnalysis.toAnalysis();
      } else if (localFileUpToDate && hasNewSteamUpdate) {
        // No project imported but timestamps differ - just sync the timestamp
        _logger.debug('Syncing timeUpdated for $workshopId (no project): $cachedTimeUpdated -> $timeUpdated');
        await _workshopModRepository.updateTimeUpdated(workshopId, timeUpdated);
      }

      // Log timestamps for debugging when there are changes or download needed
      final mod = DetectedMod(
        workshopId: workshopId,
        name: modTitle,
        packFilePath: modData.packFile.path,
        imageUrl: modData.modImagePath ?? metadata?.modImageUrl,
        metadata: metadata,
        isAlreadyImported: existingProject != null,
        existingProjectId: existingProject?.id,
        hasLocFiles: modData.hasLocFiles,
        timeUpdated: timeUpdated,
        cachedTimeUpdated: cachedTimeUpdated,
        localFileLastModified: modData.fileLastModified,
        updateAnalysis: updateAnalysis,
        isHidden: hiddenWorkshopIds.contains(workshopId),
      );

      if (mod.updateStatus.requiresAction) {
        _logger.info(
          'Mod $workshopId ($modTitle) status=${mod.updateStatus.name}: '
          'steamTime=${timeUpdated != null ? DateTime.fromMillisecondsSinceEpoch(timeUpdated * 1000).toIso8601String() : "null"}, '
          'localTime=${DateTime.fromMillisecondsSinceEpoch(modData.fileLastModified * 1000).toIso8601String()}, '
          'cachedTime=${cachedTimeUpdated != null ? DateTime.fromMillisecondsSinceEpoch(cachedTimeUpdated * 1000).toIso8601String() : "null"}',
        );
      }

      detectedMods.add(mod);
    }

    return ModScanResult(
      mods: detectedMods,
      translationStatsChanged: translationStatsChanged,
    );
  }

  /// Get metadata from database cache.
  Future<ProjectMetadata?> _getMetadataFromCache(
    String workshopId,
    ModLocalData modData,
    String modTitle,
  ) async {
    final dbModResult = await _workshopModRepository.getByWorkshopId(workshopId);
    if (dbModResult is Ok) {
      final cachedMod = dbModResult.value;
      return ProjectMetadata(
        modTitle: cachedMod.title,
        modImageUrl: modData.modImagePath,
        modSubscribers: cachedMod.subscriptions,
      );
    } else if (modData.modImagePath != null) {
      return ProjectMetadata(
        modTitle: modTitle,
        modImageUrl: modData.modImagePath,
      );
    }
    return null;
  }

  /// Analyze changes for an existing project.
  ///
  /// Uses cached analysis results when the pack file hasn't changed.
  /// Only performs expensive TSV extraction when the mod has been updated.
  ///
  /// When modified source texts are detected, this method automatically:
  /// 1. Updates the source_text in translation_units
  /// 2. Resets the status to 'pending' for all affected translation versions
  ///
  /// Returns [_AnalysisResult] with the analysis and whether stats changed.
  Future<_AnalysisResult> _analyzeProjectChanges(
    String projectId,
    String packFilePath,
    String workshopId,
    int fileLastModified,
  ) async {
    // Check cache first
    final cacheResult = await _analysisCacheRepository.getByProjectAndPath(
      projectId,
      packFilePath,
    );

    if (cacheResult.isOk) {
      final cachedAnalysis = cacheResult.value;
      if (cachedAnalysis != null &&
          cachedAnalysis.isValidFor(fileLastModified)) {
        // Cache hit - but the cache only stores counts, not the actual data
        // If there are pending changes, we need to re-analyze to get the data
        if (!cachedAnalysis.hasChanges) {
          _logger.debug('Analysis cache hit for $workshopId (no changes)');
          return _AnalysisResult(analysis: cachedAnalysis.toAnalysis());
        }

        // Cache indicates changes exist - we need to re-analyze to get the
        // actual data (newUnitsData, modifiedSourceTexts) needed to apply them
        _logger.debug(
          'Analysis cache has changes for $workshopId, re-analyzing to get data...',
        );
        // Fall through to perform fresh analysis
      }
    }

    // Cache miss or invalidated - perform analysis
    _logger.debug('Analysis cache miss for $workshopId, extracting TSV...');
    final analysisResult = await _modUpdateAnalysisService.analyzeChanges(
      projectId: projectId,
      packFilePath: packFilePath,
    );

    return analysisResult.when(
      ok: (analysis) async {
        bool statsChanged = false;

        // If there are new units, add them automatically
        // This creates TranslationUnit and TranslationVersion records with status 'pending'
        if (analysis.hasNewUnits) {
          _emitLog('  Adding ${analysis.newUnitsCount} new units...');
          _logger.info(
            'Auto-adding ${analysis.newUnitsCount} new units for project $projectId',
          );
          final addResult = await _modUpdateAnalysisService.addNewUnits(
            projectId: projectId,
            analysis: analysis,
          );
          if (addResult.isOk && addResult.value > 0) {
            _emitLog('  ✓ Added ${addResult.value} new units');
            _logger.info('Added ${addResult.value} new units');
            statsChanged = true;
          } else if (addResult.isErr) {
            _logger.warning(
              'Failed to add new units: ${addResult.error.message}',
            );
          }
        }

        // If there are modified source texts, apply changes automatically
        // This updates source texts and resets translation statuses to pending
        if (analysis.hasModifiedUnits) {
          _emitLog('  Updating ${analysis.modifiedUnitsCount} modified units...');
          _logger.info(
            'Auto-applying ${analysis.modifiedUnitsCount} source text changes for project $projectId',
          );
          final applyResult = await _modUpdateAnalysisService.applyModifiedSourceTexts(
            projectId: projectId,
            analysis: analysis,
          );
          if (applyResult.isOk) {
            final result = applyResult.value;
            _emitLog('  ✓ Updated ${result.sourceTextsUpdated} source texts');
            _logger.info(
              'Applied: ${result.sourceTextsUpdated} source texts updated, '
              '${result.translationsReset} translations reset to pending',
            );
            if (result.translationsReset > 0) {
              statsChanged = true;
            }
          } else {
            _logger.warning(
              'Failed to apply source text changes: ${applyResult.error.message}',
            );
          }
        }

        // If there are removed units, mark them as obsolete
        // This soft-deletes units that no longer exist in the mod pack
        if (analysis.hasRemovedUnits) {
          _emitLog('  Marking ${analysis.removedUnitsCount} removed units as obsolete...');
          _logger.info(
            'Auto-marking ${analysis.removedUnitsCount} removed units as obsolete for project $projectId',
          );
          final removeResult = await _modUpdateAnalysisService.markRemovedUnitsObsolete(
            projectId: projectId,
            analysis: analysis,
            onProgress: (processed, total) {
              _emitLog('  Marking obsolete: $processed/$total');
            },
          );
          if (removeResult.isOk && removeResult.value > 0) {
            _emitLog('  ✓ Marked ${removeResult.value} units as obsolete');
            _logger.info('Marked ${removeResult.value} units as obsolete');
            statsChanged = true;
          } else if (removeResult.isErr) {
            _logger.warning(
              'Failed to mark removed units as obsolete: ${removeResult.error.message}',
            );
          }
        }

        // If there are reactivated units (previously obsolete, now back in pack),
        // reactivate them and mark translations for review
        if (analysis.hasReactivatedUnits) {
          _emitLog('  Reactivating ${analysis.reactivatedUnitsCount} units...');
          _logger.info(
            'Auto-reactivating ${analysis.reactivatedUnitsCount} obsolete units for project $projectId',
          );
          final reactivateResult = await _modUpdateAnalysisService.reactivateObsoleteUnits(
            projectId: projectId,
            analysis: analysis,
            onProgress: (processed, total) {
              _emitLog('  Reactivating: $processed/$total');
            },
          );
          if (reactivateResult.isOk) {
            final result = reactivateResult.value;
            if (result.unitsReactivated > 0) {
              _emitLog('  ✓ Reactivated ${result.unitsReactivated} units');
              _logger.info(
                'Reactivated ${result.unitsReactivated} units, '
                '${result.translationsMarkedForReview} translations marked for review',
              );
              statsChanged = true;
            }
          } else {
            _logger.warning(
              'Failed to reactivate obsolete units: ${reactivateResult.error.message}',
            );
          }
        }

        // Cache the result - but with zeroed counts if changes were applied
        // This prevents stale "pending changes" badges after changes are processed
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final analysisToCache = statsChanged
            ? ModUpdateAnalysis.empty  // Changes applied, cache as "no changes"
            : analysis;  // No changes applied (or failed), cache original analysis
        final cacheEntry = ModUpdateAnalysisCache.fromAnalysis(
          id: _uuid.v4(),
          projectId: projectId,
          packFilePath: packFilePath,
          fileLastModified: fileLastModified,
          analysis: analysisToCache,
          analyzedAt: now,
        );
        await _analysisCacheRepository.upsert(cacheEntry);
        return _AnalysisResult(analysis: analysis, statsChanged: statsChanged);
      },
      err: (error) {
        _logger.warning(
            'Failed to analyze changes for $workshopId: ${error.message}');
        return const _AnalysisResult();
      },
    );
  }

  /// Validate Workshop ID format (numeric only).
  bool _isValidWorkshopId(String workshopId) {
    return RegExp(r'^\d+$').hasMatch(workshopId);
  }

  /// Clean up pack file name to make it more readable.
  /// Example: "my_awesome_mod" -> "My Awesome Mod"
  String _cleanModName(String packFileName) {
    // Replace underscores and hyphens with spaces
    String cleaned = packFileName.replaceAll(RegExp(r'[_-]'), ' ');

    // Capitalize first letter of each word
    return cleaned.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}
