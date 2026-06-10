import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:twmt/features/activity/models/activity_event.dart';
import 'package:twmt/features/activity/services/activity_logger.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/file/i_localization_parser.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

/// Data for a unit extracted from pack file
class _PackUnitData {
  final String key;
  final String sourceText;
  final String? sourceLocFile;

  const _PackUnitData({
    required this.key,
    required this.sourceText,
    this.sourceLocFile,
  });
}

/// Result of applying mod update changes
class ModUpdateApplyResult {
  /// Number of source texts updated in translation units
  final int sourceTextsUpdated;

  /// Number of translation versions reset to pending status
  final int translationsReset;

  const ModUpdateApplyResult({
    required this.sourceTextsUpdated,
    required this.translationsReset,
  });
}

/// Service for analyzing changes between a mod's pack file and existing project translations
class ModUpdateAnalysisService {
  final IRpfmService _rpfmService;
  final ILocalizationParser _locParser;
  final TranslationUnitRepository _unitRepository;
  final TranslationVersionRepository _versionRepository;
  final ProjectLanguageRepository _languageRepository;
  final ILoggingService _logger;
  final Uuid _uuid = const Uuid();

  /// Optional fire-and-forget activity logger for the Home dashboard feed.
  /// Resolved from [ServiceLocator] when not supplied explicitly; remains
  /// `null` if the locator has not been initialized (e.g. unit tests that
  /// construct the service directly without a full locator).
  final ActivityLogger? _activityLogger;

  ModUpdateAnalysisService({
    required IRpfmService rpfmService,
    required ILocalizationParser locParser,
    required TranslationUnitRepository unitRepository,
    required TranslationVersionRepository versionRepository,
    required ProjectLanguageRepository languageRepository,
    ILoggingService? logger,
    ActivityLogger? activityLogger,
  }) : _rpfmService = rpfmService,
       _locParser = locParser,
       _unitRepository = unitRepository,
       _versionRepository = versionRepository,
       _languageRepository = languageRepository,
       _logger = logger ?? ServiceLocator.get<ILoggingService>(),
       _activityLogger = activityLogger ?? _tryResolveActivityLogger();

  /// Best-effort lookup for the shared [ActivityLogger].
  ///
  /// Returns `null` if the [ServiceLocator] has not been initialized
  /// or the logger is not registered — keeping this service usable
  /// in unit tests that never call [ServiceLocator.initialize].
  static ActivityLogger? _tryResolveActivityLogger() {
    try {
      if (!ServiceLocator.isRegistered<ActivityLogger>()) return null;
      return ServiceLocator.get<ActivityLogger>();
    } catch (_) {
      return null;
    }
  }

  /// Analyze changes between pack file and existing project translations
  ///
  /// Returns analysis of:
  /// - New keys added in the pack
  /// - Keys removed from the pack
  /// - Keys with modified source text
  /// - Obsolete keys that reappeared in the pack
  Future<Result<ModUpdateAnalysis, ServiceException>> analyzeChanges({
    required String projectId,
    required String packFilePath,
  }) async {
    try {
      // Step 1: Get existing active translation units from database
      final existingUnitsResult = await _unitRepository.getActive(projectId);
      if (existingUnitsResult.isErr) {
        return Err(
          ServiceException(
            'Failed to get existing translation units: ${existingUnitsResult.error}',
          ),
        );
      }

      final existingUnits = existingUnitsResult.value;
      final existingUnitsMap = <String, TranslationUnit>{};
      for (final unit in existingUnits) {
        existingUnitsMap[unit.key] = unit;
      }

      // Step 1b: Get obsolete translation units from database
      final obsoleteUnitsResult = await _unitRepository.getObsolete(projectId);
      if (obsoleteUnitsResult.isErr) {
        return Err(
          ServiceException(
            'Failed to get obsolete translation units: ${obsoleteUnitsResult.error}',
          ),
        );
      }

      final obsoleteUnits = obsoleteUnitsResult.value;
      final obsoleteUnitsMap = <String, TranslationUnit>{};
      for (final unit in obsoleteUnits) {
        obsoleteUnitsMap[unit.key] = unit;
      }

      // Step 2: Extract and parse pack file
      final packUnitsResult = await _extractPackUnits(packFilePath);
      if (packUnitsResult.isErr) {
        return Err(packUnitsResult.error);
      }

      final packUnits = packUnitsResult.value;

      // Step 3: Compare and analyze
      final newUnitKeys = <String>[];
      final newUnitsData = <NewUnitData>[];
      final modifiedUnitKeys = <String>[];
      final modifiedSourceTexts = <String, String>{};
      final reactivatedUnitKeys = <String>[];
      final reactivatedSourceTexts = <String, String>{};
      final packKeys = <String>{};

      for (final unitData in packUnits) {
        final key = unitData.key;
        final packSourceText = unitData.sourceText;
        packKeys.add(key);

        final existingUnit = existingUnitsMap[key];
        final obsoleteUnit = obsoleteUnitsMap[key];

        if (existingUnit != null) {
          // Unit exists and is active
          if (existingUnit.sourceText != packSourceText) {
            // Modified source text
            modifiedUnitKeys.add(key);
            modifiedSourceTexts[key] = packSourceText;
          }
        } else if (obsoleteUnit != null) {
          // Unit was obsolete but reappeared in pack - needs reactivation
          reactivatedUnitKeys.add(key);
          reactivatedSourceTexts[key] = packSourceText;
        } else {
          // Truly new key - collect complete data
          newUnitKeys.add(key);
          newUnitsData.add(
            NewUnitData(
              key: key,
              sourceText: packSourceText,
              sourceLocFile: unitData.sourceLocFile,
            ),
          );
        }
      }

      // Collect removed units (exist in project but not in pack)
      final removedUnitKeys = <String>[];
      for (final key in existingUnitsMap.keys) {
        if (!packKeys.contains(key)) {
          removedUnitKeys.add(key);
        }
      }

      final analysis = ModUpdateAnalysis(
        newUnitsCount: newUnitKeys.length,
        removedUnitsCount: removedUnitKeys.length,
        modifiedUnitsCount: modifiedUnitKeys.length,
        reactivatedUnitsCount: reactivatedUnitKeys.length,
        totalPackUnits: packUnits.length,
        totalProjectUnits: existingUnits.length,
        newUnitKeys: newUnitKeys,
        newUnitsData: newUnitsData,
        removedUnitKeys: removedUnitKeys,
        modifiedUnitKeys: modifiedUnitKeys,
        modifiedSourceTexts: modifiedSourceTexts,
        reactivatedUnitKeys: reactivatedUnitKeys,
        reactivatedSourceTexts: reactivatedSourceTexts,
      );

      // Log analysis results for debugging
      if (analysis.hasChanges) {
        _logger.info(
          'ModUpdateAnalysis for project $projectId: '
          '+${analysis.newUnitsCount} new, -${analysis.removedUnitsCount} removed, '
          '~${analysis.modifiedUnitsCount} modified, ↩${analysis.reactivatedUnitsCount} reactivated '
          '(pack: ${packUnits.length}, project: ${existingUnits.length})',
        );
        _activityLogger?.log(
          ActivityEventType.modUpdatesDetected,
          projectId: projectId,
          gameCode: null,
          payload: {
            'count':
                analysis.newUnitsCount +
                analysis.modifiedUnitsCount +
                analysis.reactivatedUnitsCount,
          },
        );
      }

      return Ok(analysis);
    } catch (e, stackTrace) {
      _logger.error('Failed to analyze mod changes', e, stackTrace);
      return Err(
        ServiceException(
          'Failed to analyze mod changes: $e',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Extract all translation units from a pack file
  Future<Result<List<_PackUnitData>, ServiceException>> _extractPackUnits(
    String packFilePath,
  ) async {
    // Extract .loc files as TSV
    final extractResult = await _rpfmService.extractLocalizationFilesAsTsv(
      packFilePath,
    );

    if (extractResult.isErr) {
      return Err(
        ServiceException(
          'Failed to extract .loc files: ${extractResult.error}',
        ),
      );
    }

    final extraction = extractResult.value;
    final locFiles = extraction.extractedFiles;

    // RPFM always creates the extraction temp directory (even when it yields
    // zero TSV files), so cleanup must run on every path — including the empty
    // early return below. A try/finally guarantees the directory is deleted
    // instead of leaking one rpfm_extract_* dir per re-scan.
    try {
      if (locFiles.isEmpty) {
        return const Ok([]);
      }

      final allUnits = <_PackUnitData>[];
      final seenKeys = <String>{};

      // Parse each TSV file
      for (final tsvFilePath in locFiles) {
        final parseResult = await _locParser.parseFile(
          filePath: tsvFilePath,
          encoding: 'utf-8',
        );

        if (parseResult.isErr) {
          continue;
        }

        // Extract the original .loc file path relative to extraction directory
        // TSV path: C:\temp\rpfm_extract_xxx\text\db\something.loc.tsv
        // Extraction dir: C:\temp\rpfm_extract_xxx
        // Result: text/db/something.loc
        String sourceLocFile = tsvFilePath
            .replaceAll('\\', '/')
            .replaceFirst(
              '${extraction.outputDirectory.replaceAll('\\', '/')}/',
              '',
            );

        // Remove .tsv extension to get the original .loc path
        if (sourceLocFile.endsWith('.tsv')) {
          sourceLocFile = sourceLocFile.substring(0, sourceLocFile.length - 4);
        }

        final locFile = parseResult.value;
        for (final entry in locFile.entries) {
          // Avoid duplicates (same key from different loc files)
          if (!seenKeys.contains(entry.key)) {
            seenKeys.add(entry.key);
            allUnits.add(
              _PackUnitData(
                key: entry.key,
                sourceText: entry.value,
                sourceLocFile: sourceLocFile,
              ),
            );
          }
        }
      }

      return Ok(allUnits);
    } finally {
      // Clean up extraction directory on every exit path.
      try {
        final extractionDir = Directory(extraction.outputDirectory);
        if (await extractionDir.exists()) {
          await extractionDir.delete(recursive: true);
        }
      } catch (e) {
        // Non-critical - cleanup can fail without issue
      }
    }
  }

  /// Apply changes from a mod update analysis to the project.
  ///
  /// For modified units (source text changed):
  /// 1. Updates the source_text in translation_units table
  /// 2. Resets the status to 'pending' for ALL translation versions (all languages)
  ///
  /// This ensures that translators will review units where the source changed.
  ///
  /// Note: This method does NOT handle new or removed units - those require
  /// a full re-import process.
  ///
  /// [projectId] - The project to update
  /// [analysis] - The analysis result containing modified keys and new source texts
  /// [onProgress] - Optional callback for progress reporting (processed, total, phase)
  ///
  /// Returns [ModUpdateApplyResult] with counts of affected records.
  Future<Result<ModUpdateApplyResult, ServiceException>>
  applyModifiedSourceTexts({
    required String projectId,
    required ModUpdateAnalysis analysis,
    void Function(int processed, int total, String phase)? onProgress,
  }) async {
    try {
      if (!analysis.hasModifiedUnits) {
        return Ok(
          const ModUpdateApplyResult(
            sourceTextsUpdated: 0,
            translationsReset: 0,
          ),
        );
      }

      _logger.info(
        'Applying ${analysis.modifiedUnitsCount} source text changes for project $projectId',
      );

      final total = analysis.modifiedUnitsCount;

      // These two writes are not wrapped in a single transaction (the repo
      // helpers each autocommit), so ORDER matters for crash-safety. We reset
      // the version statuses FIRST and update the source texts SECOND.
      //
      // If the second step fails or the process crashes between them, the
      // units keep their OLD source_text, so the next Workshop scan still
      // detects them as modified and re-applies both steps — the operation is
      // self-healing. The reverse order (source first) would update
      // source_text, making the unit no longer look "modified", so a failed
      // status reset would never re-run, leaving a permanent inconsistency.

      // Step 1: Reset status to pending for all translation versions of modified units
      final resetResult = await _versionRepository.resetStatusForUnitKeys(
        projectId: projectId,
        unitKeys: analysis.modifiedUnitKeys,
        onProgress: onProgress != null
            ? (processed, batchTotal) =>
                  onProgress(processed, total, 'Resetting translations')
            : null,
      );

      if (resetResult.isErr) {
        return Err(
          ServiceException(
            'Failed to reset translation statuses: ${resetResult.error}',
          ),
        );
      }

      final translationsReset = resetResult.value;

      // Step 2: Update source texts in translation_units (last, so a failure
      // here leaves the units still detectable as modified for a retry).
      final updateResult = await _unitRepository.updateSourceTexts(
        projectId: projectId,
        sourceTextUpdates: analysis.modifiedSourceTexts,
        onProgress: onProgress != null
            ? (processed, batchTotal) =>
                  onProgress(processed, total, 'Updating source texts')
            : null,
      );

      if (updateResult.isErr) {
        return Err(
          ServiceException(
            'Failed to update source texts: ${updateResult.error}',
          ),
        );
      }

      final sourceTextsUpdated = updateResult.value;

      _logger.info(
        'Applied mod update: $sourceTextsUpdated source texts updated, '
        '$translationsReset translation versions reset to pending',
      );

      return Ok(
        ModUpdateApplyResult(
          sourceTextsUpdated: sourceTextsUpdated,
          translationsReset: translationsReset,
        ),
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to apply mod update changes', e, stackTrace);
      return Err(
        ServiceException(
          'Failed to apply mod update changes: $e',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Add new translation units from a mod update.
  ///
  /// For new units (present in pack but not in project):
  /// 1. Creates TranslationUnit records with the source text
  /// 2. Creates TranslationVersion records for each project language with status 'pending'
  ///
  /// [projectId] - The project to add units to
  /// [analysis] - The analysis result containing new unit data
  /// [onProgress] - Optional callback for progress reporting (processed, total)
  ///
  /// Returns the count of new units added.
  Future<Result<int, ServiceException>> addNewUnits({
    required String projectId,
    required ModUpdateAnalysis analysis,
    void Function(int processed, int total)? onProgress,
  }) async {
    try {
      if (!analysis.hasNewUnits || analysis.newUnitsData.isEmpty) {
        return Ok(0);
      }

      _logger.info(
        'Adding ${analysis.newUnitsCount} new units for project $projectId',
      );

      // Get project languages for creating translation versions
      final languagesResult = await _languageRepository.getByProject(projectId);
      if (languagesResult.isErr) {
        return Err(
          ServiceException(
            'Failed to get project languages: ${languagesResult.error}',
          ),
        );
      }

      final languages = languagesResult.value;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Fetch existing keys ONCE rather than a getByKey SELECT per unit.
      // analysis already classified these as new; this single query is a
      // defensive de-dup that also avoids N round-trips on the UI isolate.
      final existingResult = await _unitRepository.getByProject(projectId);
      if (existingResult.isErr) {
        return Err(
          ServiceException(
            'Failed to load existing units: ${existingResult.error}',
          ),
        );
      }
      final existingKeys = existingResult.value.map((u) => u.key).toSet();

      // Build the units to insert, skipping keys that already exist or repeat
      // within the incoming batch.
      final unitsToInsert = <TranslationUnit>[];
      final seenKeys = <String>{};
      for (final newUnit in analysis.newUnitsData) {
        if (existingKeys.contains(newUnit.key) || !seenKeys.add(newUnit.key)) {
          _logger.debug('Unit already exists, skipping: ${newUnit.key}');
          continue;
        }
        unitsToInsert.add(
          TranslationUnit(
            id: _uuid.v4(),
            projectId: projectId,
            key: newUnit.key,
            sourceText: newUnit.sourceText,
            context: null,
            notes: null,
            sourceLocFile: newUnit.sourceLocFile,
            isObsolete: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      if (unitsToInsert.isEmpty) {
        _logger.info('No genuinely-new units to add for project $projectId');
        return Ok(0);
      }

      final total = unitsToInsert.length;

      // Insert every new unit and its per-language versions in a SINGLE
      // transaction (one commit — previously each unit ran its own getByKey
      // SELECT plus its own transaction, N+1 round-trips that made large-mod
      // scans crawl on the UI isolate), but isolate each unit behind a
      // SAVEPOINT. A failing insert rolls back ONLY that unit's writes (so the
      // view-cache invariant "every unit has a full version set" holds); the
      // unit is logged, skipped, and not counted, and the rest of the batch
      // still commits. This is the contract pinned by
      // test/integration/add_new_units_transaction_test.dart.
      const savepoint = 'sp_add_new_unit';
      int added;
      try {
        added = await DatabaseService.transaction<int>((txn) async {
          var inserted = 0;
          var processed = 0;
          var lastReportedProgress = 0;
          const progressReportInterval = 100;
          for (final unit in unitsToInsert) {
            await txn.execute('SAVEPOINT $savepoint');
            try {
              await txn.insert(
                'translation_units',
                unit.toJson(),
                conflictAlgorithm: ConflictAlgorithm.abort,
              );

              for (final language in languages) {
                final version = TranslationVersion(
                  id: _uuid.v4(),
                  unitId: unit.id,
                  projectLanguageId: language.id,
                  translatedText: null,
                  isManuallyEdited: false,
                  status: TranslationVersionStatus.pending,
                  validationIssues: null,
                  createdAt: now,
                  updatedAt: now,
                );

                await txn.insert(
                  'translation_versions',
                  version.toJson(),
                  conflictAlgorithm: ConflictAlgorithm.abort,
                );
              }

              await txn.execute('RELEASE SAVEPOINT $savepoint');
              inserted++;
            } catch (e) {
              // Roll back only this unit's writes and keep going. NOTE: the
              // rollback MUST go through rawQuery, not execute — sqflite's
              // getSqlInTransactionArgument treats any statement starting
              // with "rollback" (including ROLLBACK TO SAVEPOINT) as leaving
              // the outer transaction, which corrupts its bookkeeping.
              // rawQuery skips that SQL sniffing.
              await txn.rawQuery('ROLLBACK TO SAVEPOINT $savepoint');
              await txn.execute('RELEASE SAVEPOINT $savepoint');
              _logger.warning(
                'Failed to insert new unit and its versions, rolled back: '
                '${unit.key} ($e)',
              );
            }

            processed++;
            if (onProgress != null &&
                (processed - lastReportedProgress >= progressReportInterval ||
                    processed == total)) {
              onProgress(processed, total);
              lastReportedProgress = processed;
            }
          }
          return inserted;
        });
      } catch (e, stackTrace) {
        // Whole-batch failure (BEGIN/COMMIT or a savepoint rollback itself
        // failed): everything was rolled back.
        _logger.error('Failed to insert new units, rolled back', e, stackTrace);
        return Err(
          ServiceException(
            'Failed to add new units: $e',
            error: e,
            stackTrace: stackTrace,
          ),
        );
      }

      if (added < total) {
        _logger.warning(
          'Added $added of $total new units for project $projectId '
          '(${total - added} skipped after per-unit rollback)',
        );
      } else {
        _logger.info('Added $added new units for project $projectId');
      }
      return Ok(added);
    } catch (e, stackTrace) {
      _logger.error('Failed to add new units', e, stackTrace);
      return Err(
        ServiceException(
          'Failed to add new units: $e',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Mark removed translation units as obsolete.
  ///
  /// For units that exist in the project but no longer in the mod pack:
  /// - Marks them as obsolete (soft delete) to preserve translation history
  /// - Obsolete units are excluded from active translation workflows
  ///
  /// [projectId] - The project containing the units
  /// [analysis] - The analysis result containing removed unit keys
  /// [onProgress] - Optional callback for progress reporting (processed, total)
  ///
  /// Returns the count of units marked as obsolete.
  Future<Result<int, ServiceException>> markRemovedUnitsObsolete({
    required String projectId,
    required ModUpdateAnalysis analysis,
    void Function(int processed, int total)? onProgress,
  }) async {
    try {
      if (!analysis.hasRemovedUnits) {
        return Ok(0);
      }

      _logger.info(
        'Marking ${analysis.removedUnitsCount} units as obsolete for project $projectId',
      );

      final result = await _unitRepository.markObsoleteByKeys(
        projectId: projectId,
        keys: analysis.removedUnitKeys,
        onProgress: onProgress,
      );

      if (result.isErr) {
        return Err(
          ServiceException('Failed to mark units as obsolete: ${result.error}'),
        );
      }

      final unitsMarked = result.value;
      _logger.info(
        'Marked $unitsMarked units as obsolete for project $projectId',
      );
      return Ok(unitsMarked);
    } catch (e, stackTrace) {
      _logger.error('Failed to mark removed units as obsolete', e, stackTrace);
      return Err(
        ServiceException(
          'Failed to mark removed units as obsolete: $e',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Reactivate obsolete translation units that reappeared in the mod.
  ///
  /// For units that were previously marked obsolete but now exist in the pack:
  /// - Reactivates them (sets is_obsolete = false)
  /// - Updates their source text to the new value
  /// - Sets all translation versions to needsReview status
  ///
  /// [projectId] - The project containing the units
  /// [analysis] - The analysis result containing reactivated unit data
  /// [onProgress] - Optional callback for progress reporting (processed, total)
  ///
  /// Returns a record with counts of units reactivated and translations marked for review.
  Future<
    Result<
      ({int unitsReactivated, int translationsMarkedForReview}),
      ServiceException
    >
  >
  reactivateObsoleteUnits({
    required String projectId,
    required ModUpdateAnalysis analysis,
    void Function(int processed, int total)? onProgress,
  }) async {
    try {
      if (!analysis.hasReactivatedUnits) {
        return Ok((unitsReactivated: 0, translationsMarkedForReview: 0));
      }

      _logger.info(
        'Reactivating ${analysis.reactivatedUnitsCount} obsolete units for project $projectId',
      );

      // Step 1: Reactivate units and update source texts
      final reactivateResult = await _unitRepository.reactivateByKeys(
        projectId: projectId,
        sourceTextUpdates: analysis.reactivatedSourceTexts,
        onProgress: onProgress,
      );

      if (reactivateResult.isErr) {
        return Err(
          ServiceException(
            'Failed to reactivate units: ${reactivateResult.error}',
          ),
        );
      }

      final unitsReactivated = reactivateResult.value;

      // Step 2: Set status to needsReview for all translation versions
      final reviewResult = await _versionRepository.setNeedsReviewForUnitKeys(
        projectId: projectId,
        unitKeys: analysis.reactivatedUnitKeys,
      );

      if (reviewResult.isErr) {
        return Err(
          ServiceException(
            'Failed to set translations to needsReview: ${reviewResult.error}',
          ),
        );
      }

      final translationsMarkedForReview = reviewResult.value;

      _logger.info(
        'Reactivated $unitsReactivated units, marked $translationsMarkedForReview translations for review',
      );

      return Ok((
        unitsReactivated: unitsReactivated,
        translationsMarkedForReview: translationsMarkedForReview,
      ));
    } catch (e, stackTrace) {
      _logger.error('Failed to reactivate obsolete units', e, stackTrace);
      return Err(
        ServiceException(
          'Failed to reactivate obsolete units: $e',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
