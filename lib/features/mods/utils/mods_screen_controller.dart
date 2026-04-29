import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';

import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';
import 'package:twmt/features/mods/services/mods_project_service.dart';
import 'package:twmt/features/mods/utils/mods_dialog_helper.dart';
import 'package:twmt/features/projects/utils/open_project_editor.dart';
import 'package:twmt/features/projects/widgets/project_initialization_dialog.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import '../../../providers/shared/service_providers.dart';

/// Controller for ModsScreen orchestration logic
///
/// Handles the complex workflows for project creation from mods,
/// keeping the screen focused on UI presentation.
class ModsScreenController {
  final WidgetRef _ref;

  ModsScreenController(this._ref);

  /// Navigate to projects screen with the "needs update" quick filter applied.
  ///
  /// Uses the `?filter=` deep-link pattern (shared with Home dashboard cards)
  /// because `ProjectsScreen.initState` calls `resetAll()` on mount and only
  /// restores the filter carried by `widget.initialFilter`, which the router
  /// populates from the URL. Setting the filter via the provider before
  /// navigation would be overwritten by that reset.
  void navigateToProjectsWithFilter(BuildContext context) {
    GoRouter.of(context).go('${AppRoutes.projects}?filter=needs-update');
  }

  /// Refresh the mods list by rescanning
  Future<void> handleRefresh() async {
    _ref.read(modsLoadingStateProvider.notifier).setLoading(true);
    await _ref.read(modsRefreshTriggerProvider.notifier).refresh();

    late final ProviderSubscription<AsyncValue<List<DetectedMod>>> subscription;
    subscription = _ref.listenManual(
      detectedModsProvider,
      (previous, next) {
        if (next.hasValue && !next.isLoading) {
          _ref.read(modsLoadingStateProvider.notifier).setLoading(false);
          subscription.close();
        }
      },
      fireImmediately: true,
    );
  }

  /// Toggle hidden status for a mod
  Future<void> handleToggleHidden(String workshopId, bool hide) async {
    final logger = _ref.read(loggingServiceProvider);
    logger.debug('handleToggleHidden called: workshopId=$workshopId, hide=$hide');
    await _ref.read(modHiddenToggleProvider.notifier).toggleHidden(workshopId, hide);
    logger.debug('handleToggleHidden done');
  }

  /// Force redownload a pack file by deleting it
  Future<void> handleForceRedownload(BuildContext context, String packFilePath) async {
    try {
      final file = File(packFilePath);
      if (await file.exists()) {
        await file.delete();
        if (!context.mounted) return;
        FluentToast.success(
          context,
          t.mods.messages.packFileDeleted,
        );
      } else {
        if (!context.mounted) return;
        FluentToast.warning(context, t.mods.messages.fileNotFound(path: packFilePath));
      }
    } catch (e) {
      if (!context.mounted) return;
      FluentToast.error(context, t.mods.messages.failedToDeleteFile(error: e));
    }
  }

  /// Handle tap on a mod row - navigate to existing project or create new one
  Future<void> handleModRowTap(
    BuildContext context,
    List<DetectedMod> mods,
    String workshopId,
  ) async {
    DetectedMod mod;
    try {
      mod = mods.firstWhere((m) => m.workshopId == workshopId);
    } catch (e) {
      return;
    }

    final projectRepo = _ref.read(projectRepositoryProvider);
    final projectsResult = await projectRepo.getAll();

    if (projectsResult.isOk) {
      final projects = projectsResult.unwrap();
      final existingProject = projects.where(
        (project) => project.modSteamId == workshopId,
      ).firstOrNull;

      if (existingProject != null) {
        if (!context.mounted) return;
        await openProjectEditor(context, _ref, existingProject.id);
        return;
      }
    }

    if (context.mounted) {
      await _createProjectFromMod(context, mod);
    }
  }

  /// Import a local .pack file as a project
  Future<void> handleImportLocalPack(BuildContext context) async {
    final selectedGame = await _ref.read(selectedGameProvider.future);
    if (selectedGame == null) {
      if (context.mounted) {
        FluentToast.warning(context, t.mods.messages.noGameSelected);
      }
      return;
    }

    final defaultPath = path.join(selectedGame.path, 'data');
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pack'],
      initialDirectory: defaultPath,
      dialogTitle: t.mods.hints.selectPackFile,
    );

    if (result == null || result.files.isEmpty) return;

    final packPath = result.files.single.path;
    if (packPath == null) return;

    if (!context.mounted) return;
    final confirmed = await ModsDialogHelper.showLocalPackWarning(context);
    if (!confirmed) return;

    final packFileName = path.basenameWithoutExtension(packPath);
    if (!context.mounted) return;
    final projectName = await ModsDialogHelper.showLocalPackNameDialog(context, packFileName);
    if (projectName == null || projectName.trim().isEmpty) return;

    if (!context.mounted) return;
    await _createProjectFromLocalPack(context, packPath, projectName.trim(), selectedGame);
  }

  /// Create a project from a detected workshop mod
  Future<void> _createProjectFromMod(
    BuildContext context,
    DetectedMod mod,
  ) async {
    final projectRepo = _ref.read(projectRepositoryProvider);
    final service = ModsProjectService.create(
      projectRepository: projectRepo,
      workshopModRepository: _ref.read(workshopModRepositoryProvider),
      languageRepository: _ref.read(languageRepositoryProvider),
      projectLanguageRepository: _ref.read(projectLanguageRepositoryProvider),
      settingsService: _ref.read(settingsServiceProvider),
      logger: _ref.read(loggingServiceProvider),
    );
    String? projectId;

    try {
      final games = await _ref.read(allGameInstallationsProvider.future);
      final validation = await service.validateWorkshopMod(
        mod: mod,
        gameInstallations: games,
      );

      if (validation is ValidationFailed) {
        if (!context.mounted) return;
        FluentToast.error(context, validation.error);
        return;
      }

      final valid = validation as ValidationPassed;
      projectId = await service.createProjectFromMod(
        mod: mod,
        gameInstallation: valid.gameInstallation,
        outputFolder: valid.outputFolder,
      );

      if (projectId == null) {
        if (!context.mounted) return;
        FluentToast.error(context, t.mods.messages.failedToCreateProjectSimple);
        return;
      }

      if (!context.mounted) return;
      final success = await _showInitializationDialog(
        context,
        projectId,
        mod.name,
        mod.packFilePath,
      );

      if (success == true) {
        _ref.invalidate(projectsWithDetailsProvider);
        // Update the mod's imported status locally without triggering a full rescan
        _ref.read(detectedModsProvider.notifier).updateModImported(mod.workshopId, projectId);
        if (context.mounted) {
          await openProjectEditor(context, _ref, projectId);
        }
      } else {
        await service.deleteProject(projectId);
        if (context.mounted) {
          FluentToast.warning(
            context,
            t.mods.messages.noLocalizationFiles,
          );
        }
      }
    } catch (e) {
      if (projectId != null) {
        await service.deleteProject(projectId);
      }
      if (context.mounted) {
        FluentToast.error(context, t.mods.messages.failedToCreateProject(error: e));
      }
    }
  }

  /// Create a project from a local pack file
  Future<void> _createProjectFromLocalPack(
    BuildContext context,
    String packFilePath,
    String projectName,
    ConfiguredGame selectedGame,
  ) async {
    final projectRepo = _ref.read(projectRepositoryProvider);
    final service = ModsProjectService.create(
      projectRepository: projectRepo,
      workshopModRepository: _ref.read(workshopModRepositoryProvider),
      languageRepository: _ref.read(languageRepositoryProvider),
      projectLanguageRepository: _ref.read(projectLanguageRepositoryProvider),
      settingsService: _ref.read(settingsServiceProvider),
      logger: _ref.read(loggingServiceProvider),
    );
    String? projectId;

    try {
      final games = await _ref.read(allGameInstallationsProvider.future);
      final validation = await service.validateLocalPack(
        packFilePath: packFilePath,
        selectedGame: selectedGame,
        gameInstallations: games,
      );

      if (validation is ValidationFailed) {
        if (!context.mounted) return;
        FluentToast.error(context, validation.error);
        return;
      }

      final valid = validation as ValidationPassed;
      projectId = await service.createProjectFromLocalPack(
        packFilePath: packFilePath,
        projectName: projectName,
        gameInstallation: valid.gameInstallation,
        outputFolder: valid.outputFolder,
      );

      if (projectId == null) {
        if (!context.mounted) return;
        FluentToast.error(context, t.mods.messages.failedToCreateProjectSimple);
        return;
      }

      if (!context.mounted) return;
      final success = await _showInitializationDialog(
        context,
        projectId,
        projectName,
        packFilePath,
      );

      if (success == true) {
        _ref.invalidate(projectsWithDetailsProvider);
        if (context.mounted) {
          await openProjectEditor(context, _ref, projectId);
        }
      } else {
        await service.deleteProject(projectId);
        if (context.mounted) {
          FluentToast.warning(
            context,
            t.mods.messages.noLocalizationFilesInPack,
          );
        }
      }
    } catch (e) {
      if (projectId != null) {
        await service.deleteProject(projectId);
      }
      if (context.mounted) {
        FluentToast.error(context, t.mods.messages.failedToCreateProject(error: e));
      }
    }
  }

  /// Show the project initialization dialog
  Future<bool?> _showInitializationDialog(
    BuildContext context,
    String projectId,
    String projectName,
    String packFilePath,
  ) {
    final initService = _ref.read(projectInitializationServiceProvider);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProjectInitializationDialog(
        projectName: projectName,
        logStream: initService.logStream,
        onInitialize: () => initService
            .initializeProject(
              projectId: projectId,
              packFilePath: packFilePath,
            )
            .then((result) {
          if (result.isErr) {
            throw Exception(result.error);
          }
          return result.value;
        }),
      ),
    );
  }
}
