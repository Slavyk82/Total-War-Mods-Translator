import 'package:get_it/get_it.dart';

import '../../repositories/compilation_repository.dart';
import '../../repositories/export_history_repository.dart';
import '../../repositories/game_installation_repository.dart';
import '../../repositories/glossary_repository.dart';
import '../../repositories/ignored_source_text_repository.dart';
import '../../repositories/language_repository.dart';
import '../../repositories/llm_custom_rule_repository.dart';
import '../../repositories/llm_provider_model_repository.dart';
import '../../repositories/mod_scan_cache_repository.dart';
import '../../repositories/mod_update_analysis_cache_repository.dart';
import '../../repositories/mod_version_repository.dart';
import '../../repositories/project_language_repository.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/translation_batch_repository.dart';
import '../../repositories/translation_batch_unit_repository.dart';
import '../../repositories/translation_memory_repository.dart';
import '../../repositories/translation_provider_repository.dart';
import '../../repositories/translation_unit_repository.dart';
import '../../repositories/translation_version_history_repository.dart';
import '../../repositories/translation_version_repository.dart';
import '../../repositories/workshop_mod_repository.dart';
import '../shared/logging_service.dart';

/// Registers all data repositories as lazy singletons.
///
/// Repositories provide data access layer abstractions and should be
/// registered before services that depend on them.
class RepositoryLocator {
  RepositoryLocator._();

  /// Register all repositories with the GetIt locator.
  static void register(GetIt locator) {
    final logging = locator<LoggingService>();
    logging.info('Registering repositories');

    locator.registerLazySingleton<LanguageRepository>(
      () => LanguageRepository(),
    );

    locator.registerLazySingleton<CompilationRepository>(
      () => CompilationRepository(),
    );

    locator.registerLazySingleton<TranslationProviderRepository>(
      () => TranslationProviderRepository(),
    );

    locator.registerLazySingleton<GameInstallationRepository>(
      () => GameInstallationRepository(),
    );

    locator.registerLazySingleton<ProjectRepository>(
      () => ProjectRepository(),
    );

    locator.registerLazySingleton<ProjectLanguageRepository>(
      () => ProjectLanguageRepository(),
    );

    locator.registerLazySingleton<TranslationUnitRepository>(
      () => TranslationUnitRepository(),
    );

    locator.registerLazySingleton<TranslationVersionRepository>(
      () => TranslationVersionRepository(),
    );

    locator.registerLazySingleton<TranslationBatchRepository>(
      () => TranslationBatchRepository(),
    );

    locator.registerLazySingleton<TranslationBatchUnitRepository>(
      () => TranslationBatchUnitRepository(),
    );

    locator.registerLazySingleton<TranslationMemoryRepository>(
      () => TranslationMemoryRepository(),
    );

    locator.registerLazySingleton<ModVersionRepository>(
      () => ModVersionRepository(),
    );

    locator.registerLazySingleton<GlossaryRepository>(
      () => GlossaryRepository(),
    );

    locator.registerLazySingleton<SettingsRepository>(
      () => SettingsRepository(),
    );

    locator.registerLazySingleton<TranslationVersionHistoryRepository>(
      () => TranslationVersionHistoryRepository(),
    );

    locator.registerLazySingleton<ExportHistoryRepository>(
      () => ExportHistoryRepository(),
    );

    locator.registerLazySingleton<WorkshopModRepository>(
      () => WorkshopModRepository(),
    );

    locator.registerLazySingleton<ModScanCacheRepository>(
      () => ModScanCacheRepository(),
    );

    locator.registerLazySingleton<ModUpdateAnalysisCacheRepository>(
      () => ModUpdateAnalysisCacheRepository(),
    );

    locator.registerLazySingleton<LlmProviderModelRepository>(
      () => LlmProviderModelRepository(),
    );

    locator.registerLazySingleton<LlmCustomRuleRepository>(
      () => LlmCustomRuleRepository(),
    );

    locator.registerLazySingleton<IgnoredSourceTextRepository>(
      () => IgnoredSourceTextRepository(),
    );

    logging.info('Repositories registered successfully');
  }
}
