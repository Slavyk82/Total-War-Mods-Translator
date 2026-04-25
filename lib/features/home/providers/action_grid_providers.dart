import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';

part 'action_grid_providers.g.dart';

/// Count of projects (for the selected game) that have at least one unit in
/// `needs_review` state.
///
/// Note: `ProjectStatistics.errorCount` is the field that tracks needs-review
/// units in this codebase (see `translation_version_statistics_mixin.dart` —
/// `status = 'needs_review'` is mapped onto `errorCount`). If the field is
/// renamed, update the call-site in [NextProjectAction.fromStats] as well.
@riverpod
Future<int> projectsToReviewCount(Ref ref) async {
  final versionRepo = ref.watch(translationVersionRepositoryProvider);
  final projectRepo = ref.watch(projectRepositoryProvider);
  final gameInstallationRepo = ref.watch(gameInstallationRepositoryProvider);
  final selectedGame = await ref.watch(selectedGameProvider.future);

  List<Project> projects;
  if (selectedGame == null) {
    final r = await projectRepo.getAll();
    projects = r.isOk ? r.value : const <Project>[];
  } else {
    final installResult =
        await gameInstallationRepo.getByGameCode(selectedGame.code);
    if (installResult.isErr) return 0;
    final install = installResult.value;
    final projectsResult = await projectRepo.getByGameInstallation(install.id);
    projects = projectsResult.isOk ? projectsResult.value : const <Project>[];
  }

  var count = 0;
  for (final p in projects) {
    final s = await versionRepo.getProjectStatistics(p.id);
    if (s.isErr) continue;
    if (s.value.errorCount > 0) count++;
  }
  return count;
}

/// Count of projects whose source has been modified since the last `.pack`
/// export — i.e. the on-disk pack no longer reflects the current translation
/// state and a re-export is required.
///
/// Defers to `ProjectWithDetails.isModifiedSinceLastExport` from
/// [projectsWithDetailsProvider] so the Home dashboard tile and the in-screen
/// "Export outdated" pill share a single source of truth (and the underlying
/// `MAX(exportedAt, publishedAt) + 60s` checkpoint logic stays in one place).
///
/// Marked `keepAlive` so the value survives a Home → Projects → Home round
/// trip. Otherwise the auto-disposed counter would briefly flash `0`
/// (initial AsyncLoading has no previous value) before resolving back to the
/// real count, even when the data didn't change. Refreshes still happen
/// automatically: the counter watches `projectsWithDetailsProvider`, which is
/// invalidated by every workflow that mutates project state.
@Riverpod(keepAlive: true)
Future<int> projectsExportOutdatedCount(Ref ref) async {
  final details = await ref.watch(projectsWithDetailsProvider.future);
  return details.where((d) => d.isModifiedSinceLastExport).length;
}
