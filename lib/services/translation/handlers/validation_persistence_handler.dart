import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/history/i_history_service.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/i_validation_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:uuid/uuid.dart';

/// Handles validation and persistence of translations
///
/// Responsibilities:
/// - Validate LLM translations
/// - Save translations to database
/// - Update Translation Memory
/// - Record translation history
/// - Track success/failure counts
class ValidationPersistenceHandler {
  final IValidationService _validation;
  final ITranslationMemoryService _tmService;
  final IHistoryService _historyService;
  final TranslationVersionRepository _versionRepository;
  final LoggingService _logger;
  final Uuid _uuid = const Uuid();

  ValidationPersistenceHandler({
    required IValidationService validation,
    required ITranslationMemoryService tmService,
    required IHistoryService historyService,
    required TranslationVersionRepository versionRepository,
    required LoggingService logger,
  })  : _validation = validation,
        _tmService = tmService,
        _historyService = historyService,
        _versionRepository = versionRepository,
        _logger = logger;

  /// Validate and save translations to database
  ///
  /// Validates and saves translations one by one, emitting progress updates
  /// after each successful save for real-time UI feedback.
  /// TM updates are batched at the end for performance.
  ///
  /// [cachedUnitIds] contains IDs of units that were translated via cache/deduplication
  /// rather than directly by LLM. These will be marked as TM exact matches.
  ///
  /// Returns updated progress with success/failure counts
  Future<TranslationProgress> validateAndSave({
    required Map<String, String> translations,
    required String batchId,
    required List<TranslationUnit> units,
    required TranslationContext context,
    required TranslationProgress currentProgress,
    required Future<void> Function(String batchId) checkPauseOrCancel,
    required void Function(String batchId, TranslationProgress progress) onProgressUpdate,
    Set<String> cachedUnitIds = const {},
  }) async {
    _logger.info('Starting validation and save', {'batchId': batchId});

    // Count translations to validate
    final translationsToValidate = units.where((u) => translations.containsKey(u.id)).toList();
    final totalToValidate = translationsToValidate.length;
    var validatedCount = 0;

    var progress = currentProgress.copyWith(
      currentPhase: TranslationPhase.validating,
      phaseDetail: 'Preparing validation ($totalToValidate translations)...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, progress);

    var successCount = 0;
    var failCount = 0;

    // Collect successful translations for batch TM update
    final tmBatchEntries = <({String sourceText, String targetText})>[];

    // Process each translation individually with progress updates
    for (final unit in units) {
      await checkPauseOrCancel(batchId);

      final llmTranslation = translations[unit.id];
      if (llmTranslation == null) {
        // Already translated via TM or not translated in LLM step
        continue;
      }

      validatedCount++;

      // Update phase detail with current validation progress
      progress = progress.copyWith(
        phaseDetail: 'Validating translation $validatedCount/$totalToValidate (variables, markup, glossary)...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      // Validate translation
      final validationResult = await _validation.validateTranslation(
        sourceText: unit.sourceText,
        translatedText: llmTranslation,
        key: unit.key,
        glossaryTerms: context.glossaryTerms,
      );

      // Determine status based on validation results
      // - If validation failed (error in validation process): needsReview
      // - If has errors or warnings: needsReview
      // - Otherwise: translated
      TranslationVersionStatus status = TranslationVersionStatus.translated;
      String? validationIssuesJson;

      if (validationResult.isErr) {
        // Validation process itself failed
        status = TranslationVersionStatus.needsReview;
        _logger.warning('Translation validation process failed', {
          'batchId': batchId,
          'unitId': unit.id,
          'key': unit.key,
          'error': validationResult.unwrapErr().toString(),
        });
      } else {
        final result = validationResult.unwrap();
        if (result.hasErrors || result.hasWarnings) {
          // Has validation errors or warnings - needs review
          status = TranslationVersionStatus.needsReview;
          validationIssuesJson = result.allMessages.toString();
          _logger.debug('Translation has validation issues', {
            'batchId': batchId,
            'unitId': unit.id,
            'key': unit.key,
            'errors': result.errors,
            'warnings': result.warnings,
          });
        }
      }

      // Save translation
      try {
        // Update detail: saving phase
        progress = progress.copyWith(
          currentPhase: TranslationPhase.saving,
          phaseDetail: 'Saving translation $validatedCount/$totalToValidate to database...',
          timestamp: DateTime.now(),
        );
        onProgressUpdate(batchId, progress);

        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        // Use TM exact for cached/deduplicated translations, LLM for direct translations
        final translationSource = cachedUnitIds.contains(unit.id)
            ? TranslationSource.tmExact
            : TranslationSource.llm;
        final version = TranslationVersion(
          id: _generateId(),
          unitId: unit.id,
          projectLanguageId: context.projectLanguageId,
          translatedText: llmTranslation,
          status: status,
          translationSource: translationSource,
          validationIssues: validationIssuesJson,
          createdAt: now,
          updatedAt: now,
        );

        final saveResult = await _versionRepository.upsert(version);
        if (saveResult.isErr) {
          _logger.error('Failed to save translation', {
            'unitId': unit.id,
            'error': saveResult.unwrapErr(),
          });
          failCount++;
        } else {
          successCount++;

          // Collect for batch TM update (instead of individual calls)
          // Only add to TM batch if it was a direct LLM translation (not cached)
          if (!cachedUnitIds.contains(unit.id)) {
            tmBatchEntries.add((sourceText: unit.sourceText, targetText: llmTranslation));
          }

          // Record translation history
          final isCached = cachedUnitIds.contains(unit.id);
          try {
            await _historyService.recordChange(
              versionId: version.id,
              translatedText: llmTranslation,
              status: status.name,
              changedBy: isCached ? 'tm_exact' : 'provider_${context.providerCode}',
              changeReason: isCached
                  ? 'TM exact match (100% similarity, batch deduplication)'
                  : 'LLM translation (${context.modelId ?? "default"})',
            );
          } catch (e) {
            _logger.warning('Failed to record history (non-critical)', {
              'unitId': unit.id,
              'versionId': version.id,
              'error': e,
            });
          }
        }

        // Update progress after each save
        progress = progress.copyWith(
          successfulUnits: currentProgress.successfulUnits + successCount,
          failedUnits: currentProgress.failedUnits + failCount,
          processedUnits: currentProgress.processedUnits + successCount + failCount,
          timestamp: DateTime.now(),
        );
        onProgressUpdate(batchId, progress);
      } catch (e, stackTrace) {
        _logger.error('Save operation failed', e, stackTrace);
        failCount++;

        // Update progress after failure
        progress = progress.copyWith(
          failedUnits: currentProgress.failedUnits + failCount,
          processedUnits: currentProgress.processedUnits + successCount + failCount,
          timestamp: DateTime.now(),
        );
        onProgressUpdate(batchId, progress);
      }
    }

    // Batch update Translation Memory (much faster than individual calls)
    if (tmBatchEntries.isNotEmpty) {
      progress = progress.copyWith(
        currentPhase: TranslationPhase.updatingTm,
        phaseDetail: 'Updating Translation Memory (${tmBatchEntries.length} entries)...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      try {
        final tmResult = await _tmService.addTranslationsBatch(
          translations: tmBatchEntries,
          targetLanguageCode: context.targetLanguage,
        );

        if (tmResult.isErr) {
          _logger.warning('Batch TM update failed (non-critical)', {
            'batchId': batchId,
            'error': tmResult.error,
          });
        } else {
          _logger.debug('Batch TM update completed', {
            'batchId': batchId,
            'entriesProcessed': tmResult.value,
          });
        }
      } catch (e) {
        _logger.warning('Batch TM update failed (non-critical)', {
          'batchId': batchId,
          'error': e,
        });
      }
    }

    _logger.info('Validation and save completed', {
      'batchId': batchId,
      'successCount': successCount,
      'failCount': failCount,
    });

    return progress.copyWith(
      currentPhase: TranslationPhase.finalizing,
      phaseDetail: 'Finalizing batch...',
      timestamp: DateTime.now(),
    );
  }

  /// Generate a unique ID (UUID v4)
  String _generateId() => _uuid.v4();
}
