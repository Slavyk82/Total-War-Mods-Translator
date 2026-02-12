import 'package:get_it/get_it.dart';

import '../../repositories/settings_repository.dart';
import '../concurrency/batch_isolation_manager.dart';
import '../concurrency/conflict_resolver.dart';
import '../concurrency/optimistic_lock_manager.dart';
import '../concurrency/pessimistic_lock_manager.dart';
import '../concurrency/transaction_manager.dart';
import '../database/database_service.dart';
import '../file/file_service.dart';
import '../rpfm/i_rpfm_service.dart';
import '../rpfm/rpfm_cli_manager.dart';
import '../rpfm/rpfm_service_impl.dart';
import '../search/i_search_service.dart';
import '../search/search_service_impl.dart';
import '../settings/settings_service.dart';
import '../shared/background_worker_service.dart';
import '../shared/event_bus.dart';
import '../shared/logging_service.dart';
import '../shared/process_service.dart';
import '../steam/i_steamcmd_service.dart';
import '../steam/i_workshop_api_service.dart';
import '../steam/i_workshop_publish_service.dart';
import '../steam/steam_detection_service.dart';
import '../steam/steamcmd_manager.dart';
import '../steam/steamcmd_service_impl.dart';
import '../steam/workshop_api_service_impl.dart';
import '../steam/workshop_metadata_service.dart';
import '../steam/workshop_publish_service_impl.dart';
import '../../repositories/workshop_mod_repository.dart';
import '../updates/app_update_service.dart';
import '../game/game_localization_service.dart';
import '../../features/release_notes/services/release_notes_service.dart';

/// Registers core infrastructure and miscellaneous services.
///
/// This includes:
/// - Logging and event bus
/// - File service
/// - Settings service
/// - Concurrency management
/// - RPFM and Steam services
/// - Search service
/// - Process and background worker services
/// - App update service
class CoreServiceLocator {
  CoreServiceLocator._();

  /// Register core infrastructure services (logging, events, files).
  ///
  /// These must be registered first as other services depend on them.
  static Future<void> registerInfrastructure(GetIt locator) async {
    // Logging service (singleton)
    locator.registerLazySingleton<LoggingService>(
      () => LoggingService.instance,
    );

    // Event bus (singleton)
    locator.registerLazySingleton<EventBus>(
      () => EventBus.instance,
    );

    // File service (singleton)
    locator.registerLazySingleton<FileService>(
      () => FileService.instance,
    );

    // Initialize logging
    final logging = locator<LoggingService>();
    await logging.initialize();
    logging.info('Core infrastructure services registered');
  }

  /// Register all remaining core services with the GetIt locator.
  static void register(GetIt locator) {
    final logging = locator<LoggingService>();
    logging.info('Registering core services');

    // Settings service
    locator.registerLazySingleton<SettingsService>(
      () => SettingsService(locator<SettingsRepository>()),
    );

    // RPFM Services
    locator.registerLazySingleton<RpfmCliManager>(
      () => RpfmCliManager(),
    );

    locator.registerLazySingleton<IRpfmService>(
      () => RpfmServiceImpl(),
    );

    // Steam Services
    locator.registerLazySingleton<SteamDetectionService>(
      () => SteamDetectionService(),
    );

    locator.registerLazySingleton<SteamCmdManager>(
      () => SteamCmdManager(),
    );

    locator.registerLazySingleton<ISteamCmdService>(
      () => SteamCmdServiceImpl(),
    );

    locator.registerLazySingleton<IWorkshopApiService>(
      () => WorkshopApiServiceImpl(),
    );

    locator.registerLazySingleton<WorkshopMetadataService>(
      () => WorkshopMetadataService(
        apiService: locator<IWorkshopApiService>(),
        repository: locator<WorkshopModRepository>(),
      ),
    );

    locator.registerLazySingleton<IWorkshopPublishService>(
      () => WorkshopPublishServiceImpl(),
    );

    // Concurrency Services
    locator.registerLazySingleton<PessimisticLockManager>(
      () => PessimisticLockManager(),
    );

    locator.registerLazySingleton<OptimisticLockManager>(
      () => OptimisticLockManager(),
    );

    locator.registerLazySingleton<BatchIsolationManager>(
      () => BatchIsolationManager(),
    );

    locator.registerLazySingleton<TransactionManager>(
      () => TransactionManager(),
    );

    locator.registerLazySingleton<ConflictResolver>(
      () => ConflictResolver(),
    );

    // Search Services
    locator.registerLazySingleton<ISearchService>(
      () => SearchServiceImpl(
        databaseService: DatabaseService.instance,
      ),
    );

    // Shared Services
    locator.registerLazySingleton<ProcessService>(
      () => ProcessService.instance,
    );

    locator.registerLazySingleton<BackgroundWorkerService>(
      () => BackgroundWorkerService.instance,
    );

    // Update Services
    locator.registerLazySingleton<AppUpdateService>(
      () => AppUpdateService(),
    );

    // Game Services
    locator.registerLazySingleton<GameLocalizationService>(
      () => GameLocalizationService(),
    );

    // Release Notes Service
    locator.registerLazySingleton<ReleaseNotesService>(
      () => ReleaseNotesService(
        settingsService: locator<SettingsService>(),
        updateService: locator<AppUpdateService>(),
      ),
    );

    logging.info('Core services registered successfully');
  }
}
