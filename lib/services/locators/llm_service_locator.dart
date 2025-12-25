import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import '../../repositories/ignored_source_text_repository.dart';
import '../../repositories/llm_custom_rule_repository.dart';
import '../../repositories/llm_provider_model_repository.dart';
import '../glossary/deepl_glossary_sync_service.dart';
import '../llm/i_llm_service.dart';
import '../llm/llm_batch_adjuster.dart';
import '../llm/llm_custom_rules_service.dart';
import '../llm/llm_model_management_service.dart';
import '../llm/llm_provider_factory.dart';
import '../llm/llm_service_impl.dart';
import '../llm/utils/token_calculator.dart';
import '../settings/settings_service.dart';
import '../shared/logging_service.dart';
import '../translation/ignored_source_text_service.dart';

/// Registers LLM provider services.
///
/// This includes:
/// - LLM service and provider factory
/// - Token calculation
/// - Batch adjustment
/// - Model management
/// - Custom rules
/// - Ignored source text service
class LlmServiceLocator {
  LlmServiceLocator._();

  /// Register all LLM services with the GetIt locator.
  static void register(GetIt locator) {
    final logging = locator<LoggingService>();
    logging.info('Registering LLM services');

    // Token Calculator
    locator.registerLazySingleton<TokenCalculator>(
      () => TokenCalculator(),
    );

    // LLM Provider Factory
    locator.registerLazySingleton<LlmProviderFactory>(
      () => LlmProviderFactory(),
    );

    // Batch Adjuster
    locator.registerLazySingleton<LlmBatchAdjuster>(
      () => LlmBatchAdjuster(
        providerFactory: locator<LlmProviderFactory>(),
        tokenCalculator: locator<TokenCalculator>(),
      ),
    );

    // LLM Service
    // Note: DeepLGlossarySyncService is registered later in GlossaryServiceLocator,
    // so we use a factory function for lazy resolution
    locator.registerLazySingleton<ILlmService>(
      () => LlmServiceImpl(
        providerFactory: locator<LlmProviderFactory>(),
        batchAdjuster: locator<LlmBatchAdjuster>(),
        settingsService: locator<SettingsService>(),
        secureStorage: const FlutterSecureStorage(),
        deeplGlossarySyncServiceFactory: () {
          if (locator.isRegistered<DeepLGlossarySyncService>()) {
            return locator<DeepLGlossarySyncService>();
          }
          return null;
        },
      ),
    );

    // Model Management Service
    locator.registerLazySingleton<LlmModelManagementService>(
      () => LlmModelManagementService(
        locator<LlmProviderModelRepository>(),
        locator<LoggingService>(),
      ),
    );

    // Custom Rules Service
    locator.registerLazySingleton<LlmCustomRulesService>(
      () => LlmCustomRulesService(
        repository: locator<LlmCustomRuleRepository>(),
        logging: locator<LoggingService>(),
      ),
    );

    // Ignored Source Text Service
    locator.registerLazySingleton<IgnoredSourceTextService>(
      () => IgnoredSourceTextService(
        repository: locator<IgnoredSourceTextRepository>(),
        logging: locator<LoggingService>(),
      ),
    );

    logging.info('LLM services registered successfully');
  }
}
