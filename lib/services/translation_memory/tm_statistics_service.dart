import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/tm_cache.dart';
import 'package:twmt/services/shared/logging_service.dart';

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
  final LoggingService _logger;

  const TmStatisticsService({
    required TranslationMemoryRepository repository,
    required LanguageRepository languageRepository,
    required TmCache cache,
    required LoggingService logger,
  })  : _repository = repository,
        _languageRepository = languageRepository,
        _cache = cache,
        _logger = logger;

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

      // Calculate cutoff for debugging
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

      // First, count candidates for diagnostic purposes
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

      // Delete unused entries
      final deleteResult = await _repository.deleteByAge(
        unusedDays: unusedDays,
      );

      if (deleteResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to delete entries: ${deleteResult.error}',
            error: deleteResult.error,
          ),
        );
      }

      final deletedCount = deleteResult.value;

      _logger.info(
        'TM cleanup completed',
        {'deletedEntries': deletedCount},
      );

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
      // Convert language code to ID format (e.g., 'fr' -> 'lang_fr')
      final targetLanguageId =
          targetLanguageCode != null ? 'lang_$targetLanguageCode' : null;

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

      // Calculate estimated token reuse
      // Assumption: Average entry saves ~50 tokens per reuse
      const avgTokensPerEntry = 50;
      final tokensSaved = totalUsage * avgTokensPerEntry;

      // Calculate reuse rate
      // Note: This is a simplified calculation
      // In production, you'd compare TM hits vs total translation requests
      final reuseRate = totalEntries > 0 ? totalUsage / totalEntries : 0.0;

      final stats = TmStatistics(
        totalEntries: totalEntries,
        entriesByLanguagePair: entriesByLanguagePair,
        totalReuseCount: totalUsage,
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
