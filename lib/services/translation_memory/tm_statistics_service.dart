import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/language_id.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/tm_cache.dart';
import 'package:twmt/services/shared/i_logging_service.dart';

/// Lifetime reuse count of entries deleted by past cleanups. Added on top of
/// the current live usage sum so cleanup doesn't rewrite history.
const _kArchivedReuseCountKey = 'tm_archived_reuse_count';

/// Lifetime count of entries deleted by past cleanups. Used as an extra
/// denominator term for reuse rate so cleanup doesn't inflate the ratio.
const _kArchivedEntriesCountKey = 'tm_archived_entries_count';

/// Translation Memory statistics and maintenance service
///
/// Handles:
/// - Statistics calculation and reporting
/// - Cleanup of unused entries
/// - Cache management operations
class TmStatisticsService {
  final TranslationMemoryRepository _repository;
  final LanguageRepository _languageRepository;
  final TmCache _cache;
  final ILoggingService _logger;
  final SettingsService? _settings;

  const TmStatisticsService({
    required TranslationMemoryRepository repository,
    required LanguageRepository languageRepository,
    required TmCache cache,
    required ILoggingService logger,
    SettingsService? settings,
  })  : _repository = repository,
        _languageRepository = languageRepository,
        _cache = cache,
        _logger = logger,
        _settings = settings;

  SettingsService get _settingsOrLocator =>
      _settings ?? ServiceLocator.get<SettingsService>();

  /// Clean up unused TM entries
  ///
  /// Removes entries that haven't been used in the specified period.
  /// Also clears the cache if entries were deleted.
  ///
  /// [unusedDays]: Days since last use (default: 365)
  ///
  /// Returns number of entries deleted
  Future<Result<int, TmServiceException>> cleanupUnusedEntries({
    int unusedDays = AppConstants.unusedTmCleanupDays,
  }) async {
    try {
      if (unusedDays < 0) {
        return Err(
          TmServiceException(
            'unusedDays must be non-negative',
          ),
        );
      }

      // unusedDays == 0 means "delete every entry" (full TM wipe).
      final isFullWipe = unusedDays == 0;

      if (isFullWipe) {
        _logger.info('Starting TM full wipe', {'unusedDays': 0});
      } else {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final cutoffTimestamp = now - (unusedDays * 24 * 60 * 60);
        final cutoffDate =
            DateTime.fromMillisecondsSinceEpoch(cutoffTimestamp * 1000);

        _logger.info(
          'Starting TM cleanup',
          {
            'unusedDays': unusedDays,
            'cutoffDate': cutoffDate.toIso8601String(),
            'cutoffTimestamp': cutoffTimestamp,
          },
        );

        final countResult = await _repository.countCleanupCandidates(
          unusedDays: unusedDays,
        );

        if (countResult.isOk) {
          final counts = countResult.value;
          _logger.info(
            'TM cleanup candidates analysis',
            {
              'willBeDeleted': counts['willBeDeleted'],
              'unusedOnly': counts['unusedOnly'],
            },
          );
        }
      }

      final deleteResult = isFullWipe
          ? await _repository.deleteAllEntries()
          : await _repository.deleteByAge(unusedDays: unusedDays);

      if (deleteResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to delete entries: ${deleteResult.error}',
            error: deleteResult.error,
          ),
        );
      }

      final deletedCount = deleteResult.value.deletedCount;
      final deletedUsageSum = deleteResult.value.deletedUsageSum;

      _logger.info(
        'TM cleanup completed',
        {
          'deletedEntries': deletedCount,
          'deletedUsageSum': deletedUsageSum,
        },
      );

      // Preserve historical reuse metrics: cleanup deletes rows but the
      // translation work they represent already happened, so we archive
      // their usage_count and row count into persistent lifetime counters.
      if (deletedCount > 0) {
        final settings = _settingsOrLocator;
        final priorReuse = await settings.getInt(_kArchivedReuseCountKey);
        final priorEntries = await settings.getInt(_kArchivedEntriesCountKey);
        await settings.setInt(
          _kArchivedReuseCountKey,
          priorReuse + deletedUsageSum,
        );
        await settings.setInt(
          _kArchivedEntriesCountKey,
          priorEntries + deletedCount,
        );
      }

      // Clear cache after cleanup to ensure fresh data
      if (deletedCount > 0) {
        _cache.clear();
      }

      return Ok(deletedCount);
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error during cleanup: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Get TM statistics
  ///
  /// Returns statistics about TM usage and effectiveness:
  /// - Total entries
  /// - Entries by language pair (with resolved display names)
  /// - Total reuse count
  /// - Estimated tokens saved
  /// - Reuse rate
  ///
  /// [targetLanguageCode]: Optional language filter
  Future<Result<TmStatistics, TmServiceException>> getStatistics({
    String? targetLanguageCode,
  }) async {
    try {
      final targetLanguageId = normalizeLanguageId(targetLanguageCode);

      // Get basic statistics
      final statsResult = await _repository.getStatistics(
        targetLanguageId: targetLanguageId,
      );

      if (statsResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to get statistics: ${statsResult.error}',
            error: statsResult.error,
          ),
        );
      }

      final statsData = statsResult.value;
      final totalEntries = statsData['total_entries'] as int;
      final totalUsage = statsData['total_usage'] as int;

      // Get entries by language
      final languagePairResult = await _repository.getEntriesByLanguage();

      if (languagePairResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to get language pair statistics: ${languagePairResult.error}',
            error: languagePairResult.error,
          ),
        );
      }

      // Resolve language IDs to display names
      final entriesByLanguagePair = await _resolveLanguageDisplayNames(
        languagePairResult.value,
      );

      // Archive counters are global (cleanup is not per-language), so only
      // fold them in for the unfiltered view. A per-language filter shows
      // the live numbers for that language.
      int archivedReuse = 0;
      int archivedEntries = 0;
      if (targetLanguageId == null) {
        final settings = _settingsOrLocator;
        archivedReuse = await settings.getInt(_kArchivedReuseCountKey);
        archivedEntries = await settings.getInt(_kArchivedEntriesCountKey);
      }

      final effectiveUsage = totalUsage + archivedReuse;
      final effectiveEntriesForRate = totalEntries + archivedEntries;

      // Calculate estimated token reuse
      // Assumption: Average entry saves ~50 tokens per reuse
      const avgTokensPerEntry = 50;
      final tokensSaved = effectiveUsage * avgTokensPerEntry;

      // Calculate reuse rate
      // Note: This is a simplified calculation
      // In production, you'd compare TM hits vs total translation requests
      final reuseRate = effectiveEntriesForRate > 0
          ? effectiveUsage / effectiveEntriesForRate
          : 0.0;

      final stats = TmStatistics(
        totalEntries: totalEntries,
        entriesByLanguagePair: entriesByLanguagePair,
        totalReuseCount: effectiveUsage,
        tokensSaved: tokensSaved,
        averageFuzzyScore: 0.0, // Would require separate tracking
        reuseRate: reuseRate.clamp(0.0, 1.0),
      );

      return Ok(stats);
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error getting statistics: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Resolve language IDs to display names
  ///
  /// Converts language UUIDs to human-readable names for display.
  Future<Map<String, int>> _resolveLanguageDisplayNames(
    Map<String, int> languageIdCounts,
  ) async {
    final languageIds = languageIdCounts.keys.toList();
    final languagesResult = await _languageRepository.getByIds(languageIds);

    // Build a map of ID -> display name
    final idToDisplayName = <String, String>{};
    if (languagesResult.isOk) {
      for (final lang in languagesResult.value) {
        idToDisplayName[lang.id] = lang.name;
      }
    }

    // Convert UUIDs to display names in the result
    final entriesByLanguagePair = <String, int>{};
    for (final entry in languageIdCounts.entries) {
      final displayName = idToDisplayName[entry.key] ?? entry.key;
      entriesByLanguagePair[displayName] = entry.value;
    }

    return entriesByLanguagePair;
  }

  /// Clear all TM cache
  ///
  /// Forces reload from database on next lookup.
  void clearCache() {
    _cache.clear();
  }

  /// Rebuild TM cache
  ///
  /// Preloads frequently used entries into cache for faster lookups.
  ///
  /// [maxEntries]: Maximum entries to cache
  Future<Result<void, TmServiceException>> rebuildCache({
    int maxEntries = AppConstants.maxTmCacheEntries,
  }) async {
    // TODO: Implement when repository supports getMostUsedEntries query
    // For now, just clear the cache
    _cache.clear();
    return Ok(null);
  }
}
