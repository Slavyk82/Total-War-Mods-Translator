import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';

part 'workflow_providers.g.dart';

/// Total mods detected for the selected game.
///
/// Thin wrapper over [totalModsCountProvider] so the Home feature can depend
/// on a stable primitive without reaching into the Mods feature directly.
@riverpod
Future<int> modsDiscoveredCount(Ref ref) =>
    ref.watch(totalModsCountProvider.future);

/// Mods with Steam Workshop updates available.
///
/// Thin wrapper over [needsUpdateModsCountProvider].
@riverpod
Future<int> modsWithUpdatesCount(Ref ref) =>
    ref.watch(needsUpdateModsCountProvider.future);

/// Number of active projects for the selected game.
///
/// Mirrors the filter logic used by `recentProjectsProvider`: when a game is
/// selected, only projects attached to that game's installation are counted.
/// When no game is selected, all projects are counted.
@riverpod
Future<int> activeProjectsCount(Ref ref) async {
  final projects = await _projectsForSelectedGame(ref);
  return projects.length;
}

/// Projects whose units are 100% translated AND that do not have a generated
/// pack yet.
///
/// "Pack generated" is detected via [ExportHistoryRepository.getLastPackExportByProject]
/// (the same signal used by the Projects screen's `hasBeenExported`).
@riverpod
Future<int> projectsReadyToCompileCount(Ref ref) async {
  final versionRepo = ref.watch(translationVersionRepositoryProvider);
  final exportHistoryRepo = ref.watch(exportHistoryRepositoryProvider);
  final projects = await _projectsForSelectedGame(ref);

  var count = 0;
  for (final p in projects) {
    final statsResult = await versionRepo.getProjectStatistics(p.id);
    if (statsResult.isErr) continue;
    final stats = statsResult.value;
    // A project with zero translatable units cannot be "ready to compile".
    if (stats.totalCount == 0) continue;
    final pct = ((stats.translatedCount / stats.totalCount) * 100).round();
    if (pct < 100) continue;

    final lastPack = await exportHistoryRepo.getLastPackExportByProject(p.id);
    final hasPack = lastPack != null;
    if (!hasPack) count++;
  }
  return count;
}

/// Compilations that have been generated but not yet published to Workshop
/// (or that were generated again after the last publish).
///
/// Filtered by the selected game's installation. Note the `Compilation` model
/// stores `gameInstallationId` (not a gameCode), so the filter resolves the
/// installation via [GameInstallationRepository.getByGameCode] first.
@riverpod
Future<int> packsAwaitingPublishCount(Ref ref) async {
  final compilationRepo = ref.watch(compilationRepositoryProvider);
  final gameInstallationRepo = ref.watch(gameInstallationRepositoryProvider);
  final selectedGame = await ref.watch(selectedGameProvider.future);

  String? targetInstallationId;
  if (selectedGame != null) {
    final installResult =
        await gameInstallationRepo.getByGameCode(selectedGame.code);
    if (installResult.isErr) return 0;
    targetInstallationId = installResult.value.id;
  }

  final result = await compilationRepo.getAll();
  if (result.isErr) return 0;

  return result.value.where((c) {
    final sameGame =
        targetInstallationId == null || c.gameInstallationId == targetInstallationId;
    final generated = c.lastGeneratedAt != null;
    final notPublished = c.publishedAt == null ||
        (c.lastGeneratedAt != null && c.lastGeneratedAt! > c.publishedAt!);
    return sameGame && generated && notPublished;
  }).length;
}

/// Resolve the project list filtered by the current selected game.
///
/// Shared by workflow counters that need to iterate over the current game's
/// projects. Kept private to this file; other consumers should depend on the
/// specific counter providers above.
Future<List<Project>> _projectsForSelectedGame(Ref ref) async {
  final projectRepo = ref.watch(projectRepositoryProvider);
  final gameInstallationRepo = ref.watch(gameInstallationRepositoryProvider);
  final selectedGame = await ref.watch(selectedGameProvider.future);

  if (selectedGame == null) {
    final r = await projectRepo.getAll();
    return r.isOk ? r.value : const <Project>[];
  }

  final installResult =
      await gameInstallationRepo.getByGameCode(selectedGame.code);
  if (installResult.isErr) return const <Project>[];
  final install = installResult.value;
  final projectsResult = await projectRepo.getByGameInstallation(install.id);
  return projectsResult.isOk ? projectsResult.value : const <Project>[];
}
