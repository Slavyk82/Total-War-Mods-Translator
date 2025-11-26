import 'dart:math' as math;
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/utils/string_similarity.dart';

/// Calculator for text similarity using multiple algorithms
///
/// Combines three algorithms with weighted scores:
/// - Levenshtein Distance (40% weight): Edit distance-based similarity
/// - Jaro-Winkler Similarity (30% weight): Good for typos and short strings
/// - Token-Based Similarity (30% weight): Order-independent word matching
///
/// Also applies context boost:
/// - +5% if game context matches
/// - +3% if category matches
class SimilarityCalculator {
  final TextNormalizer _normalizer = TextNormalizer();

  /// Default score weights
  static const ScoreWeights _defaultWeights = ScoreWeights();

  /// Singleton instance
  static final SimilarityCalculator _instance =
      SimilarityCalculator._internal();

  factory SimilarityCalculator() => _instance;

  SimilarityCalculator._internal();

  /// Calculate combined similarity score
  ///
  /// [text1]: First text
  /// [text2]: Second text
  /// [weights]: Score weights (default: 0.4, 0.3, 0.3)
  /// [category1]: Category of text1
  /// [category2]: Category of text2
  ///
  /// Returns similarity score (0.0 - 1.0) and detailed breakdown
  SimilarityBreakdown calculateSimilarity({
    required String text1,
    required String text2,
    ScoreWeights? weights,
    String? category1,
    String? category2,
  }) {
    final w = weights ?? _defaultWeights;

    // Normalize texts
    final normalized1 = _normalizer.normalize(text1);
    final normalized2 = _normalizer.normalize(text2);

    // Calculate individual scores
    final levenshteinScore =
        calculateLevenshteinSimilarity(normalized1, normalized2);
    final jaroWinklerScore =
        calculateJaroWinklerSimilarity(normalized1, normalized2);
    final tokenScore = calculateTokenSimilarity(normalized1, normalized2);

    // Calculate context boost
    double contextBoost = 0.0;
    if (category1 != null && category2 != null && category1 == category2) {
      contextBoost += 0.03; // +3% for matching category
    }

    return SimilarityBreakdown(
      levenshteinScore: levenshteinScore,
      jaroWinklerScore: jaroWinklerScore,
      tokenScore: tokenScore,
      contextBoost: contextBoost,
      weights: w,
    );
  }

  /// Calculate Levenshtein similarity (edit distance)
  ///
  /// Returns similarity as a score from 0.0 to 1.0:
  /// - 1.0 = identical strings
  /// - 0.0 = completely different
  ///
  /// Formula: 1 - (distance / max_length)
  ///
  /// Delegates to centralized StringSimilarity utility.
  double calculateLevenshteinSimilarity(String text1, String text2) {
    return StringSimilarity.similarity(text1, text2, caseSensitive: false);
  }

  /// Calculate Jaro-Winkler similarity
  ///
  /// Good for detecting typos and similar short strings.
  /// Gives more weight to matching prefixes.
  ///
  /// Returns score from 0.0 to 1.0
  double calculateJaroWinklerSimilarity(String text1, String text2) {
    if (text1 == text2) return 1.0;
    if (text1.isEmpty || text2.isEmpty) return 0.0;

    // Calculate Jaro similarity first
    final jaroSim = _calculateJaroSimilarity(text1, text2);

    // Calculate common prefix length (up to 4 characters)
    int prefixLength = 0;
    final maxPrefix = math.min(math.min(text1.length, text2.length), 4);
    for (int i = 0; i < maxPrefix; i++) {
      if (text1[i] == text2[i]) {
        prefixLength++;
      } else {
        break;
      }
    }

    // Apply Winkler modification (boost for common prefix)
    const scalingFactor = 0.1;
    return jaroSim + (prefixLength * scalingFactor * (1.0 - jaroSim));
  }

  /// Calculate Jaro similarity
  double _calculateJaroSimilarity(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;

    // Match window (max distance for matches)
    final matchWindow = (math.max(len1, len2) / 2).floor() - 1;
    if (matchWindow < 0) return 0.0;

    // Track matches
    final s1Matches = List.filled(len1, false);
    final s2Matches = List.filled(len2, false);

    int matches = 0;
    int transpositions = 0;

    // Find matches
    for (int i = 0; i < len1; i++) {
      final start = math.max(0, i - matchWindow);
      final end = math.min(i + matchWindow + 1, len2);

      for (int j = start; j < end; j++) {
        if (s2Matches[j] || s1[i] != s2[j]) continue;
        s1Matches[i] = true;
        s2Matches[j] = true;
        matches++;
        break;
      }
    }

    if (matches == 0) return 0.0;

    // Count transpositions
    int k = 0;
    for (int i = 0; i < len1; i++) {
      if (!s1Matches[i]) continue;
      while (!s2Matches[k]) {
        k++;
      }
      if (s1[i] != s2[k]) transpositions++;
      k++;
    }

    // Calculate Jaro similarity
    return (matches / len1 + matches / len2 + (matches - transpositions / 2) / matches) / 3.0;
  }

  /// Calculate token-based similarity (Jaccard index)
  ///
  /// Order-independent matching based on word overlap.
  /// Good for detecting paraphrases and reordered text.
  ///
  /// Formula: |intersection| / |union|
  ///
  /// Returns score from 0.0 to 1.0
  double calculateTokenSimilarity(String text1, String text2) {
    if (text1 == text2) return 1.0;
    if (text1.isEmpty || text2.isEmpty) return 0.0;

    // Tokenize both texts
    final tokens1 = _normalizer.tokenize(text1);
    final tokens2 = _normalizer.tokenize(text2);

    if (tokens1.isEmpty || tokens2.isEmpty) return 0.0;

    // Calculate Jaccard similarity (intersection / union)
    final intersection = tokens1.intersection(tokens2);
    final union = tokens1.union(tokens2);

    return intersection.length / union.length;
  }

  /// Calculate n-gram similarity (character n-grams)
  ///
  /// Alternative algorithm using character n-grams.
  /// Useful for detecting partial matches and misspellings.
  ///
  /// [text1]: First text
  /// [text2]: Second text
  /// [n]: N-gram size (default: 2 for bigrams)
  ///
  /// Returns Jaccard similarity of n-gram sets
  double calculateNGramSimilarity(String text1, String text2, {int n = 2}) {
    if (text1 == text2) return 1.0;
    if (text1.isEmpty || text2.isEmpty) return 0.0;

    final ngrams1 = _normalizer.getNGrams(text1, n: n);
    final ngrams2 = _normalizer.getNGrams(text2, n: n);

    if (ngrams1.isEmpty || ngrams2.isEmpty) return 0.0;

    final intersection = ngrams1.intersection(ngrams2);
    final union = ngrams1.union(ngrams2);

    return intersection.length / union.length;
  }

  /// Determine if two texts are similar enough
  ///
  /// Convenience method that returns true if combined similarity
  /// exceeds the threshold.
  ///
  /// [text1]: First text
  /// [text2]: Second text
  /// [threshold]: Minimum similarity threshold (default: 0.85 = 85%)
  ///
  /// Returns true if similarity >= threshold
  bool areSimilar({
    required String text1,
    required String text2,
    double threshold = 0.85,
    String? category1,
    String? category2,
  }) {
    final breakdown = calculateSimilarity(
      text1: text1,
      text2: text2,
      category1: category1,
      category2: category2,
    );

    return breakdown.combinedScore >= threshold;
  }
}
