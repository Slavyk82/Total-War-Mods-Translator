import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/repositories/compilation_repository.dart';
import 'package:twmt/repositories/export_history_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/repositories/ignored_source_text_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/llm_custom_rule_repository.dart';
import 'package:twmt/repositories/llm_provider_model_repository.dart';
import 'package:twmt/repositories/mod_scan_cache_repository.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';
import 'package:twmt/repositories/mod_version_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/settings_repository.dart';
import 'package:twmt/repositories/translation_batch_repository.dart';
import 'package:twmt/repositories/translation_batch_unit_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/repositories/translation_provider_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_history_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/file/export_orchestrator_service.dart';
import 'package:twmt/services/file/file_import_export_service.dart';
import 'package:twmt/services/file/i_loc_file_service.dart';
import 'package:twmt/services/file/i_localization_parser.dart';
import 'package:twmt/services/file/i_pack_image_generator_service.dart';
import 'package:twmt/services/file/utils/file_validator.dart';
import 'package:twmt/services/mods/game_installation_sync_service.dart';
import 'package:twmt/services/mods/mod_update_analysis_service.dart';
import 'package:twmt/services/mods/workshop_scanner_service.dart';
import 'package:twmt/services/projects/i_project_initialization_service.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';
import 'package:twmt/services/glossary/deepl_glossary_sync_service.dart';
import 'package:twmt/services/glossary/glossary_deepl_service.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/llm_batch_adjuster.dart';
import 'package:twmt/services/llm/llm_custom_rules_service.dart';
import 'package:twmt/services/llm/llm_model_management_service.dart';
import 'package:twmt/services/llm/llm_provider_factory.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';
import 'package:twmt/services/translation/ignored_source_text_service.dart';
import 'package:twmt/services/locators/core_service_locator.dart';
import 'package:twmt/services/locators/file_service_locator.dart';
import 'package:twmt/services/locators/glossary_service_locator.dart';
import 'package:twmt/services/locators/llm_service_locator.dart';
import 'package:twmt/services/locators/repository_locator.dart';
import 'package:twmt/services/locators/translation_service_locator.dart';
import 'package:twmt/services/concurrency/transaction_manager.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/services/shared/event_bus.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/services/translation/i_validation_service.dart';
import 'package:twmt/services/translation/utils/batch_optimizer.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/similarity_calculator.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tm_cache.dart';
import 'package:twmt/services/translation_memory/tm_import_export_service.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';
import 'package:twmt/services/history/i_history_service.dart';
import 'package:twmt/services/validation/i_translation_validation_service.dart';

import '../../helpers/noop_logger.dart';
import '../../helpers/test_bootstrap.dart';

class _MockSettingsService extends Mock implements SettingsService {}

class _MockTransactionManager extends Mock implements TransactionManager {}

class _MockRpfmService extends Mock implements IRpfmService {}

class _MockWorkshopApiService extends Mock implements IWorkshopApiService {}

class _MockTmxService extends Mock implements TmxService {}

void main() {
  late GetIt locator;

  setUp(() async {
    // Repositories resolve ServiceLocator.get<ILoggingService>() (the global
    // GetIt.instance) in their constructors, so a fake logger must live there
    // before any repo is constructed.
    await TestBootstrap.registerFakes();
    // Isolated container for the locators under test; registrations are lazy
    // so nothing is constructed until explicitly resolved.
    locator = GetIt.asNewInstance();
    locator.registerSingleton<ILoggingService>(NoopLogger());
  });

  tearDown(() => locator.reset());

  group('RepositoryLocator', () {
    test('registers and can construct every repository', () {
      RepositoryLocator.register(locator);

      // Repositories take no constructor args and access the database lazily
      // (via a getter), so resolving them here executes each factory closure
      // without any real database I/O.
      expect(locator<LanguageRepository>(), isA<LanguageRepository>());
      expect(locator<CompilationRepository>(), isA<CompilationRepository>());
      expect(locator<TranslationProviderRepository>(),
          isA<TranslationProviderRepository>());
      expect(locator<GameInstallationRepository>(),
          isA<GameInstallationRepository>());
      expect(locator<ProjectRepository>(), isA<ProjectRepository>());
      expect(locator<ProjectLanguageRepository>(),
          isA<ProjectLanguageRepository>());
      expect(
          locator<TranslationUnitRepository>(), isA<TranslationUnitRepository>());
      expect(locator<TranslationVersionRepository>(),
          isA<TranslationVersionRepository>());
      expect(locator<TranslationBatchRepository>(),
          isA<TranslationBatchRepository>());
      expect(locator<TranslationBatchUnitRepository>(),
          isA<TranslationBatchUnitRepository>());
      expect(locator<TranslationMemoryRepository>(),
          isA<TranslationMemoryRepository>());
      expect(locator<ModVersionRepository>(), isA<ModVersionRepository>());
      expect(locator<GlossaryRepository>(), isA<GlossaryRepository>());
      expect(locator<SettingsRepository>(), isA<SettingsRepository>());
      expect(locator<TranslationVersionHistoryRepository>(),
          isA<TranslationVersionHistoryRepository>());
      expect(
          locator<ExportHistoryRepository>(), isA<ExportHistoryRepository>());
      expect(locator<WorkshopModRepository>(), isA<WorkshopModRepository>());
      expect(locator<ModScanCacheRepository>(), isA<ModScanCacheRepository>());
      expect(locator<ModUpdateAnalysisCacheRepository>(),
          isA<ModUpdateAnalysisCacheRepository>());
      expect(locator<LlmProviderModelRepository>(),
          isA<LlmProviderModelRepository>());
      expect(
          locator<LlmCustomRuleRepository>(), isA<LlmCustomRuleRepository>());
      expect(locator<IgnoredSourceTextRepository>(),
          isA<IgnoredSourceTextRepository>());
    });
  });

  group('GlossaryServiceLocator', () {
    test('registers and can construct glossary services', () {
      // Glossary services depend only on a repository + secure storage, so
      // they construct without touching infrastructure once repos exist.
      RepositoryLocator.register(locator);
      GlossaryServiceLocator.register(locator);

      expect(locator<IGlossaryService>(), isA<IGlossaryService>());
      expect(locator<GlossaryDeepLService>(), isA<GlossaryDeepLService>());
      expect(locator<DeepLGlossarySyncService>(),
          isA<DeepLGlossarySyncService>());
    });
  });

  group('LlmServiceLocator', () {
    test('registers and constructs its repo-backed services', () {
      // Every LLM service except ILlmService (which needs the core
      // SettingsService) depends only on repositories + the provider factory.
      RepositoryLocator.register(locator);
      LlmServiceLocator.register(locator);

      expect(locator<TokenCalculator>(), isA<TokenCalculator>());
      expect(locator<LlmProviderFactory>(), isA<LlmProviderFactory>());
      expect(locator<LlmBatchAdjuster>(), isA<LlmBatchAdjuster>());
      expect(locator<LlmModelManagementService>(),
          isA<LlmModelManagementService>());
      expect(locator<LlmCustomRulesService>(), isA<LlmCustomRulesService>());
      expect(
          locator<IgnoredSourceTextService>(), isA<IgnoredSourceTextService>());
      // ILlmService is wired but needs core infrastructure to construct.
      expect(locator.isRegistered<ILlmService>(), isTrue);
    });
  });

  // The locators below wire services whose factory closures depend on core
  // infrastructure (RPFM/Steam/process services, the orchestrator) that is only
  // assembled by CoreServiceLocator at app start. Here we verify the
  // registration wiring without constructing that graph.
  group('TranslationServiceLocator', () {
    test('registers and constructs the translation service graph', () {
      // Every translation service is backed by repositories, the token
      // calculator, or other translation services. The orchestrator also needs
      // a SettingsService (normally from core), so a mock stands in for it.
      RepositoryLocator.register(locator);
      GlossaryServiceLocator.register(locator);
      LlmServiceLocator.register(locator);
      // Part of the orchestrator graph reaches into the global ServiceLocator
      // (GetIt.instance) for repositories, so mirror the repos there too.
      RepositoryLocator.register(GetIt.instance);
      locator.registerSingleton<SettingsService>(_MockSettingsService());
      locator.registerSingleton<TransactionManager>(_MockTransactionManager());
      locator.registerSingleton<EventBus>(EventBus.instance);
      TranslationServiceLocator.register(locator);

      expect(locator<TextNormalizer>(), isA<TextNormalizer>());
      expect(locator<SimilarityCalculator>(), isA<SimilarityCalculator>());
      expect(locator<TmCache>(), isA<TmCache>());
      expect(locator<BatchOptimizer>(), isA<BatchOptimizer>());
      expect(locator<TmxService>(), isA<TmxService>());
      expect(locator<TmImportExportService>(), isA<TmImportExportService>());
      expect(locator<IPromptBuilderService>(), isA<IPromptBuilderService>());
      expect(locator<IValidationService>(), isA<IValidationService>());
      expect(locator<ITranslationMemoryService>(),
          isA<ITranslationMemoryService>());
      expect(locator<IHistoryService>(), isA<IHistoryService>());
      expect(locator<ITranslationValidationService>(),
          isA<ITranslationValidationService>());
      expect(
          locator<ITranslationOrchestrator>(), isA<ITranslationOrchestrator>());
    });
  });

  // CoreServiceLocator.register wires process/isolate/Steam/update services
  // whose construction is real infrastructure (RPFM CLI, Dio HTTP, background
  // isolates). We only verify it registers its services; constructing them is
  // out of scope for a pure-logic unit test. (registerInfrastructure is omitted
  // entirely: it performs real LoggingService file initialisation.)
  group('CoreServiceLocator', () {
    test('register wires the core service layer', () {
      CoreServiceLocator.register(locator);
      expect(locator.isRegistered<SettingsService>(), isTrue);
      expect(locator.isRegistered<IRpfmService>(), isTrue);
      expect(locator.isRegistered<TransactionManager>(), isTrue);
    });
  });

  group('FileServiceLocator', () {
    test('registers and constructs the file service graph', () {
      // File services depend on repositories plus the RPFM / Workshop-API /
      // settings / TMX services that core normally provides — mocks stand in
      // for those so every factory closure can construct.
      RepositoryLocator.register(locator);
      locator.registerSingleton<IRpfmService>(_MockRpfmService());
      locator.registerSingleton<IWorkshopApiService>(_MockWorkshopApiService());
      locator.registerSingleton<SettingsService>(_MockSettingsService());
      locator.registerSingleton<TmxService>(_MockTmxService());
      FileServiceLocator.register(locator);

      expect(locator<FileValidator>(), isA<FileValidator>());
      expect(locator<ILocalizationParser>(), isA<ILocalizationParser>());
      expect(locator<ILocFileService>(), isA<ILocFileService>());
      expect(
          locator<FileImportExportService>(), isA<FileImportExportService>());
      expect(locator<IPackImageGeneratorService>(),
          isA<IPackImageGeneratorService>());
      expect(locator<ExportOrchestratorService>(),
          isA<ExportOrchestratorService>());
      expect(
          locator<ModUpdateAnalysisService>(), isA<ModUpdateAnalysisService>());
      expect(locator<WorkshopScannerService>(), isA<WorkshopScannerService>());
      expect(locator<GameInstallationSyncService>(),
          isA<GameInstallationSyncService>());
      expect(locator<IProjectInitializationService>(),
          isA<IProjectInitializationService>());
    });
  });
}
