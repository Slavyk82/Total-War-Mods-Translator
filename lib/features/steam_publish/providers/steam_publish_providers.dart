import 'dart:io';

import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:twmt/features/steam_publish/providers/published_subs_cache_provider.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';

part 'steam_publish_providers.g.dart';

/// Sort mode for the Steam Publish list.
enum SteamPublishSortMode { exportDate, name, publishDate }

/// Display filter applied on top of the publishable-items list.
enum SteamPublishDisplayFilter { all, outdated, noPackGenerated }

/// Current set of selected item ids (project or compilation) in the Steam
/// Publish list. Kept dumb — the screen reads membership via `contains()`
/// and flips it via direct state assignment.
final steamPublishSelectionProvider = StateProvider<Set<String>>((_) => {});

/// Current search query for filtering publishable items by display name.
final steamPublishSearchQueryProvider = StateProvider<String>((_) => '');

/// Current sort mode. Defaults to export date, most recent first.
final steamPublishSortModeProvider =
    StateProvider<SteamPublishSortMode>((_) => SteamPublishSortMode.exportDate);

/// Current sort direction. False means descending (default).
final steamPublishSortAscendingProvider = StateProvider<bool>((_) => false);

/// Current display filter pill selection.
final steamPublishDisplayFilterProvider =
    StateProvider<SteamPublishDisplayFilter>(
  (_) => SteamPublishDisplayFilter.all,
);

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
  final exportHistoryRepo = ref.watch(exportHistoryRepositoryProvider);
  final projectRepo = ref.watch(projectRepositoryProvider);
  final compilationRepo = ref.watch(compilationRepositoryProvider);
  final languageRepo = ref.watch(languageRepositoryProvider);
  final projectLanguageRepo = ref.watch(projectLanguageRepositoryProvider);
  final gameInstallationRepo = ref.watch(gameInstallationRepositoryProvider);

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

/// Returns the publishable items filtered by [steamPublishDisplayFilterProvider]
/// and [steamPublishSearchQueryProvider], then sorted by
/// [steamPublishSortModeProvider] and [steamPublishSortAscendingProvider].
///
/// When the upstream [publishableItemsProvider] is loading or errored the
/// filtered provider returns an empty list — the screen consults
/// `publishableItemsProvider` directly for loading/error/empty chrome.
@riverpod
List<PublishableItem> filteredPublishableItems(Ref ref) {
  final asyncItems = ref.watch(publishableItemsProvider);
  final items = asyncItems.asData?.value ?? const <PublishableItem>[];
  if (items.isEmpty) return const [];

  final filter = ref.watch(steamPublishDisplayFilterProvider);
  final query = ref.watch(steamPublishSearchQueryProvider).toLowerCase();
  final sortMode = ref.watch(steamPublishSortModeProvider);
  final ascending = ref.watch(steamPublishSortAscendingProvider);

  var result = items.toList();

  // Apply display filter.
  switch (filter) {
    case SteamPublishDisplayFilter.all:
      break;
    case SteamPublishDisplayFilter.outdated:
      result = result
          .where(
            (e) => e.publishedAt != null && e.exportedAt > e.publishedAt!,
          )
          .toList();
    case SteamPublishDisplayFilter.noPackGenerated:
      result = result.where((e) => !e.hasPack).toList();
  }

  // Apply search query.
  if (query.isNotEmpty) {
    result = result
        .where((e) => e.displayName.toLowerCase().contains(query))
        .toList();
  }

  // Apply sort.
  result.sort((a, b) {
    int cmp = 0;
    switch (sortMode) {
      case SteamPublishSortMode.exportDate:
        // Items without pack (exportedAt == 0) go to the end.
        if (a.exportedAt == 0 && b.exportedAt == 0) {
          return a.displayName
              .toLowerCase()
              .compareTo(b.displayName.toLowerCase());
        }
        if (a.exportedAt == 0) return 1;
        if (b.exportedAt == 0) return -1;
        cmp = a.exportedAt.compareTo(b.exportedAt);
      case SteamPublishSortMode.name:
        cmp = a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase());
      case SteamPublishSortMode.publishDate:
        final aPub = a.publishedAt;
        final bPub = b.publishedAt;
        // Unpublished items always sort to the end, regardless of direction.
        if (aPub == null && bPub == null) {
          return a.exportedAt.compareTo(b.exportedAt);
        }
        if (aPub == null) return 1;
        if (bPub == null) return -1;
        cmp = aPub.compareTo(bPub);
        if (cmp == 0) {
          cmp = a.exportedAt.compareTo(b.exportedAt);
        }
    }
    return ascending ? cmp : -cmp;
  });

  return result;
}

/// Count of items matching the 'outdated' display filter — used to label the
/// Outdated filter pill and disable the Select-outdated action when zero.
@riverpod
int outdatedPublishableItemsCount(Ref ref) {
  final asyncItems = ref.watch(publishableItemsProvider);
  final items = asyncItems.asData?.value ?? const <PublishableItem>[];
  return items
      .where((e) => e.publishedAt != null && e.exportedAt > e.publishedAt!)
      .length;
}

/// Count of items matching the 'no pack' display filter.
@riverpod
int noPackPublishableItemsCount(Ref ref) {
  final asyncItems = ref.watch(publishableItemsProvider);
  final items = asyncItems.asData?.value ?? const <PublishableItem>[];
  return items.where((e) => !e.hasPack).length;
}

/// Sum of subscriber counts across the currently filtered publishable items,
/// resolved against the session-level [publishedSubsCacheProvider]. Items
/// without a `publishedSteamId` or absent from the cache contribute 0.
@riverpod
int filteredPublishableItemsSubsTotal(Ref ref) {
  final items = ref.watch(filteredPublishableItemsProvider);
  final cache = ref.watch(publishedSubsCacheProvider);
  if (items.isEmpty || cache.isEmpty) return 0;
  var sum = 0;
  for (final item in items) {
    final id = item.publishedSteamId;
    if (id == null || id.isEmpty) continue;
    sum += cache[id] ?? 0;
  }
  return sum;
}
