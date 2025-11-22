import 'dart:math' as math;
import 'dart:collection';

/// Centralized string similarity and distance calculations
///
/// Provides optimized implementations of:
/// - Levenshtein distance (edit distance)
/// - Damerau-Levenshtein distance (with transpositions)
/// - Word-level distance calculations
///
/// Features:
/// - Space-optimized O(min(m,n)) implementation
/// - Optional LRU caching for repeated calculations
/// - Multiple convenience methods for similarity scores
class StringSimilarity {
  /// Optional LRU cache for repeated calculations
  static LinkedHashMap<String, int>? _cache;
  static const int _defaultCacheSize = 1000;

  /// Enable caching with specified size
  ///
  /// Cache improves performance for repeated comparisons.
  /// Useful in TM lookup scenarios where same strings are compared multiple times.
  ///
  /// [maxSize]: Maximum number of cached results (default: 1000)
  static void enableCache({int maxSize = _defaultCacheSize}) {
    _cache = LinkedHashMap<String, int>();
  }

  /// Disable and clear cache
  static void disableCache() {
    _cache = null;
  }

  /// Clear cache entries
  static void clearCache() {
    _cache?.clear();
  }

  /// Calculate Levenshtein distance between two strings
  ///
  /// Returns the minimum number of single-character edits (insertions,
  /// deletions, or substitutions) required to change one string into the other.
  ///
  /// Space optimized: Uses O(min(m,n)) space instead of O(m*n).
  ///
  /// Parameters:
  /// - [source]: Source string
  /// - [target]: Target string
  /// - [caseSensitive]: Whether comparison is case-sensitive (default: false)
  ///
  /// Returns: Edit distance as integer
  ///
  /// Example:
  /// ```dart
  /// final distance = StringSimilarity.levenshteinDistance('kitten', 'sitting');
  /// // Returns: 3 (k→s, e→i, insert g)
  /// ```
  static int levenshteinDistance(
    String source,
    String target, {
    bool caseSensitive = false,
  }) {
    // Normalize case if needed
    final s1 = caseSensitive ? source : source.toLowerCase();
    final s2 = caseSensitive ? target : target.toLowerCase();

    // Early exits
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    // Check cache
    if (_cache != null) {
      final cacheKey = '$s1|$s2';
      if (_cache!.containsKey(cacheKey)) {
        // Move to end (most recently used)
        final value = _cache!.remove(cacheKey)!;
        _cache![cacheKey] = value;
        return value;
      }
    }

    // Ensure s1 is the shorter string for space optimization
    final shorter = s1.length <= s2.length ? s1 : s2;
    final longer = s1.length <= s2.length ? s2 : s1;

    // Use single array that we reuse (space optimization)
    // Only need O(min(m,n)) space instead of O(m*n)
    final previousRow = List<int>.filled(shorter.length + 1, 0);
    final currentRow = List<int>.filled(shorter.length + 1, 0);

    // Initialize first row (0, 1, 2, 3, ...)
    for (int j = 0; j <= shorter.length; j++) {
      previousRow[j] = j;
    }

    // Fill matrix row by row
    for (int i = 1; i <= longer.length; i++) {
      currentRow[0] = i; // First column value

      for (int j = 1; j <= shorter.length; j++) {
        final cost = longer[i - 1] == shorter[j - 1] ? 0 : 1;

        currentRow[j] = math.min(
          math.min(
            currentRow[j - 1] + 1, // Insertion
            previousRow[j] + 1, // Deletion
          ),
          previousRow[j - 1] + cost, // Substitution
        );
      }

      // Swap rows for next iteration
      for (int j = 0; j <= shorter.length; j++) {
        previousRow[j] = currentRow[j];
      }
    }

    final result = currentRow[shorter.length];

    // Cache result
    if (_cache != null) {
      final cacheKey = '$s1|$s2';

      // Evict LRU if full
      if (_cache!.length >= _defaultCacheSize) {
        _cache!.remove(_cache!.keys.first);
      }

      _cache![cacheKey] = result;
    }

    return result;
  }

  /// Calculate similarity score between two strings (0.0 - 1.0)
  ///
  /// Returns 1.0 for identical strings, 0.0 for completely different strings.
  ///
  /// Formula: 1.0 - (distance / max_length)
  ///
  /// Parameters:
  /// - [source]: Source string
  /// - [target]: Target string
  /// - [caseSensitive]: Whether comparison is case-sensitive (default: false)
  ///
  /// Returns: Similarity score (0.0 - 1.0)
  ///
  /// Example:
  /// ```dart
  /// final similarity = StringSimilarity.similarity('kitten', 'sitting');
  /// // Returns: ~0.57 (4 matching characters out of 7)
  /// ```
  static double similarity(
    String source,
    String target, {
    bool caseSensitive = false,
  }) {
    if (source == target) return 1.0;
    if (source.isEmpty || target.isEmpty) return 0.0;

    final distance = levenshteinDistance(source, target, caseSensitive: caseSensitive);
    final maxLength = math.max(source.length, target.length);

    return 1.0 - (distance / maxLength);
  }

  /// Calculate normalized distance (0.0 - 1.0)
  ///
  /// Returns 0.0 for identical strings, 1.0 for completely different.
  /// This is the inverse of similarity().
  static double normalizedDistance(
    String source,
    String target, {
    bool caseSensitive = false,
  }) {
    return 1.0 - similarity(source, target, caseSensitive: caseSensitive);
  }

  /// Calculate similarity percentage between two strings (0 - 100)
  ///
  /// Convenience method that returns similarity as a percentage.
  ///
  /// Returns: Similarity as percentage (0 - 100)
  static double similarityPercentage(
    String source,
    String target, {
    bool caseSensitive = false,
  }) {
    return similarity(source, target, caseSensitive: caseSensitive) * 100.0;
  }

  /// Check if two strings are similar within a threshold
  ///
  /// Parameters:
  /// - [source]: Source string
  /// - [target]: Target string
  /// - [threshold]: Minimum similarity score (0.0 - 1.0, default: 0.85)
  /// - [caseSensitive]: Whether comparison is case-sensitive (default: false)
  ///
  /// Returns: true if similarity >= threshold
  ///
  /// Example:
  /// ```dart
  /// final areSimilar = StringSimilarity.areSimilar('hello', 'helo', threshold: 0.8);
  /// // Returns: true (similarity: 0.8)
  /// ```
  static bool areSimilar(
    String source,
    String target, {
    double threshold = 0.85,
    bool caseSensitive = false,
  }) {
    return similarity(source, target, caseSensitive: caseSensitive) >= threshold;
  }

  /// Calculate Damerau-Levenshtein distance (includes transpositions)
  ///
  /// Similar to Levenshtein but also considers adjacent character swaps
  /// as a single operation.
  ///
  /// Example: "ab" → "ba" has distance 1 (transposition) instead of 2
  ///
  /// Note: This uses O(m*n) space due to the need to track transpositions.
  static int damerauLevenshteinDistance(
    String source,
    String target, {
    bool caseSensitive = false,
  }) {
    final s1 = caseSensitive ? source : source.toLowerCase();
    final s2 = caseSensitive ? target : target.toLowerCase();

    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final sourceLength = s1.length;
    final targetLength = s2.length;
    final maxDist = sourceLength + targetLength;

    // Create distance matrix with extra row/column
    final matrix = List.generate(
      sourceLength + 2,
      (i) => List.filled(targetLength + 2, 0),
    );

    matrix[0][0] = maxDist;

    // Initialize first column
    for (int i = 0; i <= sourceLength; i++) {
      matrix[i + 1][0] = maxDist;
      matrix[i + 1][1] = i;
    }

    // Initialize first row
    for (int j = 0; j <= targetLength; j++) {
      matrix[0][j + 1] = maxDist;
      matrix[1][j + 1] = j;
    }

    for (int i = 1; i <= sourceLength; i++) {
      int db = 0;
      for (int j = 1; j <= targetLength; j++) {
        int k = db;
        int cost = 1;

        if (s1[i - 1] == s2[j - 1]) {
          cost = 0;
          db = j;
        }

        matrix[i + 1][j + 1] = _min4(
          matrix[i][j] + cost, // Substitution
          matrix[i + 1][j] + 1, // Insertion
          matrix[i][j + 1] + 1, // Deletion
          matrix[k][j - 1] + (i - k - 1) + 1 + (j - 1 - db), // Transposition
        );
      }
    }

    return matrix[sourceLength + 1][targetLength + 1];
  }

  /// Calculate word-level Levenshtein distance
  ///
  /// Treats entire words as units instead of characters.
  /// Useful for comparing sentences.
  ///
  /// Example:
  /// ```dart
  /// final distance = StringSimilarity.wordDistance(
  ///   'the quick brown fox',
  ///   'the slow brown dog',
  /// );
  /// // Returns: 2 (quick→slow, fox→dog)
  /// ```
  static int wordDistance(
    String source,
    String target, {
    bool caseSensitive = false,
  }) {
    final s1 = caseSensitive ? source : source.toLowerCase();
    final s2 = caseSensitive ? target : target.toLowerCase();

    final sourceWords = s1.split(RegExp(r'\s+'));
    final targetWords = s2.split(RegExp(r'\s+'));

    if (sourceWords.isEmpty) return targetWords.length;
    if (targetWords.isEmpty) return sourceWords.length;

    final sourceLength = sourceWords.length;
    final targetLength = targetWords.length;

    final matrix = List.generate(
      sourceLength + 1,
      (i) => List.filled(targetLength + 1, 0),
    );

    for (int i = 0; i <= sourceLength; i++) {
      matrix[i][0] = i;
    }

    for (int j = 0; j <= targetLength; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= sourceLength; i++) {
      for (int j = 1; j <= targetLength; j++) {
        final cost = sourceWords[i - 1] == targetWords[j - 1] ? 0 : 1;

        matrix[i][j] = math.min(
          math.min(
            matrix[i - 1][j] + 1,
            matrix[i][j - 1] + 1,
          ),
          matrix[i - 1][j - 1] + cost,
        );
      }
    }

    return matrix[sourceLength][targetLength];
  }

  /// Calculate word-level similarity (0.0 - 1.0)
  static double wordSimilarity(
    String source,
    String target, {
    bool caseSensitive = false,
  }) {
    final s1 = caseSensitive ? source : source.toLowerCase();
    final s2 = caseSensitive ? target : target.toLowerCase();

    final sourceWords = s1.split(RegExp(r'\s+'));
    final targetWords = s2.split(RegExp(r'\s+'));

    if (sourceWords.isEmpty || targetWords.isEmpty) return 0.0;

    final distance = wordDistance(source, target, caseSensitive: caseSensitive);
    final maxLength = math.max(sourceWords.length, targetWords.length);

    return 1.0 - (distance / maxLength);
  }

  /// Get minimum of three integers
  static int _min3(int a, int b, int c) {
    int min = a;
    if (b < min) min = b;
    if (c < min) min = c;
    return min;
  }

  /// Get minimum of four integers
  static int _min4(int a, int b, int c, int d) {
    return _min3(_min3(a, b, c), d, d);
  }

  /// Get cache statistics
  ///
  /// Returns information about cache usage if caching is enabled.
  static CacheStats? getCacheStats() {
    if (_cache == null) return null;

    return CacheStats(
      size: _cache!.length,
      maxSize: _defaultCacheSize,
    );
  }
}

/// Cache statistics
class CacheStats {
  final int size;
  final int maxSize;

  const CacheStats({
    required this.size,
    required this.maxSize,
  });

  double get utilization => maxSize > 0 ? size / maxSize : 0.0;

  @override
  String toString() {
    return 'CacheStats(size: $size/$maxSize, utilization: ${(utilization * 100).toStringAsFixed(1)}%)';
  }
}
