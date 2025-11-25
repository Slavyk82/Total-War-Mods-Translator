import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/models/domain/mod_scan_cache.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/repositories/mod_scan_cache_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/utils/rpfm_output_parser.dart';
import 'package:twmt/services/mods/mod_update_analysis_service.dart';

/// Service for scanning Steam Workshop folders and discovering/importing mods
class WorkshopScannerService {
  final ProjectRepository _projectRepository;
  final GameInstallationRepository _gameInstallationRepository;
  final WorkshopModRepository _workshopModRepository;
  final ModScanCacheRepository _modScanCacheRepository;
  final IWorkshopApiService _workshopApiService;
  final IRpfmService _rpfmService;
  final ModUpdateAnalysisService _modUpdateAnalysisService;
  final LoggingService _logger = LoggingService.instance;
  final Uuid _uuid = const Uuid();

  WorkshopScannerService({
    required ProjectRepository projectRepository,
    required GameInstallationRepository gameInstallationRepository,
    required WorkshopModRepository workshopModRepository,
    required ModScanCacheRepository modScanCacheRepository,
    required IWorkshopApiService workshopApiService,
    required IRpfmService rpfmService,
    required ModUpdateAnalysisService modUpdateAnalysisService,
  })  : _projectRepository = projectRepository,
        _gameInstallationRepository = gameInstallationRepository,
        _workshopModRepository = workshopModRepository,
        _modScanCacheRepository = modScanCacheRepository,
        _workshopApiService = workshopApiService,
        _rpfmService = rpfmService,
        _modUpdateAnalysisService = modUpdateAnalysisService;

  /// Scan Workshop folder for a game and return detected mods without creating projects
  Future<Result<List<DetectedMod>, ServiceException>> scanMods(
    String gameCode,
  ) async {
    try {
      _logger.info('Scanning Workshop folder for game: $gameCode');

      // Get game installation from database
      final gameInstallationResult =
          await _gameInstallationRepository.getByGameCode(gameCode);

      late final GameInstallation gameInstallation;
      if (gameInstallationResult is Err) {
        final error = gameInstallationResult.error;
        _logger.error('Game installation not found for $gameCode: ${error.message}');
        throw ServiceException(
          'Game installation not found: ${error.message}',
          error: error,
        );
      }
      
      gameInstallation = gameInstallationResult.value;

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
      final existingProjectsResult = await _projectRepository.getAll();
      late final List<Project> existingProjects;
      existingProjectsResult.when(
        ok: (projects) => existingProjects = projects,
        err: (_) => existingProjects = [],
      );

      // Map of existing Steam Workshop IDs to projects
      final existingWorkshopIds = <String, Project>{};
      for (final project in existingProjects) {
        if (project.modSteamId != null && project.modSteamId!.isNotEmpty) {
          existingWorkshopIds[project.modSteamId!] = project;
        }
      }

      // Scan Workshop folder for mod directories
      final modDirs = await gameWorkshopDir
          .list()
          .where((entity) => entity is Directory)
          .cast<Directory>()
          .toList();

      _logger.info('Found ${modDirs.length} Workshop items');

      // Check if RPFM is available for loc file detection
      final rpfmAvailable = await _rpfmService.isRpfmAvailable();
      if (!rpfmAvailable) {
        _logger.warning('RPFM-CLI not available, cannot filter mods by loc files');
      }

      // Phase 1: Collect all mod information locally (pack files, images, loc files check)
      // Use cache to avoid re-scanning mods that haven't changed
      final modDataList = <_ModLocalData>[];
      final packFileInfos = <_PackFileInfo>[];

      // First pass: collect all valid pack files and their modification times
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

        packFileInfos.add(_PackFileInfo(
          workshopId: workshopId,
          modDir: modDir,
          packFile: packFile,
          packFileName: packFileName,
          fileLastModified: fileLastModified,
        ));
      }

      _logger.debug('Found ${packFileInfos.length} pack files to check');

      // Fetch cache entries for all pack files in batch
      final packFilePaths = packFileInfos.map((info) => info.packFile.path).toList();
      final cacheResult = await _modScanCacheRepository.getByPackFilePaths(packFilePaths);
      final cacheMap = cacheResult is Ok<Map<String, ModScanCache>, dynamic>
          ? cacheResult.value
          : <String, ModScanCache>{};

      int cacheHits = 0;
      int cacheMisses = 0;
      int cacheSkipped = 0;
      final cacheUpdates = <ModScanCache>[];
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Second pass: check cache and scan if necessary
      for (final info in packFileInfos) {
        final cacheEntry = cacheMap[info.packFile.path];
        bool hasLocFiles = false;

        // Check if we have a valid cache entry
        if (cacheEntry != null && cacheEntry.isValidFor(info.fileLastModified)) {
          // Cache hit - file hasn't been modified
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
          final listResult = await _rpfmService.listPackContents(info.packFile.path);
          listResult.when(
            ok: (files) {
              final locFiles = RpfmOutputParser.filterLocalizationFiles(files);
              hasLocFiles = locFiles.isNotEmpty;
              if (!hasLocFiles) {
                _logger.debug('No loc files in ${info.workshopId} (${info.packFileName}), skipping');
              }
            },
            err: (error) {
              _logger.warning('Failed to list pack contents for ${info.workshopId}: ${error.message}');
              // Skip mod if we can't determine if it has loc files
            },
          );

          // Update cache with scan result
          cacheUpdates.add(ModScanCache(
            id: cacheEntry?.id ?? _uuid.v4(),
            packFilePath: info.packFile.path,
            fileLastModified: info.fileLastModified,
            hasLocFiles: hasLocFiles,
            scannedAt: now,
          ));

          // Skip mods without loc files (not translatable)
          if (!hasLocFiles) {
            continue;
          }
        } else {
          // RPFM not available and no cache - skip
          continue;
        }

        // Try to find mod image in the mod directory
        final modImagePath = await _findModImage(info.modDir, info.packFileName);

        modDataList.add(_ModLocalData(
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

      _logger.debug(
        'Cache: hits=$cacheHits, misses=$cacheMisses, skipped=$cacheSkipped'
      );

      // Phase 2: Batch fetch Steam Workshop data
      final workshopModsMap = <String, WorkshopMod>{};

      if (gameInstallation.steamAppId != null) {
        final appId = int.tryParse(gameInstallation.steamAppId!);
        if (appId != null && modDataList.isNotEmpty) {
          final workshopIds = modDataList.map((m) => m.workshopId).toList();

          // Process in batches of 100 (Steam API limit)
          for (int i = 0; i < workshopIds.length; i += 100) {
            final batchEnd = (i + 100 < workshopIds.length) ? i + 100 : workshopIds.length;
            final batch = workshopIds.sublist(i, batchEnd);

            final modInfosResult = await _workshopApiService.getMultipleModInfo(
              workshopIds: batch,
              appId: appId,
            );

            if (modInfosResult is Ok) {
              final modInfos = modInfosResult.value;

              // Save all fetched mods to database
              final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

              for (final modInfo in modInfos) {
                // Check if mod already exists
                final existingModResult = await _workshopModRepository.getByWorkshopId(modInfo.workshopId);
                
                final bool isNewMod;
                final String modId;
                final int createdAt;
                final bool hasChanges;
                
                WorkshopMod? existingMod;
                if (existingModResult is Ok) {
                  // Mod exists, check if data has changed
                  existingMod = existingModResult.value;
                  modId = existingMod.id;
                  createdAt = existingMod.createdAt;
                  isNewMod = false;
                  
                  // Compare relevant fields (excluding internal timestamps)
                  hasChanges = existingMod.title != modInfo.title ||
                      existingMod.workshopUrl != modInfo.workshopUrl ||
                      existingMod.fileSize != modInfo.fileSize ||
                      existingMod.timeCreated != modInfo.timeCreated ||
                      existingMod.timeUpdated != modInfo.timeUpdated ||
                      existingMod.subscriptions != modInfo.subscriptions ||
                      !_tagsEqual(existingMod.tags, modInfo.tags);
                } else {
                  // New mod, generate new ID
                  modId = _uuid.v4();
                  createdAt = now;
                  isNewMod = true;
                  hasChanges = true; // New mod always has changes
                }

                final workshopMod = WorkshopMod(
                  id: modId,
                  workshopId: modInfo.workshopId,
                  title: modInfo.title,
                  appId: appId,
                  workshopUrl: modInfo.workshopUrl,
                  fileSize: modInfo.fileSize,
                  timeCreated: modInfo.timeCreated,
                  timeUpdated: modInfo.timeUpdated,
                  subscriptions: modInfo.subscriptions,
                  tags: modInfo.tags,
                  createdAt: createdAt,
                  updatedAt: hasChanges ? now : (existingMod?.updatedAt ?? now),
                  lastCheckedAt: now,
                );

                workshopModsMap[modInfo.workshopId] = workshopMod;

                // Only upsert if it's a new mod or if data has changed
                if (isNewMod || hasChanges) {
                  _workshopModRepository.upsert(workshopMod).then((result) {
                    result.when(
                      ok: (_) {},
                      err: (error) => _logger.error('Failed to save mod ${modInfo.workshopId}: ${error.message}'),
                    );
                  });
                } else {
                  // Only update lastCheckedAt without changing updatedAt
                  _workshopModRepository.updateLastChecked(modInfo.workshopId, now).then((result) {
                    result.when(
                      ok: (_) {},
                      err: (error) => _logger.warning('Failed to update lastCheckedAt for mod ${modInfo.workshopId}: ${error.message}'),
                    );
                  });
                }
              }
            } else {
              final error = modInfosResult.error;
              _logger.warning('Steam API batch failed: ${error.message}');
            }
          }
        }
      }

      // Phase 3: Build DetectedMod list with fetched data
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
          final dbModResult = await _workshopModRepository.getByWorkshopId(workshopId);
          if (dbModResult is Ok) {
            final cachedMod = dbModResult.value;
            modTitle = cachedMod.title;
            timeUpdated = cachedMod.timeUpdated;
            metadata = ProjectMetadata(
              modTitle: cachedMod.title,
              modImageUrl: modData.modImagePath,
              modSubscribers: cachedMod.subscriptions,
            );
          } else if (modData.modImagePath != null) {
            // Use local image and cleaned name if both API and DB failed
            metadata = ProjectMetadata(
              modTitle: modTitle,
              modImageUrl: modData.modImagePath,
            );
          }
        }

        // Check if mod is already imported
        final existingProject = existingWorkshopIds[workshopId];

        // Analyze changes for imported projects
        ModUpdateAnalysis? updateAnalysis;
        if (existingProject != null) {
          final analysisResult = await _modUpdateAnalysisService.analyzeChanges(
            projectId: existingProject.id,
            packFilePath: modData.packFile.path,
          );
          analysisResult.when(
            ok: (analysis) {
              updateAnalysis = analysis;
            },
            err: (error) {
              _logger.warning('Failed to analyze changes for $workshopId: ${error.message}');
            },
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

  /// Scan Workshop folder for a game and import mods as projects
  @Deprecated('Use scanMods() instead and manually import selected mods')
  Future<Result<List<Project>, ServiceException>> scanAndImportMods(
    String gameCode,
  ) async {
    try {
      _logger.info('Scanning Workshop folder for game: $gameCode');

      // Get game installation from database
      final gameInstallationResult =
          await _gameInstallationRepository.getByGameCode(gameCode);

      late final GameInstallation gameInstallation;
      if (gameInstallationResult is Err) {
        final error = gameInstallationResult.error;
        _logger.error('Game installation not found for $gameCode: ${error.message}');
        throw ServiceException(
          'Game installation not found: ${error.message}',
          error: error,
        );
      }
      
      gameInstallation = gameInstallationResult.value;

      // Check if Workshop path is configured
      if (!gameInstallation.hasWorkshopPath) {
        _logger.debug('No Workshop path configured for $gameCode');
        return const Ok([]);
      }

      final workshopPath = gameInstallation.steamWorkshopPath!;
      
      // workshopPath already contains the app ID
      // Format: Steam/steamapps/workshop/content/[appId]/
      final gameWorkshopDir = Directory(workshopPath);

      if (!await gameWorkshopDir.exists()) {
        _logger.debug('Workshop folder does not exist: $workshopPath');
        return const Ok([]);
      }

      // Get existing projects to avoid duplicates
      final existingProjectsResult = await _projectRepository.getAll();
      late final List<Project> existingProjects;
      existingProjectsResult.when(
        ok: (projects) => existingProjects = projects,
        err: (_) => existingProjects = [],
      );

      // Map of existing Steam Workshop IDs to projects
      final existingWorkshopIds = <String, Project>{};
      for (final project in existingProjects) {
        if (project.modSteamId != null && project.modSteamId!.isNotEmpty) {
          existingWorkshopIds[project.modSteamId!] = project;
        }
      }

      // Scan Workshop folder for mod directories
      final modDirs = await gameWorkshopDir
          .list()
          .where((entity) => entity is Directory)
          .cast<Directory>()
          .toList();

      final importedProjects = <Project>[];
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      for (final modDir in modDirs) {
        final workshopId = path.basename(modDir.path);

        // Skip if not a valid Workshop ID (numeric)
        if (!_isValidWorkshopId(workshopId)) {
          continue;
        }

        // Check if mod already exists
        final existingProject = existingWorkshopIds[workshopId];
        if (existingProject != null) {
          // Update metadata if missing image
          if (existingProject.imageUrl == null || existingProject.imageUrl!.isEmpty) {
            await _updateProjectMetadata(
              existingProject,
              modDir,
              gameInstallation,
              workshopId,
            );
          }
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
          continue;
        }

        // Use the first .pack file found
        final packFile = packFiles.first;
        final packFileName = path.basenameWithoutExtension(packFile.path);

        // Try to find mod image in the mod directory
        String? modImagePath;
        final imageExtensions = ['.jpg', '.jpeg', '.png'];
        
        // 1. First, check for image with same name as .pack file
        for (final ext in imageExtensions) {
          final imagePath = path.join(modDir.path, '$packFileName$ext');
          if (await File(imagePath).exists()) {
            modImagePath = imagePath;
            break;
          }
        }
        
        // 2. If not found, try preview.*
        if (modImagePath == null) {
          for (final ext in imageExtensions) {
            final imagePath = path.join(modDir.path, 'preview$ext');
            if (await File(imagePath).exists()) {
              modImagePath = imagePath;
              break;
            }
          }
        }
        
        // 3. If still not found, try to find any image file
        if (modImagePath == null) {
          final imageFiles = await modDir
              .list()
              .where((entity) => entity is File)
              .cast<File>()
              .where((file) => imageExtensions.any((ext) => 
                  file.path.toLowerCase().endsWith(ext)))
              .toList();
          if (imageFiles.isNotEmpty) {
            modImagePath = imageFiles.first.path;
          }
        }

        // Try to fetch mod info from Steam Workshop API
        // Use cleaned file name as fallback
        String modTitle = _cleanModName(packFileName);
        ProjectMetadata? metadata;
        
        if (gameInstallation.steamAppId != null) {
          final appId = int.tryParse(gameInstallation.steamAppId!);
          if (appId != null) {
            final modInfoResult = await _workshopApiService.getModInfo(
              workshopId: workshopId,
              appId: appId,
            );
            
            modInfoResult.when(
              ok: (modInfo) {
                modTitle = modInfo.title;
                metadata = ProjectMetadata(
                  modTitle: modInfo.title,
                  modImageUrl: modImagePath,
                  modSubscribers: modInfo.subscriptions,
                );
              },
              err: (error) {
                // Use local image and cleaned name if API failed
                if (modImagePath != null) {
                  metadata = ProjectMetadata(
                    modTitle: _cleanModName(packFileName),
                    modImageUrl: modImagePath,
                  );
                }
              },
            );
          }
        } else if (modImagePath != null) {
          // No Steam App ID, use local image and cleaned name
          metadata = ProjectMetadata(
            modTitle: _cleanModName(packFileName),
            modImageUrl: modImagePath,
          );
        }

        // Create project
        final project = Project(
          id: _uuid.v4(),
          name: modTitle,
          modSteamId: workshopId,
          modVersion: null,
          gameInstallationId: gameInstallation.id,
          sourceFilePath: packFile.path,
          outputFilePath: null,
          status: ProjectStatus.draft,
          lastUpdateCheck: null,
          sourceModUpdated: null,
          batchSize: 25,
          parallelBatches: 3,
          customPrompt: null,
          createdAt: now,
          updatedAt: now,
          completedAt: null,
          metadata: metadata?.toJsonString(),
        );

        // Insert into database
        final insertResult = await _projectRepository.insert(project);
        insertResult.when(
          ok: (insertedProject) {
            importedProjects.add(insertedProject);
          },
          err: (error) {
            _logger.error('Failed to import mod $workshopId: ${error.message}');
          },
        );
      }

      _logger.info('Import complete: ${importedProjects.length} new mods');
      return Ok(importedProjects);
    } catch (e, stackTrace) {
      _logger.error('Failed to scan Workshop folder: $e', stackTrace);
      return Err(ServiceException(
        'Failed to scan Workshop folder: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Update metadata for existing project without image
  Future<void> _updateProjectMetadata(
    Project existingProject,
    Directory modDir,
    GameInstallation gameInstallation,
    String workshopId,
  ) async {
    try {
      // Find .pack file to get the base name
      final packFiles = await modDir
          .list()
          .where((entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.pack'))
          .cast<File>()
          .toList();

      if (packFiles.isEmpty) {
        return;
      }

      final packFile = packFiles.first;
      final packFileName = path.basenameWithoutExtension(packFile.path);

      // Try to find mod image in the mod directory
      String? modImagePath;
      final imageExtensions = ['.jpg', '.jpeg', '.png'];
      
      // 1. First, check for image with same name as .pack file
      for (final ext in imageExtensions) {
        final imagePath = path.join(modDir.path, '$packFileName$ext');
        if (await File(imagePath).exists()) {
          modImagePath = imagePath;
          break;
        }
      }
      
      // 2. If not found, try preview.*
      if (modImagePath == null) {
        for (final ext in imageExtensions) {
          final imagePath = path.join(modDir.path, 'preview$ext');
          if (await File(imagePath).exists()) {
            modImagePath = imagePath;
            break;
          }
        }
      }

      // 3. If still not found, try to find any image file
      if (modImagePath == null) {
        final imageFiles = await modDir
            .list()
            .where((entity) => entity is File)
            .cast<File>()
            .where((file) => imageExtensions.any((ext) => 
                file.path.toLowerCase().endsWith(ext)))
            .toList();
        if (imageFiles.isNotEmpty) {
          modImagePath = imageFiles.first.path;
        }
      }

      // Try to fetch mod info from Steam Workshop API
      ProjectMetadata? metadata;
      
      if (gameInstallation.steamAppId != null) {
        final appId = int.tryParse(gameInstallation.steamAppId!);
        if (appId != null) {
          final modInfoResult = await _workshopApiService.getModInfo(
            workshopId: workshopId,
            appId: appId,
          );
          
          modInfoResult.when(
            ok: (modInfo) {
              metadata = ProjectMetadata(
                modTitle: modInfo.title,
                modImageUrl: modImagePath,
                modSubscribers: modInfo.subscriptions,
              );
            },
            err: (error) {
              // Use local image if API failed
              if (modImagePath != null) {
                metadata = ProjectMetadata(
                  modTitle: existingProject.name,
                  modImageUrl: modImagePath,
                );
              }
            },
          );
        }
      } else if (modImagePath != null) {
        // No Steam App ID, use local image
        metadata = ProjectMetadata(
          modTitle: existingProject.name,
          modImageUrl: modImagePath,
        );
      }

      // Update project if metadata was found
      if (metadata != null) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final updatedProject = existingProject.copyWith(
          metadata: metadata!.toJsonString(),
          updatedAt: now,
        );

        final updateResult = await _projectRepository.update(updatedProject);
        updateResult.when(
          ok: (_) {},
          err: (error) {
            _logger.error('Failed to update metadata for $workshopId: ${error.message}');
          },
        );
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to update project metadata for $workshopId: $e', stackTrace);
    }
  }

  /// Find mod image in the mod directory
  Future<String?> _findModImage(Directory modDir, String packFileName) async {
    String? modImagePath;
    final imageExtensions = ['.jpg', '.jpeg', '.png'];
    
    // 1. First, check for image with same name as .pack file
    for (final ext in imageExtensions) {
      final imagePath = path.join(modDir.path, '$packFileName$ext');
      if (await File(imagePath).exists()) {
        modImagePath = imagePath;
        break;
      }
    }
    
    // 2. If not found, try preview.*
    if (modImagePath == null) {
      for (final ext in imageExtensions) {
        final imagePath = path.join(modDir.path, 'preview$ext');
        if (await File(imagePath).exists()) {
          modImagePath = imagePath;
          break;
        }
      }
    }
    
    // 3. If still not found, try to find any image file
    if (modImagePath == null) {
      final imageFiles = await modDir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .where((file) => imageExtensions.any((ext) => 
              file.path.toLowerCase().endsWith(ext)))
          .toList();
      if (imageFiles.isNotEmpty) {
        modImagePath = imageFiles.first.path;
      }
    }

    return modImagePath;
  }

  /// Validate Workshop ID format (numeric only)
  bool _isValidWorkshopId(String workshopId) {
    return RegExp(r'^\d+$').hasMatch(workshopId);
  }

  /// Clean up pack file name to make it more readable
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

  /// Compare two tag lists for equality
  bool _tagsEqual(List<String>? tags1, List<String>? tags2) {
    if (tags1 == null && tags2 == null) return true;
    if (tags1 == null || tags2 == null) return false;
    if (tags1.length != tags2.length) return false;
    
    final sorted1 = List<String>.from(tags1)..sort();
    final sorted2 = List<String>.from(tags2)..sort();
    return sorted1.join(',') == sorted2.join(',');
  }
}

/// Helper class to store local mod data during scanning
class _ModLocalData {
  final String workshopId;
  final File packFile;
  final String packFileName;
  final String? modImagePath;
  /// Whether the pack file contains localization (.loc) files
  final bool hasLocFiles;
  /// Local file last modified timestamp (Unix epoch seconds)
  final int fileLastModified;

  _ModLocalData({
    required this.workshopId,
    required this.packFile,
    required this.packFileName,
    this.modImagePath,
    this.hasLocFiles = false,
    required this.fileLastModified,
  });
}

/// Helper class to store pack file info before cache lookup
class _PackFileInfo {
  final String workshopId;
  final Directory modDir;
  final File packFile;
  final String packFileName;
  final int fileLastModified;

  _PackFileInfo({
    required this.workshopId,
    required this.modDir,
    required this.packFile,
    required this.packFileName,
    required this.fileLastModified,
  });
}

