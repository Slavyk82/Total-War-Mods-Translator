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
    required String projectLanguageId,
  }) async {
    try {
      final versionRepo = ref.read(translationVersionRepositoryProvider);

      final result = await versionRepo.filterUntranslatedIds(
        ids: unitIds,
        projectLanguageId: projectLanguageId,
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
    // Check if at least one translation provider is configured with an API key
    // This includes both LLM providers (Anthropic, OpenAI, DeepSeek, Gemini)
    // and specialized translation services (DeepL)
    final llmSettings = await getSettings();

    // Check all possible providers - any one with an API key is sufficient
    final hasAnthropic = llmSettings['anthropic_api_key']?.isNotEmpty ?? false;
    final hasOpenai = llmSettings['openai_api_key']?.isNotEmpty ?? false;
    final hasDeepl = llmSettings['deepl_api_key']?.isNotEmpty ?? false;
    final hasDeepseek = llmSettings['deepseek_api_key']?.isNotEmpty ?? false;
    final hasGemini = llmSettings['gemini_api_key']?.isNotEmpty ?? false;

    return hasAnthropic || hasOpenai || hasDeepl || hasDeepseek || hasGemini;
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
    bool? skipTranslationMemory,
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

      // Source language is always English for this application
      // DeepL API requires uppercase language codes
      const sourceLanguageCode = 'EN';

      // Get project language to determine target language
      // DeepL API requires uppercase language codes
      final projectLanguageResult = await projectLanguageRepo.getById(projectLanguageId);
      String targetLanguage = 'EN'; // Default fallback
      String? languageId;

      if (projectLanguageResult.isOk) {
        final projectLanguage = projectLanguageResult.unwrap();
        languageId = projectLanguage.languageId;

        // Get the actual language entity to retrieve the language code
        final languageResult = await languageRepo.getById(projectLanguage.languageId);

        if (languageResult.isOk) {
          final language = languageResult.unwrap();
          targetLanguage = language.code.toUpperCase();
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

      // Get primary glossary ID for DeepL sync
      // DeepL only supports one glossary per request, so we use the first game-specific glossary
      String? glossaryId;
      if (gameInstallationId != null) {
        final glossaries = await glossaryRepo.getAllGlossaries(
          gameInstallationId: gameInstallationId,
          includeUniversal: true,
        );
        // Prefer game-specific glossary over universal
        final gameSpecificGlossary = glossaries.where((g) => !g.isGlobal).firstOrNull;
        final universalGlossary = glossaries.where((g) => g.isGlobal).firstOrNull;
        glossaryId = gameSpecificGlossary?.id ?? universalGlossary?.id;
      }

      if (glossaryEntries.isNotEmpty) {
        logging.info('Loaded glossary entries with variants', {
          'projectId': projectId,
          'languageId': languageId,
          'termCount': glossaryEntries.length,
          'variantCount': glossaryEntries.fold<int>(
            0,
            (sum, e) => sum + e.variants.length,
          ),
          'glossaryId': glossaryId,
        });
      }

      // DEBUG: Log TranslationContext creation
      logging.debug('buildTranslationContext', {
        'providerId': providerId,
        'modelId': modelId,
        'targetLanguage': targetLanguage,
        'sourceLanguage': sourceLanguageCode,
        'glossaryEntries': '${glossaryEntries.length} terms',
        'totalVariants': glossaryEntries.fold<int>(0, (sum, e) => sum + e.variants.length),
        'glossaryId': glossaryId,
      });

      return TranslationContext(
        id: const Uuid().v4(),
        projectId: projectId,
        projectLanguageId: projectLanguageId,
        providerId: providerId,
        modelId: modelId,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguageCode,
        glossaryEntries: glossaryEntries.isEmpty ? null : glossaryEntries,
        glossaryId: glossaryId,
        unitsPerBatch: unitsPerBatch ?? 0, // 0 = auto mode
        parallelBatches: parallelBatches ?? 1,
        skipTranslationMemory: skipTranslationMemory ?? false,
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
        skipTranslationMemory: skipTranslationMemory ?? false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
  }
}
