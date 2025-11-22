import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../models/domain/translation_batch.dart';
import '../../../models/domain/translation_batch_unit.dart';
import '../../../services/translation/models/translation_context.dart';
import '../providers/editor_providers.dart';

/// Helper for managing translation batch creation and execution
///
/// Handles:
/// - Fetching untranslated unit IDs
/// - Filtering unit lists
/// - Creating batch entities
/// - Building translation contexts
class TranslationBatchHelper {
  const TranslationBatchHelper._();

  static Future<List<String>> getUntranslatedUnitIds({
    required WidgetRef ref,
    required String projectLanguageId,
  }) async {
    try {
      final versionRepo = ref.read(translationVersionRepositoryProvider);

      final result = await versionRepo.getUntranslatedIds(
        projectLanguageId: projectLanguageId,
      );

      if (result.isOk) {
        return result.unwrap();
      } else {
        throw result.unwrapErr();
      }
    } catch (e) {
      ref.read(loggingServiceProvider).error(
        'Failed to get untranslated unit IDs',
        e,
      );
      return [];
    }
  }

  static Future<List<String>> filterUntranslatedUnits({
    required WidgetRef ref,
    required List<String> unitIds,
  }) async {
    try {
      final versionRepo = ref.read(translationVersionRepositoryProvider);

      final result = await versionRepo.filterUntranslatedIds(
        ids: unitIds,
      );

      if (result.isOk) {
        return result.unwrap();
      } else {
        throw result.unwrapErr();
      }
    } catch (e) {
      ref.read(loggingServiceProvider).error(
        'Failed to filter untranslated unit IDs',
        e,
      );
      return [];
    }
  }

  static Future<bool> checkProviderConfigured({
    required WidgetRef ref,
    required Future<Map<String, dynamic>> Function() getSettings,
  }) async {
    // Check if an LLM provider is configured
    final llmSettings = await getSettings();

    final activeProvider = llmSettings['active_llm_provider'] ?? '';
    if (activeProvider.isEmpty) {
      return false;
    }

    // Check if the active provider has an API key
    switch (activeProvider) {
      case 'anthropic':
        return llmSettings['anthropic_api_key']?.isNotEmpty ?? false;
      case 'openai':
        return llmSettings['openai_api_key']?.isNotEmpty ?? false;
      case 'deepl':
        return llmSettings['deepl_api_key']?.isNotEmpty ?? false;
      default:
        return false;
    }
  }

  static Future<String?> createAndPrepareBatch({
    required WidgetRef ref,
    required String projectLanguageId,
    required List<String> unitIds,
    required String providerId,
    required VoidCallback onError,
  }) async {
    try {
      final batchRepo = ref.read(translationBatchRepositoryProvider);
      final batchUnitRepo = ref.read(translationBatchUnitRepositoryProvider);
      final logging = ref.read(loggingServiceProvider);

      // Get the next batch number for this project language
      final existingBatchesResult = await batchRepo.getByProjectLanguage(
        projectLanguageId,
      );
      final batchNumber = existingBatchesResult.when(
        ok: (batches) => batches.isEmpty
            ? 1
            : (batches.map((b) => b.batchNumber).reduce((a, b) => a > b ? a : b) + 1),
        err: (_) => 1,
      );

      // Create batch entity
      final batchId = const Uuid().v4();

      final batch = TranslationBatch(
        id: batchId,
        projectLanguageId: projectLanguageId,
        providerId: providerId,
        batchNumber: batchNumber,
        unitsCount: unitIds.length,
        status: TranslationBatchStatus.pending,
      );

      final batchInsertResult = await batchRepo.insert(batch);
      if (batchInsertResult.isErr) {
        logging.error(
          'Failed to create batch',
          batchInsertResult.unwrapErr(),
        );
        onError();
        return null;
      }

      // Create batch unit entities
      for (var i = 0; i < unitIds.length; i++) {
        final batchUnit = TranslationBatchUnit(
          id: const Uuid().v4(),
          batchId: batchId,
          unitId: unitIds[i],
          processingOrder: i,
          status: TranslationBatchUnitStatus.pending,
        );

        final unitInsertResult = await batchUnitRepo.insert(batchUnit);
        if (unitInsertResult.isErr) {
          logging.error(
            'Failed to create batch unit',
            unitInsertResult.unwrapErr(),
          );
          // Continue with other units even if one fails
        }
      }

      return batchId;
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to create and prepare batch',
        e,
        stackTrace,
      );
      onError();
      return null;
    }
  }

  static Future<TranslationContext> buildTranslationContext({
    required WidgetRef ref,
    required String projectId,
    required String projectLanguageId,
    required String providerId,
    String? modelId,
  }) async {
    try {
      final projectLanguageRepo = ref.read(projectLanguageRepositoryProvider);
      final languageRepo = ref.read(languageRepositoryProvider);
      final logging = ref.read(loggingServiceProvider);

      // Get project language to determine target language
      final projectLanguageResult = await projectLanguageRepo.getById(projectLanguageId);
      String targetLanguage = 'en'; // Default fallback

      if (projectLanguageResult.isOk) {
        final projectLanguage = projectLanguageResult.unwrap();

        // Get the actual language entity to retrieve the language code
        final languageResult = await languageRepo.getById(projectLanguage.languageId);

        if (languageResult.isOk) {
          final language = languageResult.unwrap();
          targetLanguage = language.code;
        } else {
          logging.warning(
            'Failed to get language for translation context: ${languageResult.unwrapErr()}',
          );
        }
      } else {
        logging.warning(
          'Failed to get project language for translation context: ${projectLanguageResult.unwrapErr()}',
        );
      }

      // DEBUG: Log TranslationContext creation
      print('[DEBUG] buildTranslationContext:');
      print('[DEBUG]   - providerId: $providerId');
      print('[DEBUG]   - modelId: $modelId');
      print('[DEBUG]   - targetLanguage: $targetLanguage');

      return TranslationContext(
        id: const Uuid().v4(),
        projectId: projectId,
        projectLanguageId: projectLanguageId,
        providerId: providerId,
        modelId: modelId,
        targetLanguage: targetLanguage,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to build translation context',
        e,
        stackTrace,
      );

      // Return a default context as fallback
      return TranslationContext(
        id: const Uuid().v4(),
        projectId: projectId,
        projectLanguageId: projectLanguageId,
        providerId: providerId,
        modelId: modelId,
        targetLanguage: 'en',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
  }
}
