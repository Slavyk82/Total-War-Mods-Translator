import 'package:json_annotation/json_annotation.dart';

part 'conflict_resolution.g.dart';

/// Type of conflict detected
enum ConflictType {
  /// Manual edit vs LLM translation
  manualVsLlm,

  /// Manual edit vs manual edit (different users)
  manualVsManual,

  /// LLM translation vs LLM translation (different batches)
  llmVsLlm,

  /// Version mismatch (optimistic locking)
  versionMismatch,

  /// Lock timeout during edit
  lockTimeout,
}

/// Strategy for resolving conflicts
enum ResolutionStrategy {
  /// Keep the user's manual version
  keepUser,

  /// Keep the LLM-generated version
  keepLlm,

  /// Keep the newer version (by timestamp)
  keepNewer,

  /// Keep the older version
  keepOlder,

  /// Merge both versions (if similar enough)
  merge,

  /// Prompt user to manually resolve
  manualResolve,

  /// Keep current value (reject change)
  keepCurrent,

  /// Discard conflicting change
  discard,
}

/// Information about a detected conflict
@JsonSerializable()
class ConflictInfo {
  /// Unique conflict identifier
  final String id;

  /// Translation unit ID
  final String translationUnitId;

  /// Language code
  final String languageCode;

  /// Type of conflict
  final ConflictType conflictType;

  /// Current value in database
  final String currentValue;

  /// Current version number
  final int currentVersion;

  /// Source of current value ('user', 'llm', 'batch_123', etc.)
  final String currentSource;

  /// Timestamp of current value
  final DateTime currentTimestamp;

  /// Incoming value trying to be saved
  final String incomingValue;

  /// Incoming version number
  final int incomingVersion;

  /// Source of incoming value
  final String incomingSource;

  /// Timestamp of incoming value
  final DateTime incomingTimestamp;

  /// Similarity score between current and incoming (0.0 - 1.0)
  final double similarityScore;

  /// Whether conflict can be auto-resolved
  final bool canAutoResolve;

  /// Suggested resolution strategy
  final ResolutionStrategy? suggestedStrategy;

  /// Additional context about the conflict
  final Map<String, dynamic>? metadata;

  const ConflictInfo({
    required this.id,
    required this.translationUnitId,
    required this.languageCode,
    required this.conflictType,
    required this.currentValue,
    required this.currentVersion,
    required this.currentSource,
    required this.currentTimestamp,
    required this.incomingValue,
    required this.incomingVersion,
    required this.incomingSource,
    required this.incomingTimestamp,
    required this.similarityScore,
    required this.canAutoResolve,
    this.suggestedStrategy,
    this.metadata,
  });

  /// JSON serialization
  factory ConflictInfo.fromJson(Map<String, dynamic> json) =>
      _$ConflictInfoFromJson(json);

  /// JSON deserialization
  Map<String, dynamic> toJson() => _$ConflictInfoToJson(this);

  /// Check if values are nearly identical (similarity >= 95%)
  bool get areNearlyIdentical => similarityScore >= 0.95;

  /// Check if incoming value is newer
  bool get incomingIsNewer =>
      incomingTimestamp.isAfter(currentTimestamp);

  /// Create copy with updated fields
  ConflictInfo copyWith({
    String? id,
    String? translationUnitId,
    String? languageCode,
    ConflictType? conflictType,
    String? currentValue,
    int? currentVersion,
    String? currentSource,
    DateTime? currentTimestamp,
    String? incomingValue,
    int? incomingVersion,
    String? incomingSource,
    DateTime? incomingTimestamp,
    double? similarityScore,
    bool? canAutoResolve,
    ResolutionStrategy? suggestedStrategy,
    Map<String, dynamic>? metadata,
  }) {
    return ConflictInfo(
      id: id ?? this.id,
      translationUnitId: translationUnitId ?? this.translationUnitId,
      languageCode: languageCode ?? this.languageCode,
      conflictType: conflictType ?? this.conflictType,
      currentValue: currentValue ?? this.currentValue,
      currentVersion: currentVersion ?? this.currentVersion,
      currentSource: currentSource ?? this.currentSource,
      currentTimestamp: currentTimestamp ?? this.currentTimestamp,
      incomingValue: incomingValue ?? this.incomingValue,
      incomingVersion: incomingVersion ?? this.incomingVersion,
      incomingSource: incomingSource ?? this.incomingSource,
      incomingTimestamp: incomingTimestamp ?? this.incomingTimestamp,
      similarityScore: similarityScore ?? this.similarityScore,
      canAutoResolve: canAutoResolve ?? this.canAutoResolve,
      suggestedStrategy: suggestedStrategy ?? this.suggestedStrategy,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConflictInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          translationUnitId == other.translationUnitId &&
          languageCode == other.languageCode &&
          conflictType == other.conflictType &&
          currentValue == other.currentValue &&
          currentVersion == other.currentVersion &&
          currentSource == other.currentSource &&
          currentTimestamp == other.currentTimestamp &&
          incomingValue == other.incomingValue &&
          incomingVersion == other.incomingVersion &&
          incomingSource == other.incomingSource &&
          incomingTimestamp == other.incomingTimestamp &&
          similarityScore == other.similarityScore &&
          canAutoResolve == other.canAutoResolve &&
          suggestedStrategy == other.suggestedStrategy;

  @override
  int get hashCode =>
      id.hashCode ^
      translationUnitId.hashCode ^
      languageCode.hashCode ^
      conflictType.hashCode ^
      currentValue.hashCode ^
      currentVersion.hashCode ^
      currentSource.hashCode ^
      currentTimestamp.hashCode ^
      incomingValue.hashCode ^
      incomingVersion.hashCode ^
      incomingSource.hashCode ^
      incomingTimestamp.hashCode ^
      similarityScore.hashCode ^
      canAutoResolve.hashCode ^
      suggestedStrategy.hashCode;

  @override
  String toString() {
    return 'ConflictInfo(id: $id, type: $conflictType, '
        'similarity: ${(similarityScore * 100).toStringAsFixed(1)}%, '
        'canAutoResolve: $canAutoResolve, suggested: $suggestedStrategy)';
  }
}

/// Result of conflict resolution
@JsonSerializable()
class ConflictResolution {
  /// Conflict ID that was resolved
  final String conflictId;

  /// Resolution strategy used
  final ResolutionStrategy strategy;

  /// Final value after resolution
  final String resolvedValue;

  /// Final version number
  final int resolvedVersion;

  /// Source of resolved value
  final String resolvedSource;

  /// When the conflict was resolved
  final DateTime resolvedAt;

  /// Who/what resolved the conflict (user_id, system, etc.)
  final String resolvedBy;

  /// Whether resolution was automatic or manual
  final bool wasAutomatic;

  /// Reason for the resolution (optional)
  final String? reason;

  const ConflictResolution({
    required this.conflictId,
    required this.strategy,
    required this.resolvedValue,
    required this.resolvedVersion,
    required this.resolvedSource,
    required this.resolvedAt,
    required this.resolvedBy,
    required this.wasAutomatic,
    this.reason,
  });

  /// JSON serialization
  factory ConflictResolution.fromJson(Map<String, dynamic> json) =>
      _$ConflictResolutionFromJson(json);

  /// JSON deserialization
  Map<String, dynamic> toJson() => _$ConflictResolutionToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConflictResolution &&
          runtimeType == other.runtimeType &&
          conflictId == other.conflictId &&
          strategy == other.strategy &&
          resolvedValue == other.resolvedValue &&
          resolvedVersion == other.resolvedVersion &&
          resolvedSource == other.resolvedSource &&
          resolvedAt == other.resolvedAt &&
          resolvedBy == other.resolvedBy &&
          wasAutomatic == other.wasAutomatic &&
          reason == other.reason;

  @override
  int get hashCode =>
      conflictId.hashCode ^
      strategy.hashCode ^
      resolvedValue.hashCode ^
      resolvedVersion.hashCode ^
      resolvedSource.hashCode ^
      resolvedAt.hashCode ^
      resolvedBy.hashCode ^
      wasAutomatic.hashCode ^
      reason.hashCode;

  @override
  String toString() {
    return 'ConflictResolution(conflictId: $conflictId, strategy: $strategy, '
        'wasAutomatic: $wasAutomatic)';
  }
}

/// Configuration for automatic conflict resolution
@JsonSerializable()
class ConflictResolutionConfig {
  /// Auto-resolve if similarity >= this threshold (default: 0.95)
  final double autoResolveSimilarityThreshold;

  /// Auto-resolve if versions are within this delta (default: 1)
  final int autoResolveVersionDelta;

  /// Prefer user edits over LLM translations
  final bool preferUserEdits;

  /// Prefer newer versions over older
  final bool preferNewerVersions;

  /// Enable automatic merging for similar values
  final bool enableAutoMerge;

  /// Maximum time between edits to consider them concurrent (minutes)
  final int concurrentEditWindowMinutes;

  const ConflictResolutionConfig({
    this.autoResolveSimilarityThreshold = 0.95,
    this.autoResolveVersionDelta = 1,
    this.preferUserEdits = true,
    this.preferNewerVersions = true,
    this.enableAutoMerge = false,
    this.concurrentEditWindowMinutes = 5,
  });

  /// JSON serialization
  factory ConflictResolutionConfig.fromJson(Map<String, dynamic> json) =>
      _$ConflictResolutionConfigFromJson(json);

  /// JSON deserialization
  Map<String, dynamic> toJson() => _$ConflictResolutionConfigToJson(this);

  /// Default configuration
  static const ConflictResolutionConfig defaultConfig =
      ConflictResolutionConfig();

  @override
  String toString() {
    return 'ConflictResolutionConfig(similarityThreshold: $autoResolveSimilarityThreshold, '
        'preferUserEdits: $preferUserEdits, preferNewer: $preferNewerVersions)';
  }
}
