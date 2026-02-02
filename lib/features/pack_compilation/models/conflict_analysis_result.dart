import 'package:json_annotation/json_annotation.dart';

import 'compilation_conflict.dart';

part 'conflict_analysis_result.g.dart';

/// Result of conflict analysis for a compilation
@JsonSerializable()
class ConflictAnalysisResult {
  /// All detected conflicts
  final List<CompilationConflict> conflicts;

  /// Summary statistics
  final ConflictSummary summary;

  /// Timestamp when analysis was performed (Unix timestamp in seconds)
  @JsonKey(name: 'analyzed_at')
  final int analyzedAt;

  /// Project IDs that were analyzed
  @JsonKey(name: 'analyzed_project_ids')
  final List<String> analyzedProjectIds;

  /// Language ID for which translations were compared
  @JsonKey(name: 'language_id')
  final String languageId;

  const ConflictAnalysisResult({
    required this.conflicts,
    required this.summary,
    required this.analyzedAt,
    required this.analyzedProjectIds,
    required this.languageId,
  });

  /// Whether there are any conflicts
  bool get hasConflicts => conflicts.isNotEmpty;

  /// Whether there are unresolved conflicts (excluding auto-resolvable duplicates)
  bool get hasUnresolvedConflicts => conflicts.any(
        (c) => !c.isResolved && !c.canAutoResolve,
      );

  /// Count of unresolved conflicts (excluding auto-resolvable duplicates)
  int get unresolvedCount =>
      conflicts.where((c) => !c.isResolved && !c.canAutoResolve).length;

  /// Get unresolved conflicts (excluding auto-resolvable duplicates)
  List<CompilationConflict> get unresolvedConflicts =>
      conflicts.where((c) => !c.isResolved && !c.canAutoResolve).toList();

  /// Get conflicts that require manual resolution
  List<CompilationConflict> get manualResolutionRequired =>
      conflicts.where((c) => !c.canAutoResolve).toList();

  /// Get conflicts by type
  List<CompilationConflict> getByType(CompilationConflictType type) =>
      conflicts.where((c) => c.conflictType == type).toList();

  /// Create a copy with updated conflicts (after resolutions applied)
  ConflictAnalysisResult withResolvedConflicts(
    CompilationConflictResolutions resolutions,
  ) {
    final updatedConflicts = conflicts.map((conflict) {
      if (conflict.isResolved) return conflict;

      final resolution = resolutions.getResolution(conflict.id);
      final projectId = resolutions.getResolutionProjectId(conflict.id);

      if (resolution != null) {
        return conflict.copyWith(
          resolution: resolution,
          resolvedWithProjectId: projectId,
        );
      }

      // Auto-resolve duplicates if no explicit resolution
      if (conflict.canAutoResolve) {
        return conflict.copyWith(
          resolution: CompilationConflictResolution.useFirst,
          resolvedWithProjectId: conflict.firstEntry.projectId,
        );
      }

      return conflict;
    }).toList();

    return ConflictAnalysisResult(
      conflicts: updatedConflicts,
      summary: _buildSummaryFromConflicts(updatedConflicts),
      analyzedAt: analyzedAt,
      analyzedProjectIds: analyzedProjectIds,
      languageId: languageId,
    );
  }

  static ConflictSummary _buildSummaryFromConflicts(
    List<CompilationConflict> conflicts,
  ) {
    int keyCollisionCount = 0;
    int translationConflictCount = 0;
    int duplicateCount = 0;
    int resolvedCount = 0;

    for (final conflict in conflicts) {
      switch (conflict.conflictType) {
        case CompilationConflictType.keyCollisionDifferentSource:
          keyCollisionCount++;
          break;
        case CompilationConflictType.translationConflict:
          translationConflictCount++;
          break;
        case CompilationConflictType.duplicate:
          duplicateCount++;
          break;
      }
      if (conflict.isResolved) {
        resolvedCount++;
      }
    }

    return ConflictSummary(
      totalCount: conflicts.length,
      keyCollisionCount: keyCollisionCount,
      translationConflictCount: translationConflictCount,
      duplicateCount: duplicateCount,
      resolvedCount: resolvedCount,
    );
  }

  factory ConflictAnalysisResult.fromJson(Map<String, dynamic> json) =>
      _$ConflictAnalysisResultFromJson(json);

  Map<String, dynamic> toJson() => _$ConflictAnalysisResultToJson(this);

  /// Create an empty result (no conflicts)
  factory ConflictAnalysisResult.empty({
    required List<String> projectIds,
    required String languageId,
  }) {
    return ConflictAnalysisResult(
      conflicts: const [],
      summary: const ConflictSummary(
        totalCount: 0,
        keyCollisionCount: 0,
        translationConflictCount: 0,
        duplicateCount: 0,
        resolvedCount: 0,
      ),
      analyzedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      analyzedProjectIds: projectIds,
      languageId: languageId,
    );
  }
}

/// Summary statistics for conflict analysis
@JsonSerializable()
class ConflictSummary {
  /// Total number of conflicts
  @JsonKey(name: 'total_count')
  final int totalCount;

  /// Number of key collisions with different source text
  @JsonKey(name: 'key_collision_count')
  final int keyCollisionCount;

  /// Number of translation conflicts (same source, different translation)
  @JsonKey(name: 'translation_conflict_count')
  final int translationConflictCount;

  /// Number of duplicates (can auto-resolve)
  @JsonKey(name: 'duplicate_count')
  final int duplicateCount;

  /// Number of resolved conflicts
  @JsonKey(name: 'resolved_count')
  final int resolvedCount;

  const ConflictSummary({
    required this.totalCount,
    required this.keyCollisionCount,
    required this.translationConflictCount,
    required this.duplicateCount,
    this.resolvedCount = 0,
  });

  /// Number of conflicts requiring manual resolution
  int get manualResolutionRequired =>
      keyCollisionCount + translationConflictCount;

  /// Number of unresolved conflicts
  int get unresolvedCount => totalCount - resolvedCount;

  /// Whether all conflicts are resolved
  bool get allResolved => resolvedCount >= totalCount;

  /// Whether there are conflicts requiring user attention
  bool get needsUserAttention => manualResolutionRequired > resolvedCount;

  ConflictSummary copyWith({
    int? totalCount,
    int? keyCollisionCount,
    int? translationConflictCount,
    int? duplicateCount,
    int? resolvedCount,
  }) {
    return ConflictSummary(
      totalCount: totalCount ?? this.totalCount,
      keyCollisionCount: keyCollisionCount ?? this.keyCollisionCount,
      translationConflictCount:
          translationConflictCount ?? this.translationConflictCount,
      duplicateCount: duplicateCount ?? this.duplicateCount,
      resolvedCount: resolvedCount ?? this.resolvedCount,
    );
  }

  factory ConflictSummary.fromJson(Map<String, dynamic> json) =>
      _$ConflictSummaryFromJson(json);

  Map<String, dynamic> toJson() => _$ConflictSummaryToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConflictSummary &&
        other.totalCount == totalCount &&
        other.keyCollisionCount == keyCollisionCount &&
        other.translationConflictCount == translationConflictCount &&
        other.duplicateCount == duplicateCount &&
        other.resolvedCount == resolvedCount;
  }

  @override
  int get hashCode => Object.hash(
        totalCount,
        keyCollisionCount,
        translationConflictCount,
        duplicateCount,
        resolvedCount,
      );
}
