import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/repositories/export_history_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/service_locator.dart';

part 'steam_publish_providers.g.dart';

/// Bundles an [ExportHistory] with its associated [Project] (nullable if deleted).
class RecentPackExport {
  final ExportHistory export;
  final Project? project;

  const RecentPackExport({required this.export, this.project});

  String get projectDisplayName => project?.displayName ?? export.projectId;

  String? get projectImageUrl => project?.imageUrl;

  String? get steamWorkshopId => project?.modSteamId;

  String? get publishedSteamId => project?.publishedSteamId;

  int? get publishedAt => project?.publishedAt;

  bool get isFromSteamWorkshop => project?.isFromSteamWorkshop ?? false;
}

/// Updates the published Steam ID for a project and refreshes the exports list.
Future<void> updatePublishedSteamId(
  WidgetRef ref, {
  required String projectId,
  required String? value,
}) async {
  final projectRepo = ServiceLocator.get<ProjectRepository>();
  final result = await projectRepo.getById(projectId);
  if (result.isOk) {
    final updated = result.value.copyWith(
      publishedSteamId: value,
    );
    await projectRepo.update(updated);
    ref.invalidate(recentPackExportsProvider);
  }
}

/// Provider that loads all pack exports sorted by date DESC, with their projects.
@riverpod
Future<List<RecentPackExport>> recentPackExports(Ref ref) async {
  final exportHistoryRepo = ServiceLocator.get<ExportHistoryRepository>();
  final projectRepo = ServiceLocator.get<ProjectRepository>();

  final allPackExports = await exportHistoryRepo.getByFormat(ExportFormat.pack);

  final results = <RecentPackExport>[];
  for (final export in allPackExports) {
    final projectResult = await projectRepo.getById(export.projectId);
    final project = projectResult.isOk ? projectResult.value : null;
    results.add(RecentPackExport(export: export, project: project));
  }

  return results;
}
