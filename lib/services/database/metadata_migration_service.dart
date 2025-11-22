import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';

/// Service for migrating legacy projects to include metadata
///
/// This service ensures all projects have the metadata field populated
/// with at least the mod title, which is used for display in the UI.
/// For Steam Workshop mods, it fetches the real mod title from the API.
class MetadataMigrationService {
  final ProjectRepository _projectRepository;
  final GameInstallationRepository _gameInstallationRepository;
  final IWorkshopApiService _workshopApiService;
  final LoggingService _logger;

  MetadataMigrationService({
    required ProjectRepository projectRepository,
    required GameInstallationRepository gameInstallationRepository,
    required IWorkshopApiService workshopApiService,
    LoggingService? logger,
  })  : _projectRepository = projectRepository,
        _gameInstallationRepository = gameInstallationRepository,
        _workshopApiService = workshopApiService,
        _logger = logger ?? LoggingService.instance;

  /// Migrate all projects without metadata
  ///
  /// For each project without metadata or with incomplete metadata:
  /// - If from Steam Workshop: fetches real mod title from API
  /// - Otherwise: uses cleaned project name as mod title
  ///
  /// Returns the number of projects updated.
  Future<int> migrateProjectsWithoutMetadata() async {
    _logger.info('Starting metadata migration for projects');

    try {
      // Get all projects
      final projectsResult = await _projectRepository.getAll();
      
      if (projectsResult.isErr) {
        _logger.error('Failed to load projects for migration: ${projectsResult.error}');
        return 0;
      }

      final projects = projectsResult.value;
      int updatedCount = 0;

      for (final project in projects) {
        // Check if project needs metadata migration
        final needsMigration = project.metadata == null || 
                              project.metadata!.isEmpty ||
                              project.parsedMetadata?.modTitle == null;
        
        if (needsMigration) {
          _logger.info('Migrating project: ${project.id} - ${project.name}');
          
          // Try to fetch real mod title from Steam Workshop
          ProjectMetadata? metadata;
          String? modTitle;
          
          if (project.modSteamId != null && project.modSteamId!.isNotEmpty) {
            _logger.info('Fetching Workshop info for mod: ${project.modSteamId}');
            
            // Get game installation to get Steam App ID
            final gameInstResult = await _gameInstallationRepository.getById(
              project.gameInstallationId,
            );
            
            if (gameInstResult.isOk) {
              final gameInst = gameInstResult.value;
              final appId = int.tryParse(gameInst.steamAppId ?? '');
              
              if (appId != null) {
                final modInfoResult = await _workshopApiService.getModInfo(
                  workshopId: project.modSteamId!,
                  appId: appId,
                );
                
                modInfoResult.when(
                  ok: (modInfo) {
                    modTitle = modInfo.title;
                    metadata = ProjectMetadata(
                      modTitle: modInfo.title,
                      modSubscribers: modInfo.subscriptions,
                    );
                    _logger.info('Retrieved mod info: $modTitle');
                  },
                  err: (error) {
                    _logger.warning(
                      'Failed to fetch mod info for ${project.modSteamId}: ${error.message}',
                    );
                    // Fallback to cleaned name
                    modTitle = _cleanModName(project.name);
                    metadata = ProjectMetadata(modTitle: modTitle);
                  },
                );
              } else {
                _logger.warning('No Steam App ID for game installation');
                modTitle = _cleanModName(project.name);
                metadata = ProjectMetadata(modTitle: modTitle);
              }
            } else {
              _logger.warning('Failed to load game installation');
              modTitle = _cleanModName(project.name);
              metadata = ProjectMetadata(modTitle: modTitle);
            }
          } else {
            // No Steam Workshop ID, use cleaned name
            modTitle = _cleanModName(project.name);
            metadata = ProjectMetadata(modTitle: modTitle);
          }
          
          if (metadata != null) {
            // Update project with metadata and possibly new name
            final metadataJson = metadata!.toJsonString();
            final updatedProject = project.copyWith(
              name: modTitle ?? project.name,
              metadata: metadataJson,
              updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            );

            final updateResult = await _projectRepository.update(updatedProject);
            
            if (updateResult.isOk) {
              updatedCount++;
              _logger.info('Successfully migrated project: ${modTitle ?? project.name}');
            } else {
              _logger.error(
                'Failed to migrate project ${project.id}: ${updateResult.error}',
              );
            }
          }
        }
      }

      _logger.info('Metadata migration complete. Updated $updatedCount projects.');
      return updatedCount;
    } catch (e, stackTrace) {
      _logger.error('Unexpected error during metadata migration', e, stackTrace);
      return 0;
    }
  }

  /// Clean up pack file name to make it more readable
  /// Removes leading exclamation marks and formats the name
  String _cleanModName(String name) {
    // Remove leading exclamation marks
    String cleaned = name.replaceAll(RegExp(r'^!+'), '');
    
    // Remove file extension if present
    cleaned = cleaned.replaceAll(RegExp(r'\.(pack|bin)$', caseSensitive: false), '');
    
    // Replace underscores and hyphens with spaces
    cleaned = cleaned.replaceAll(RegExp(r'[_-]'), ' ');
    
    // Trim whitespace
    cleaned = cleaned.trim();
    
    // Capitalize first letter of each word
    if (cleaned.isEmpty) return name;
    
    return cleaned.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Check if any projects need migration
  ///
  /// Returns true if there are projects without metadata.
  Future<bool> hasProjectsNeedingMigration() async {
    try {
      final projectsResult = await _projectRepository.getAll();
      
      if (projectsResult.isErr) {
        return false;
      }

      final projects = projectsResult.value;
      return projects.any((p) => p.metadata == null || p.metadata!.isEmpty);
    } catch (e) {
      _logger.error('Error checking for projects needing migration', e);
      return false;
    }
  }
}

