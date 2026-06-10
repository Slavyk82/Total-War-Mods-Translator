import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../models/domain/translation_version_history.dart';
import '../../models/history/diff_models.dart';
import '../shared/service_providers.dart';

part 'history_providers.g.dart';

/// Provider for history entries of a specific translation version
///
/// Returns all history entries for a version, ordered by creation date (newest first).
@riverpod
Future<List<TranslationVersionHistory>> versionHistory(
  Ref ref,
  String versionId,
) async {
  final service = ref.watch(historyServiceProvider);
  final result = await service.getHistory(versionId);
  return result.when(
    ok: (history) => history,
    err: (error) => throw Exception('Failed to load history: $error'),
  );
}

/// Provider for a specific history entry
@riverpod
Future<TranslationVersionHistory> historyEntry(
  Ref ref,
  String historyId,
) async {
  final service = ref.watch(historyServiceProvider);
  final result = await service.getHistoryEntry(historyId);
  return result.when(
    ok: (entry) => entry,
    err: (error) => throw Exception('Failed to load history entry: $error'),
  );
}

/// Provider for comparing two history versions
@riverpod
Future<VersionComparison> versionComparison(
  Ref ref,
  String historyId1,
  String historyId2,
) async {
  final service = ref.watch(historyServiceProvider);
  final result = await service.compareVersions(
    historyId1: historyId1,
    historyId2: historyId2,
  );
  return result.when(
    ok: (comparison) => comparison,
    err: (error) => throw Exception('Failed to compare versions: $error'),
  );
}

/// Provider for history statistics
@riverpod
Future<HistoryStats> historyStatistics(Ref ref) async {
  final service = ref.watch(historyServiceProvider);
  final result = await service.getStatistics();
  return result.when(
    ok: (stats) => stats,
    err: (error) => throw Exception('Failed to load statistics: $error'),
  );
}

/// Provider for history statistics of a specific version
@riverpod
Future<HistoryStats> versionHistoryStatistics(
  Ref ref,
  String versionId,
) async {
  final service = ref.watch(historyServiceProvider);
  final result = await service.getStatisticsForVersion(versionId);
  return result.when(
    ok: (stats) => stats,
    err: (error) => throw Exception('Failed to load statistics: $error'),
  );
}
