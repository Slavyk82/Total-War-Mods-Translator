import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/repositories/compilation_repository.dart';
import 'package:twmt/repositories/export_history_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
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

  /// Timestamp used for sorting by export/generation date.
  int get exportedAt;
}

/// A project export that can be published.
class ProjectPublishItem extends PublishableItem {
  final ExportHistory export;
  final Project project;

  ProjectPublishItem({required this.export, required this.project});

  @override
  String get displayName => project.displayName;

  @override
  String? get imageUrl => project.imageUrl;

  @override
  String get outputPath => export.outputPath;

  @override
  String? get publishedSteamId => project.publishedSteamId;

  @override
  int? get publishedAt => project.publishedAt;

  @override
  bool get isCompilation => false;

  @override
  int get exportedAt => export.exportedAt;

  String? get steamWorkshopId => project.modSteamId;

  bool get isFromSteamWorkshop => project.isFromSteamWorkshop;

  List<String> get languagesList => export.languagesList;

  int get entryCount => export.entryCount;

  String get fileSizeFormatted => export.fileSizeFormatted;
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
  String get outputPath => compilation.lastOutputPath!;

  @override
  String? get publishedSteamId => compilation.publishedSteamId;

  @override
  int? get publishedAt => compilation.publishedAt;

  @override
  bool get isCompilation => true;

  @override
  int get exportedAt => compilation.lastGeneratedAt!;

  String get fileSizeFormatted {
    if (fileSize == null) return 'Unknown';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Provider that loads all publishable items (project exports + compilations).
@riverpod
Future<List<PublishableItem>> publishableItems(Ref ref) async {
  final exportHistoryRepo = ServiceLocator.get<ExportHistoryRepository>();
  final projectRepo = ServiceLocator.get<ProjectRepository>();
  final compilationRepo = ServiceLocator.get<CompilationRepository>();
  final languageRepo = ServiceLocator.get<LanguageRepository>();

  // --- Project exports ---
  final allPackExports = await exportHistoryRepo.getByFormat(ExportFormat.pack);

  // Keep only the most recent export per project (already sorted by date DESC)
  final seenProjects = <String>{};
  final latestExports = <ExportHistory>[];
  for (final export in allPackExports) {
    if (seenProjects.add(export.projectId)) {
      latestExports.add(export);
    }
  }

  final items = <PublishableItem>[];
  for (final export in latestExports) {
    final projectResult = await projectRepo.getById(export.projectId);
    if (!projectResult.isOk) continue; // Skip deleted projects
    items.add(ProjectPublishItem(export: export, project: projectResult.value));
  }

  // --- Compilations ---
  final compilationsResult = await compilationRepo.getAll();
  if (compilationsResult.isOk) {
    for (final compilation in compilationsResult.value) {
      if (!compilation.hasBeenGenerated) continue;
      if (compilation.lastOutputPath == null) continue;

      // Check that the output file still exists
      if (!File(compilation.lastOutputPath!).existsSync()) continue;

      // Resolve language code
      String? langCode;
      if (compilation.languageId != null) {
        final langResult = await languageRepo.getById(compilation.languageId!);
        if (langResult.isOk) {
          langCode = langResult.value.code;
        }
      }

      // Get project count
      final projectIdsResult = await compilationRepo.getProjectIds(compilation.id);
      final projectCount = projectIdsResult.isOk ? projectIdsResult.value.length : 0;

      // Get file size
      int? fileSize;
      try {
        fileSize = File(compilation.lastOutputPath!).lengthSync();
      } catch (_) {}

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

