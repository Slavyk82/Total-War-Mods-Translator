import 'package:twmt/models/domain/mod_update_analysis.dart';

/// Cache entry for mod update analysis results.
///
/// Stores the analysis result (new/removed/modified units) for a specific
/// project and pack file combination. Cache is invalidated when the pack
/// file's modification timestamp changes.
class ModUpdateAnalysisCache {
  final String id;
  final String projectId;
  final String packFilePath;
  final int fileLastModified;
  final int newUnitsCount;
  final int removedUnitsCount;
  final int modifiedUnitsCount;
  final int totalPackUnits;
  final int totalProjectUnits;
  final int analyzedAt;

  const ModUpdateAnalysisCache({
    required this.id,
    required this.projectId,
    required this.packFilePath,
    required this.fileLastModified,
    required this.newUnitsCount,
    required this.removedUnitsCount,
    required this.modifiedUnitsCount,
    required this.totalPackUnits,
    required this.totalProjectUnits,
    required this.analyzedAt,
  });

  factory ModUpdateAnalysisCache.fromJson(Map<String, dynamic> json) {
    return ModUpdateAnalysisCache(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      packFilePath: json['pack_file_path'] as String,
      fileLastModified: json['file_last_modified'] as int,
      newUnitsCount: json['new_units_count'] as int,
      removedUnitsCount: json['removed_units_count'] as int,
      modifiedUnitsCount: json['modified_units_count'] as int,
      totalPackUnits: json['total_pack_units'] as int,
      totalProjectUnits: json['total_project_units'] as int,
      analyzedAt: json['analyzed_at'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'project_id': projectId,
      'pack_file_path': packFilePath,
      'file_last_modified': fileLastModified,
      'new_units_count': newUnitsCount,
      'removed_units_count': removedUnitsCount,
      'modified_units_count': modifiedUnitsCount,
      'total_pack_units': totalPackUnits,
      'total_project_units': totalProjectUnits,
      'analyzed_at': analyzedAt,
    };
  }

  /// Check if the cache entry is still valid for the given file modification time.
  bool isValidFor(int currentFileLastModified) {
    return fileLastModified == currentFileLastModified;
  }

  /// Convert cached data to ModUpdateAnalysis domain object.
  ModUpdateAnalysis toAnalysis() {
    return ModUpdateAnalysis(
      newUnitsCount: newUnitsCount,
      removedUnitsCount: removedUnitsCount,
      modifiedUnitsCount: modifiedUnitsCount,
      totalPackUnits: totalPackUnits,
      totalProjectUnits: totalProjectUnits,
    );
  }

  /// Create a cache entry from analysis result.
  static ModUpdateAnalysisCache fromAnalysis({
    required String id,
    required String projectId,
    required String packFilePath,
    required int fileLastModified,
    required ModUpdateAnalysis analysis,
    required int analyzedAt,
  }) {
    return ModUpdateAnalysisCache(
      id: id,
      projectId: projectId,
      packFilePath: packFilePath,
      fileLastModified: fileLastModified,
      newUnitsCount: analysis.newUnitsCount,
      removedUnitsCount: analysis.removedUnitsCount,
      modifiedUnitsCount: analysis.modifiedUnitsCount,
      totalPackUnits: analysis.totalPackUnits,
      totalProjectUnits: analysis.totalProjectUnits,
      analyzedAt: analyzedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModUpdateAnalysisCache &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ModUpdateAnalysisCache(projectId: $projectId, new: $newUnitsCount, removed: $removedUnitsCount, modified: $modifiedUnitsCount)';
}
