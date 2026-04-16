import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import '../models/activity_event.dart';
import '../repositories/activity_event_repository.dart';
import '../repositories/activity_event_repository_impl.dart';
import '../services/activity_logger.dart';
import '../services/activity_logger_impl.dart';

part 'activity_providers.g.dart';

/// Singleton repository for persistent activity events.
@Riverpod(keepAlive: true)
ActivityEventRepository activityEventRepository(Ref ref) =>
    ActivityEventRepositoryImpl();

/// Singleton fire-and-forget activity logger backed by
/// [activityEventRepositoryProvider].
@Riverpod(keepAlive: true)
ActivityLogger activityLogger(Ref ref) =>
    ActivityLoggerImpl(repository: ref.watch(activityEventRepositoryProvider));

/// Last 20 activity events for the current game (or all if none selected).
///
/// Returns an empty list when the underlying repository query fails,
/// so the Home dashboard never surfaces errors for this best-effort feed.
@riverpod
Future<List<ActivityEvent>> activityFeed(Ref ref) async {
  final repo = ref.watch(activityEventRepositoryProvider);
  final selectedGame = await ref.watch(selectedGameProvider.future);
  final result = await repo.getRecent(
    gameCode: selectedGame?.code,
    limit: 20,
  );
  if (result.isErr) return const [];
  return result.value;
}
