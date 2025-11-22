import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/concurrency/transaction_manager.dart';
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
  final TransactionManager _transactionManager;
  final LoggingService _logger;
  final Uuid _uuid = const Uuid();

  ValidationPersistenceHandler({
    required IValidationService validation,
    required ITranslationMemoryService tmService,
    required TranslationVersionRepository versionRepository,
    required TransactionManager transactionManager,
    required LoggingService logger,
  })  : _validation = validation,
        _tmService = tmService,
        _versionRepository = versionRepository,
        _transactionManager = transactionManager,
        _logger = logger;

  /// Validate and save translations to database
  ///
  /// Returns updated progress with success/failure counts
  Future<TranslationProgress> validateAndSave({
    required Map<String, String> translations,
    required String batchId,
    required List<TranslationUnit> units,
    required TranslationContext context,
    required TranslationProgress currentProgress,
    required Future<void> Function(String batchId) checkPauseOrCancel,
  }) async {
    _logger.info('Starting validation and save', {'batchId': batchId});

    var progress = currentProgress.copyWith(
      currentPhase: TranslationPhase.validating,
      timestamp: DateTime.now(),
    );

    var successCount = 0;
    var failCount = 0;

    // Validate and save each translation in a transaction
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
        failCount++;
        continue;
      }

      // Save translation to database WITHOUT transaction to avoid DB lock
      // UPSERT: Check if translation exists, then UPDATE or INSERT
      try {
        _logger.debug('Step 1: Generating timestamp', {
          'unitId': unit.id,
          'key': unit.key,
        });
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        _logger.debug('Step 1 complete: Timestamp generated', {
          'timestamp': now,
          'timestampInSeconds': now,
        });

        // Check if translation version already exists
        _logger.debug('Step 2: Checking if translation exists', {
          'unitId': unit.id,
          'projectLanguageId': context.projectLanguageId,
        });
        final existingResult = await _versionRepository.getByUnitAndProjectLanguage(
          unitId: unit.id,
          projectLanguageId: context.projectLanguageId,
        );
        _logger.debug('Step 2 complete: Existence check done', {
          'exists': existingResult.isOk,
        });

        final Result<TranslationVersion, dynamic> saveResult;

        if (existingResult.isOk) {
          // UPDATE existing translation
          _logger.debug('Step 3a: Updating existing translation', {
            'existingId': existingResult.unwrap().id,
            'existingCreatedAt': existingResult.unwrap().createdAt,
          });
          final existing = existingResult.unwrap();

          final updated = existing.copyWith(
            translatedText: llmTranslation,
            status: TranslationVersionStatus.translated,
            confidenceScore: 0.8,
            updatedAt: now,
          );

          _logger.debug('Step 3a: Calling repository.update()', {
            'versionId': updated.id,
            'createdAt': updated.createdAt,
            'updatedAt': updated.updatedAt,
          });
          saveResult = await _versionRepository.update(updated);
          _logger.debug('Step 3a complete: UPDATE result', {
            'success': saveResult.isOk,
          });
        } else {
          // INSERT new translation
          final versionId = _generateId();
          _logger.debug('Step 3b: Inserting new translation', {
            'generatedId': versionId,
            'createdAt': now,
            'updatedAt': now,
          });
          final version = TranslationVersion(
            id: versionId,
            unitId: unit.id,
            projectLanguageId: context.projectLanguageId,
            translatedText: llmTranslation,
            status: TranslationVersionStatus.translated,
            confidenceScore: 0.8,
            createdAt: now,
            updatedAt: now,
          );

          _logger.debug('Step 3b: Calling repository.insert()', {
            'versionId': version.id,
            'unitId': version.unitId,
            'projectLanguageId': version.projectLanguageId,
          });
          saveResult = await _versionRepository.insert(version);
          _logger.debug('Step 3b complete: INSERT result', {
            'success': saveResult.isOk,
          });
        }

        if (saveResult.isErr) {
          _logger.error('Step 3 failed: Save result error', {
            'error': saveResult.unwrapErr(),
          });
          throw Exception(
              'Failed to save translation: ${saveResult.unwrapErr()}');
        }

        // Add to Translation Memory
        _logger.debug('Step 4: Adding to Translation Memory', {
          'sourceText': unit.sourceText,
          'targetText': llmTranslation,
        });
        await _tmService.addTranslation(
          sourceText: unit.sourceText,
          targetText: llmTranslation,
          targetLanguageCode: context.targetLanguage,
          gameContext: context.gameContext,
          category: context.category,
          quality: 0.8,
        );
        _logger.debug('Step 4 complete: Added to TM');

        successCount++;
        _logger.info('Translation saved successfully', {
          'unitId': unit.id,
          'key': unit.key,
        });
      } catch (e, stackTrace) {
        _logger.error('Failed to save translation', e, stackTrace);
        failCount++;
      }
    }

    _logger.info('Validation and save completed', {
      'batchId': batchId,
      'successCount': successCount,
      'failCount': failCount,
    });

    return progress.copyWith(
      currentPhase: TranslationPhase.finalizing,
      successfulUnits: currentProgress.successfulUnits + successCount,
      failedUnits: currentProgress.failedUnits + failCount,
      processedUnits:
          currentProgress.processedUnits + successCount + failCount,
      timestamp: DateTime.now(),
    );
  }

  /// Generate a unique ID (UUID v4)
  String _generateId() => _uuid.v4();
}
