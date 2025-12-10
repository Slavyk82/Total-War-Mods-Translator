import 'dart:collection';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';

/// LRU Cache for Translation Memory lookups
///
/// Caches frequently accessed TM entries and match results
/// to improve performance and reduce database queries.
///
/// Features:
/// - LRU (Least Recently Used) eviction policy with O(1) operations
/// - Configurable maximum size
/// - Automatic invalidation on TM updates
/// - Cache statistics tracking
///
/// Performance:
/// - O(1) cache access (get/put)
/// - O(1) LRU eviction
/// - Uses LinkedHashMap for efficient ordering
class TmCache {
  /// Maximum cache size (default: 10,000 entries)
  final int maxSize;

  /// Cache for exact matches (sourceHash -> TmMatch)
  /// LinkedHashMap maintains insertion order for efficient LRU tracking
  final LinkedHashMap<String, TmMatch?> _exactMatchCache = LinkedHashMap<String, TmMatch?>();

  /// Cache statistics
  int _hits = 0;
  int _misses = 0;

  /// Singleton instance with configurable size
  static TmCache? _instance;

  factory TmCache({int maxSize = 10000}) {
    _instance ??= TmCache._internal(maxSize);
    return _instance!;
  }

  TmCache._internal(this.maxSize);

  /// Get exact match from cache
  ///
  /// [cacheKey]: Key to lookup (usually source hash + language pair)
  ///
  /// Returns cached match if found, null if not in cache
  ///
  /// Performance: O(1) lookup and reordering
  TmMatch? getExactMatch(String cacheKey) {
    if (_exactMatchCache.containsKey(cacheKey)) {
      _hits++;

      // Move to end (most recently used) - O(1) remove and re-insert
      final value = _exactMatchCache.remove(cacheKey);
      _exactMatchCache[cacheKey] = value;

      return value;
    }

    _misses++;
    return null;
  }

  /// Put exact match in cache
  ///
  /// [cacheKey]: Key to store under
  /// [match]: Match result to cache (null for "no match")
  ///
  /// Performance: O(1) eviction and insertion
  void putExactMatch(String cacheKey, TmMatch? match) {
    // If key already exists, remove it first to reorder
    if (_exactMatchCache.containsKey(cacheKey)) {
      _exactMatchCache.remove(cacheKey);
    }

    // If cache is full, evict LRU entry (first entry in LinkedHashMap)
    if (_exactMatchCache.length >= maxSize) {
      _evictLeastRecentlyUsed();
    }

    // Add to end (most recently used)
    _exactMatchCache[cacheKey] = match;
  }

  /// Evict least recently used entry
  ///
  /// Performance: O(1) - removes first entry in LinkedHashMap
  void _evictLeastRecentlyUsed() {
    if (_exactMatchCache.isEmpty) return;

    // Remove first entry (least recently used)
    _exactMatchCache.remove(_exactMatchCache.keys.first);
  }

  /// Invalidate a specific cache entry
  ///
  /// Called when a TM entry is updated or deleted
  ///
  /// Performance: O(1)
  void invalidate(String cacheKey) {
    _exactMatchCache.remove(cacheKey);
  }

  /// Invalidate all cache entries for a language pair
  ///
  /// [sourceLanguageCode]: Source language
  /// [targetLanguageCode]: Target language
  ///
  /// Performance: O(n) where n is number of matching entries
  void invalidateLanguagePair(
      String sourceLanguageCode, String targetLanguageCode) {
    final languagePairPrefix = '${sourceLanguageCode}_${targetLanguageCode}_';

    // Find all keys matching this language pair
    final keysToRemove = _exactMatchCache.keys
        .where((key) => key.startsWith(languagePairPrefix))
        .toList();

    // Remove them
    for (final key in keysToRemove) {
      _exactMatchCache.remove(key);
    }
  }

  /// Clear entire cache
  ///
  /// Performance: O(1)
  void clear() {
    _exactMatchCache.clear();
    _resetStatistics();
  }

  /// Get cache statistics
  CacheStatistics getStatistics() {
    final hitRate = (_hits + _misses) > 0 ? _hits / (_hits + _misses) : 0.0;

    return CacheStatistics(
      size: _exactMatchCache.length,
      maxSize: maxSize,
      hits: _hits,
      misses: _misses,
      hitRate: hitRate,
    );
  }

  /// Reset statistics counters
  void _resetStatistics() {
    _hits = 0;
    _misses = 0;
  }

  /// Get current cache size
  int get size => _exactMatchCache.length;

  /// Check if cache is empty
  bool get isEmpty => _exactMatchCache.isEmpty;

  /// Check if cache is full
  bool get isFull => _exactMatchCache.length >= maxSize;

  /// Generate cache key for exact match lookup
  ///
  /// [sourceHash]: Hash of source text
  /// [sourceLanguageCode]: Source language
  /// [targetLanguageCode]: Target language
  ///
  /// Returns cache key string
  static String generateExactMatchKey({
    required String sourceHash,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) {
    final parts = [
      sourceLanguageCode,
      targetLanguageCode,
      sourceHash,
    ];
    return parts.join('_');
  }

  /// Preload frequently used TM entries into cache
  ///
  /// [entries]: TM entries to preload
  /// [sourceLanguageCode]: Source language
  /// [targetLanguageCode]: Target language
  ///
  /// Useful for warming up cache at application startup
  void preloadEntries({
    required List<TranslationMemoryEntry> entries,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) {
    for (final entry in entries) {
      final cacheKey = generateExactMatchKey(
        sourceHash: entry.sourceHash,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );

      // Create TmMatch from entry
      final match = TmMatch(
        entryId: entry.id,
        sourceText: entry.sourceText,
        targetText: entry.translatedText,
        targetLanguageCode: entry.targetLanguageId,
        similarityScore: 1.0, // Exact match
        matchType: TmMatchType.exact,
        breakdown: SimilarityBreakdown(
          levenshteinScore: 1.0,
          jaroWinklerScore: 1.0,
          tokenScore: 1.0,
          contextBoost: 0.0,
          weights: ScoreWeights.defaultWeights,
        ),
        category: null, // Not stored in TranslationMemoryEntry model
        usageCount: entry.usageCount,
        lastUsedAt: DateTime.fromMillisecondsSinceEpoch(entry.lastUsedAt * 1000),
        autoApplied: true,
      );

      putExactMatch(cacheKey, match);

      // Stop if cache is full
      if (isFull) break;
    }
  }
}

/// Statistics for cache performance
class CacheStatistics {
  /// Current number of entries in cache
  final int size;

  /// Maximum cache size
  final int maxSize;

  /// Number of cache hits
  final int hits;

  /// Number of cache misses
  final int misses;

  /// Hit rate (0.0 - 1.0)
  final double hitRate;

  const CacheStatistics({
    required this.size,
    required this.maxSize,
    required this.hits,
    required this.misses,
    required this.hitRate,
  });

  /// Total cache accesses
  int get totalAccesses => hits + misses;

  /// Cache utilization percentage (0.0 - 1.0)
  double get utilization => maxSize > 0 ? size / maxSize : 0.0;

  @override
  String toString() {
    return 'CacheStatistics('
        'size: $size/$maxSize (${(utilization * 100).toStringAsFixed(1)}%), '
        'hits: $hits, misses: $misses, '
        'hitRate: ${(hitRate * 100).toStringAsFixed(1)}%)';
  }
}
