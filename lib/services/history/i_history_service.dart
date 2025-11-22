import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../../models/domain/translation_version_history.dart';
import '../../models/history/diff_models.dart';

/// Service for managing translation version history and comparisons
///
/// Provides operations for recording changes, viewing history, reverting
/// to previous versions, and comparing different versions of translations.
abstract class IHistoryService {
  /// Record a change to translation history
  ///
  /// Called automatically when a translation is edited. This creates a new
  /// history entry with the old value before the change is applied.
  ///
  /// [versionId] - ID of the translation version being changed
  /// [translatedText] - The translated text at this point
  /// [status] - Status of the translation (pending, translated, validated, etc.)
  /// [confidenceScore] - Optional confidence score (0.0-1.0)
  /// [changedBy] - Who made the change ('user', 'provider_anthropic', 'system')
  /// [changeReason] - Optional reason for change ('Manual edit', 'LLM translation', etc.)
  ///
  /// Returns [Ok] on success or [Err] with exception on failure
  Future<Result<void, TWMTDatabaseException>> recordChange({
    required String versionId,
    required String translatedText,
    required String status,
    double? confidenceScore,
    required String changedBy,
    String? changeReason,
  });

  /// Get complete history for a translation version
  ///
  /// Returns all history entries for a specific translation version,
  /// ordered by creation date (newest first).
  ///
  /// [versionId] - ID of the translation version
  ///
  /// Returns [Ok] with list of history entries or [Err] on failure
  Future<Result<List<TranslationVersionHistory>, TWMTDatabaseException>>
      getHistory(String versionId);

  /// Get specific history entry by ID
  ///
  /// [historyId] - ID of the history entry
  ///
  /// Returns [Ok] with history entry or [Err] if not found
  Future<Result<TranslationVersionHistory, TWMTDatabaseException>>
      getHistoryEntry(String historyId);

  /// Revert to a specific version
  ///
  /// Creates a new history entry with reverted content and updates the
  /// current translation version to match the historical version.
  ///
  /// [versionId] - ID of the translation version to revert
  /// [historyId] - ID of the history entry to revert to
  /// [changedBy] - Who is performing the revert
  ///
  /// Returns [Ok] on success or [Err] on failure
  Future<Result<void, TWMTDatabaseException>> revertToVersion({
    required String versionId,
    required String historyId,
    required String changedBy,
  });

  /// Compare two versions (diff)
  ///
  /// Calculates character-level differences between two history entries
  /// and provides statistics about the changes.
  ///
  /// [historyId1] - ID of first history entry (older)
  /// [historyId2] - ID of second history entry (newer)
  ///
  /// Returns [Ok] with comparison result or [Err] on failure
  Future<Result<VersionComparison, TWMTDatabaseException>> compareVersions({
    required String historyId1,
    required String historyId2,
  });

  /// Delete history entries older than specified days
  ///
  /// Used for cleanup to prevent database bloat. Permanently removes
  /// old history entries that are no longer needed.
  ///
  /// [olderThanDays] - Delete entries older than this many days
  ///
  /// Returns [Ok] with number of entries deleted or [Err] on failure
  Future<Result<int, TWMTDatabaseException>> cleanupOldHistory({
    required int olderThanDays,
  });

  /// Get history statistics
  ///
  /// Returns aggregated statistics about all history entries, including
  /// counts by type, user, and LLM provider.
  ///
  /// Returns [Ok] with statistics or [Err] on failure
  Future<Result<HistoryStats, TWMTDatabaseException>> getStatistics();

  /// Get history statistics for a specific version
  ///
  /// [versionId] - ID of the translation version
  ///
  /// Returns [Ok] with statistics or [Err] on failure
  Future<Result<HistoryStats, TWMTDatabaseException>> getStatisticsForVersion(
      String versionId);
}
