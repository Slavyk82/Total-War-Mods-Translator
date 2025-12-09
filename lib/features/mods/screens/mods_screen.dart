import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/features/mods/widgets/detected_mods_datagrid.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';
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

/// Complete mods screen with Syncfusion DataGrid
class ModsScreen extends ConsumerStatefulWidget {
  const ModsScreen({super.key});

  @override
  ConsumerState<ModsScreen> createState() => _ModsScreenState();
}

class _ModsScreenState extends ConsumerState<ModsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredModsAsync = ref.watch(filteredModsProvider);
    final searchQuery = ref.watch(modsSearchQueryProvider);
    final isRefreshing = ref.watch(modsLoadingStateProvider);
    final currentFilter = ref.watch(modsFilterStateProvider);
    final totalModsAsync = ref.watch(totalModsCountProvider);
    final notImportedCountAsync = ref.watch(notImportedModsCountProvider);
    final needsUpdateCountAsync = ref.watch(needsUpdateModsCountProvider);
    final showHidden = ref.watch(showHiddenModsProvider);
    final hiddenCountAsync = ref.watch(hiddenModsCountProvider);

    return CallbackShortcuts(
      bindings: {
        // Ctrl+F to focus search
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          // Focus will be handled by the toolbar
        },
        // Ctrl+R to refresh
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
          _handleRefresh();
        },
      },
      child: Focus(
        autofocus: true,
        child: FluentScaffold(
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                _buildHeader(theme),
                const SizedBox(height: 24),

                // Toolbar
                filteredModsAsync.when(
                  data: (filteredMods) => ModsToolbar(
                    searchQuery: searchQuery,
                    onSearchChanged: (query) {
                      ref.read(modsSearchQueryProvider.notifier).setQuery(query);
                    },
                    onRefresh: () => _handleRefresh(),
                    isRefreshing: isRefreshing,
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
                      ref.read(showHiddenModsProvider.notifier).set(value);
                    },
                    hiddenCount: hiddenCountAsync.value ?? 0,
                  ),
                  loading: () => ModsToolbar(
                    searchQuery: searchQuery,
                    onSearchChanged: (query) {
                      ref.read(modsSearchQueryProvider.notifier).setQuery(query);
                    },
                    onRefresh: () => _handleRefresh(),
                    isRefreshing: true,
                    totalMods: 0,
                    filteredMods: 0,
                    currentFilter: currentFilter,
                    onFilterChanged: (filter) {
                      ref.read(modsFilterStateProvider.notifier).setFilter(filter);
                    },
                    notImportedCount: 0,
                    needsUpdateCount: 0,
                    showHidden: showHidden,
                    onShowHiddenChanged: (value) {
                      ref.read(showHiddenModsProvider.notifier).set(value);
                    },
                    hiddenCount: 0,
                  ),
                  error: (error, stack) => ModsToolbar(
                    searchQuery: searchQuery,
                    onSearchChanged: (query) {
                      ref.read(modsSearchQueryProvider.notifier).setQuery(query);
                    },
                    onRefresh: () => _handleRefresh(),
                    isRefreshing: false,
                    totalMods: 0,
                    filteredMods: 0,
                    currentFilter: currentFilter,
                    onFilterChanged: (filter) {
                      ref.read(modsFilterStateProvider.notifier).setFilter(filter);
                    },
                    notImportedCount: 0,
                    needsUpdateCount: 0,
                    showHidden: showHidden,
                    onShowHiddenChanged: (value) {
                      ref.read(showHiddenModsProvider.notifier).set(value);
                    },
                    hiddenCount: 0,
                  ),
                ),
                const SizedBox(height: 16),

                // DataGrid
                Expanded(
                  child: filteredModsAsync.when(
                    data: (mods) => DetectedModsDataGrid(
                      mods: mods,
                      onRowTap: (workshopId) => _openCreateProjectDialog(context, mods, workshopId),
                      onToggleHidden: (workshopId, hide) => _handleToggleHidden(workshopId, hide),
                      onForceRedownload: (packFilePath) => _handleForceRedownload(context, packFilePath),
                      isLoading: false,
                      isScanning: isRefreshing,
                      showingHidden: showHidden,
                      scanLogStream: isRefreshing ? ref.watch(scanLogStreamProvider) : null,
                    ),
                    loading: () => DetectedModsDataGrid(
                      mods: const [],
                      onRowTap: _dummyCallback,
                      isLoading: true,
                      showingHidden: showHidden,
                      scanLogStream: ref.watch(scanLogStreamProvider),
                    ),
                    error: (error, stack) => _buildErrorState(theme, error),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _dummyCallback(String _) {}

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

  void _handleRefresh() {
    ref.read(modsLoadingStateProvider.notifier).setLoading(true);
    ref.read(modsRefreshTriggerProvider.notifier).refresh();
    
    // Listen for completion and reset loading state
    late final ProviderSubscription<AsyncValue<List<DetectedMod>>> subscription;
    subscription = ref.listenManual(
      filteredModsProvider,
      (previous, next) {
        // When data arrives, reset loading state and close subscription
        if (next.hasValue && mounted) {
          ref.read(modsLoadingStateProvider.notifier).setLoading(false);
          subscription.close();
        }
      },
      fireImmediately: false,
    );
  }

  Future<void> _handleToggleHidden(String workshopId, bool hide) async {
    await ref.read(modHiddenToggleProvider.notifier).toggleHidden(workshopId, hide);
    
    // Refresh to reflect the change immediately
    if (mounted) {
      ref.invalidate(detectedModsProvider);
    }
  }

  Future<void> _handleForceRedownload(BuildContext context, String packFilePath) async {
    try {
      final file = File(packFilePath);
      if (await file.exists()) {
        await file.delete();
        if (mounted) {
          FluentToast.success(
            context,
            'Pack file deleted. Launch the game to redownload.',
          );
          _handleRefresh();
        }
      } else {
        if (mounted) {
          FluentToast.warning(context, 'File not found: $packFilePath');
        }
      }
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Failed to delete file: $e');
      }
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
}
