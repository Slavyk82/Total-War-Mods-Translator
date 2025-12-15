import 'package:uuid/uuid.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/mod_update_analysis_cache.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/mods/mod_update_analysis_service.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';

/// Callback type for emitting scan log messages.
typedef ScanLogEmitter = void Function(String message, [ScanLogLevel level]);

/// Result of analyzing a project for changes.
class ProjectAnalysisResult {
  final ModUpdateAnalysis? analysis;
  final bool statsChanged;

  const ProjectAnalysisResult({this.analysis, this.statsChanged = false});
}

/// Handles project change analysis during Workshop scanning.
///
/// Analyzes changes between mod pack files and existing project translations:
/// - Detects new, modified, and removed translation units
/// - Auto-applies changes (adds new units, updates source texts, marks obsolete)
/// - Manages analysis cache for efficient future scans
class ProjectAnalysisHandler {
  final ProjectRepository _projectRepository;
  final ModUpdateAnalysisCacheRepository _analysisCacheRepository;
  final ModUpdateAnalysisService _modUpdateAnalysisService;
  final LoggingService _logger = LoggingService.instance;
  final Uuid _uuid = const Uuid();

  ProjectAnalysisHandler({
    required ProjectRepository projectRepository,
    required ModUpdateAnalysisCacheRepository analysisCacheRepository,
    required ModUpdateAnalysisService modUpdateAnalysisService,
  })  : _projectRepository = projectRepository,
        _analysisCacheRepository = analysisCacheRepository,
        _modUpdateAnalysisService = modUpdateAnalysisService;

  /// Analyze changes for an existing project.
  ///
  /// Uses cached analysis results when the pack file hasn't changed.
  /// Only performs expensive TSV extraction when the mod has been updated.
  ///
  /// When modified source texts are detected, this method automatically:
  /// 1. Updates the source_text in translation_units
  /// 2. Resets the status to 'pending' for all affected translation versions
  ///
  /// Returns [ProjectAnalysisResult] with the analysis and whether stats changed.
  Future<ProjectAnalysisResult> analyzeProjectChanges({
    required String projectId,
    required String packFilePath,
    required String workshopId,
    required int fileLastModified,
    ScanLogEmitter? emitLog,
  }) async {
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
          return ProjectAnalysisResult(analysis: cachedAnalysis.toAnalysis());
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
          emitLog?.call('  Adding ${analysis.newUnitsCount} new units...');
          _logger.info(
            'Auto-adding ${analysis.newUnitsCount} new units for project $projectId',
          );
          final addResult = await _modUpdateAnalysisService.addNewUnits(
            projectId: projectId,
            analysis: analysis,
            onProgress: (processed, total) {
              emitLog?.call('  Adding new units: $processed/$total');
            },
          );
          if (addResult.isOk && addResult.value > 0) {
            emitLog?.call('  [OK] Added ${addResult.value} new units');
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
          emitLog?.call(
              '  Updating ${analysis.modifiedUnitsCount} modified units...');
          _logger.info(
            'Auto-applying ${analysis.modifiedUnitsCount} source text changes for project $projectId',
          );
          final applyResult =
              await _modUpdateAnalysisService.applyModifiedSourceTexts(
            projectId: projectId,
            analysis: analysis,
            onProgress: (processed, total, phase) {
              emitLog?.call('  $phase: $processed/$total');
            },
          );
          if (applyResult.isOk) {
            final result = applyResult.value;
            emitLog?.call(
                '  [OK] Updated ${result.sourceTextsUpdated} source texts');
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
          emitLog?.call(
              '  Marking ${analysis.removedUnitsCount} removed units as obsolete...');
          _logger.info(
            'Auto-marking ${analysis.removedUnitsCount} removed units as obsolete for project $projectId',
          );
          final removeResult =
              await _modUpdateAnalysisService.markRemovedUnitsObsolete(
            projectId: projectId,
            analysis: analysis,
            onProgress: (processed, total) {
              emitLog?.call('  Marking obsolete: $processed/$total');
            },
          );
          if (removeResult.isOk && removeResult.value > 0) {
            emitLog
                ?.call('  [OK] Marked ${removeResult.value} units as obsolete');
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
          emitLog?.call(
              '  Reactivating ${analysis.reactivatedUnitsCount} units...');
          _logger.info(
            'Auto-reactivating ${analysis.reactivatedUnitsCount} obsolete units for project $projectId',
          );
          final reactivateResult =
              await _modUpdateAnalysisService.reactivateObsoleteUnits(
            projectId: projectId,
            analysis: analysis,
            onProgress: (processed, total) {
              emitLog?.call('  Reactivating: $processed/$total');
            },
          );
          if (reactivateResult.isOk) {
            final result = reactivateResult.value;
            if (result.unitsReactivated > 0) {
              emitLog
                  ?.call('  [OK] Reactivated ${result.unitsReactivated} units');
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

        // Set mod update impact flag on project if changes were applied
        // This allows users to filter for projects that were affected by mod updates
        if (statsChanged) {
          final flagResult =
              await _projectRepository.setModUpdateImpact(projectId, true);
          if (flagResult.isErr) {
            _logger.warning(
              'Failed to set mod update impact flag: ${flagResult.error.message}',
            );
          }
        }

        // Cache the result - but with zeroed counts if changes were applied
        // This prevents stale "pending changes" badges after changes are processed
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final analysisToCache = statsChanged
            ? ModUpdateAnalysis.empty // Changes applied, cache as "no changes"
            : analysis; // No changes applied (or failed), cache original analysis
        final cacheEntry = ModUpdateAnalysisCache.fromAnalysis(
          id: _uuid.v4(),
          projectId: projectId,
          packFilePath: packFilePath,
          fileLastModified: fileLastModified,
          analysis: analysisToCache,
          analyzedAt: now,
        );
        await _analysisCacheRepository.upsert(cacheEntry);
        return ProjectAnalysisResult(
            analysis: analysis, statsChanged: statsChanged);
      },
      err: (error) {
        _logger.warning(
            'Failed to analyze changes for $workshopId: ${error.message}');
        return const ProjectAnalysisResult();
      },
    );
  }
}
