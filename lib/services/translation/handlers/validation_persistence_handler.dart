import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
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
/// - Track success/failure counts
class ValidationPersistenceHandler {
  final IValidationService _validation;
  final ITranslationMemoryService _tmService;
  final TranslationVersionRepository _versionRepository;
  final LoggingService _logger;
  final Uuid _uuid = const Uuid();

  ValidationPersistenceHandler({
    required IValidationService validation,
    required ITranslationMemoryService tmService,
    required TranslationVersionRepository versionRepository,
    required LoggingService logger,
  })  : _validation = validation,
        _tmService = tmService,
        _versionRepository = versionRepository,
        _logger = logger;

  /// Validate and save translations to database
  ///
  /// Validates and saves translations one by one, emitting progress updates
  /// after each successful save for real-time UI feedback.
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
  }) async {
    _logger.info('Starting validation and save', {'batchId': batchId});

    var progress = currentProgress.copyWith(
      currentPhase: TranslationPhase.validating,
      timestamp: DateTime.now(),
    );

    var successCount = 0;
    var failCount = 0;

    // Process each translation individually with progress updates
    for (final unit in units) {
      await checkPauseOrCancel(batchId);

      final llmTranslation = translations[unit.id];
      if (llmTranslation == null) {
        // Already translated via TM or not translated in LLM step
        continue;
      }

      // Validate translation
      final validationResult = await _validation.validateTranslation(
        sourceText: unit.sourceText,
        translatedText: llmTranslation,
        key: unit.key,
        glossaryTerms: context.glossaryTerms,
      );

      if (validationResult.isErr || !validationResult.unwrap().isValid) {
        _logger.warning('Translation validation failed', {
          'batchId': batchId,
          'unitId': unit.id,
          'key': unit.key,
          'errors': validationResult.isOk
              ? validationResult
                  .unwrap()
                  .errors
                  .map((e) => e.toString())
                  .toList()
              : [validationResult.unwrapErr()],
        });
        // Debug: log actual texts for comparison
        _logger.debug('Validation debug', {
          'sourceText': unit.sourceText.substring(0, unit.sourceText.length.clamp(0, 500)),
          'translatedText': llmTranslation.substring(0, llmTranslation.length.clamp(0, 500)),
        });
        failCount++;
        
        // Update progress after failure
        progress = progress.copyWith(
          failedUnits: currentProgress.failedUnits + failCount,
          processedUnits: currentProgress.processedUnits + successCount + failCount,
          timestamp: DateTime.now(),
        );
        onProgressUpdate(batchId, progress);
        continue;
      }

      // Save translation
      try {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final version = TranslationVersion(
          id: _generateId(),
          unitId: unit.id,
          projectLanguageId: context.projectLanguageId,
          translatedText: llmTranslation,
          status: TranslationVersionStatus.translated,
          confidenceScore: 0.8,
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

          // Add to Translation Memory
          try {
            await _tmService.addTranslation(
              sourceText: unit.sourceText,
              targetText: llmTranslation,
              targetLanguageCode: context.targetLanguage,
              gameContext: context.gameContext,
              category: context.category,
              quality: 0.8,
            );
          } catch (e) {
            _logger.warning('Failed to add to TM (non-critical)', {
              'unitId': unit.id,
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

    _logger.info('Validation and save completed', {
      'batchId': batchId,
      'successCount': successCount,
      'failCount': failCount,
    });

    return progress.copyWith(
      currentPhase: TranslationPhase.finalizing,
      timestamp: DateTime.now(),
    );
  }

  /// Generate a unique ID (UUID v4)
  String _generateId() => _uuid.v4();
}
