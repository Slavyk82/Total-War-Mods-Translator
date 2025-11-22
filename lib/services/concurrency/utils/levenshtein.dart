import 'package:twmt/utils/string_similarity.dart';

/// Utility class for calculating Levenshtein distance and text similarity
///
/// Used by conflict resolver to determine how similar two versions are.
///
/// DEPRECATION NOTE: This class now delegates to the centralized
/// StringSimilarity utility. Prefer using StringSimilarity directly
/// for new code.
class LevenshteinDistance {
  /// Calculate Levenshtein distance between two strings
  ///
  /// Delegates to StringSimilarity.levenshteinDistance()
  static int calculate(String source, String target) {
    return StringSimilarity.levenshteinDistance(source, target);
  }

  /// Calculate similarity score between two strings (0.0 - 1.0)
  ///
  /// Delegates to StringSimilarity.similarity()
  static double similarity(String source, String target) {
    return StringSimilarity.similarity(source, target);
  }

  /// Calculate similarity percentage between two strings (0 - 100)
  ///
  /// Delegates to StringSimilarity.similarityPercentage()
  static double similarityPercentage(String source, String target) {
    return StringSimilarity.similarityPercentage(source, target);
  }

  /// Check if two strings are similar within a threshold
  ///
  /// Delegates to StringSimilarity.areSimilar()
  static bool areSimilar(
    String source,
    String target, {
    double threshold = 0.85,
  }) {
    return StringSimilarity.areSimilar(source, target, threshold: threshold);
  }

  /// Calculate normalized Levenshtein distance (0.0 - 1.0)
  ///
  /// Delegates to StringSimilarity.normalizedDistance()
  static double normalizedDistance(String source, String target) {
    return StringSimilarity.normalizedDistance(source, target);
  }

  /// Calculate Damerau-Levenshtein distance (includes transpositions)
  ///
  /// Delegates to StringSimilarity.damerauLevenshteinDistance()
  static int calculateDamerauLevenshtein(String source, String target) {
    return StringSimilarity.damerauLevenshteinDistance(source, target);
  }

  /// Calculate word-level Levenshtein distance
  ///
  /// Delegates to StringSimilarity.wordDistance()
  static int wordDistance(String source, String target) {
    return StringSimilarity.wordDistance(source, target);
  }

  /// Calculate word-level similarity (0.0 - 1.0)
  ///
  /// Delegates to StringSimilarity.wordSimilarity()
  static double wordSimilarity(String source, String target) {
    return StringSimilarity.wordSimilarity(source, target);
  }
}
