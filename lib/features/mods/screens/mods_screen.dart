import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';
import 'package:twmt/features/mods/widgets/detected_mods_datagrid.dart';
import 'package:twmt/features/mods/widgets/mods_toolbar.dart';
import 'package:twmt/features/projects/widgets/project_initialization_dialog.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/projects/i_project_initialization_service.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/providers/selected_game_provider.dart';

/// Complete mods screen with Syncfusion DataGrid
class ModsScreen extends ConsumerStatefulWidget {
  const ModsScreen({super.key});

  @override
  ConsumerState<ModsScreen> createState() => _ModsScreenState();
}

class _ModsScreenState extends ConsumerState<ModsScreen> {
  @override
  Widget build(BuildContext context) {
    LoggingService.instance.debug('ModsScreen build() called');
    final theme = Theme.of(context);
    // Synchronous filtered mods - instant filtering
    final filteredMods = ref.watch(filteredModsProvider);
    LoggingService.instance.debug('filteredMods count: ${filteredMods.length}');
    // Loading/error state from source provider
    final isInitialLoading = ref.watch(modsIsLoadingProvider);
    final modsError = ref.watch(modsErrorProvider);
    final searchQuery = ref.watch(modsSearchQueryProvider);
    final isRefreshing = ref.watch(modsLoadingStateProvider);
    final currentFilter = ref.watch(modsFilterStateProvider);
    final totalModsAsync = ref.watch(totalModsCountProvider);
    final notImportedCountAsync = ref.watch(notImportedModsCountProvider);
    final needsUpdateCountAsync = ref.watch(needsUpdateModsCountProvider);
    final showHidden = ref.watch(showHiddenModsProvider);
    final hiddenCountAsync = ref.watch(hiddenModsCountProvider);
    final pendingProjectsCountAsync = ref.watch(projectsWithPendingChangesCountProvider);

    return FluentScaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(theme),
            const SizedBox(height: 24),

            // Toolbar - always responsive, uses sync filtered mods
            ModsToolbar(
              searchQuery: searchQuery,
              onSearchChanged: (query) {
                ref.read(modsSearchQueryProvider.notifier).setQuery(query);
              },
              onRefresh: () => _handleRefresh(),
              isRefreshing: isRefreshing || isInitialLoading,
              totalMods: totalModsAsync.value ?? 0,
              filteredMods: filteredMods.length,
              currentFilter: currentFilter,
              onFilterChanged: (filter) {
                ref.read(modsFilterStateProvider.notifier).setFilter(filter);
              },
              notImportedCount: notImportedCountAsync.value ?? 0,
              needsUpdateCount: needsUpdateCountAsync.value ?? 0,
              showHidden: showHidden,
              onShowHiddenChanged: (value) {
                LoggingService.instance.debug('onShowHiddenChanged called with: $value');
                ref.read(showHiddenModsProvider.notifier).set(value);
                LoggingService.instance.debug('showHiddenModsProvider.set() done');
              },
              hiddenCount: hiddenCountAsync.value ?? 0,
              projectsWithPendingChanges: pendingProjectsCountAsync.value ?? 0,
              onNavigateToProjects: () => _navigateToProjectsWithFilter(context),
              onImportLocalPack: () => _handleImportLocalPack(context),
            ),
            const SizedBox(height: 16),

            // DataGrid
            Expanded(
              child: modsError != null
                  ? _buildErrorState(theme, modsError)
                  : DetectedModsDataGrid(
                      mods: filteredMods,
                      onRowTap: (workshopId) => _openCreateProjectDialog(context, filteredMods, workshopId),
                      onToggleHidden: (workshopId, hide) => _handleToggleHidden(workshopId, hide),
                      onForceRedownload: (packFilePath) => _handleForceRedownload(context, packFilePath),
                      isLoading: isInitialLoading,
                      isScanning: isRefreshing,
                      showingHidden: showHidden,
                      scanLogStream: (isRefreshing || isInitialLoading) ? ref.watch(scanLogStreamProvider) : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Icon(
          FluentIcons.cube_24_regular,
          size: 32,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Text(
          'Mods',
          style: theme.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(ThemeData theme, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 64,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading mods',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _buildRetryButton(theme),
        ],
      ),
    );
  }

  Widget _buildRetryButton(ThemeData theme) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _handleRefresh(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.arrow_sync_24_regular,
                color: theme.colorScheme.onPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                'Retry',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    ref.read(modsLoadingStateProvider.notifier).setLoading(true);

    // Clear cache and invalidate provider to force a rescan
    await ref.read(modsRefreshTriggerProvider.notifier).refresh();

    // Set up subscription after triggering refresh to wait for completion
    late final ProviderSubscription<AsyncValue<List<DetectedMod>>> subscription;
    subscription = ref.listenManual(
      detectedModsProvider,
      (previous, next) {
        // When data arrives AND loading is complete, reset loading state
        // Check !next.isLoading because Riverpod keeps previous value during reload
        if (next.hasValue && !next.isLoading && mounted) {
          ref.read(modsLoadingStateProvider.notifier).setLoading(false);
          subscription.close();
        }
      },
      fireImmediately: true,
    );
  }

  void _navigateToProjectsWithFilter(BuildContext context) {
    // Set the quick filter to show only projects with updates
    ref.read(projectsFilterProvider.notifier).setQuickFilter(ProjectQuickFilter.needsUpdate);
    // Navigate to projects screen
    GoRouter.of(context).go('/projects');
  }

  Future<void> _handleToggleHidden(String workshopId, bool hide) async {
    LoggingService.instance.debug('_handleToggleHidden called: workshopId=$workshopId, hide=$hide');
    await ref.read(modHiddenToggleProvider.notifier).toggleHidden(workshopId, hide);
    LoggingService.instance.debug('_handleToggleHidden done');
    // No need to invalidate - the mod list is updated locally by the provider
  }

  Future<void> _handleForceRedownload(BuildContext context, String packFilePath) async {
    try {
      final file = File(packFilePath);
      if (await file.exists()) {
        await file.delete();
        if (!context.mounted) return;
        FluentToast.success(
          context,
          'Pack file deleted. Launch the game to redownload.',
        );
        _handleRefresh();
      } else {
        if (!context.mounted) return;
        FluentToast.warning(context, 'File not found: $packFilePath');
      }
    } catch (e) {
      if (!context.mounted) return;
      FluentToast.error(context, 'Failed to delete file: $e');
    }
  }

  Future<void> _openCreateProjectDialog(
    BuildContext context,
    List<DetectedMod> mods,
    String workshopId,
  ) async {
    // Find the mod by workshopId
    DetectedMod mod;
    try {
      mod = mods.firstWhere(
        (m) => m.workshopId == workshopId,
      );
    } catch (e) {
      return;
    }

    final router = GoRouter.of(context);

    // Check if a project already exists for this workshop ID
    final projectRepo = ref.read(projectRepositoryProvider);
    final projectsResult = await projectRepo.getAll();

    if (projectsResult.isOk) {
      final projects = projectsResult.unwrap();
      final existingProject = projects.where(
        (project) => project.modSteamId == workshopId,
      ).firstOrNull;

      if (existingProject != null) {
        // If project exists, navigate to it
        router.go('/projects/${existingProject.id}');
        return;
      }
    }

    // Create project directly
    if (context.mounted) {
      await _createProjectDirectly(context, mod, router);
    }
  }

  Future<void> _createProjectDirectly(
    BuildContext context,
    DetectedMod mod,
    GoRouter router,
  ) async {
    final projectRepo = ref.read(projectRepositoryProvider);
    String? projectId;

    try {
      // Validate RPFM schema path is configured
      final settingsService = ServiceLocator.get<SettingsService>();
      final schemaPath = await settingsService.getString('rpfm_schema_path');

      if (schemaPath.isEmpty) {
        if (!context.mounted) return;
        FluentToast.error(
          context,
          'RPFM schema path is not configured. Please configure it in Settings > RPFM Tool.',
        );
        return;
      }

      // Load workshop mod and game installation
      final workshopRepo = ref.read(workshopModRepositoryProvider);
      final modResult = await workshopRepo.getByWorkshopId(mod.workshopId);

      if (modResult.isErr) {
        if (!context.mounted) return;
        FluentToast.error(
          context,
          'Failed to load mod data: ${modResult.error}',
        );
        return;
      }

      final workshopMod = modResult.unwrap();

      // Find game installation matching the mod's appId
      // Wait for games to load
      final games = await ref.read(allGameInstallationsProvider.future);
      String? gameId;
      String? outputFolder;

      final matchingGame = games.firstWhere(
        (game) =>
            game.steamAppId != null &&
            int.tryParse(game.steamAppId!) == workshopMod.appId,
        orElse: () =>
            games.isNotEmpty ? games.first : throw StateError('No games found'),
      );
      gameId = matchingGame.id;
      if (matchingGame.installationPath != null) {
        outputFolder = path.join(matchingGame.installationPath!, 'data');
      }

      if (outputFolder == null) {
        if (!context.mounted) return;
        FluentToast.error(context, 'Game installation path is not configured');
        return;
      }

      // Create project
      const uuid = Uuid();
      projectId = uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final metadata = ProjectMetadata(
        modTitle: mod.name,
        modImageUrl: mod.imageUrl,
      );

      final project = Project(
        id: projectId,
        name: mod.name,
        modSteamId: mod.workshopId,
        gameInstallationId: gameId,
        sourceFilePath: mod.packFilePath,
        outputFilePath: outputFolder,
        batchSize: 25,
        parallelBatches: 3,
        createdAt: now,
        updatedAt: now,
        metadata: metadata.toJsonString(),
      );

      final createResult = await projectRepo.insert(project);

      if (createResult.isErr) {
        if (!context.mounted) return;
        FluentToast.error(
          context,
          'Failed to create project: ${createResult.error}',
        );
        return;
      }

      // Add favorite language to the project
      final languageRepo = ServiceLocator.get<LanguageRepository>();
      final projectLanguageRepo = ServiceLocator.get<ProjectLanguageRepository>();

      final favoriteLanguageCode = await settingsService.getString(
        SettingsKeys.defaultTargetLanguage,
        defaultValue: SettingsKeys.defaultTargetLanguageValue,
      );

      final languageResult = await languageRepo.getByCode(favoriteLanguageCode);
      if (languageResult.isOk) {
        final language = languageResult.unwrap();
        final projectLanguage = ProjectLanguage(
          id: uuid.v4(),
          projectId: projectId,
          languageId: language.id,
          createdAt: now,
          updatedAt: now,
        );
        await projectLanguageRepo.insert(projectLanguage);
      }

      // Show initialization dialog
      if (!context.mounted) return;

      final initService = ServiceLocator.get<IProjectInitializationService>();

      final success = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => ProjectInitializationDialog(
          projectName: mod.name,
          logStream: initService.logStream,
          onInitialize: () => initService.initializeProject(
            projectId: projectId!,
            packFilePath: mod.packFilePath,
          ).then((result) {
            if (result.isErr) {
              throw Exception(result.error);
            }
            return result.value;
          }),
        ),
      );

      if (success == true) {
        // Refresh projects list
        ref.invalidate(projectsWithDetailsProvider);
        _handleRefresh();

        // Navigate to project detail screen
        if (context.mounted) {
          router.go('/projects/$projectId');
        }
      } else {
        // Delete the project if initialization failed (no loc files or error)
        await projectRepo.delete(projectId);
        if (context.mounted) {
          FluentToast.warning(
            context,
            'Project not created: no localization files found in the mod.',
          );
        }
      }
    } catch (e) {
      // Delete the project on error if it was created
      if (projectId != null) {
        await projectRepo.delete(projectId);
      }
      if (context.mounted) {
        FluentToast.error(
          context,
          'Failed to create project: $e',
        );
      }
    }
  }

  Future<void> _handleImportLocalPack(BuildContext context) async {
    // 1. Get selected game for default path
    final selectedGame = await ref.read(selectedGameProvider.future);
    if (selectedGame == null) {
      if (context.mounted) {
        FluentToast.warning(context, 'No game selected. Please select a game first.');
      }
      return;
    }

    // 2. Default folder = game's data folder
    final defaultPath = path.join(selectedGame.path, 'data');

    // 3. Open file picker
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pack'],
      initialDirectory: defaultPath,
      dialogTitle: 'Select a .pack file',
    );

    if (result == null || result.files.isEmpty) return;

    final packPath = result.files.single.path;
    if (packPath == null) return;

    // 4. Show warning about non-Workshop pack
    if (!context.mounted) return;
    final confirmed = await _showLocalPackWarning(context);
    if (!confirmed) return;

    // 5. Get project name from user
    final packFileName = path.basenameWithoutExtension(packPath);
    if (!context.mounted) return;
    final projectName = await _showLocalPackNameDialog(context, packFileName);
    if (projectName == null || projectName.trim().isEmpty) return;

    // 6. Create the project
    if (!context.mounted) return;
    await _createLocalPackProject(context, packPath, projectName.trim(), selectedGame);
  }

  Future<bool> _showLocalPackWarning(BuildContext context) async {
    final theme = Theme.of(context);
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              FluentIcons.warning_24_regular,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 12),
            const Text('Local Pack File'),
          ],
        ),
        content: const SizedBox(
          width: 450,
          child: Text(
            'This pack file is not linked to the Steam Workshop.\n\n'
            'The mod will not be automatically updated when the author releases a new version. '
            'You will need to manually reimport the pack file to get updates.',
          ),
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FluentButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import Anyway'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<String?> _showLocalPackNameDialog(BuildContext context, String defaultName) async {
    final controller = TextEditingController(text: defaultName);
    final theme = Theme.of(context);

    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              FluentIcons.edit_24_regular,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            const Text('Project Name'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Enter project name',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          FluentButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create Project'),
          ),
        ],
      ),
    );
  }

  Future<void> _createLocalPackProject(
    BuildContext context,
    String packFilePath,
    String projectName,
    ConfiguredGame selectedGame,
  ) async {
    final projectRepo = ref.read(projectRepositoryProvider);
    final router = GoRouter.of(context);
    String? projectId;

    try {
      // Validate RPFM schema path is configured
      final settingsService = ServiceLocator.get<SettingsService>();
      final schemaPath = await settingsService.getString('rpfm_schema_path');

      if (schemaPath.isEmpty) {
        if (!context.mounted) return;
        FluentToast.error(
          context,
          'RPFM schema path is not configured. Please configure it in Settings > RPFM Tool.',
        );
        return;
      }

      // Find game installation matching the selected game
      final games = await ref.read(allGameInstallationsProvider.future);
      final matchingGame = games.firstWhere(
        (game) => game.gameCode == selectedGame.code,
        orElse: () => games.isNotEmpty ? games.first : throw StateError('No games found'),
      );

      final outputFolder = matchingGame.installationPath != null
          ? path.join(matchingGame.installationPath!, 'data')
          : null;

      if (outputFolder == null) {
        if (!context.mounted) return;
        FluentToast.error(context, 'Game installation path is not configured');
        return;
      }

      // Create project
      const uuid = Uuid();
      projectId = uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final metadata = ProjectMetadata(
        modTitle: projectName,
        modImageUrl: null,
      );

      final project = Project(
        id: projectId,
        name: projectName,
        modSteamId: null, // Not linked to Steam Workshop
        gameInstallationId: matchingGame.id,
        sourceFilePath: packFilePath,
        outputFilePath: outputFolder,
        batchSize: 25,
        parallelBatches: 3,
        createdAt: now,
        updatedAt: now,
        metadata: metadata.toJsonString(),
      );

      final createResult = await projectRepo.insert(project);

      if (createResult.isErr) {
        if (!context.mounted) return;
        FluentToast.error(
          context,
          'Failed to create project: ${createResult.error}',
        );
        return;
      }

      // Add favorite language to the project
      final languageRepo = ServiceLocator.get<LanguageRepository>();
      final projectLanguageRepo = ServiceLocator.get<ProjectLanguageRepository>();

      final favoriteLanguageCode = await settingsService.getString(
        SettingsKeys.defaultTargetLanguage,
        defaultValue: SettingsKeys.defaultTargetLanguageValue,
      );

      final languageResult = await languageRepo.getByCode(favoriteLanguageCode);
      if (languageResult.isOk) {
        final language = languageResult.unwrap();
        final projectLanguage = ProjectLanguage(
          id: uuid.v4(),
          projectId: projectId,
          languageId: language.id,
          createdAt: now,
          updatedAt: now,
        );
        await projectLanguageRepo.insert(projectLanguage);
      }

      // Show initialization dialog
      if (!context.mounted) return;

      final initService = ServiceLocator.get<IProjectInitializationService>();

      final success = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => ProjectInitializationDialog(
          projectName: projectName,
          logStream: initService.logStream,
          onInitialize: () => initService.initializeProject(
            projectId: projectId!,
            packFilePath: packFilePath,
          ).then((result) {
            if (result.isErr) {
              throw Exception(result.error);
            }
            return result.value;
          }),
        ),
      );

      if (success == true) {
        // Refresh projects list
        ref.invalidate(projectsWithDetailsProvider);

        // Navigate to project detail screen
        if (context.mounted) {
          router.go('/projects/$projectId');
        }
      } else {
        // Delete the project if initialization failed (no loc files or error)
        await projectRepo.delete(projectId);
        if (context.mounted) {
          FluentToast.warning(
            context,
            'Project not created: no localization files found in the pack.',
          );
        }
      }
    } catch (e) {
      // Delete the project on error if it was created
      if (projectId != null) {
        await projectRepo.delete(projectId);
      }
      if (context.mounted) {
        FluentToast.error(
          context,
          'Failed to create project: $e',
        );
      }
    }
  }
}
