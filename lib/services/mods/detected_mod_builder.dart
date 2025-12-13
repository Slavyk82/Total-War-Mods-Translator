import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/mod_update_analysis_cache.dart';
import 'package:twmt/models/domain/mod_scan_result.dart';
import 'package:twmt/models/domain/mod_update_status.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/mods/utils/workshop_scan_models.dart';
import 'package:twmt/services/mods/project_analysis_handler.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';

/// Callback type for emitting scan log messages.
typedef ScanLogEmitter = void Function(String message, [ScanLogLevel level]);

/// Builds DetectedMod instances from collected mod data.
///
/// Handles the third phase of Workshop scanning:
/// - Merging local mod data with Steam Workshop metadata
/// - Determining mod update status by comparing timestamps
/// - Triggering project analysis when updates are detected
/// - Building the final list of detected mods
class DetectedModBuilder {
  final WorkshopModRepository _workshopModRepository;
  final ModUpdateAnalysisCacheRepository _analysisCacheRepository;
  final ProjectAnalysisHandler _analysisHandler;
  final LoggingService _logger = LoggingService.instance;

  DetectedModBuilder({
    required WorkshopModRepository workshopModRepository,
    required ModUpdateAnalysisCacheRepository analysisCacheRepository,
    required ProjectAnalysisHandler analysisHandler,
  })  : _workshopModRepository = workshopModRepository,
        _analysisCacheRepository = analysisCacheRepository,
        _analysisHandler = analysisHandler;

  /// Build list of DetectedMod from collected data.
  ///
  /// [modDataList] - Local mod data from pack file scanning
  /// [workshopModsMap] - Workshop metadata from Steam API
  /// [cachedModsMap] - Previous workshop mod state from database
  /// [existingWorkshopIds] - Map of workshop IDs to existing projects
  /// [hiddenWorkshopIds] - Set of workshop IDs that user has hidden
  /// [emitLog] - Optional callback for emitting scan progress messages
  ///
  /// Returns [ModScanResult] with the mods list and whether translation stats changed.
  Future<ModScanResult> buildDetectedMods({
    required List<ModLocalData> modDataList,
    required Map<String, WorkshopMod> workshopModsMap,
    required Map<String, WorkshopMod> cachedModsMap,
    required Map<String, Project> existingWorkshopIds,
    required Set<String> hiddenWorkshopIds,
    ScanLogEmitter? emitLog,
  }) async {
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
      final localFileUpToDate =
          timeUpdated == null || modData.fileLastModified >= timeUpdated;
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
      if (existingProject != null &&
          localFileUpToDate &&
          (hasNewSteamUpdate || analysisCacheInvalid)) {
        if (hasNewSteamUpdate) {
          _logger.info(
              'New Steam update detected for $workshopId, analyzing changes...');
          emitLog?.call('Update detected: $modTitle - analyzing changes...');
        } else {
          _logger.info(
              'Analysis cache invalidated for $workshopId (file re-downloaded), analyzing changes...');
          emitLog?.call('Re-analyzing: $modTitle');
        }
        final analysisResult = await _analysisHandler.analyzeProjectChanges(
          projectId: existingProject.id,
          packFilePath: modData.packFile.path,
          workshopId: workshopId,
          fileLastModified: modData.fileLastModified,
          emitLog: emitLog,
        );
        updateAnalysis = analysisResult.analysis;
        if (analysisResult.statsChanged) {
          translationStatsChanged = true;
        }
        if (updateAnalysis != null && updateAnalysis.hasChanges) {
          emitLog?.call(
              '  -> ${updateAnalysis.newUnitsCount} new, ${updateAnalysis.modifiedUnitsCount} modified, ${updateAnalysis.removedUnitsCount} removed');
        }

        // Only sync timeUpdated AFTER analysis if there are NO changes
        // If there are changes, we wait until they are dismissed by the user
        if (updateAnalysis == null || !updateAnalysis.hasChanges) {
          if (hasNewSteamUpdate) {
            _logger.debug(
                'Syncing timeUpdated for $workshopId (no changes): $cachedTimeUpdated -> $timeUpdated');
            await _workshopModRepository.updateTimeUpdated(
                workshopId, timeUpdated);
          }
        }
      } else if (validCachedAnalysis != null && validCachedAnalysis.hasChanges) {
        // Use cached analysis that still has unprocessed changes
        // This allows showing changes even after timeUpdated was synced
        _logger.debug('Using cached analysis with changes for $workshopId');
        updateAnalysis = validCachedAnalysis.toAnalysis();
      } else if (localFileUpToDate && hasNewSteamUpdate) {
        // No project imported but timestamps differ - just sync the timestamp
        _logger.debug(
            'Syncing timeUpdated for $workshopId (no project): $cachedTimeUpdated -> $timeUpdated');
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
