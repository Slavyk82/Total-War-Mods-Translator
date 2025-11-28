import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import '../repositories/game_installation_repository.dart';
import '../repositories/glossary_repository.dart';
import '../repositories/language_repository.dart';
import '../repositories/mod_version_repository.dart';
import '../repositories/project_language_repository.dart';
import '../repositories/project_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/translation_batch_repository.dart';
import '../repositories/translation_memory_repository.dart';
import '../repositories/translation_provider_repository.dart';
import '../repositories/translation_unit_repository.dart';
import '../repositories/translation_version_repository.dart';
import '../repositories/translation_batch_unit_repository.dart';
import '../repositories/export_history_repository.dart';
import '../repositories/workshop_mod_repository.dart';
import '../repositories/mod_scan_cache_repository.dart';
import '../repositories/mod_update_analysis_cache_repository.dart';
import '../repositories/llm_provider_model_repository.dart';
import 'database/database_service.dart';
import 'database/migration_service.dart';
import 'file/file_service.dart';
import 'file/i_loc_file_service.dart';
import 'file/loc_file_service_impl.dart';
import 'file/export_orchestrator_service.dart';
import 'file/file_import_export_service.dart';
import 'settings/settings_service.dart';
import 'shared/event_bus.dart';
import 'shared/logging_service.dart';

// LLM Services
import 'llm/i_llm_service.dart';
import 'llm/llm_service_impl.dart';
import 'llm/llm_provider_factory.dart';
import 'llm/llm_batch_adjuster.dart';
import 'llm/llm_model_management_service.dart';
import 'llm/utils/token_calculator.dart';

// RPFM Services
import 'rpfm/i_rpfm_service.dart';
import 'rpfm/rpfm_service_impl.dart';
import 'rpfm/rpfm_cli_manager.dart';

// Project Services
import 'projects/i_project_initialization_service.dart';
import 'projects/project_initialization_service_impl.dart';

// Localization Parser
import 'file/i_localization_parser.dart';
import 'file/tsv_localization_parser.dart';

// Steam Services
import 'steam/i_steamcmd_service.dart';
import 'steam/steamcmd_service_impl.dart';
import 'steam/i_workshop_api_service.dart';
import 'steam/workshop_api_service_impl.dart';
import 'steam/steamcmd_manager.dart';
import 'steam/workshop_metadata_service.dart';
import 'steam/steam_detection_service.dart';

// Mod Services
import 'mods/workshop_scanner_service.dart';
import 'mods/game_installation_sync_service.dart';
import 'mods/mod_update_analysis_service.dart';

// Translation Services
import 'translation/i_prompt_builder_service.dart';
import 'translation/i_validation_service.dart';
import 'translation/i_translation_orchestrator.dart';
import 'translation/prompt_builder_service_impl.dart';
import 'translation/validation_service_impl.dart';
import 'translation/translation_orchestrator_impl.dart';
import 'translation/utils/batch_optimizer.dart';

// Translation Memory Services
import 'translation_memory/i_translation_memory_service.dart';
import 'translation_memory/translation_memory_service_impl.dart';
import 'translation_memory/text_normalizer.dart';
import 'translation_memory/similarity_calculator.dart';
import 'translation_memory/tm_cache.dart';
import 'translation_memory/tmx_service.dart';
import 'translation_memory/tm_import_export_service.dart';

// File Services
import 'file/utils/file_validator.dart';

// Glossary Services
import 'glossary/i_glossary_service.dart';
import 'glossary/glossary_service_impl.dart';

// History Services
import 'history/i_history_service.dart';
import 'history/history_service_impl.dart';
import '../repositories/translation_version_history_repository.dart';

// Search Services
import 'search/i_search_service.dart';
import 'search/search_service_impl.dart';

// Concurrency Services
import 'concurrency/pessimistic_lock_manager.dart';
import 'concurrency/optimistic_lock_manager.dart';
import 'concurrency/batch_isolation_manager.dart';
import 'concurrency/transaction_manager.dart';
import 'concurrency/conflict_resolver.dart';

// Validation Services
import 'validation/i_translation_validation_service.dart';
import 'validation/translation_validation_service.dart';

// Shared Services (Category 10)
import 'shared/process_service.dart';
import 'shared/notification_service.dart';
import 'shared/background_worker_service.dart';

/// Service locator for dependency injection.
///
/// Registers and provides access to all services and repositories
/// throughout the application using the GetIt package.
///
/// Usage:
/// ```dart
/// // Initialize at app startup
/// await ServiceLocator.initialize();
///
/// // Get a service
/// final projectRepo = ServiceLocator.get<ProjectRepository>();
/// final settings = ServiceLocator.get<SettingsService>();
/// ```
class ServiceLocator {
  ServiceLocator._();

  static final GetIt _locator = GetIt.instance;

  /// Single completer for all concurrent initialization requests
  /// This prevents race conditions by ensuring atomic initialization
  static Completer<void>? _initCompleter;

  /// Check if the service locator has been initialized
  static bool get isInitialized => _locator.isRegistered<DatabaseService>();

  /// Initialize all services and repositories.
  ///
  /// This must be called before accessing any services.
  /// Typically called in main() after Flutter initialization.
  ///
  /// Thread-safe: Multiple concurrent calls will wait for the first
  /// initialization to complete rather than running in parallel.
  static Future<void> initialize() async {
    // Return early if already initialized
    if (isInitialized) {
      return;
    }

    // If initialization is in progress, wait for existing completer
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    // Create new completer and start initialization
    _initCompleter = Completer<void>();

    try {
      // Initialize core services first
      await _registerCoreServices();

      // Initialize database
      await _initializeDatabase();

      // Register repositories
      _registerRepositories();

      // Register application services
      _registerApplicationServices();

      // Mark as complete
      _initCompleter!.complete();
    } catch (e) {
      // Complete with error
      _initCompleter!.completeError(e);
      // Reset for retry
      _initCompleter = null;
      rethrow;
    }
  }

  /// Register core infrastructure services
  static Future<void> _registerCoreServices() async {
    // Logging service (singleton)
    _locator.registerLazySingleton<LoggingService>(
      () => LoggingService.instance,
    );

    // Event bus (singleton)
    _locator.registerLazySingleton<EventBus>(
      () => EventBus.instance,
    );

    // File service (singleton)
    _locator.registerLazySingleton<FileService>(
      () => FileService.instance,
    );

    // Initialize logging
    final logging = _locator<LoggingService>();
    await logging.initialize();
    logging.info('Service locator initialization started');
  }

  /// Initialize database services
  static Future<void> _initializeDatabase() async {
    final logging = _locator<LoggingService>();

    try {
      // Initialize database service
      logging.info('Initializing database service');
      await DatabaseService.initialize();

      // Run migrations
      logging.info('Running database migrations');
      await MigrationService.runMigrations();

      // Ensure performance indexes exist (safe for existing databases)
      await MigrationService.ensurePerformanceIndexes();

      // Clean up orphaned and old translation batches
      logging.info('Cleaning up orphaned translation batches');
      await _cleanupTranslationBatches();

      logging.info('Database initialized successfully');
    } catch (e, stackTrace) {
      logging.error('Failed to initialize database', e, stackTrace);
      rethrow;
    }
  }

  /// Clean up orphaned and old translation batches
  static Future<void> _cleanupTranslationBatches() async {
    final logging = _locator<LoggingService>();

    try {
      // Import here to avoid circular dependencies
      final batchRepo = TranslationBatchRepository();
      final result = await batchRepo.cleanupOrphanedBatches();

      result.when(
        ok: (stats) {
          if (stats.deleted > 0) {
            logging.info(
              'Translation batch cleanup completed',
              {
                'deleted': stats.deleted,
              },
            );
          } else {
            logging.debug('No batches to clean up');
          }
        },
        err: (error) {
          // Log warning but don't fail initialization
          logging.warning(
            'Failed to clean up translation batches: ${error.message}',
          );
        },
      );
    } catch (e, stackTrace) {
      // Log warning but don't fail initialization
      logging.warning(
        'Exception during batch cleanup: $e',
        {'stackTrace': stackTrace.toString()},
      );
    }
  }

  /// Register all data repositories
  static void _registerRepositories() {
    final logging = _locator<LoggingService>();
    logging.info('Registering repositories');

    // Register repositories as lazy singletons
    _locator.registerLazySingleton<LanguageRepository>(
      () => LanguageRepository(),
    );

    _locator.registerLazySingleton<TranslationProviderRepository>(
      () => TranslationProviderRepository(),
    );

    _locator.registerLazySingleton<GameInstallationRepository>(
      () => GameInstallationRepository(),
    );

    _locator.registerLazySingleton<ProjectRepository>(
      () => ProjectRepository(),
    );

    _locator.registerLazySingleton<ProjectLanguageRepository>(
      () => ProjectLanguageRepository(),
    );

    _locator.registerLazySingleton<TranslationUnitRepository>(
      () => TranslationUnitRepository(),
    );

    _locator.registerLazySingleton<TranslationVersionRepository>(
      () => TranslationVersionRepository(),
    );

    _locator.registerLazySingleton<TranslationBatchRepository>(
      () => TranslationBatchRepository(),
    );

    _locator.registerLazySingleton<TranslationBatchUnitRepository>(
      () => TranslationBatchUnitRepository(),
    );

    _locator.registerLazySingleton<TranslationMemoryRepository>(
      () => TranslationMemoryRepository(),
    );

    _locator.registerLazySingleton<ModVersionRepository>(
      () => ModVersionRepository(),
    );

    _locator.registerLazySingleton<GlossaryRepository>(
      () => GlossaryRepository(),
    );

    _locator.registerLazySingleton<SettingsRepository>(
      () => SettingsRepository(),
    );

    _locator.registerLazySingleton<TranslationVersionHistoryRepository>(
      () => TranslationVersionHistoryRepository(),
    );

    _locator.registerLazySingleton<ExportHistoryRepository>(
      () => ExportHistoryRepository(),
    );

    _locator.registerLazySingleton<WorkshopModRepository>(
      () => WorkshopModRepository(),
    );

    _locator.registerLazySingleton<ModScanCacheRepository>(
      () => ModScanCacheRepository(),
    );

    _locator.registerLazySingleton<ModUpdateAnalysisCacheRepository>(
      () => ModUpdateAnalysisCacheRepository(),
    );

    _locator.registerLazySingleton<LlmProviderModelRepository>(
      () => LlmProviderModelRepository(),
    );

    logging.info('Repositories registered successfully');
  }

  /// Register application services
  static void _registerApplicationServices() {
    final logging = _locator<LoggingService>();
    logging.info('Registering application services');

    // Settings service
    _locator.registerLazySingleton<SettingsService>(
      () => SettingsService(_locator<SettingsRepository>()),
    );

    // LLM Services
    _locator.registerLazySingleton<TokenCalculator>(
      () => TokenCalculator(),
    );

    _locator.registerLazySingleton<LlmProviderFactory>(
      () => LlmProviderFactory(),
    );

    _locator.registerLazySingleton<LlmBatchAdjuster>(
      () => LlmBatchAdjuster(
        providerFactory: _locator<LlmProviderFactory>(),
        tokenCalculator: _locator<TokenCalculator>(),
      ),
    );

    _locator.registerLazySingleton<ILlmService>(
      () => LlmServiceImpl(
        providerFactory: _locator<LlmProviderFactory>(),
        batchAdjuster: _locator<LlmBatchAdjuster>(),
        settingsService: _locator<SettingsService>(),
        secureStorage: const FlutterSecureStorage(),
      ),
    );

    _locator.registerLazySingleton<LlmModelManagementService>(
      () => LlmModelManagementService(
        _locator<LlmProviderModelRepository>(),
        _locator<LoggingService>(),
      ),
    );

    // RPFM Services
    _locator.registerLazySingleton<RpfmCliManager>(
      () => RpfmCliManager(),
    );

    _locator.registerLazySingleton<IRpfmService>(
      () => RpfmServiceImpl(),
    );

    // Steam Services
    _locator.registerLazySingleton<SteamDetectionService>(
      () => SteamDetectionService(),
    );

    _locator.registerLazySingleton<SteamCmdManager>(
      () => SteamCmdManager(),
    );

    _locator.registerLazySingleton<ISteamCmdService>(
      () => SteamCmdServiceImpl(),
    );

    _locator.registerLazySingleton<IWorkshopApiService>(
      () => WorkshopApiServiceImpl(),
    );

    _locator.registerLazySingleton<WorkshopMetadataService>(
      () => WorkshopMetadataService(
        apiService: _locator<IWorkshopApiService>(),
        repository: _locator<WorkshopModRepository>(),
      ),
    );

    // Mod Services
    _locator.registerLazySingleton<ModUpdateAnalysisService>(
      () => ModUpdateAnalysisService(
        rpfmService: _locator<IRpfmService>(),
        locParser: _locator<ILocalizationParser>(),
        unitRepository: _locator<TranslationUnitRepository>(),
      ),
    );

    _locator.registerLazySingleton<WorkshopScannerService>(
      () => WorkshopScannerService(
        projectRepository: _locator<ProjectRepository>(),
        gameInstallationRepository: _locator<GameInstallationRepository>(),
        workshopModRepository: _locator<WorkshopModRepository>(),
        modScanCacheRepository: _locator<ModScanCacheRepository>(),
        analysisCacheRepository: _locator<ModUpdateAnalysisCacheRepository>(),
        workshopApiService: _locator<IWorkshopApiService>(),
        rpfmService: _locator<IRpfmService>(),
        modUpdateAnalysisService: _locator<ModUpdateAnalysisService>(),
      ),
    );

    _locator.registerLazySingleton<GameInstallationSyncService>(
      () => GameInstallationSyncService(
        gameInstallationRepository: _locator<GameInstallationRepository>(),
        settingsService: _locator<SettingsService>(),
      ),
    );

    // Translation Services
    _locator.registerLazySingleton<IPromptBuilderService>(
      () => PromptBuilderServiceImpl(_locator<TokenCalculator>()),
    );

    _locator.registerLazySingleton<IValidationService>(
      () => ValidationServiceImpl(),
    );

    _locator.registerLazySingleton<ITranslationOrchestrator>(
      () => TranslationOrchestratorImpl(
        llmService: _locator<ILlmService>(),
        tmService: _locator<ITranslationMemoryService>(),
        promptBuilder: _locator<IPromptBuilderService>(),
        validation: _locator<IValidationService>(),
        historyService: _locator<IHistoryService>(),
        versionRepository: _locator<TranslationVersionRepository>(),
        unitRepository: _locator<TranslationUnitRepository>(),
        batchRepository: _locator<TranslationBatchRepository>(),
        batchUnitRepository: _locator<TranslationBatchUnitRepository>(),
        isolationManager: _locator<BatchIsolationManager>(),
        transactionManager: _locator<TransactionManager>(),
        eventBus: _locator<EventBus>(),
        logger: _locator<LoggingService>(),
      ),
    );

    _locator.registerLazySingleton<BatchOptimizer>(
      () => BatchOptimizer(_locator<TokenCalculator>()),
    );

    // Translation Memory Services
    _locator.registerLazySingleton<TextNormalizer>(
      () => TextNormalizer(),
    );

    _locator.registerLazySingleton<SimilarityCalculator>(
      () => SimilarityCalculator(),
    );

    _locator.registerLazySingleton<TmCache>(
      () => TmCache(maxSize: 10000),
    );

    _locator.registerLazySingleton<TmxService>(
      () => TmxService(
        repository: _locator<TranslationMemoryRepository>(),
        normalizer: _locator<TextNormalizer>(),
      ),
    );

    _locator.registerLazySingleton<TmImportExportService>(
      () => TmImportExportService(
        repository: _locator<TranslationMemoryRepository>(),
        tmxService: _locator<TmxService>(),
        logger: _locator<LoggingService>(),
      ),
    );

    _locator.registerLazySingleton<ITranslationMemoryService>(
      () => TranslationMemoryServiceImpl(
        repository: _locator<TranslationMemoryRepository>(),
        languageRepository: _locator<LanguageRepository>(),
        normalizer: _locator<TextNormalizer>(),
        similarityCalculator: _locator<SimilarityCalculator>(),
        cache: _locator<TmCache>(),
      ),
    );

    // File Services
    _locator.registerLazySingleton<FileValidator>(
      () => FileValidator(),
    );

    _locator.registerLazySingleton<ILocFileService>(
      () => LocFileServiceImpl(
        unitRepository: _locator<TranslationUnitRepository>(),
        versionRepository: _locator<TranslationVersionRepository>(),
        projectLanguageRepository: _locator<ProjectLanguageRepository>(),
      ),
    );

    _locator.registerLazySingleton<FileImportExportService>(
      () => FileImportExportService(),
    );

    _locator.registerLazySingleton<ExportOrchestratorService>(
      () => ExportOrchestratorService(
        locFileService: _locator<ILocFileService>(),
        rpfmService: _locator<IRpfmService>(),
        fileImportExportService: _locator<FileImportExportService>(),
        tmxService: _locator<TmxService>(),
        exportHistoryRepository: _locator<ExportHistoryRepository>(),
        gameInstallationRepository: _locator<GameInstallationRepository>(),
        projectRepository: _locator<ProjectRepository>(),
        projectLanguageRepository: _locator<ProjectLanguageRepository>(),
        translationUnitRepository: _locator<TranslationUnitRepository>(),
        translationVersionRepository: _locator<TranslationVersionRepository>(),
      ),
    );

    // Glossary Services
    _locator.registerLazySingleton<IGlossaryService>(
      () => GlossaryServiceImpl(
        repository: _locator<GlossaryRepository>(),
        settingsService: _locator<SettingsService>(),
      ),
    );

    // Localization Parser (TSV format from RPFM-CLI)
    _locator.registerLazySingleton<ILocalizationParser>(
      () => TsvLocalizationParser(),
    );

    // Project Initialization Service
    _locator.registerLazySingleton<IProjectInitializationService>(
      () => ProjectInitializationServiceImpl(
        rpfmService: _locator<IRpfmService>(),
        locParser: _locator<ILocalizationParser>(),
        unitRepository: _locator<TranslationUnitRepository>(),
        versionRepository: _locator<TranslationVersionRepository>(),
        languageRepository: _locator<ProjectLanguageRepository>(),
      ),
    );

    // History Services
    _locator.registerLazySingleton<IHistoryService>(
      () => HistoryServiceImpl(
        historyRepository: _locator<TranslationVersionHistoryRepository>(),
        versionRepository: _locator<TranslationVersionRepository>(),
      ),
    );

    // Search Services
    _locator.registerLazySingleton<ISearchService>(
      () => SearchServiceImpl(
        databaseService: DatabaseService.instance,
      ),
    );

    // Validation Services
    _locator.registerLazySingleton<ITranslationValidationService>(
      () => TranslationValidationService(),
    );

    // Concurrency Services
    _locator.registerLazySingleton<PessimisticLockManager>(
      () => PessimisticLockManager(),
    );

    _locator.registerLazySingleton<OptimisticLockManager>(
      () => OptimisticLockManager(),
    );

    _locator.registerLazySingleton<BatchIsolationManager>(
      () => BatchIsolationManager(),
    );

    _locator.registerLazySingleton<TransactionManager>(
      () => TransactionManager(),
    );

    _locator.registerLazySingleton<ConflictResolver>(
      () => ConflictResolver(),
    );

    // Shared Services (Category 10 Enhancements)
    _locator.registerLazySingleton<ProcessService>(
      () => ProcessService.instance,
    );

    _locator.registerLazySingleton<NotificationService>(
      () => NotificationService.instance,
    );

    _locator.registerLazySingleton<BackgroundWorkerService>(
      () => BackgroundWorkerService.instance,
    );

    // Note: CacheService is generic and created per use case,
    // not registered as singleton

    logging.info('Application services registered successfully');
  }

  /// Get a registered service or repository.
  ///
  /// Throws an error if the type is not registered.
  ///
  /// Example:
  /// ```dart
  /// final projectRepo = ServiceLocator.get<ProjectRepository>();
  /// ```
  static T get<T extends Object>() {
    if (!_locator.isRegistered<T>()) {
      throw StateError(
        'Type $T is not registered in ServiceLocator. '
        'Did you forget to register it in initialize()?',
      );
    }
    return _locator<T>();
  }

  /// Check if a type is registered.
  static bool isRegistered<T extends Object>() {
    return _locator.isRegistered<T>();
  }

  /// Reset the service locator (for testing).
  ///
  /// WARNING: This should only be used in tests.
  static Future<void> reset() async {
    await _locator.reset();
  }

  /// Dispose of resources.
  ///
  /// Should be called when the application is shutting down.
  static Future<void> dispose() async {
    final logging = _locator<LoggingService>();
    logging.info('Service locator shutting down');

    // Close event bus
    if (_locator.isRegistered<EventBus>()) {
      await _locator<EventBus>().dispose();
    }

    // Close database
    if (DatabaseService.isInitialized) {
      await DatabaseService.close();
    }

    logging.info('Service locator shut down complete');
  }
}
