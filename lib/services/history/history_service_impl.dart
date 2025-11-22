import 'package:uuid/uuid.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../../models/domain/translation_version.dart';
import '../../models/domain/translation_version_history.dart';
import '../../models/history/diff_models.dart';
import '../../repositories/translation_version_history_repository.dart';
import '../../repositories/translation_version_repository.dart';
import 'diff_calculator.dart';
import 'i_history_service.dart';

/// Implementation of history service
///
/// Manages translation version history including recording changes,
/// viewing history, reverting versions, and comparing versions.
class HistoryServiceImpl implements IHistoryService {
  final TranslationVersionHistoryRepository _historyRepository;
  final TranslationVersionRepository _versionRepository;
  final Uuid _uuid;

  const HistoryServiceImpl({
    required TranslationVersionHistoryRepository historyRepository,
    required TranslationVersionRepository versionRepository,
    Uuid? uuid,
  })  : _historyRepository = historyRepository,
        _versionRepository = versionRepository,
        _uuid = uuid ?? const Uuid();

  @override
  Future<Result<void, TWMTDatabaseException>> recordChange({
    required String versionId,
    required String translatedText,
    required String status,
    double? confidenceScore,
    required String changedBy,
    String? changeReason,
  }) async {
    try {
      // Parse status string to enum
      final statusEnum = _parseStatus(status);

      final historyEntry = TranslationVersionHistory(
        id: _uuid.v4(),
        versionId: versionId,
        translatedText: translatedText,
        status: statusEnum,
        confidenceScore: confidenceScore,
        changedBy: changedBy,
        changeReason: changeReason,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final result = await _historyRepository.insert(historyEntry);

      return result.when(
        ok: (_) => const Ok(null),
        err: (error) => Err(error),
      );
    } catch (e) {
      return Err(TWMTDatabaseException(
        'Failed to record history change: $e',
      ));
    }
  }

  @override
  Future<Result<List<TranslationVersionHistory>, TWMTDatabaseException>>
      getHistory(String versionId) async {
    return await _historyRepository.getByVersion(versionId);
  }

  @override
  Future<Result<TranslationVersionHistory, TWMTDatabaseException>>
      getHistoryEntry(String historyId) async {
    return await _historyRepository.getById(historyId);
  }

  @override
  Future<Result<void, TWMTDatabaseException>> revertToVersion({
    required String versionId,
    required String historyId,
    required String changedBy,
  }) async {
    try {
      // Get the history entry to revert to
      final historyResult = await _historyRepository.getById(historyId);
      if (historyResult.isErr) {
        return Err(historyResult.error);
      }

      final historyEntry = historyResult.value;

      // Verify it belongs to the correct version
      if (historyEntry.versionId != versionId) {
        return Err(TWMTDatabaseException(
          'History entry $historyId does not belong to version $versionId',
        ));
      }

      // Get current version
      final versionResult = await _versionRepository.getById(versionId);
      if (versionResult.isErr) {
        return Err(versionResult.error);
      }

      final currentVersion = versionResult.value;

      // Record current state before reverting
      final recordResult = await recordChange(
        versionId: versionId,
        translatedText: currentVersion.translatedText ?? '',
        status: currentVersion.status.name,
        confidenceScore: currentVersion.confidenceScore,
        changedBy: changedBy,
        changeReason: 'Before revert to version $historyId',
      );

      if (recordResult.isErr) {
        return Err(recordResult.error);
      }

      // Update version with historical data
      final updatedVersion = currentVersion.copyWith(
        translatedText: historyEntry.translatedText,
        status: historyEntry.status,
        confidenceScore: historyEntry.confidenceScore,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final updateResult = await _versionRepository.update(updatedVersion);

      if (updateResult.isErr) {
        return Err(updateResult.error);
      }

      // Record the revert action
      final revertRecordResult = await recordChange(
        versionId: versionId,
        translatedText: historyEntry.translatedText,
        status: historyEntry.status.name,
        confidenceScore: historyEntry.confidenceScore,
        changedBy: changedBy,
        changeReason: 'Reverted to version $historyId',
      );

      return revertRecordResult;
    } catch (e) {
      return Err(TWMTDatabaseException(
        'Failed to revert to version: $e',
      ));
    }
  }

  @override
  Future<Result<VersionComparison, TWMTDatabaseException>> compareVersions({
    required String historyId1,
    required String historyId2,
  }) async {
    try {
      // Get both history entries
      final result1 = await _historyRepository.getById(historyId1);
      if (result1.isErr) return Err(result1.error);

      final result2 = await _historyRepository.getById(historyId2);
      if (result2.isErr) return Err(result2.error);

      final version1 = result1.value;
      final version2 = result2.value;

      // Calculate diff
      final diff = DiffCalculator.calculateDiff(
        version1.translatedText,
        version2.translatedText,
      );

      // Calculate stats from diff
      final stats = DiffStats.fromSegments(diff);

      final comparison = VersionComparison(
        version1: version1,
        version2: version2,
        diff: diff,
        stats: stats,
      );

      return Ok(comparison);
    } catch (e) {
      return Err(TWMTDatabaseException(
        'Failed to compare versions: $e',
      ));
    }
  }

  @override
  Future<Result<int, TWMTDatabaseException>> cleanupOldHistory({
    required int olderThanDays,
  }) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: olderThanDays));
      final timestamp = cutoffDate.millisecondsSinceEpoch ~/ 1000;

      return await _historyRepository.deleteOlderThan(timestamp);
    } catch (e) {
      return Err(TWMTDatabaseException(
        'Failed to cleanup old history: $e',
      ));
    }
  }

  @override
  Future<Result<HistoryStats, TWMTDatabaseException>> getStatistics() async {
    try {
      // Get statistics from repository
      final statsResult = await _historyRepository.getStatistics();
      if (statsResult.isErr) return Err(statsResult.error);

      final changesByAttribution = statsResult.value;

      // Get total count
      final countResult = await _historyRepository.count();
      if (countResult.isErr) return Err(countResult.error);

      final totalEntries = countResult.value;

      // Get time range
      final timeRangeResult = await _historyRepository.getTimeRange();
      if (timeRangeResult.isErr) return Err(timeRangeResult.error);

      final timeRange = timeRangeResult.value;

      // Categorize changes
      var manualEdits = 0;
      var llmTranslations = 0;
      var reverts = 0;
      var systemChanges = 0;
      final changesByUser = <String, int>{};
      final changesByLlm = <String, int>{};

      for (final entry in changesByAttribution.entries) {
        final changedBy = entry.key;
        final count = entry.value;

        if (changedBy == 'system') {
          systemChanges += count;
        } else if (changedBy.startsWith('provider_')) {
          llmTranslations += count;
          final providerName = changedBy.replaceFirst('provider_', '');
          changesByLlm[providerName] = count;
        } else {
          manualEdits += count;
          changesByUser[changedBy] = count;
        }
      }

      // Count reverts separately by checking change_reason field
      final revertCountResult = await _historyRepository.countReverts();
      if (revertCountResult.isOk) {
        reverts = revertCountResult.value;
      }

      final stats = HistoryStats(
        totalEntries: totalEntries,
        manualEdits: manualEdits,
        llmTranslations: llmTranslations,
        reverts: reverts,
        systemChanges: systemChanges,
        changesByUser: changesByUser,
        changesByLlm: changesByLlm,
        mostRecentChange: timeRange['newest'],
        oldestChange: timeRange['oldest'],
      );

      return Ok(stats);
    } catch (e) {
      return Err(TWMTDatabaseException(
        'Failed to get statistics: $e',
      ));
    }
  }

  @override
  Future<Result<HistoryStats, TWMTDatabaseException>> getStatisticsForVersion(
      String versionId) async {
    try {
      // Get all history for this version
      final historyResult = await _historyRepository.getByVersion(versionId);
      if (historyResult.isErr) return Err(historyResult.error);

      final history = historyResult.value;

      // Calculate statistics
      var manualEdits = 0;
      var llmTranslations = 0;
      var reverts = 0;
      var systemChanges = 0;
      final changesByUser = <String, int>{};
      final changesByLlm = <String, int>{};

      int? mostRecent;
      int? oldest;

      for (final entry in history) {
        // Update time range
        if (mostRecent == null || entry.createdAt > mostRecent) {
          mostRecent = entry.createdAt;
        }
        if (oldest == null || entry.createdAt < oldest) {
          oldest = entry.createdAt;
        }

        // Categorize change
        if (entry.changedBy == 'system') {
          systemChanges++;
        } else if (entry.changedBy.startsWith('provider_')) {
          llmTranslations++;
          final providerName = entry.changedBy.replaceFirst('provider_', '');
          changesByLlm[providerName] = (changesByLlm[providerName] ?? 0) + 1;
        } else {
          manualEdits++;
          changesByUser[entry.changedBy] =
              (changesByUser[entry.changedBy] ?? 0) + 1;
        }

        // Check if it's a revert
        if (entry.changeReason?.contains('Reverted') ?? false) {
          reverts++;
        }
      }

      final stats = HistoryStats(
        totalEntries: history.length,
        manualEdits: manualEdits,
        llmTranslations: llmTranslations,
        reverts: reverts,
        systemChanges: systemChanges,
        changesByUser: changesByUser,
        changesByLlm: changesByLlm,
        mostRecentChange: mostRecent,
        oldestChange: oldest,
      );

      return Ok(stats);
    } catch (e) {
      return Err(TWMTDatabaseException(
        'Failed to get statistics for version: $e',
      ));
    }
  }

  /// Parse status string to enum
  TranslationVersionStatus _parseStatus(String status) {
    return TranslationVersionStatus.values.firstWhere(
      (s) => s.name == status,
      orElse: () => TranslationVersionStatus.pending,
    );
  }
}
