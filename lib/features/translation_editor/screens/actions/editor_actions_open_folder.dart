import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

import '../../../../providers/shared/logging_providers.dart';
import '../../../../providers/shared/repository_providers.dart' as shared_repo;
import 'editor_actions_base.dart';

/// Mixin handling "open mod folder" — reveals the local game data folder
/// where generated `.pack` mods are written.
mixin EditorActionsOpenFolder on EditorActionsBase {
  Future<void> handleOpenModFolder() async {
    final logger = ref.read(loggingServiceProvider);
    try {
      final projectRepo = ref.read(shared_repo.projectRepositoryProvider);
      final projectResult = await projectRepo.getById(projectId);
      if (projectResult.isErr) {
        throw Exception('Project not found');
      }
      final project = projectResult.unwrap();

      final gameRepo = ref.read(shared_repo.gameInstallationRepositoryProvider);
      final gameResult = await gameRepo.getById(project.gameInstallationId);
      if (gameResult.isErr) {
        throw Exception('Game installation not found');
      }
      final gameInstallation = gameResult.unwrap();

      final installationPath = gameInstallation.installationPath;
      if (installationPath == null || installationPath.isEmpty) {
        if (!context.mounted) return;
        FluentToast.warning(
          context,
          'Game installation path is not configured.',
        );
        return;
      }

      // Resolve the actual folder to reveal: prefer the `data` subfolder
      // (where `.pack` files land) and fall back to the installation root
      // if it doesn't exist yet.
      final dataPath = p.join(installationPath, 'data');
      final targetPath =
          await Directory(dataPath).exists() ? dataPath : installationPath;

      if (Platform.isWindows) {
        await Process.start(
          'explorer',
          [targetPath],
          mode: ProcessStartMode.detached,
        );
      } else if (Platform.isMacOS) {
        await Process.start(
          'open',
          [targetPath],
          mode: ProcessStartMode.detached,
        );
      } else {
        await Process.start(
          'xdg-open',
          [targetPath],
          mode: ProcessStartMode.detached,
        );
      }
    } catch (e, stackTrace) {
      logger.error('Failed to open mod folder', e, stackTrace);
      if (!context.mounted) return;
      FluentToast.error(context, 'Failed to open mod folder: $e');
    }
  }
}
