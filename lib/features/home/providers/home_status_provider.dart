import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'action_grid_providers.dart';
import 'workflow_providers.dart';

part 'home_status_provider.g.dart';

enum HomeStatusKind { needsAttention, readyToCompile, modUpdates, allCaughtUp }

class HomeStatus {
  final HomeStatusKind kind;
  final int count;
  const HomeStatus(this.kind, this.count);

  String get label => switch (kind) {
        HomeStatusKind.needsAttention => count == 1
          ? t.home.status.needsAttentionOne
          : t.home.status.needsAttentionMany(count: count),
        HomeStatusKind.readyToCompile => count == 1
          ? t.home.status.readyToCompileOne
          : t.home.status.readyToCompileMany(count: count),
        HomeStatusKind.modUpdates => count == 1
          ? t.home.status.modUpdatesOne
          : t.home.status.modUpdatesMany(count: count),
        HomeStatusKind.allCaughtUp => t.home.status.allCaughtUp,
      };
}

@riverpod
Future<HomeStatus> homeStatus(Ref ref) async {
  final toReview = await ref.watch(projectsToReviewCountProvider.future);
  if (toReview > 0) return HomeStatus(HomeStatusKind.needsAttention, toReview);
  final ready = await ref.watch(projectsReadyToCompileCountProvider.future);
  if (ready > 0) return HomeStatus(HomeStatusKind.readyToCompile, ready);
  final updates = await ref.watch(modsWithUpdatesCountProvider.future);
  if (updates > 0) return HomeStatus(HomeStatusKind.modUpdates, updates);
  return const HomeStatus(HomeStatusKind.allCaughtUp, 0);
}
