import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:uuid/uuid.dart';
import '../../../models/domain/translation_batch.dart';
import '../../../models/domain/translation_batch_unit.dart';
import '../../../services/translation/models/translation_context.dart';
import '../../../services/glossary/glossary_filter_service.dart';
import '../../../services/glossary/models/glossary_term_with_variants.dart';
import '../../../providers/shared/logging_providers.dart';
import '../../../providers/shared/repository_providers.dart' as shared_repo;
import '../../../providers/shared/service_providers.dart' as shared_svc;

/// Generic provider-read function. Both `WidgetRef.read` and `Ref.read`
/// have this signature, so callers can pass either as `read: ref.read`.
typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// Helper for managing translation batch creation and execution
///
/// Handles:
/// - Fetching untranslated unit IDs
/// - Filtering unit lists
/// - Creating batch entities
/// - Building translation contexts
///
/// All methods take a [Reader] (typically `ref.read` from a widget, notifier
/// or provider) so the helper works uniformly from both widget and
/// notifier call sites.
class TranslationBatchHelper {
  const TranslationBatchHelper._();

  static Future<List<String>> getUntranslatedUnitIds({
    required Reader read,
    required String projectLanguageId,
  }) async {
    try {
      final versionRepo = read(shared_repo.translationVersionRepositoryProvider);

      final result = await versionRepo.getUntranslatedIds(
        projectLanguageId: projectLanguageId,
      );

      if (result.isOk) {
        return result.unwrap();
      } else {
        throw result.unwrapErr();
      }
    } catch (e) {
      read(loggingServiceProvider).error(
        'Failed to get untranslated unit IDs',
        e,
      );
      return [];
    }
  }

  static Future<List<String>> filterUntranslatedUnits({
    required Reader read,
    required List<String> unitIds,
    required String projectLanguageId,
  }) async {
    try {
      final versionRepo = read(shared_repo.translationVersionRepositoryProvider);

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
      read(loggingServiceProvider).error(
        'Failed to filter untranslated unit IDs',
        e,
      );
      return [];
    }
  }

  static Future<bool> checkProviderConfigured({
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
    required Reader read,
    required String projectLanguageId,
    required List<String> unitIds,
    required String providerId,
    required void Function() onError,
  }) async {
    try {
      final batchRepo = read(shared_svc.translationBatchRepositoryProvider);
      final batchUnitRepo = read(shared_svc.translationBatchUnitRepositoryProvider);
      final logging = read(loggingServiceProvider);

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
      read(loggingServiceProvider).error(
        'Failed to create and prepare batch',
        e,
        stackTrace,
      );
      onError();
      return null;
    }
  }

  static Future<TranslationContext> buildTranslationContext({
    required Reader read,
    required String projectId,
    required String projectLanguageId,
    required String providerId,
    String? modelId,
    int? unitsPerBatch,
    int? parallelBatches,
    bool? skipTranslationMemory,
  }) async {
    try {
      final projectRepo = read(shared_repo.projectRepositoryProvider);
      final projectLanguageRepo = read(shared_repo.projectLanguageRepositoryProvider);
      final languageRepo = read(shared_repo.languageRepositoryProvider);
      final glossaryRepo = read(shared_repo.glossaryRepositoryProvider);
      final gameInstallationRepo =
          read(shared_repo.gameInstallationRepositoryProvider);
      final logging = read(loggingServiceProvider);

      // Get project to determine game code for glossary lookup
      String? gameCode;
      final projectResult = await projectRepo.getById(projectId);
      if (projectResult.isOk) {
        final project = projectResult.unwrap();
        final gameInstallationResult =
            await gameInstallationRepo.getById(project.gameInstallationId);
        if (gameInstallationResult.isOk) {
          gameCode = gameInstallationResult.unwrap().gameCode;
        } else {
          logging.warning(
            'Failed to resolve gameCode from gameInstallationId for translation context: ${gameInstallationResult.unwrapErr()}',
          );
        }
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
      List<GlossaryTermWithVariants> glossaryEntries = gameCode != null
          ? await glossaryFilterService.loadAllTerms(
              gameCode: gameCode,
              targetLanguageId: languageId ?? '',
              targetLanguageCode: targetLanguage,
            )
          : <GlossaryTermWithVariants>[];

      // Get primary glossary ID for DeepL sync.
      // DeepL only supports one glossary per request, so we pick the first
      // glossary scoped to this game.
      String? glossaryId;
      if (gameCode != null) {
        final glossaries = await glossaryRepo.getAllGlossaries(
          gameCode: gameCode,
        );
        // TODO(future): scope by (gameCode, targetLanguageId) once callers
        // consistently thread targetLanguageId through here.
        glossaryId = glossaries.firstOrNull?.id;
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
      read(loggingServiceProvider).error(
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
