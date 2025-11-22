import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/mod_update_info.dart';
import 'package:twmt/models/domain/mod_version.dart';
import 'package:twmt/repositories/mod_version_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/mods/i_mod_update_service.dart';
import 'package:twmt/services/steam/i_steam_workshop_service.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/steam/models/workshop_item_update.dart';

/// Implementation of mod update tracking service.
///
/// Integrates with Steam Workshop API to detect mod updates and manages
/// version tracking in the database.
class ModUpdateServiceImpl implements IModUpdateService {
  final ISteamWorkshopService _workshopService;
  final ProjectRepository _projectRepository;
  final ModVersionRepository _modVersionRepository;
  final LoggingService _logger = LoggingService.instance;
  final Uuid _uuid = const Uuid();

  ModUpdateServiceImpl({
    required ISteamWorkshopService workshopService,
    required ProjectRepository projectRepository,
    required ModVersionRepository modVersionRepository,
  })  : _workshopService = workshopService,
        _projectRepository = projectRepository,
        _modVersionRepository = modVersionRepository;

  @override
  Future<Result<List<ModUpdateInfo>, ServiceException>>
      checkAllModsForUpdates() async {
    try {
      _logger.info('Checking all mods for updates');

      // Get all projects
      final projectsResult = await _projectRepository.getAll();
      if (projectsResult is Err) {
        return Err(ServiceException(
          'Failed to fetch projects',
          error: projectsResult.error,
        ));
      }

      final projects = projectsResult.value;

      // Filter projects with Steam Workshop IDs
      final steamProjects = projects
          .where((p) => p.modSteamId != null && p.modSteamId!.isNotEmpty)
          .toList();

      if (steamProjects.isEmpty) {
        _logger.info('No projects with Steam Workshop IDs found');
        return const Ok([]);
      }

      _logger.info('Found ${steamProjects.length} Steam Workshop projects');

      // Build map of workshop IDs to last known update times
      final workshopIdsMap = <String, DateTime>{};

      for (final project in steamProjects) {
        final currentVersionResult =
            await _modVersionRepository.getCurrent(project.id);

        if (currentVersionResult is Ok) {
          final currentVersion = currentVersionResult.value;
          final updateTime = currentVersion.steamUpdateAsDateTime;

          if (updateTime != null) {
            workshopIdsMap[project.modSteamId!] = updateTime;
          }
        }
      }

      if (workshopIdsMap.isEmpty) {
        _logger.warning(
            'No projects have Steam update timestamps in their current versions');
        return const Ok([]);
      }

      // Check for updates via Steam Workshop API
      final updatesResult = await _workshopService.checkForUpdates(
        workshopIds: workshopIdsMap,
      );

      if (updatesResult is Err) {
        return Err(ServiceException(
          'Failed to check Steam Workshop for updates',
          error: updatesResult.error,
        ));
      }

      final workshopUpdates = updatesResult.value;

      // Build ModUpdateInfo list
      final updateInfoList = <ModUpdateInfo>[];

      for (final project in steamProjects) {
        WorkshopItemUpdate? workshopUpdate;
        try {
          workshopUpdate = workshopUpdates.firstWhere(
            (u) => u.workshopId == project.modSteamId,
          );
        } catch (_) {
          // No matching workshop update found, skip this project
          continue;
        }

        final currentVersionResult =
            await _modVersionRepository.getCurrent(project.id);

        if (currentVersionResult is Err) {
          continue;
        }

        final currentVersion = currentVersionResult.value;

        final updateInfo = ModUpdateInfo(
          projectId: project.id,
          modName: project.name,
          currentVersionId: currentVersion.id,
          currentVersionString: currentVersion.versionString,
          latestVersionId: workshopUpdate.hasUpdate ? null : currentVersion.id,
          latestVersionString: workshopUpdate.hasUpdate
              ? _generateVersionString(workshopUpdate.latestUpdate)
              : currentVersion.versionString,
          updateAvailableDate: workshopUpdate.latestUpdate,
          hasUpdate: workshopUpdate.hasUpdate,
          affectedTranslations: 0,
        );

        updateInfoList.add(updateInfo);
      }

      _logger.info(
          'Update check complete: ${updateInfoList.where((u) => u.hasUpdate).length}/${updateInfoList.length} have updates');

      return Ok(updateInfoList);
    } catch (e, stackTrace) {
      return Err(ServiceException(
        'Failed to check all mods for updates: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<ModUpdateInfo, ServiceException>> checkModForUpdate({
    required String projectId,
  }) async {
    try {
      _logger.info('Checking mod for update: $projectId');

      // Get project
      final projectResult = await _projectRepository.getById(projectId);
      if (projectResult is Err) {
        return Err(ServiceException(
          'Project not found',
          error: projectResult.error,
        ));
      }

      final project = projectResult.value;

      // Verify project has Steam Workshop ID
      if (project.modSteamId == null || project.modSteamId!.isEmpty) {
        return Err(const ServiceException(
          'Project does not have a Steam Workshop ID',
        ));
      }

      // Get current version
      final currentVersionResult =
          await _modVersionRepository.getCurrent(projectId);
      if (currentVersionResult is Err) {
        return Err(ServiceException(
          'Current version not found for project',
          error: currentVersionResult.error,
        ));
      }

      final currentVersion = currentVersionResult.value;
      final lastKnownUpdate = currentVersion.steamUpdateAsDateTime;

      if (lastKnownUpdate == null) {
        return Err(const ServiceException(
          'Current version does not have a Steam update timestamp',
        ));
      }

      // Check Workshop for latest update
      final workshopDetailsResult = await _workshopService.getWorkshopItemDetails(
        workshopId: project.modSteamId!,
      );

      if (workshopDetailsResult is Err) {
        return Err(ServiceException(
          'Failed to fetch Workshop item details',
          error: workshopDetailsResult.error,
        ));
      }

      final workshopDetails = workshopDetailsResult.value;
      final hasUpdate = workshopDetails.timeUpdated.isAfter(lastKnownUpdate);

      final updateInfo = ModUpdateInfo(
        projectId: project.id,
        modName: project.name,
        currentVersionId: currentVersion.id,
        currentVersionString: currentVersion.versionString,
        latestVersionId: hasUpdate ? null : currentVersion.id,
        latestVersionString: hasUpdate
            ? _generateVersionString(workshopDetails.timeUpdated)
            : currentVersion.versionString,
        updateAvailableDate: workshopDetails.timeUpdated,
        hasUpdate: hasUpdate,
        affectedTranslations: 0,
      );

      if (hasUpdate) {
        _logger.info('Update available for ${project.name}');
      } else {
        _logger.info('No update available for ${project.name}');
      }

      return Ok(updateInfo);
    } catch (e, stackTrace) {
      return Err(ServiceException(
        'Failed to check mod for update: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<void, ServiceException>> trackModUpdate({
    required String projectId,
    required String newVersionString,
  }) async {
    try {
      _logger.info('Tracking mod update for project: $projectId');

      // Get project
      final projectResult = await _projectRepository.getById(projectId);
      if (projectResult is Err) {
        return Err(ServiceException(
          'Project not found',
          error: projectResult.error,
        ));
      }

      final project = projectResult.value;

      // Get Workshop details for latest timestamp
      if (project.modSteamId == null || project.modSteamId!.isEmpty) {
        return Err(const ServiceException(
          'Project does not have a Steam Workshop ID',
        ));
      }

      final workshopDetailsResult = await _workshopService.getWorkshopItemDetails(
        workshopId: project.modSteamId!,
      );

      if (workshopDetailsResult is Err) {
        return Err(ServiceException(
          'Failed to fetch Workshop details',
          error: workshopDetailsResult.error,
        ));
      }

      final workshopDetails = workshopDetailsResult.value;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Create new mod version
      final newVersion = ModVersion(
        id: _uuid.v4(),
        projectId: projectId,
        versionString: newVersionString,
        releaseDate: workshopDetails.timeUpdated.millisecondsSinceEpoch ~/ 1000,
        steamUpdateTimestamp:
            workshopDetails.timeUpdated.millisecondsSinceEpoch ~/ 1000,
        unitsAdded: 0,
        unitsModified: 0,
        unitsDeleted: 0,
        isCurrent: false,
        detectedAt: now,
      );

      // Insert new version
      final insertResult = await _modVersionRepository.insert(newVersion);
      if (insertResult is Err) {
        return Err(ServiceException(
          'Failed to insert new mod version',
          error: insertResult.error,
        ));
      }

      // Mark new version as current
      final markCurrentResult =
          await _modVersionRepository.markAsCurrent(newVersion.id);
      if (markCurrentResult is Err) {
        return Err(ServiceException(
          'Failed to mark new version as current',
          error: markCurrentResult.error,
        ));
      }

      // Update project's source_mod_updated timestamp
      final updatedProject = project.copyWith(
        sourceModUpdated: now,
        lastUpdateCheck: now,
        updatedAt: now,
      );

      final updateProjectResult =
          await _projectRepository.update(updatedProject);
      if (updateProjectResult is Err) {
        return Err(ServiceException(
          'Failed to update project timestamps',
          error: updateProjectResult.error,
        ));
      }

      _logger.info(
          'Successfully tracked mod update: ${project.name} -> $newVersionString');

      return const Ok(null);
    } catch (e, stackTrace) {
      return Err(ServiceException(
        'Failed to track mod update: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<List<ModUpdateInfo>, ServiceException>>
      getPendingUpdates() async {
    try {
      _logger.info('Getting pending updates');

      final allUpdatesResult = await checkAllModsForUpdates();
      if (allUpdatesResult is Err) {
        return allUpdatesResult;
      }

      final allUpdates = allUpdatesResult.value;
      final pendingUpdates =
          allUpdates.where((update) => update.hasUpdate).toList();

      _logger.info('Found ${pendingUpdates.length} pending updates');

      return Ok(pendingUpdates);
    } catch (e, stackTrace) {
      return Err(ServiceException(
        'Failed to get pending updates: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Generate a version string from a DateTime timestamp.
  ///
  /// Format: YYYY.MM.DD (e.g., 2024.12.25)
  String _generateVersionString(DateTime timestamp) {
    return '${timestamp.year}.${timestamp.month.toString().padLeft(2, '0')}.${timestamp.day.toString().padLeft(2, '0')}';
  }
}
