import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/repositories/compilation_repository.dart';
import 'package:twmt/repositories/export_history_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/service_locator.dart';

part 'steam_publish_providers.g.dart';

/// Sealed class representing an item that can be published to Steam Workshop.
sealed class PublishableItem {
  String get displayName;
  String? get imageUrl;
  String get outputPath;
  String? get publishedSteamId;
  int? get publishedAt;
  bool get isCompilation;

  /// Whether a pack file exists on disk for this item.
  bool get hasPack;

  /// Unique identifier for selection (project ID or compilation ID).
  String get itemId;

  /// Timestamp used for sorting by export/generation date.
  /// Returns 0 when no pack exists (sorts to end).
  int get exportedAt;
}

/// A project that can be published.
class ProjectPublishItem extends PublishableItem {
  final ExportHistory? export;
  final Project project;
  final List<String> languageCodes;

  ProjectPublishItem({
    required this.export,
    required this.project,
    required this.languageCodes,
  });

  @override
  String get displayName => project.displayName;

  @override
  String? get imageUrl => project.imageUrl;

  @override
  String get outputPath => export?.outputPath ?? '';

  @override
  String? get publishedSteamId => project.publishedSteamId;

  @override
  int? get publishedAt => project.publishedAt;

  @override
  bool get isCompilation => false;

  @override
  bool get hasPack =>
      export != null &&
      export!.outputPath.isNotEmpty &&
      File(export!.outputPath).existsSync();

  @override
  String get itemId => project.id;

  @override
  int get exportedAt => export?.exportedAt ?? 0;

  String? get steamWorkshopId => project.modSteamId;

  bool get isFromSteamWorkshop => project.isFromSteamWorkshop;

  List<String> get languagesList => export?.languagesList ?? languageCodes;

  int get entryCount => export?.entryCount ?? 0;

  String get fileSizeFormatted => export?.fileSizeFormatted ?? '';
}

/// A compilation that can be published.
class CompilationPublishItem extends PublishableItem {
  final Compilation compilation;
  final String? languageCode;
  final int projectCount;
  final int? fileSize;

  CompilationPublishItem({
    required this.compilation,
    this.languageCode,
    required this.projectCount,
    this.fileSize,
  });

  @override
  String get displayName => compilation.name;

  @override
  String? get imageUrl => null;

  @override
  String get outputPath => compilation.lastOutputPath ?? '';

  @override
  String? get publishedSteamId => compilation.publishedSteamId;

  @override
  int? get publishedAt => compilation.publishedAt;

  @override
  bool get isCompilation => true;

  @override
  bool get hasPack =>
      compilation.hasBeenGenerated &&
      compilation.lastOutputPath != null &&
      File(compilation.lastOutputPath!).existsSync();

  @override
  String get itemId => compilation.id;

  @override
  int get exportedAt => compilation.lastGeneratedAt ?? 0;

  String get fileSizeFormatted {
    if (fileSize == null) return 'Unknown';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Provider that loads publishable items filtered by the selected game.
@riverpod
Future<List<PublishableItem>> publishableItems(Ref ref) async {
  final exportHistoryRepo = ServiceLocator.get<ExportHistoryRepository>();
  final projectRepo = ServiceLocator.get<ProjectRepository>();
  final compilationRepo = ServiceLocator.get<CompilationRepository>();
  final languageRepo = ServiceLocator.get<LanguageRepository>();
  final projectLanguageRepo = ServiceLocator.get<ProjectLanguageRepository>();
  final gameInstallationRepo =
      ServiceLocator.get<GameInstallationRepository>();

  // Get selected game to filter by
  final selectedGame = await ref.watch(selectedGameProvider.future);
  final gameCode = selectedGame?.code;

  // Resolve game installation ID for filtering
  String? gameInstallationId;
  if (gameCode != null) {
    final gameInstallationResult =
        await gameInstallationRepo.getByGameCode(gameCode);
    if (gameInstallationResult.isOk) {
      gameInstallationId = gameInstallationResult.value.id;
    }
  }

  final items = <PublishableItem>[];

  // --- Projects (filtered by game) ---
  final projectsResult = gameInstallationId != null
      ? await projectRepo.getByGameInstallation(gameInstallationId)
      : await projectRepo.getAll();
  if (projectsResult.isOk) {
    for (final project in projectsResult.value) {
      // Load latest pack export (nullable)
      final lastExport =
          await exportHistoryRepo.getLastPackExportByProject(project.id);

      // Load language codes for this project
      final langCodes = <String>[];
      final plResult = await projectLanguageRepo.getByProject(project.id);
      if (plResult.isOk) {
        for (final pl in plResult.value) {
          final langResult = await languageRepo.getById(pl.languageId);
          if (langResult.isOk) {
            langCodes.add(langResult.value.code);
          }
        }
      }

      items.add(ProjectPublishItem(
        export: lastExport,
        project: project,
        languageCodes: langCodes,
      ));
    }
  }

  // --- Compilations (filtered by game) ---
  final compilationsResult = gameInstallationId != null
      ? await compilationRepo.getByGameInstallation(gameInstallationId)
      : await compilationRepo.getAll();
  if (compilationsResult.isOk) {
    for (final compilation in compilationsResult.value) {
      // Resolve language code
      String? langCode;
      if (compilation.languageId != null) {
        final langResult = await languageRepo.getById(compilation.languageId!);
        if (langResult.isOk) {
          langCode = langResult.value.code;
        }
      }

      // Get project count
      final projectIdsResult =
          await compilationRepo.getProjectIds(compilation.id);
      final projectCount =
          projectIdsResult.isOk ? projectIdsResult.value.length : 0;

      // Get file size (only if pack exists)
      int? fileSize;
      if (compilation.hasBeenGenerated && compilation.lastOutputPath != null) {
        try {
          final file = File(compilation.lastOutputPath!);
          if (file.existsSync()) {
            fileSize = file.lengthSync();
          }
        } catch (_) {}
      }

      items.add(CompilationPublishItem(
        compilation: compilation,
        languageCode: langCode,
        projectCount: projectCount,
        fileSize: fileSize,
      ));
    }
  }

  return items;
}
