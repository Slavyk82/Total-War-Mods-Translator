import 'package:get_it/get_it.dart';

import '../../repositories/export_history_repository.dart';
import '../../repositories/game_installation_repository.dart';
import '../../repositories/language_repository.dart';
import '../../repositories/mod_scan_cache_repository.dart';
import '../../repositories/mod_update_analysis_cache_repository.dart';
import '../../repositories/project_language_repository.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/translation_unit_repository.dart';
import '../../repositories/translation_version_repository.dart';
import '../../repositories/workshop_mod_repository.dart';
import '../file/export_orchestrator_service.dart';
import '../file/file_import_export_service.dart';
import '../file/i_loc_file_service.dart';
import '../file/i_localization_parser.dart';
import '../file/i_pack_image_generator_service.dart';
import '../file/loc_file_service_impl.dart';
import '../file/pack_image_generator_service.dart';
import '../file/tsv_localization_parser.dart';
import '../file/utils/file_validator.dart';
import '../mods/game_installation_sync_service.dart';
import '../mods/mod_update_analysis_service.dart';
import '../mods/workshop_scanner_service.dart';
import '../projects/i_project_initialization_service.dart';
import '../projects/project_initialization_service_impl.dart';
import '../rpfm/i_rpfm_service.dart';
import '../settings/settings_service.dart';
import '../shared/logging_service.dart';
import '../steam/i_workshop_api_service.dart';
import '../translation_memory/tmx_service.dart';

/// Registers file, import/export, and mod-related services.
///
/// This includes:
/// - File validation and parsing
/// - LOC file services
/// - Import/export orchestration
/// - Mod scanning and sync services
/// - Project initialization
class FileServiceLocator {
  FileServiceLocator._();

  /// Register all file services with the GetIt locator.
  static void register(GetIt locator) {
    final logging = locator<LoggingService>();
    logging.info('Registering file services');

    // File Validation
    locator.registerLazySingleton<FileValidator>(
      () => FileValidator(),
    );

    // Localization Parser (TSV format from RPFM-CLI)
    locator.registerLazySingleton<ILocalizationParser>(
      () => TsvLocalizationParser(),
    );

    // LOC File Service
    locator.registerLazySingleton<ILocFileService>(
      () => LocFileServiceImpl(
        unitRepository: locator<TranslationUnitRepository>(),
        versionRepository: locator<TranslationVersionRepository>(),
        projectLanguageRepository: locator<ProjectLanguageRepository>(),
        languageRepository: locator<LanguageRepository>(),
      ),
    );

    // File Import/Export
    locator.registerLazySingleton<FileImportExportService>(
      () => FileImportExportService(),
    );

    // Pack Image Generator
    locator.registerLazySingleton<IPackImageGeneratorService>(
      () => PackImageGeneratorService(),
    );

    // Export Orchestrator
    locator.registerLazySingleton<ExportOrchestratorService>(
      () => ExportOrchestratorService(
        locFileService: locator<ILocFileService>(),
        rpfmService: locator<IRpfmService>(),
        fileImportExportService: locator<FileImportExportService>(),
        tmxService: locator<TmxService>(),
        packImageGenerator: locator<IPackImageGeneratorService>(),
        exportHistoryRepository: locator<ExportHistoryRepository>(),
        gameInstallationRepository: locator<GameInstallationRepository>(),
        projectRepository: locator<ProjectRepository>(),
        projectLanguageRepository: locator<ProjectLanguageRepository>(),
        translationUnitRepository: locator<TranslationUnitRepository>(),
        translationVersionRepository: locator<TranslationVersionRepository>(),
      ),
    );

    // Mod Update Analysis Service
    locator.registerLazySingleton<ModUpdateAnalysisService>(
      () => ModUpdateAnalysisService(
        rpfmService: locator<IRpfmService>(),
        locParser: locator<ILocalizationParser>(),
        unitRepository: locator<TranslationUnitRepository>(),
        versionRepository: locator<TranslationVersionRepository>(),
        languageRepository: locator<ProjectLanguageRepository>(),
      ),
    );

    // Workshop Scanner Service
    locator.registerLazySingleton<WorkshopScannerService>(
      () => WorkshopScannerService(
        projectRepository: locator<ProjectRepository>(),
        gameInstallationRepository: locator<GameInstallationRepository>(),
        workshopModRepository: locator<WorkshopModRepository>(),
        modScanCacheRepository: locator<ModScanCacheRepository>(),
        analysisCacheRepository: locator<ModUpdateAnalysisCacheRepository>(),
        workshopApiService: locator<IWorkshopApiService>(),
        rpfmService: locator<IRpfmService>(),
        modUpdateAnalysisService: locator<ModUpdateAnalysisService>(),
      ),
    );

    // Game Installation Sync Service
    locator.registerLazySingleton<GameInstallationSyncService>(
      () => GameInstallationSyncService(
        gameInstallationRepository: locator<GameInstallationRepository>(),
        settingsService: locator<SettingsService>(),
      ),
    );

    // Project Initialization Service
    locator.registerLazySingleton<IProjectInitializationService>(
      () => ProjectInitializationServiceImpl(
        rpfmService: locator<IRpfmService>(),
        locParser: locator<ILocalizationParser>(),
        unitRepository: locator<TranslationUnitRepository>(),
        versionRepository: locator<TranslationVersionRepository>(),
        languageRepository: locator<ProjectLanguageRepository>(),
        analysisCacheRepository: locator<ModUpdateAnalysisCacheRepository>(),
      ),
    );

    logging.info('File services registered successfully');
  }
}
