import 'dart:async';

import 'package:get_it/get_it.dart';

import '../repositories/translation_batch_repository.dart';
import 'database/database_service.dart';
import 'database/migration_service.dart';
import 'locators/core_service_locator.dart';
import 'locators/file_service_locator.dart';
import 'locators/glossary_service_locator.dart';
import 'locators/llm_service_locator.dart';
import 'locators/repository_locator.dart';
import 'locators/translation_service_locator.dart';
import 'rpfm/rpfm_service_impl.dart';
import 'rpfm/i_rpfm_service.dart';
import 'mods/workshop_scanner_service.dart';
import 'shared/event_bus.dart';
import 'shared/logging_service.dart';
import 'translation/ignored_source_text_service.dart';
import 'translation/utils/translation_skip_filter.dart';

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

  /// Single completer for all concurrent initialization requests.
  /// This prevents race conditions by ensuring atomic initialization.
  static Completer<void>? _initCompleter;

  /// Check if the service locator has been initialized.
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
      // 1. Register core infrastructure (logging, events, files)
      await CoreServiceLocator.registerInfrastructure(_locator);

      // 2. Initialize database
      await _initializeDatabase();

      // 3. Register repositories (data layer)
      RepositoryLocator.register(_locator);

      // 4. Register core services (settings, RPFM, Steam, concurrency)
      CoreServiceLocator.register(_locator);

      // 5. Register LLM services
      LlmServiceLocator.register(_locator);

      // 6. Register translation services (depends on LLM)
      TranslationServiceLocator.register(_locator);

      // 7. Register file services (depends on translation services)
      FileServiceLocator.register(_locator);

      // 8. Register glossary services
      GlossaryServiceLocator.register(_locator);

      // 9. Initialize TranslationSkipFilter with service
      await _initializeTranslationSkipFilter();

      // Note: Data migrations (TM hash, TM rebuild) are handled by
      // DataMigrationProvider in the UI layer with progress dialog

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

  /// Initialize database services.
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

  /// Clean up orphaned and old translation batches.
  static Future<void> _cleanupTranslationBatches() async {
    final logging = _locator<LoggingService>();

    try {
      final batchRepo = TranslationBatchRepository();
      final result = await batchRepo.cleanupOrphanedBatches();

      result.when(
        ok: (stats) {
          if (stats.deleted > 0) {
            logging.info(
              'Translation batch cleanup completed',
              {'deleted': stats.deleted},
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

  /// Initialize the TranslationSkipFilter with the database-backed service.
  static Future<void> _initializeTranslationSkipFilter() async {
    final logging = _locator<LoggingService>();
    try {
      final service = _locator<IgnoredSourceTextService>();
      TranslationSkipFilter.initialize(service);
      await service.ensureCacheLoaded();
      logging.info('TranslationSkipFilter initialized with database service');
    } catch (e, stackTrace) {
      logging.error('Failed to initialize TranslationSkipFilter', e, stackTrace);
      // Non-fatal: skip filter will use hardcoded fallback
    }
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

    // Dispose services with stream controllers
    if (_locator.isRegistered<IRpfmService>()) {
      final rpfmService = _locator<IRpfmService>();
      if (rpfmService is RpfmServiceImpl) {
        rpfmService.dispose();
      }
    }

    if (_locator.isRegistered<WorkshopScannerService>()) {
      _locator<WorkshopScannerService>().dispose();
    }

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
