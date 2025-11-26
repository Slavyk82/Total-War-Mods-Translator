import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../models/domain/translation_batch.dart';
import '../../../models/domain/translation_batch_unit.dart';
import '../../../services/translation/models/translation_context.dart';
import '../../../repositories/glossary_repository.dart';
import '../../../repositories/project_repository.dart';
import '../../../services/glossary/glossary_filter_service.dart';
import '../../../services/glossary/models/glossary_term_with_variants.dart';
import '../../../services/service_locator.dart';
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

      // Create batch unit entities (optimized: single transaction)
      final batchUnits = <TranslationBatchUnit>[];
      for (var i = 0; i < unitIds.length; i++) {
        batchUnits.add(TranslationBatchUnit(
          id: const Uuid().v4(),
          batchId: batchId,
          unitId: unitIds[i],
          processingOrder: i,
          status: TranslationBatchUnitStatus.pending,
        ));
      }

      final unitsInsertResult = await batchUnitRepo.insertBatch(batchUnits);
      if (unitsInsertResult.isErr) {
        logging.error(
          'Failed to create batch units',
          unitsInsertResult.unwrapErr(),
        );
        onError();
        return null;
      }

      logging.info('Created batch with ${batchUnits.length} units in single transaction');

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
    int? unitsPerBatch,
    int? parallelBatches,
  }) async {
    try {
      final projectRepo = ServiceLocator.get<ProjectRepository>();
      final projectLanguageRepo = ref.read(projectLanguageRepositoryProvider);
      final languageRepo = ref.read(languageRepositoryProvider);
      final glossaryRepo = ServiceLocator.get<GlossaryRepository>();
      final logging = ref.read(loggingServiceProvider);

      // Get project to determine game installation ID for glossary lookup
      String? gameInstallationId;
      final projectResult = await projectRepo.getById(projectId);
      if (projectResult.isOk) {
        gameInstallationId = projectResult.unwrap().gameInstallationId;
      }

      // Get project language to determine target language
      final projectLanguageResult = await projectLanguageRepo.getById(projectLanguageId);
      String targetLanguage = 'en'; // Default fallback
      String? languageId;

      if (projectLanguageResult.isOk) {
        final projectLanguage = projectLanguageResult.unwrap();
        languageId = projectLanguage.languageId;

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

      // Load glossary entries with variant support for this game and target language
      // The full glossary is loaded here; filtering happens per-batch in PromptBuilderService
      final glossaryFilterService = GlossaryFilterService(glossaryRepo);
      List<GlossaryTermWithVariants> glossaryEntries = gameInstallationId != null
          ? await glossaryFilterService.loadAllTerms(
              gameInstallationId: gameInstallationId,
              targetLanguageId: languageId ?? '',
              targetLanguageCode: targetLanguage,
            )
          : <GlossaryTermWithVariants>[];

      if (glossaryEntries.isNotEmpty) {
        logging.info('Loaded glossary entries with variants', {
          'projectId': projectId,
          'languageId': languageId,
          'termCount': glossaryEntries.length,
          'variantCount': glossaryEntries.fold<int>(
            0,
            (sum, e) => sum + e.variants.length,
          ),
        });
      }

      // DEBUG: Log TranslationContext creation
      print('[DEBUG] buildTranslationContext:');
      print('[DEBUG]   - providerId: $providerId');
      print('[DEBUG]   - modelId: $modelId');
      print('[DEBUG]   - targetLanguage: $targetLanguage');
      print('[DEBUG]   - glossaryEntries: ${glossaryEntries.length} terms');
      print('[DEBUG]   - total variants: ${glossaryEntries.fold<int>(0, (sum, e) => sum + e.variants.length)}');

      return TranslationContext(
        id: const Uuid().v4(),
        projectId: projectId,
        projectLanguageId: projectLanguageId,
        providerId: providerId,
        modelId: modelId,
        targetLanguage: targetLanguage,
        glossaryEntries: glossaryEntries.isEmpty ? null : glossaryEntries,
        unitsPerBatch: unitsPerBatch ?? 0, // 0 = auto mode
        parallelBatches: parallelBatches ?? 1,
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
        unitsPerBatch: unitsPerBatch ?? 0, // 0 = auto mode
        parallelBatches: parallelBatches ?? 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
  }
}
