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
  Future<Result<List<DetectedMod>, ServiceException>> scanMods(
    String gameCode,
  ) async {
    try {
      _logger.info('Scanning Workshop folder for game: $gameCode');

      // Get game installation from database
      final gameInstallationResult =
          await _gameInstallationRepository.getByGameCode(gameCode);

      if (gameInstallationResult is Err) {
        final error = gameInstallationResult.error;
        _logger.error('Game installation not found for $gameCode: ${error.message}');
        throw ServiceException(
          'Game installation not found: ${error.message}',
          error: error,
        );
      }

      final gameInstallation = gameInstallationResult.value;

      // Check if Workshop path is configured
      if (!gameInstallation.hasWorkshopPath) {
        _logger.debug('No Workshop path configured for $gameCode');
        return const Ok([]);
      }

      final workshopPath = gameInstallation.steamWorkshopPath!;
      final gameWorkshopDir = Directory(workshopPath);

      if (!await gameWorkshopDir.exists()) {
        _logger.debug('Workshop folder does not exist: $workshopPath');
        return const Ok([]);
      }

      // Get existing projects to mark which mods are already imported
      final existingWorkshopIds = await _getExistingWorkshopIds();

      // Scan Workshop folder for mod directories
      final modDirs = await gameWorkshopDir
          .list()
          .where((entity) => entity is Directory)
          .cast<Directory>()
          .toList();

      _logger.info('Found ${modDirs.length} Workshop items');

      // Phase 1: Collect pack file info and check cache
      final modDataList = await _collectModData(modDirs);

      // Phase 2: Batch fetch Steam Workshop data
      final workshopModsMap = await _fetchWorkshopData(
        modDataList,
        gameInstallation.steamAppId,
      );

      // Phase 3: Build DetectedMod list
      final detectedMods = await _buildDetectedMods(
        modDataList,
        workshopModsMap,
        existingWorkshopIds,
      );

      _logger.info('Scan complete: ${detectedMods.length} translatable mods');
      return Ok(detectedMods);
    } catch (e, stackTrace) {
      _logger.error('Failed to scan Workshop folder: $e', stackTrace);
      return Err(ServiceException(
        'Failed to scan Workshop folder: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
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

    for (final info in packFileInfos) {
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
  Future<List<DetectedMod>> _buildDetectedMods(
    List<ModLocalData> modDataList,
    Map<String, WorkshopMod> workshopModsMap,
    Map<String, Project> existingWorkshopIds,
  ) async {
    final detectedMods = <DetectedMod>[];

    for (final modData in modDataList) {
      final workshopId = modData.workshopId;
      String modTitle = _cleanModName(modData.packFileName);
      ProjectMetadata? metadata;
      int? timeUpdated;

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
      }

      // Check if mod is already imported
      final existingProject = existingWorkshopIds[workshopId];

      // Analyze changes for imported projects (uses cache when mod hasn't changed)
      ModUpdateAnalysis? updateAnalysis;
      if (existingProject != null) {
        updateAnalysis = await _analyzeProjectChanges(
          existingProject.id,
          modData.packFile.path,
          workshopId,
          modData.fileLastModified,
        );
      }

      detectedMods.add(DetectedMod(
        workshopId: workshopId,
        name: modTitle,
        packFilePath: modData.packFile.path,
        imageUrl: modData.modImagePath ?? metadata?.modImageUrl,
        metadata: metadata,
        isAlreadyImported: existingProject != null,
        existingProjectId: existingProject?.id,
        hasLocFiles: modData.hasLocFiles,
        timeUpdated: timeUpdated,
        localFileLastModified: modData.fileLastModified,
        updateAnalysis: updateAnalysis,
      ));
    }

    return detectedMods;
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
  Future<ModUpdateAnalysis?> _analyzeProjectChanges(
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
        _logger.debug('Analysis cache hit for $workshopId');
        return cachedAnalysis.toAnalysis();
      }
    }

    // Cache miss or invalidated - perform analysis
    _logger.debug('Analysis cache miss for $workshopId, extracting TSV...');
    final analysisResult = await _modUpdateAnalysisService.analyzeChanges(
      projectId: projectId,
      packFilePath: packFilePath,
    );

    return analysisResult.when(
      ok: (analysis) {
        // Cache the result
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final cacheEntry = ModUpdateAnalysisCache.fromAnalysis(
          id: _uuid.v4(),
          projectId: projectId,
          packFilePath: packFilePath,
          fileLastModified: fileLastModified,
          analysis: analysis,
          analyzedAt: now,
        );
        _analysisCacheRepository.upsert(cacheEntry);
        return analysis;
      },
      err: (error) {
        _logger.warning(
            'Failed to analyze changes for $workshopId: ${error.message}');
        return null;
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
