import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/project_statistics.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';

/// Extended project data with related information
class ProjectWithDetails {
  final Project project;
  final GameInstallation? gameInstallation;
  final List<ProjectLanguageWithInfo> languages;
  final ModUpdateAnalysis? updateAnalysis;
  final ExportHistory? lastPackExport;

  const ProjectWithDetails({
    required this.project,
    this.gameInstallation,
    required this.languages,
    this.updateAnalysis,
    this.lastPackExport,
  });

  /// Calculate overall progress across all languages
  double get overallProgress {
    if (languages.isEmpty) return 0.0;
    final sum = languages.fold<double>(
      0.0,
      (sum, lang) => sum + lang.progressPercent,
    );
    return sum / languages.length;
  }

  /// Check if there are pending changes to apply (excludes auto-applied changes)
  /// OR if the project was impacted by a mod update (flag set during scan).
  ///
  /// The persistent `has_mod_update_impact` flag is cleared only when the
  /// translation editor's initState runs. Bulk workflows that don't route
  /// through that path (per-row edits from the Projects screen, multi-project
  /// bulk translate/validate) would otherwise leave the flag stuck at 1 even
  /// when the remediation work is already done. Guard against that by also
  /// checking the derived "everything is done" state.
  bool get hasUpdates {
    if (updateAnalysis?.hasPendingChanges ?? false) return true;
    if (project.hasModUpdateImpact) {
      return !(isFullyTranslated && !hasNeedsReviewUnits);
    }
    return false;
  }

  /// Check if all configured languages are 100% translated
  bool get isFullyTranslated {
    if (languages.isEmpty) return false;
    return languages.every((lang) => lang.isComplete);
  }

  /// Check if at least one language is 100% translated
  bool get hasAtLeastOneCompleteLanguage {
    if (languages.isEmpty) return false;
    return languages.any((lang) => lang.isComplete);
  }

  /// Whether any configured language has at least one unit flagged
  /// as `needs_review` (mapped onto [ProjectLanguageWithInfo.needsReviewUnits]).
  bool get hasNeedsReviewUnits {
    if (languages.isEmpty) return false;
    return languages.any((lang) => lang.needsReviewUnits > 0);
  }

  /// Check if the project has been exported at least once
  bool get hasBeenExported => lastPackExport != null;

  /// Check if the project was modified after the last export.
  ///
  /// Uses the most recent of (last pack export, last Steam Workshop publish)
  /// as the "checkpoint" against which `updatedAt` is compared, with a
  /// 60-second margin to absorb minor write-time skew. The publish timestamp
  /// is included on purpose: a publish operation persists `published_at` /
  /// `published_steam_id` on the project row, and historically (before the
  /// `trg_projects_updated_at` column-scope migration) that write also
  /// bumped `updated_at` via the auto-stamp trigger — flagging every
  /// just-published project as "Export outdated". Treating publish as a
  /// checkpoint keeps existing databases correct without a data-migration
  /// pass over `updated_at`.
  bool get isModifiedSinceLastExport {
    if (lastPackExport == null) return false;
    var checkpoint = lastPackExport!.exportedAt;
    final publishedAt = project.publishedAt;
    if (publishedAt != null && publishedAt > checkpoint) {
      checkpoint = publishedAt;
    }
    return project.updatedAt > checkpoint + 60;
  }

  /// True when this project is part of a Steam Workshop publish flow —
  /// either the source is a workshop mod, or the project itself has
  /// already been pushed to Workshop at least once.
  ///
  /// Local packs and game translations return false: they never reach
  /// Steam, so the "Exported" pill can keep its original "pack generated"
  /// meaning for them.
  bool get hasSteamPublishWorkflow {
    final modSteamId = project.modSteamId;
    if (modSteamId != null && modSteamId.isNotEmpty) return true;
    final publishedId = project.publishedSteamId;
    return publishedId != null && publishedId.isNotEmpty;
  }

  /// True when the latest local pack is also live on Steam Workshop —
  /// the project has a Workshop id and its last publish timestamp is
  /// newer than (or equal to) the last export timestamp.
  ///
  /// Drives the green "Exported" status pill for Steam-workflow projects:
  /// after a bulk generate, the new pack is on disk but Steam still hosts
  /// the previous version, so this returns false and the pill falls back
  /// to "Unpublished".
  bool get isPackPublishedOnSteam {
    final export = lastPackExport;
    if (export == null) return false;
    final publishedId = project.publishedSteamId;
    if (publishedId == null || publishedId.isEmpty) return false;
    final publishedAt = project.publishedAt;
    if (publishedAt == null) return false;
    return publishedAt >= export.exportedAt;
  }
}

/// Project language with language info and translation stats
class ProjectLanguageWithInfo {
  final ProjectLanguage projectLanguage;
  final Language? language;
  final int totalUnits;
  final int translatedUnits;
  final int needsReviewUnits;

  const ProjectLanguageWithInfo({
    required this.projectLanguage,
    this.language,
    this.totalUnits = 0,
    this.translatedUnits = 0,
    this.needsReviewUnits = 0,
  });

  /// Calculate progress percentage based on actual translation counts
  /// Only units with status = 'translated' count as complete
  double get progressPercent {
    if (totalUnits == 0) return 0.0;
    return (translatedUnits / totalUnits) * 100;
  }

  /// Check if this language is 100% translated
  bool get isComplete => totalUnits > 0 && translatedUnits >= totalUnits;
}

/// Notifier for translation statistics version counter.
/// Increment this to trigger refresh of all translation-related providers.
class TranslationStatsVersionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

/// Global version counter for translation statistics.
/// Used by pack compilation and other screens that display translation progress.
final translationStatsVersionProvider =
    NotifierProvider<TranslationStatsVersionNotifier, int>(
  TranslationStatsVersionNotifier.new,
);

/// Notifier backing [projectsWithDetailsProvider].
///
/// `build()` does the full list load. [refreshProject] recomputes a single
/// project and patches its entry in place — avoiding a full reload when only
/// one project was modified (e.g. returning from the project detail screen).
/// [removeProject] drops a project from the cached state after a local delete.
class ProjectsWithDetailsNotifier
    extends AsyncNotifier<List<ProjectWithDetails>> {
  /// Project ids whose missing image URL has already been back-filled to the DB
  /// during this session. The back-fill is a write performed from the read/load
  /// path (`_computeOne`, invoked concurrently via `Future.wait` and also from
  /// `refreshProject`); guarding it here ensures the DB is mutated at most once
  /// per project per session instead of on every render that rediscovers the
  /// image, and prevents two concurrent loads (e.g. `refreshProject` racing a
  /// `_loadAll`) from issuing duplicate `update()`s on the same row.
  final Set<String> _imageBackfilledProjectIds = <String>{};

  @override
  Future<List<ProjectWithDetails>> build() => _loadAll();

  /// Recompute details for [projectId] and replace its entry in the list.
  ///
  /// If no cached data exists yet, falls back to a full rebuild.
  /// If the project no longer exists in the database, removes it from the list.
  Future<void> refreshProject(String projectId) async {
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }

    final projectRepo = ref.read(projectRepositoryProvider);
    final projectResult = await projectRepo.getById(projectId);
    if (projectResult.isErr) {
      state = AsyncData(
        current.where((p) => p.project.id != projectId).toList(growable: false),
      );
      return;
    }

    final project = projectResult.unwrap();
    final (languagesMap, gamesMap) = await _loadLookupMaps();
    final updated = await _computeOne(
      project: project,
      gameInstallation: gamesMap[project.gameInstallationId],
      languagesMap: languagesMap,
    );

    state = AsyncData([
      for (final p in current)
        if (p.project.id == projectId) updated else p,
    ]);
  }

  /// Remove [projectId] from the cached list without reloading others.
  void removeProject(String projectId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.where((p) => p.project.id != projectId).toList(growable: false),
    );
  }

  Future<List<ProjectWithDetails>> _loadAll() async {
    final logging = ref.read(loggingServiceProvider);
    logging.debug('Starting projectsWithDetailsProvider');
    final projectRepo = ref.read(projectRepositoryProvider);
    final gameRepo = ref.read(gameInstallationRepositoryProvider);

    // Watch the selected game to filter projects (full rebuild when it changes)
    final selectedGame = await ref.watch(selectedGameProvider.future);
    if (selectedGame == null) {
      logging.debug('No game selected, returning empty project list');
      return <ProjectWithDetails>[];
    }

    final gameInstallationResult =
        await gameRepo.getByGameCode(selectedGame.code);
    if (gameInstallationResult.isErr) {
      logging.debug('No game installation found for ${selectedGame.code}');
      return <ProjectWithDetails>[];
    }
    final gameInstallation = gameInstallationResult.unwrap();

    final projectsResult =
        await projectRepo.getModTranslationsByInstallation(gameInstallation.id);
    if (projectsResult.isErr) {
      final error = projectsResult.unwrapErr();
      logging.error('Failed to fetch projects', error);
      throw Exception('Failed to load projects');
    }

    final projects = projectsResult.unwrap();
    logging.debug('Loaded projects', {'count': projects.length});

    final (languagesMap, gamesMap) = await _loadLookupMaps();

    // Compute each project's details concurrently. Previously this ran
    // sequentially, serializing O(projects x languages) DB round-trips and
    // blocking the list render. Future.wait preserves input order.
    final projectsWithDetails = await Future.wait(
      projects.map((project) => _computeOne(
            project: project,
            gameInstallation: gamesMap[project.gameInstallationId],
            languagesMap: languagesMap,
          )),
    );
    return projectsWithDetails;
  }

  /// Pre-load languages and game installations once.
  /// Both are small fixed sets, so loading all is cheaper than N+1 queries.
  Future<(Map<String, Language>, Map<String, GameInstallation>)>
      _loadLookupMaps() async {
    final langRepo = ref.read(languageRepositoryProvider);
    final gameRepo = ref.read(gameInstallationRepositoryProvider);

    final languagesMap = <String, Language>{};
    final langResult = await langRepo.getAll();
    if (langResult.isOk) {
      for (final lang in langResult.unwrap()) {
        languagesMap[lang.id] = lang;
      }
    }

    final gamesMap = <String, GameInstallation>{};
    final gamesResult = await gameRepo.getAll();
    if (gamesResult.isOk) {
      for (final g in gamesResult.unwrap()) {
        gamesMap[g.id] = g;
      }
    }

    return (languagesMap, gamesMap);
  }

  /// Compute full [ProjectWithDetails] for a single project, reusing pre-loaded
  /// language and game installation lookups.
  Future<ProjectWithDetails> _computeOne({
    required Project project,
    required GameInstallation? gameInstallation,
    required Map<String, Language> languagesMap,
  }) async {
    final projectRepo = ref.read(projectRepositoryProvider);
    final projectLangRepo = ref.read(projectLanguageRepositoryProvider);
    final workshopModRepo = ref.read(workshopModRepositoryProvider);
    final versionRepo = ref.read(translationVersionRepositoryProvider);
    final updateAnalysisService = ref.read(modUpdateAnalysisServiceProvider);
    final exportHistoryRepo = ref.read(exportHistoryRepositoryProvider);

    // Auto-fill missing or stale image URL from workshop folder if available
    // Skip for game translation projects (they use the game icon instead)
    final hasValidImage =
        project.imageUrl != null && await File(project.imageUrl!).exists();
    if (!hasValidImage && project.isModTranslation) {
      String? imagePath;

      if (project.sourceFilePath != null) {
        imagePath = await _findModImage(project.sourceFilePath!);
      }

      if (imagePath == null &&
          project.modSteamId != null &&
          gameInstallation?.steamWorkshopPath != null) {
        final workshopModDir = path.join(
            gameInstallation!.steamWorkshopPath!, project.modSteamId!);
        imagePath = await _findModImageInDir(workshopModDir);
      }

      if (imagePath != null) {
        final currentMetadata = project.parsedMetadata;
        final updatedMetadata =
            (currentMetadata ?? const ProjectMetadata()).copyWith(
          modImageUrl: imagePath,
        );

        final updatedProject = project.copyWith(
          metadata: updatedMetadata.toJsonString(),
          updatedAt: project.updatedAt,
        );

        // Reflect the discovered image in the returned details regardless, so
        // the UI shows it immediately. Only persist the back-fill to the DB once
        // per project per session (see [_imageBackfilledProjectIds]) to keep the
        // write out of the hot read path and avoid concurrent same-row updates.
        project = updatedProject;
        if (_imageBackfilledProjectIds.add(project.id)) {
          await projectRepo.update(updatedProject);
        }
      }
    }

    // Get project languages
    final langResult = await projectLangRepo.getByProject(project.id);
    final List<ProjectLanguageWithInfo> languagesWithInfo = [];

    if (langResult.isOk) {
      final projLangs = langResult.unwrap();
      // Fetch per-language statistics concurrently rather than one round-trip
      // at a time, to avoid an N+1 serialized chain that blocks the list render.
      final statsResults = await Future.wait(
        projLangs.map((projLang) =>
            versionRepo.getLanguageStatistics(projLang.id)),
      );

      for (var i = 0; i < projLangs.length; i++) {
        final projLang = projLangs[i];
        final language = languagesMap[projLang.languageId];
        final statsResult = statsResults[i];
        final stats = statsResult.isOk
            ? statsResult.unwrap()
            : ProjectStatistics.empty();

        languagesWithInfo.add(ProjectLanguageWithInfo(
          projectLanguage: projLang,
          language: language,
          totalUnits: stats.totalCount,
          translatedUnits: stats.translatedCount,
          needsReviewUnits: stats.errorCount,
        ));
      }
    }

    final lastPackExport =
        await exportHistoryRepo.getLastPackExportByProject(project.id);

    // Check for updates by comparing Steam timestamp vs local file timestamp
    ModUpdateAnalysis? updateAnalysis;
    bool needsUpdate = false;

    if (project.hasSourceFile &&
        project.sourceFilePath != null &&
        project.modSteamId != null) {
      int? steamTimestamp;
      final workshopModResult =
          await workshopModRepo.getByWorkshopId(project.modSteamId!);
      if (workshopModResult.isOk) {
        steamTimestamp = workshopModResult.unwrap().timeUpdated;
      }

      int? localTimestamp;
      final sourceFile = File(project.sourceFilePath!);
      if (await sourceFile.exists()) {
        final stat = await sourceFile.stat();
        localTimestamp = stat.modified.millisecondsSinceEpoch ~/ 1000;
      }

      if (steamTimestamp != null && localTimestamp != null) {
        needsUpdate = steamTimestamp > localTimestamp;
      }

      if (needsUpdate) {
        final analysisResult = await updateAnalysisService.analyzeChanges(
          projectId: project.id,
          packFilePath: project.sourceFilePath!,
        );
        if (analysisResult.isOk) {
          updateAnalysis = analysisResult.unwrap();
        }
      } else if (steamTimestamp != null && localTimestamp != null) {
        updateAnalysis = ModUpdateAnalysis.empty;
      }
    }

    // Auto-heal the persistent `has_mod_update_impact` flag.
    //
    // The flag is set by `ProjectAnalysisHandler` during a mod scan and was
    // originally cleared only by `TranslationEditorScreen.initState`. Any
    // workflow that doesn't route through the editor (per-row edits from the
    // Projects screen, bulk translate/validate spanning multiple projects)
    // would otherwise leave the flag stuck at 1 even when the remediation
    // work is complete — causing the "Needs Update" filter and "Mod updated"
    // badges to remain stale. Clearing the flag here, when the project has
    // nothing left to do, keeps the UI consistent with the actual DB state.
    if (project.hasModUpdateImpact &&
        languagesWithInfo.isNotEmpty &&
        languagesWithInfo.every((lang) => lang.isComplete) &&
        languagesWithInfo.every((lang) => lang.needsReviewUnits == 0) &&
        !(updateAnalysis?.hasPendingChanges ?? false)) {
      final clearResult = await projectRepo.clearModUpdateImpact(project.id);
      if (clearResult.isOk) {
        project = project.copyWith(hasModUpdateImpact: false);
      }
    }

    return ProjectWithDetails(
      project: project,
      gameInstallation: gameInstallation,
      languages: languagesWithInfo,
      updateAnalysis: updateAnalysis,
      lastPackExport: lastPackExport,
    );
  }
}

/// Provider for all projects with details.
///
/// Prefer [ProjectsWithDetailsNotifier.refreshProject] over
/// `ref.invalidate(projectsWithDetailsProvider)` when only one project changed,
/// to avoid a full list reload.
final projectsWithDetailsProvider = AsyncNotifierProvider<
    ProjectsWithDetailsNotifier,
    List<ProjectWithDetails>>(ProjectsWithDetailsNotifier.new);

/// Find mod preview image in the mod directory.
///
/// Searches for images in a specific priority order:
/// 1. Image with same name as pack file (e.g., my_mod.jpg for my_mod.pack)
/// 2. preview.* files
/// 3. Any image file in the directory
Future<String?> _findModImage(String packFilePath) async {
  const imageExtensions = ['.jpg', '.jpeg', '.png'];

  try {
    final packFile = File(packFilePath);
    if (!await packFile.exists()) return null;

    final modDir = packFile.parent;
    final packFileName = path.basenameWithoutExtension(packFilePath);

    // 1. Check for image with same name as .pack file
    for (final ext in imageExtensions) {
      final imagePath = path.join(modDir.path, '$packFileName$ext');
      if (await File(imagePath).exists()) {
        return imagePath;
      }
    }

    // 2. Try preview.*
    for (final ext in imageExtensions) {
      final imagePath = path.join(modDir.path, 'preview$ext');
      if (await File(imagePath).exists()) {
        return imagePath;
      }
    }

    // 3. Try to find any image file
    final entries = await modDir.list().toList();
    for (final entity in entries) {
      if (entity is File) {
        final lowerPath = entity.path.toLowerCase();
        if (imageExtensions.any((ext) => lowerPath.endsWith(ext))) {
          return entity.path;
        }
      }
    }
  } catch (e) {
    // Ignore errors when searching for images
  }

  return null;
}

/// Find mod preview image directly in a workshop directory.
///
/// Used as fallback when the pack file path is stale (e.g., after PC reformat).
/// Searches for preview.* files or any image file in the directory.
Future<String?> _findModImageInDir(String dirPath) async {
  const imageExtensions = ['.jpg', '.jpeg', '.png'];

  try {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return null;

    // 1. Try preview.*
    for (final ext in imageExtensions) {
      final imagePath = path.join(dir.path, 'preview$ext');
      if (await File(imagePath).exists()) {
        return imagePath;
      }
    }

    // 2. Try any image file
    final entries = await dir.list().toList();
    for (final entity in entries) {
      if (entity is File) {
        final lowerPath = entity.path.toLowerCase();
        if (imageExtensions.any((ext) => lowerPath.endsWith(ext))) {
          return entity.path;
        }
      }
    }
  } catch (e) {
    // Ignore errors when searching for images
  }

  return null;
}
