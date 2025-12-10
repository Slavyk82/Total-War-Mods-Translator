import 'package:json_annotation/json_annotation.dart';

part 'tm_match.g.dart';

/// A Translation Memory match result
///
/// Contains information about a matched translation from TM,
/// including the similarity score and match type.
@JsonSerializable()
class TmMatch {
  /// Unique identifier of the TM entry
  final String entryId;

  /// Source text that matched
  final String sourceText;

  /// Translation in target language
  final String targetText;

  /// Target language code
  final String targetLanguageCode;

  /// Overall similarity score (0.0 - 1.0)
  final double similarityScore;

  /// Match type (exact, fuzzy, context)
  final TmMatchType matchType;

  /// Breakdown of similarity components
  final SimilarityBreakdown breakdown;

  /// Category context that was matched (if any)
  final String? category;

  /// How many times this TM entry has been used
  final int usageCount;

  /// When this TM entry was last used
  final DateTime lastUsedAt;

  /// Whether this match was auto-applied (>95% similarity)
  final bool autoApplied;

  const TmMatch({
    required this.entryId,
    required this.sourceText,
    required this.targetText,
    required this.targetLanguageCode,
    required this.similarityScore,
    required this.matchType,
    required this.breakdown,
    this.category,
    required this.usageCount,
    required this.lastUsedAt,
    this.autoApplied = false,
  });

  /// Whether this is an exact match (100%)
  bool get isExactMatch => similarityScore >= 0.999;

  /// Whether this is a high-quality fuzzy match (>=95%)
  bool get isHighQualityMatch => similarityScore >= 0.95;

  /// Whether this is a good fuzzy match (>=85%)
  bool get isGoodMatch => similarityScore >= 0.85;

  /// Whether context matches (category)
  bool get hasContextMatch => category != null;

  // JSON serialization
  factory TmMatch.fromJson(Map<String, dynamic> json) =>
      _$TmMatchFromJson(json);

  Map<String, dynamic> toJson() => _$TmMatchToJson(this);

  // CopyWith method
  TmMatch copyWith({
    String? entryId,
    String? sourceText,
    String? targetText,
    String? targetLanguageCode,
    double? similarityScore,
    TmMatchType? matchType,
    SimilarityBreakdown? breakdown,
    String? category,
    int? usageCount,
    DateTime? lastUsedAt,
    bool? autoApplied,
  }) {
    return TmMatch(
      entryId: entryId ?? this.entryId,
      sourceText: sourceText ?? this.sourceText,
      targetText: targetText ?? this.targetText,
      targetLanguageCode: targetLanguageCode ?? this.targetLanguageCode,
      similarityScore: similarityScore ?? this.similarityScore,
      matchType: matchType ?? this.matchType,
      breakdown: breakdown ?? this.breakdown,
      category: category ?? this.category,
      usageCount: usageCount ?? this.usageCount,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      autoApplied: autoApplied ?? this.autoApplied,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TmMatch &&
          runtimeType == other.runtimeType &&
          entryId == other.entryId &&
          similarityScore == other.similarityScore;

  @override
  int get hashCode => entryId.hashCode ^ similarityScore.hashCode;

  @override
  String toString() {
    return 'TmMatch(entryId: $entryId, similarity: ${(similarityScore * 100).toStringAsFixed(1)}%, '
        'type: $matchType)';
  }
}

/// Type of Translation Memory match
enum TmMatchType {
  /// Exact match (100% similarity, hash-based)
  @JsonValue('exact')
  exact,

  /// Fuzzy match (85-99% similarity)
  @JsonValue('fuzzy')
  fuzzy,

  /// Context-boosted match (similarity increased by context)
  @JsonValue('context')
  context,
}

/// Breakdown of similarity score components
@JsonSerializable()
class SimilarityBreakdown {
  /// Levenshtein distance score (0.0 - 1.0)
  final double levenshteinScore;

  /// Jaro-Winkler similarity score (0.0 - 1.0)
  final double jaroWinklerScore;

  /// Token-based similarity score (0.0 - 1.0)
  final double tokenScore;

  /// Context boost applied (0.0 - 0.08)
  final double contextBoost;

  /// Weights used for combining scores
  final ScoreWeights weights;

  const SimilarityBreakdown({
    required this.levenshteinScore,
    required this.jaroWinklerScore,
    required this.tokenScore,
    required this.contextBoost,
    required this.weights,
  });

  /// Calculate combined score
  double get combinedScore {
    return (levenshteinScore * weights.levenshteinWeight) +
        (jaroWinklerScore * weights.jaroWinklerWeight) +
        (tokenScore * weights.tokenWeight) +
        contextBoost;
  }

  // JSON serialization
  factory SimilarityBreakdown.fromJson(Map<String, dynamic> json) =>
      _$SimilarityBreakdownFromJson(json);

  Map<String, dynamic> toJson() => _$SimilarityBreakdownToJson(this);

  @override
  String toString() {
    return 'SimilarityBreakdown(levenshtein: ${(levenshteinScore * 100).toStringAsFixed(1)}%, '
        'jaroWinkler: ${(jaroWinklerScore * 100).toStringAsFixed(1)}%, '
        'token: ${(tokenScore * 100).toStringAsFixed(1)}%, '
        'contextBoost: ${(contextBoost * 100).toStringAsFixed(1)}%)';
  }
}

/// Weights for combining similarity scores
@JsonSerializable()
class ScoreWeights {
  /// Levenshtein weight (default: 0.4)
  final double levenshteinWeight;

  /// Jaro-Winkler weight (default: 0.3)
  final double jaroWinklerWeight;

  /// Token-based weight (default: 0.3)
  final double tokenWeight;

  const ScoreWeights({
    this.levenshteinWeight = 0.4,
    this.jaroWinklerWeight = 0.3,
    this.tokenWeight = 0.3,
  });

  /// Default weights
  static const ScoreWeights defaultWeights = ScoreWeights();

  // JSON serialization
  factory ScoreWeights.fromJson(Map<String, dynamic> json) =>
      _$ScoreWeightsFromJson(json);

  Map<String, dynamic> toJson() => _$ScoreWeightsToJson(this);

  /// Validate that weights sum to approximately 1.0
  bool get isValid {
    final sum = levenshteinWeight + jaroWinklerWeight + tokenWeight;
    return (sum - 1.0).abs() < 0.01; // Allow small floating point error
  }

  @override
  String toString() {
    return 'ScoreWeights(levenshtein: $levenshteinWeight, '
        'jaroWinkler: $jaroWinklerWeight, token: $tokenWeight)';
  }
}
