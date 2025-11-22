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
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';

/// Service for scanning Steam Workshop folders and discovering/importing mods
class WorkshopScannerService {
  final ProjectRepository _projectRepository;
  final GameInstallationRepository _gameInstallationRepository;
  final WorkshopModRepository _workshopModRepository;
  final IWorkshopApiService _workshopApiService;
  final LoggingService _logger = LoggingService.instance;
  final Uuid _uuid = const Uuid();

  WorkshopScannerService({
    required ProjectRepository projectRepository,
    required GameInstallationRepository gameInstallationRepository,
    required WorkshopModRepository workshopModRepository,
    required IWorkshopApiService workshopApiService,
  })  : _projectRepository = projectRepository,
        _gameInstallationRepository = gameInstallationRepository,
        _workshopModRepository = workshopModRepository,
        _workshopApiService = workshopApiService;

  /// Scan Workshop folder for a game and return detected mods without creating projects
  Future<Result<List<DetectedMod>, ServiceException>> scanMods(
    String gameCode,
  ) async {
    try {
      _logger.info('Scanning Workshop folder for game: $gameCode');

      // Get game installation from database
      _logger.info('Looking up game installation for: $gameCode');
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
      _logger.info('Found game installation: ${gameInstallation.gameName}');

      // Check if Workshop path is configured
      if (!gameInstallation.hasWorkshopPath) {
        _logger.warning('No Workshop path configured for $gameCode');
        return const Ok([]);
      }

      final workshopPath = gameInstallation.steamWorkshopPath!;
      final gameWorkshopDir = Directory(workshopPath);

      if (!await gameWorkshopDir.exists()) {
        _logger.info('Workshop folder does not exist: $workshopPath');
        return const Ok([]);
      }
      
      _logger.info('Scanning Workshop directory: $workshopPath');

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

      // Phase 1: Collect all mod information locally (pack files, images)
      final modDataList = <_ModLocalData>[];

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

        // Try to find mod image in the mod directory
        final modImagePath = await _findModImage(modDir, packFileName);

        modDataList.add(_ModLocalData(
          workshopId: workshopId,
          packFile: packFile,
          packFileName: packFileName,
          modImagePath: modImagePath,
        ));
      }

      _logger.info('Found ${modDataList.length} valid mods with pack files');

      // Phase 2: Batch fetch Steam Workshop data
      final workshopModsMap = <String, WorkshopMod>{};

      if (gameInstallation.steamAppId != null) {
        final appId = int.tryParse(gameInstallation.steamAppId!);
        if (appId != null && modDataList.isNotEmpty) {
          final workshopIds = modDataList.map((m) => m.workshopId).toList();

          _logger.info('Fetching Steam Workshop info for ${workshopIds.length} mods in batches of 100');

          // Process in batches of 100 (Steam API limit)
          for (int i = 0; i < workshopIds.length; i += 100) {
            final batchEnd = (i + 100 < workshopIds.length) ? i + 100 : workshopIds.length;
            final batch = workshopIds.sublist(i, batchEnd);

            _logger.info('Fetching batch ${(i ~/ 100) + 1}: ${batch.length} mods');

            final modInfosResult = await _workshopApiService.getMultipleModInfo(
              workshopIds: batch,
              appId: appId,
            );

            if (modInfosResult is Ok) {
              final modInfos = modInfosResult.value;
              _logger.info('Successfully fetched ${modInfos.length}/${batch.length} mods from batch ${(i ~/ 100) + 1}');

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
                  final isModUpdate = !isNewMod;
                  _workshopModRepository.upsert(workshopMod).then((result) {
                    result.when(
                      ok: (_) => _logger.debug(
                        isModUpdate 
                          ? 'Updated mod in database: ${modInfo.workshopId}'
                          : 'Saved new mod to database: ${modInfo.workshopId}'
                      ),
                      err: (error) => _logger.error('Failed to save mod ${modInfo.workshopId}: ${error.message}'),
                    );
                  });
                } else {
                  // Only update lastCheckedAt without changing updatedAt
                  _workshopModRepository.updateLastChecked(modInfo.workshopId, now).then((result) {
                    result.when(
                      ok: (_) => _logger.debug('Checked mod (no changes): ${modInfo.workshopId}'),
                      err: (error) => _logger.warning('Failed to update lastCheckedAt for mod ${modInfo.workshopId}: ${error.message}'),
                    );
                  });
                }
              }
            } else {
              final error = modInfosResult.error;
              _logger.warning('Failed to fetch batch ${(i ~/ 100) + 1}: ${error.message}');
            }
          }

          _logger.info('Batch fetching complete. Retrieved ${workshopModsMap.length}/${workshopIds.length} mods from Steam');
        }
      }

      // Phase 3: Build DetectedMod list with fetched data
      final detectedMods = <DetectedMod>[];

      for (final modData in modDataList) {
        final workshopId = modData.workshopId;
        String modTitle = _cleanModName(modData.packFileName);
        ProjectMetadata? metadata;

        // Try to get Workshop data from batch fetch
        final workshopMod = workshopModsMap[workshopId];

        if (workshopMod != null) {
          modTitle = workshopMod.title;
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
            metadata = ProjectMetadata(
              modTitle: cachedMod.title,
              modImageUrl: modData.modImagePath,
              modSubscribers: cachedMod.subscriptions,
            );
            _logger.debug('Loaded mod from database cache: $modTitle');
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

        detectedMods.add(DetectedMod(
          workshopId: workshopId,
          name: modTitle,
          packFilePath: modData.packFile.path,
          imageUrl: modData.modImagePath ?? metadata?.modImageUrl,
          metadata: metadata,
          isAlreadyImported: existingProject != null,
          existingProjectId: existingProject?.id,
        ));
      }

      _logger.info('Scan complete. Found ${detectedMods.length} mods.');
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
      _logger.info('Looking up game installation for: $gameCode');
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
      _logger.info('Found game installation: ${gameInstallation.gameName}');

      // Check if Workshop path is configured
      if (!gameInstallation.hasWorkshopPath) {
        _logger.warning('No Workshop path configured for $gameCode');
        return const Ok([]);
      }

      final workshopPath = gameInstallation.steamWorkshopPath!;
      
      // workshopPath already contains the app ID
      // Format: Steam/steamapps/workshop/content/[appId]/
      final gameWorkshopDir = Directory(workshopPath);

      if (!await gameWorkshopDir.exists()) {
        _logger.info('Workshop folder does not exist: $workshopPath');
        return const Ok([]);
      }
      
      _logger.info('Scanning Workshop directory: $workshopPath');

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

      _logger.info('Found ${modDirs.length} Workshop items');

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
            _logger.info('Updating metadata for existing mod: $workshopId');
            await _updateProjectMetadata(
              existingProject,
              modDir,
              gameInstallation,
              workshopId,
            );
          } else {
            _logger.debug('Mod $workshopId already exists with image, skipping');
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
          _logger.debug('No .pack files found in $workshopId, skipping');
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
            _logger.debug('Found mod image: $packFileName$ext');
            break;
          }
        }
        
        // 2. If not found, try preview.*
        if (modImagePath == null) {
          for (final ext in imageExtensions) {
            final imagePath = path.join(modDir.path, 'preview$ext');
            if (await File(imagePath).exists()) {
              modImagePath = imagePath;
              _logger.debug('Found preview image: preview$ext');
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
            _logger.debug('Found fallback image: ${path.basename(imageFiles.first.path)}');
          }
        }

        // Try to fetch mod info from Steam Workshop API
        // Use cleaned file name as fallback
        String modTitle = _cleanModName(packFileName);
        ProjectMetadata? metadata;
        
        if (gameInstallation.steamAppId != null) {
          final appId = int.tryParse(gameInstallation.steamAppId!);
          if (appId != null) {
            _logger.info('Fetching Workshop info for mod: $workshopId');
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
                _logger.info('Retrieved mod info: $modTitle');
              },
              err: (error) {
                _logger.warning('Failed to fetch mod info for $workshopId: ${error.message}');
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
            _logger.info('Imported mod: $packFileName (Workshop ID: $workshopId)');
          },
          err: (error) {
            _logger.error('Failed to import mod $workshopId: ${error.message}');
          },
        );
      }

      _logger.info('Import complete. Imported ${importedProjects.length} new mods.');
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
        _logger.debug('No .pack files found in $workshopId for update');
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
          _logger.debug('Found mod image: $packFileName$ext');
          break;
        }
      }
      
      // 2. If not found, try preview.*
      if (modImagePath == null) {
        for (final ext in imageExtensions) {
          final imagePath = path.join(modDir.path, 'preview$ext');
          if (await File(imagePath).exists()) {
            modImagePath = imagePath;
            _logger.debug('Found preview image: preview$ext');
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
          _logger.debug('Found fallback image: ${path.basename(imageFiles.first.path)}');
        }
      }

      // Try to fetch mod info from Steam Workshop API
      ProjectMetadata? metadata;
      
      if (gameInstallation.steamAppId != null) {
        final appId = int.tryParse(gameInstallation.steamAppId!);
        if (appId != null) {
          _logger.info('Fetching Workshop info for mod: $workshopId');
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
              _logger.info('Retrieved mod info: ${modInfo.title}');
            },
            err: (error) {
              _logger.warning('Failed to fetch mod info for $workshopId: ${error.message}');
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
          ok: (_) {
            _logger.info('Updated metadata for mod: $workshopId');
          },
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
        _logger.debug('Found mod image: $packFileName$ext');
        break;
      }
    }
    
    // 2. If not found, try preview.*
    if (modImagePath == null) {
      for (final ext in imageExtensions) {
        final imagePath = path.join(modDir.path, 'preview$ext');
        if (await File(imagePath).exists()) {
          modImagePath = imagePath;
          _logger.debug('Found preview image: preview$ext');
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
        _logger.debug('Found fallback image: ${path.basename(imageFiles.first.path)}');
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

  _ModLocalData({
    required this.workshopId,
    required this.packFile,
    required this.packFileName,
    this.modImagePath,
  });
}

