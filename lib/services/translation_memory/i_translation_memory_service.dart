import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';

/// Service for managing Translation Memory
///
/// Translation Memory (TM) stores previously translated text pairs
/// and enables reuse through exact and fuzzy matching.
///
/// Key features:
/// - Exact match lookup (hash-based, O(1) performance)
/// - Fuzzy match lookup (3 algorithms: Levenshtein, Jaro-Winkler, Token-based)
/// - Context-aware matching (game, category boost)
/// - Auto-accept for >95% matches
/// - Usage tracking
/// - Import/Export (.tmx format)
abstract class ITranslationMemoryService {
  /// Add a translation to Translation Memory
  ///
  /// Automatically deduplicates based on source hash.
  /// If entry exists, updates usage count and last_used timestamp.
  ///
  /// [sourceText]: Source text to store
  /// [targetText]: Translated text
  /// [sourceLanguageCode]: Source language (ISO 639-1), defaults to 'en'
  /// [targetLanguageCode]: Target language (ISO 639-1)
  /// [category]: Optional category (e.g., "UI", "narrative")
  ///
  /// Returns the created or updated TM entry
  Future<Result<TranslationMemoryEntry, TmAddException>> addTranslation({
    required String sourceText,
    required String targetText,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
    String? category,
  });

  /// Add multiple translations to Translation Memory in batch
  ///
  /// Efficiently inserts or updates multiple translations in a single transaction.
  /// This is significantly faster than calling addTranslation() repeatedly.
  ///
  /// Automatically deduplicates based on source hash:
  /// - Existing entries: increments usage count
  /// - New entries: creates with provided values
  ///
  /// [translations]: List of translation pairs (sourceText, targetText)
  /// [sourceLanguageCode]: Source language (ISO 639-1), defaults to 'en'
  /// [targetLanguageCode]: Target language (ISO 639-1)
  ///
  /// Returns number of entries processed (inserted + updated)
  Future<Result<int, TmAddException>> addTranslationsBatch({
    required List<({String sourceText, String targetText})> translations,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
  });

  /// Find exact match in Translation Memory
  ///
  /// Uses hash-based lookup for O(1) performance.
  ///
  /// [sourceText]: Text to match
  /// [targetLanguageCode]: Target language
  ///
  /// Returns exact match if found, null otherwise
  Future<Result<TmMatch?, TmLookupException>> findExactMatch({
    required String sourceText,
    required String targetLanguageCode,
  });

  /// Find fuzzy matches in Translation Memory
  ///
  /// Uses 3 similarity algorithms combined:
  /// - Levenshtein Distance (40% weight)
  /// - Jaro-Winkler Similarity (30% weight)
  /// - Token-Based Similarity (30% weight)
  ///
  /// Context boost:
  /// - +3% if category matches
  ///
  /// [sourceText]: Text to match
  /// [targetLanguageCode]: Target language
  /// [minSimilarity]: Minimum similarity threshold (default: 0.85 = 85%)
  /// [maxResults]: Maximum number of results (default: 5)
  /// [category]: Optional category for boost
  ///
  /// Returns list of fuzzy matches sorted by similarity (highest first)
  Future<Result<List<TmMatch>, TmLookupException>> findFuzzyMatches({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = 0.85,
    int maxResults = 5,
    String? category,
  });

  /// Find best match (exact or fuzzy)
  ///
  /// Convenience method that tries exact match first,
  /// then falls back to best fuzzy match if none found.
  ///
  /// Returns match with auto-applied flag if similarity >= 95%
  Future<Result<TmMatch?, TmLookupException>> findBestMatch({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = 0.85,
    String? category,
  });

  /// Find fuzzy matches using isolate for better performance
  ///
  /// This method runs similarity calculations in a background isolate
  /// to prevent UI freezing during heavy computation.
  /// Use this method for batch processing of many translations.
  ///
  /// [sourceText]: Text to match
  /// [targetLanguageCode]: Target language
  /// [minSimilarity]: Minimum similarity threshold (default: 0.85 = 85%)
  /// [maxResults]: Maximum number of results (default: 5)
  /// [category]: Optional category for boost
  ///
  /// Returns list of fuzzy matches sorted by similarity (highest first)
  Future<Result<List<TmMatch>, TmLookupException>> findFuzzyMatchesIsolate({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = 0.85,
    int maxResults = 5,
    String? category,
  });

  /// Update usage statistics for a TM entry
  ///
  /// Increments usage count and updates last_used timestamp.
  /// Used when a TM match is applied to a translation.
  ///
  /// [entryId]: TM entry identifier
  ///
  /// Returns updated entry
  Future<Result<TranslationMemoryEntry, TmServiceException>>
      incrementUsageCount({
    required String entryId,
  });

  /// Delete a TM entry
  ///
  /// [entryId]: TM entry identifier
  Future<Result<void, TmServiceException>> deleteEntry({
    required String entryId,
  });

  /// Delete unused entries (cleanup)
  ///
  /// Removes entries with:
  /// - No usage in specified period
  ///
  /// [unusedDays]: Days since last use (default: 365)
  ///
  /// Returns number of entries deleted
  Future<Result<int, TmServiceException>> cleanupUnusedEntries({
    int unusedDays = 365,
  });

  /// Get TM statistics
  ///
  /// Returns statistics about TM usage and effectiveness:
  /// - Total entries
  /// - Entries by language
  /// - Total reuse count
  /// - Tokens saved
  Future<Result<TmStatistics, TmServiceException>> getStatistics({
    String? targetLanguageCode,
  });

  /// Import TM entries from TMX file
  ///
  /// TMX (Translation Memory eXchange) is the standard format
  /// for exchanging translation memories.
  ///
  /// [filePath]: Path to .tmx file
  /// [overwriteExisting]: Whether to overwrite existing entries (default: false)
  /// [onProgress]: Optional progress callback (processed, total)
  ///
  /// Returns number of entries imported
  Future<Result<int, TmImportException>> importFromTmx({
    required String filePath,
    bool overwriteExisting = false,
    void Function(int processed, int total)? onProgress,
  });

  /// Export TM entries to TMX file
  ///
  /// [outputPath]: Path for output .tmx file
  /// [sourceLanguageCode]: Optional source language filter
  /// [targetLanguageCode]: Optional target language filter
  ///
  /// Returns number of entries exported
  Future<Result<int, TmExportException>> exportToTmx({
    required String outputPath,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  });

  /// Get TM entries for review/editing
  ///
  /// [targetLanguageCode]: Optional target language filter
  /// [limit]: Maximum results
  /// [offset]: Pagination offset
  /// [orderBy]: Sort column and direction (default: 'usage_count DESC')
  ///
  /// Returns paginated list of TM entries
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>> getEntries({
    String? targetLanguageCode,
    int limit = 50,
    int offset = 0,
    String orderBy = 'usage_count DESC',
  });

  /// Search TM entries by text
  ///
  /// Uses FTS5 full-text search for fast results.
  ///
  /// [searchText]: Text to search for
  /// [searchIn]: Where to search (source, target, both)
  /// [targetLanguageCode]: Optional language filter
  /// [limit]: Maximum results
  ///
  /// Returns matching TM entries
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>>
      searchEntries({
    required String searchText,
    TmSearchScope searchIn = TmSearchScope.both,
    String? targetLanguageCode,
    int limit = 50,
  });

  /// Clear all TM cache
  ///
  /// Forces reload from database on next lookup.
  Future<void> clearCache();

  /// Rebuild TM cache
  ///
  /// Preloads frequently used entries into cache for faster lookups.
  ///
  /// [maxEntries]: Maximum entries to cache
  Future<Result<void, TmServiceException>> rebuildCache({
    int maxEntries = 10000,
  });
}

/// Translation Memory statistics
class TmStatistics {
  /// Total number of TM entries
  final int totalEntries;

  /// Entries by language pair
  final Map<String, int> entriesByLanguagePair;

  /// Total times TM was reused
  final int totalReuseCount;

  /// Estimated tokens saved by TM reuse
  final int tokensSaved;

  /// Average similarity score for fuzzy matches
  final double averageFuzzyScore;

  /// TM reuse rate (% of translations from TM vs LLM)
  final double reuseRate;

  const TmStatistics({
    required this.totalEntries,
    required this.entriesByLanguagePair,
    required this.totalReuseCount,
    required this.tokensSaved,
    required this.averageFuzzyScore,
    required this.reuseRate,
  });

  @override
  String toString() {
    return 'TmStatistics(entries: $totalEntries, '
        'reuseRate: ${(reuseRate * 100).toStringAsFixed(1)}%, '
        'tokensSaved: $tokensSaved)';
  }
}

/// Scope for searching TM entries
enum TmSearchScope {
  /// Search only in source text
  source,

  /// Search only in target text
  target,

  /// Search in both source and target
  both,
}
