import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/release_notes/services/release_notes_service.dart';
import '../../repositories/export_history_repository.dart';
import '../../repositories/llm_provider_model_repository.dart';
import '../../repositories/mod_update_analysis_cache_repository.dart';
import '../../repositories/mod_version_repository.dart';
import '../../repositories/translation_batch_repository.dart';
import '../../repositories/translation_batch_unit_repository.dart';
import '../../repositories/translation_memory_repository.dart';
import '../../repositories/translation_version_history_repository.dart';
import '../../services/backup/database_backup_service.dart';
import '../../services/file/export_orchestrator_service.dart';
import '../../services/file/file_import_export_service.dart';
import '../../services/file/i_file_service.dart';
import '../../services/file/i_loc_file_service.dart';
import '../../services/file/i_pack_image_generator_service.dart';
import '../../services/game/game_localization_service.dart';
import '../../services/glossary/glossary_auto_provisioning_service.dart';
import '../../services/glossary/glossary_migration_service.dart';
import '../../services/glossary/i_glossary_service.dart';
import '../../services/history/i_history_service.dart';
import '../../services/llm/llm_custom_rules_service.dart';
import '../../services/llm/llm_model_management_service.dart';
import '../../services/llm/llm_provider_factory.dart';
import '../../services/mods/game_installation_sync_service.dart';
import '../../services/mods/mod_update_analysis_service.dart';
import '../../services/mods/workshop_scanner_service.dart';
import '../../services/projects/i_project_initialization_service.dart';
import '../../services/rpfm/i_rpfm_service.dart';
import '../../services/search/i_search_service.dart';
import '../../services/service_locator.dart';
import '../../services/settings/settings_service.dart';
import '../../services/shared/event_bus.dart';
import '../../services/steam/i_steamcmd_service.dart';
import '../../services/steam/i_workshop_api_service.dart';
import '../../services/steam/i_workshop_publish_service.dart';
import '../../services/steam/steam_detection_service.dart';
import '../../services/steam/steamcmd_manager.dart';
import '../../services/translation/i_prompt_builder_service.dart';
import '../../services/translation/i_translation_orchestrator.dart';
import '../../services/translation/i_validation_service.dart';
import '../../services/translation/ignored_source_text_service.dart';
import '../../services/translation_memory/i_translation_memory_service.dart';
import '../../services/updates/app_update_service.dart';
import '../../services/validation/i_translation_validation_service.dart';

part 'service_providers.g.dart';

// Services

@Riverpod(keepAlive: true)
AppUpdateService appUpdateService(Ref ref) =>
    ServiceLocator.get<AppUpdateService>();

@Riverpod(keepAlive: true)
DatabaseBackupService databaseBackupService(Ref ref) =>
    DatabaseBackupService();

@Riverpod(keepAlive: true)
EventBus eventBus(Ref ref) => EventBus.instance;

@Riverpod(keepAlive: true)
ExportOrchestratorService exportOrchestratorService(Ref ref) =>
    ServiceLocator.get<ExportOrchestratorService>();

@Riverpod(keepAlive: true)
FileImportExportService fileImportExportService(Ref ref) =>
    ServiceLocator.get<FileImportExportService>();

@Riverpod(keepAlive: true)
IFileService fileService(Ref ref) => ServiceLocator.get<IFileService>();

@Riverpod(keepAlive: true)
GameInstallationSyncService gameInstallationSyncService(Ref ref) =>
    ServiceLocator.get<GameInstallationSyncService>();

@Riverpod(keepAlive: true)
GameLocalizationService gameLocalizationService(Ref ref) =>
    ServiceLocator.get<GameLocalizationService>();

@Riverpod(keepAlive: true)
IGlossaryService glossaryService(Ref ref) =>
    ServiceLocator.get<IGlossaryService>();

@Riverpod(keepAlive: true)
GlossaryMigrationService glossaryMigrationService(Ref ref) =>
    ServiceLocator.get<GlossaryMigrationService>();

@Riverpod(keepAlive: true)
GlossaryAutoProvisioningService glossaryAutoProvisioningService(Ref ref) =>
    ServiceLocator.get<GlossaryAutoProvisioningService>();

@Riverpod(keepAlive: true)
IHistoryService historyService(Ref ref) =>
    ServiceLocator.get<IHistoryService>();

@Riverpod(keepAlive: true)
IgnoredSourceTextService ignoredSourceTextService(Ref ref) =>
    ServiceLocator.get<IgnoredSourceTextService>();

@Riverpod(keepAlive: true)
LlmCustomRulesService llmCustomRulesService(Ref ref) =>
    ServiceLocator.get<LlmCustomRulesService>();

@Riverpod(keepAlive: true)
LlmModelManagementService llmModelManagementService(Ref ref) =>
    ServiceLocator.get<LlmModelManagementService>();

@Riverpod(keepAlive: true)
LlmProviderFactory llmProviderFactory(Ref ref) =>
    ServiceLocator.get<LlmProviderFactory>();

@Riverpod(keepAlive: true)
ILocFileService locFileService(Ref ref) =>
    ServiceLocator.get<ILocFileService>();

@Riverpod(keepAlive: true)
ModUpdateAnalysisService modUpdateAnalysisService(Ref ref) =>
    ServiceLocator.get<ModUpdateAnalysisService>();

@Riverpod(keepAlive: true)
IPackImageGeneratorService packImageGeneratorService(Ref ref) =>
    ServiceLocator.get<IPackImageGeneratorService>();

@Riverpod(keepAlive: true)
IProjectInitializationService projectInitializationService(Ref ref) =>
    ServiceLocator.get<IProjectInitializationService>();

@Riverpod(keepAlive: true)
IPromptBuilderService promptBuilderService(Ref ref) =>
    ServiceLocator.get<IPromptBuilderService>();

@Riverpod(keepAlive: true)
ReleaseNotesService releaseNotesService(Ref ref) =>
    ServiceLocator.get<ReleaseNotesService>();

@Riverpod(keepAlive: true)
IRpfmService rpfmService(Ref ref) => ServiceLocator.get<IRpfmService>();

@Riverpod(keepAlive: true)
ISearchService searchService(Ref ref) => ServiceLocator.get<ISearchService>();

@Riverpod(keepAlive: true)
SettingsService settingsService(Ref ref) =>
    ServiceLocator.get<SettingsService>();

@Riverpod(keepAlive: true)
SteamDetectionService steamDetectionService(Ref ref) =>
    ServiceLocator.get<SteamDetectionService>();

@Riverpod(keepAlive: true)
SteamCmdManager steamCmdManager(Ref ref) =>
    ServiceLocator.get<SteamCmdManager>();

@Riverpod(keepAlive: true)
ISteamCmdService steamCmdService(Ref ref) =>
    ServiceLocator.get<ISteamCmdService>();

@Riverpod(keepAlive: true)
ITranslationMemoryService translationMemoryService(Ref ref) =>
    ServiceLocator.get<ITranslationMemoryService>();

@Riverpod(keepAlive: true)
ITranslationOrchestrator translationOrchestrator(Ref ref) =>
    ServiceLocator.get<ITranslationOrchestrator>();

@Riverpod(keepAlive: true)
ITranslationValidationService translationValidationService(Ref ref) =>
    ServiceLocator.get<ITranslationValidationService>();

@Riverpod(keepAlive: true)
IValidationService validationService(Ref ref) =>
    ServiceLocator.get<IValidationService>();

@Riverpod(keepAlive: true)
IWorkshopPublishService workshopPublishService(Ref ref) =>
    ServiceLocator.get<IWorkshopPublishService>();

@Riverpod(keepAlive: true)
IWorkshopApiService workshopApiService(Ref ref) =>
    ServiceLocator.get<IWorkshopApiService>();

@Riverpod(keepAlive: true)
WorkshopScannerService workshopScannerService(Ref ref) =>
    ServiceLocator.get<WorkshopScannerService>();

// Repositories

@Riverpod(keepAlive: true)
ExportHistoryRepository exportHistoryRepository(Ref ref) =>
    ServiceLocator.get<ExportHistoryRepository>();

@Riverpod(keepAlive: true)
LlmProviderModelRepository llmProviderModelRepository(Ref ref) =>
    ServiceLocator.get<LlmProviderModelRepository>();

@Riverpod(keepAlive: true)
ModUpdateAnalysisCacheRepository modUpdateAnalysisCacheRepository(Ref ref) =>
    ServiceLocator.get<ModUpdateAnalysisCacheRepository>();

@Riverpod(keepAlive: true)
ModVersionRepository modVersionRepository(Ref ref) =>
    ServiceLocator.get<ModVersionRepository>();

@Riverpod(keepAlive: true)
TranslationBatchRepository translationBatchRepository(Ref ref) =>
    ServiceLocator.get<TranslationBatchRepository>();

@Riverpod(keepAlive: true)
TranslationBatchUnitRepository translationBatchUnitRepository(Ref ref) =>
    ServiceLocator.get<TranslationBatchUnitRepository>();

@Riverpod(keepAlive: true)
TranslationMemoryRepository translationMemoryRepository(Ref ref) =>
    ServiceLocator.get<TranslationMemoryRepository>();

@Riverpod(keepAlive: true)
TranslationVersionHistoryRepository translationVersionHistoryRepository(
  Ref ref,
) =>
    ServiceLocator.get<TranslationVersionHistoryRepository>();
