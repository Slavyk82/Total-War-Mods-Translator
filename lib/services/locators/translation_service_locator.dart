import 'package:get_it/get_it.dart';

import '../../repositories/glossary_repository.dart';
import '../../repositories/translation_batch_repository.dart';
import '../../repositories/translation_batch_unit_repository.dart';
import '../../repositories/translation_memory_repository.dart';
import '../../repositories/translation_unit_repository.dart';
import '../../repositories/translation_version_history_repository.dart';
import '../../repositories/translation_version_repository.dart';
import '../../repositories/language_repository.dart';
import '../concurrency/transaction_manager.dart';
import '../history/history_service_impl.dart';
import '../history/i_history_service.dart';
import '../llm/i_llm_service.dart';
import '../llm/llm_custom_rules_service.dart';
import '../llm/utils/token_calculator.dart';
import '../shared/event_bus.dart';
import '../shared/logging_service.dart';
import '../translation/i_prompt_builder_service.dart';
import '../translation/i_translation_orchestrator.dart';
import '../translation/i_validation_service.dart';
import '../translation/prompt_builder_service_impl.dart';
import '../translation/translation_orchestrator_impl.dart';
import '../translation/utils/batch_optimizer.dart';
import '../translation/validation_service_impl.dart';
import '../translation_memory/i_translation_memory_service.dart';
import '../translation_memory/similarity_calculator.dart';
import '../translation_memory/text_normalizer.dart';
import '../translation_memory/tm_cache.dart';
import '../translation_memory/tm_import_export_service.dart';
import '../translation_memory/tmx_service.dart';
import '../translation_memory/translation_memory_service_impl.dart';
import '../validation/i_translation_validation_service.dart';
import '../validation/translation_validation_service.dart';

/// Registers translation-related services.
///
/// This includes:
/// - Translation orchestrator and related services
/// - Translation memory services
/// - Prompt building and validation
/// - History tracking
class TranslationServiceLocator {
  TranslationServiceLocator._();

  /// Register all translation services with the GetIt locator.
  static void register(GetIt locator) {
    final logging = locator<LoggingService>();
    logging.info('Registering translation services');

    // Translation Services
    locator.registerLazySingleton<IPromptBuilderService>(
      () => PromptBuilderServiceImpl(
        locator<TokenCalculator>(),
        locator<GlossaryRepository>(),
        locator<LlmCustomRulesService>(),
      ),
    );

    locator.registerLazySingleton<IValidationService>(
      () => ValidationServiceImpl(),
    );

    locator.registerLazySingleton<BatchOptimizer>(
      () => BatchOptimizer(locator<TokenCalculator>()),
    );

    // Translation Memory Services
    locator.registerLazySingleton<TextNormalizer>(
      () => TextNormalizer(),
    );

    locator.registerLazySingleton<SimilarityCalculator>(
      () => SimilarityCalculator(),
    );

    locator.registerLazySingleton<TmCache>(
      () => TmCache(maxSize: 10000),
    );

    locator.registerLazySingleton<TmxService>(
      () => TmxService(
        repository: locator<TranslationMemoryRepository>(),
        normalizer: locator<TextNormalizer>(),
      ),
    );

    locator.registerLazySingleton<TmImportExportService>(
      () => TmImportExportService(
        repository: locator<TranslationMemoryRepository>(),
        tmxService: locator<TmxService>(),
        logger: locator<LoggingService>(),
      ),
    );

    locator.registerLazySingleton<ITranslationMemoryService>(
      () => TranslationMemoryServiceImpl(
        repository: locator<TranslationMemoryRepository>(),
        languageRepository: locator<LanguageRepository>(),
        normalizer: locator<TextNormalizer>(),
        similarityCalculator: locator<SimilarityCalculator>(),
        cache: locator<TmCache>(),
      ),
    );

    // History Services
    locator.registerLazySingleton<IHistoryService>(
      () => HistoryServiceImpl(
        historyRepository: locator<TranslationVersionHistoryRepository>(),
        versionRepository: locator<TranslationVersionRepository>(),
      ),
    );

    // Validation Services
    locator.registerLazySingleton<ITranslationValidationService>(
      () => TranslationValidationService(),
    );

    // Translation Orchestrator (depends on TM and History services)
    locator.registerLazySingleton<ITranslationOrchestrator>(
      () => TranslationOrchestratorImpl(
        llmService: locator<ILlmService>(),
        tmService: locator<ITranslationMemoryService>(),
        promptBuilder: locator<IPromptBuilderService>(),
        validation: locator<IValidationService>(),
        historyService: locator<IHistoryService>(),
        versionRepository: locator<TranslationVersionRepository>(),
        unitRepository: locator<TranslationUnitRepository>(),
        batchRepository: locator<TranslationBatchRepository>(),
        batchUnitRepository: locator<TranslationBatchUnitRepository>(),
        transactionManager: locator<TransactionManager>(),
        eventBus: locator<EventBus>(),
        logger: locator<LoggingService>(),
      ),
    );

    logging.info('Translation services registered successfully');
  }
}
