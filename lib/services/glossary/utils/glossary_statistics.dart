import 'package:twmt/models/domain/glossary_entry.dart';

/// Utility class for calculating glossary statistics
///
/// Provides static methods for analyzing glossary entries and generating
/// statistical information about language pairs, categories, and usage.
class GlossaryStatistics {
  GlossaryStatistics._(); // Private constructor to prevent instantiation

  /// Calculate statistics for a list of glossary entries
  ///
  /// Returns a map containing:
  /// - totalEntries: Total number of entries
  /// - languagePairs: Map of language pair to count
  /// - categories: Map of category to count
  ///
  /// [entries] - List of glossary entries to analyze
  static Map<String, dynamic> calculateStats(List<GlossaryEntry> entries) {
    // Count by language pair
    final languagePairs = <String, int>{};
    for (final entry in entries) {
      final pair = entry.targetLanguageCode;
      languagePairs[pair] = (languagePairs[pair] ?? 0) + 1;
    }

    // Count by category
    final categories = <String, int>{};
    for (final entry in entries) {
      final cat = entry.category ?? 'Uncategorized';
      categories[cat] = (categories[cat] ?? 0) + 1;
    }

    return {
      'totalEntries': entries.length,
      'languagePairs': languagePairs,
      'categories': categories,
    };
  }

  /// Get language pairs present in entries
  ///
  /// Returns a set of language pair strings (e.g., 'en-fr', 'de-en')
  ///
  /// [entries] - List of glossary entries
  static Set<String> getLanguagePairs(List<GlossaryEntry> entries) {
    return entries
        .map((e) => e.targetLanguageCode)
        .toSet();
  }

  /// Get categories present in entries
  ///
  /// Returns a set of category names (uncategorized entries marked as 'Uncategorized')
  ///
  /// [entries] - List of glossary entries
  static Set<String> getCategories(List<GlossaryEntry> entries) {
    return entries.map((e) => e.category ?? 'Uncategorized').toSet();
  }

  /// Count entries by language pair
  ///
  /// Returns a map of language pair to count
  ///
  /// [entries] - List of glossary entries
  static Map<String, int> countByLanguagePair(List<GlossaryEntry> entries) {
    final counts = <String, int>{};
    for (final entry in entries) {
      final pair = entry.targetLanguageCode;
      counts[pair] = (counts[pair] ?? 0) + 1;
    }
    return counts;
  }

  /// Count entries by category
  ///
  /// Returns a map of category to count
  ///
  /// [entries] - List of glossary entries
  static Map<String, int> countByCategory(List<GlossaryEntry> entries) {
    final counts = <String, int>{};
    for (final entry in entries) {
      final cat = entry.category ?? 'Uncategorized';
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
    return counts;
  }

  /// Get most common terms (source terms that appear most frequently)
  ///
  /// Returns a sorted list of term-count pairs, descending by count.
  ///
  /// [entries] - List of glossary entries
  /// [limit] - Maximum number of results to return (default: 10)
  static List<MapEntry<String, int>> getMostCommonTerms(
    List<GlossaryEntry> entries, {
    int limit = 10,
  }) {
    final termCounts = <String, int>{};
    for (final entry in entries) {
      final term = entry.sourceTerm.toLowerCase();
      termCounts[term] = (termCounts[term] ?? 0) + 1;
    }

    final sortedEntries = termCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedEntries.take(limit).toList();
  }
}
