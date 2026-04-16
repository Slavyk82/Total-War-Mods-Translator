import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/features/home/models/next_project_action.dart';
import 'package:twmt/features/home/models/project_with_next_action.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';

part 'home_providers.g.dart';

/// Recent projects (last 5 by updatedAt desc), each annotated with its
/// contextual next-action per the Plan 3 classifier.
///
/// Filter logic mirrors [activeProjectsCountProvider] / [workflow_providers]:
/// when a game is selected, only projects attached to that game's
/// installation are listed; otherwise all projects are considered.
///
/// The "pack generated" flag is derived from
/// [ExportHistoryRepository.getLastPackExportByProject] — the same signal
/// used by `projectsReadyToCompileCountProvider`. `needsReview` maps onto
/// [ProjectStatistics.errorCount] (see Task 10 learnings: "errorCount" is the
/// current needs-review counter).
@riverpod
Future<List<ProjectWithNextAction>> recentProjects(Ref ref) async {
  final projectRepo = ref.watch(projectRepositoryProvider);
  final versionRepo = ref.watch(translationVersionRepositoryProvider);
  final gameInstallationRepo = ref.watch(gameInstallationRepositoryProvider);
  final exportHistoryRepo = ref.watch(exportHistoryRepositoryProvider);
  final selectedGame = await ref.watch(selectedGameProvider.future);

  List<Project> projects;
  if (selectedGame != null) {
    final installResult =
        await gameInstallationRepo.getByGameCode(selectedGame.code);
    if (installResult.isErr) return const [];
    final install = installResult.value;
    final r = await projectRepo.getByGameInstallation(install.id);
    projects = r.isOk ? r.value : <Project>[];
  } else {
    final r = await projectRepo.getAll();
    projects = r.isOk ? r.value : <Project>[];
  }

  // Copy into a mutable list before sorting — repository implementations (and
  // test mocks) may return unmodifiable lists.
  final sorted = [...projects]
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final top = sorted.take(5).toList();

  final result = <ProjectWithNextAction>[];
  for (final p in top) {
    final s = await versionRepo.getProjectStatistics(p.id);
    if (s.isErr) continue;
    final stats = s.value;
    final pct = stats.totalCount == 0
        ? 0
        : ((stats.translatedCount / stats.totalCount) * 100).round();

    // "Pack generated" is detected via export history (no lastExportPath on
    // Project). Matches the pattern used in workflow_providers.dart and
    // projects_screen_providers.dart.
    final lastExport = await exportHistoryRepo.getLastPackExportByProject(p.id);
    final hasPack = lastExport != null;

    final action = NextProjectAction.fromStats(
      translatedPct: pct,
      // ProjectStatistics exposes the needs-review count via errorCount (see
      // Task 10 note: `status = 'needs_review'` is mapped onto errorCount).
      needsReview: stats.errorCount,
      packGenerated: hasPack,
    );
    result.add(ProjectWithNextAction(
      project: p,
      action: action,
      translatedPct: pct,
    ));
  }
  return result;
}
