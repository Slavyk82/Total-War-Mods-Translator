import 'dart:convert';

import '../../../models/common/result.dart';
import '../../../models/common/service_exception.dart';
import '../../../repositories/translation_unit_repository.dart';
import '../models/compilation_conflict.dart';
import '../models/conflict_analysis_result.dart';

/// Callback for reporting conflict analysis progress.
typedef ConflictAnalysisProgressCallback = void Function(
  int current,
  int total,
  String phase,
);

/// Service responsible for detecting conflicts between projects in a compilation.
class CompilationConflictService {
  final TranslationUnitRepository _unitRepository;

  const CompilationConflictService(this._unitRepository);

  /// Analyze conflicts for a set of projects being compiled together.
  Future<Result<ConflictAnalysisResult, ServiceException>> analyzeConflicts({
    required List<String> projectIds,
    required String languageId,
    ConflictAnalysisProgressCallback? onProgress,
  }) async {
    try {
      if (projectIds.length < 2) {
        return Ok(ConflictAnalysisResult.empty(
          projectIds: projectIds,
          languageId: languageId,
        ));
      }

      onProgress?.call(0, 4, 'Finding duplicate keys...');

      final duplicateKeysResult =
          await _unitRepository.findDuplicateKeysAcrossProjects(
        projectIds: projectIds,
      );

      if (duplicateKeysResult.isErr) {
        return Err(ServiceException(
          'Failed to find duplicate keys: ${duplicateKeysResult.error}',
        ));
      }

      final duplicateKeys = duplicateKeysResult.value;

      if (duplicateKeys.isEmpty) {
        onProgress?.call(4, 4, 'No conflicts found');
        return Ok(ConflictAnalysisResult.empty(
          projectIds: projectIds,
          languageId: languageId,
        ));
      }

      onProgress?.call(
          1, 4, 'Loading translation data for ${duplicateKeys.length} keys...');

      final unitsResult = await _unitRepository.getUnitsForKeysAcrossProjects(
        projectIds: projectIds,
        keys: duplicateKeys,
        languageId: languageId,
      );

      if (unitsResult.isErr) {
        return Err(ServiceException(
          'Failed to load translation units: ${unitsResult.error}',
        ));
      }

      onProgress?.call(2, 4, 'Analyzing conflicts...');

      final unitsByKey = _groupUnitsByKey(unitsResult.value);
      final conflicts = _detectConflicts(unitsByKey);

      onProgress?.call(3, 4, 'Building summary...');

      final summary = _buildSummary(conflicts);

      onProgress?.call(4, 4, 'Analysis complete');

      return Ok(ConflictAnalysisResult(
        conflicts: conflicts,
        summary: summary,
        analyzedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        analyzedProjectIds: projectIds,
        languageId: languageId,
      ));
    } catch (e, stackTrace) {
      return Err(ServiceException(
        'Conflict analysis failed: $e',
        stackTrace: stackTrace,
      ));
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupUnitsByKey(
    List<Map<String, dynamic>> units,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final unit in units) {
      final key = unit['key'] as String;
      grouped.putIfAbsent(key, () => []).add(unit);
    }
    return grouped;
  }

  List<CompilationConflict> _detectConflicts(
    Map<String, List<Map<String, dynamic>>> unitsByKey,
  ) {
    final conflicts = <CompilationConflict>[];
    var conflictId = 0;

    for (final entry in unitsByKey.entries) {
      final key = entry.key;
      final units = entry.value;

      for (var i = 0; i < units.length; i++) {
        for (var j = i + 1; j < units.length; j++) {
          final first = units[i];
          final second = units[j];

          if (first['project_id'] == second['project_id']) continue;

          // Only create conflict if source text is different
          // Same key with identical source text is NOT a conflict
          final firstSource = first['source_text'] as String;
          final secondSource = second['source_text'] as String;
          if (firstSource == secondSource) continue;

          final conflict = _createConflict(
            id: 'conflict_${conflictId++}',
            key: key,
            first: first,
            second: second,
          );

          conflicts.add(conflict);
        }
      }
    }

    return conflicts;
  }

  CompilationConflict _createConflict({
    required String id,
    required String key,
    required Map<String, dynamic> first,
    required Map<String, dynamic> second,
  }) {
    // At this point, we know source texts are different (key collision)
    return CompilationConflict(
      id: id,
      key: key,
      conflictType: CompilationConflictType.keyCollisionDifferentSource,
      firstEntry: _createConflictEntry(first),
      secondEntry: _createConflictEntry(second),
    );
  }

  ConflictEntry _createConflictEntry(Map<String, dynamic> data) {
    String projectName = data['project_name'] as String;
    final metadata = data['project_metadata'] as String?;

    if (metadata != null && metadata.isNotEmpty) {
      try {
        final parsed = jsonDecode(metadata) as Map<String, dynamic>;
        final modTitle = parsed['mod_title'] as String?;
        if (modTitle != null && modTitle.isNotEmpty) {
          projectName = modTitle;
        }
      } catch (_) {}
    }

    return ConflictEntry(
      projectId: data['project_id'] as String,
      projectName: projectName,
      unitId: data['unit_id'] as String,
      sourceText: data['source_text'] as String,
      translatedText: data['translated_text'] as String?,
      status: data['status'] as String?,
      isManuallyEdited: (data['is_manually_edited'] as int?) == 1,
      updatedAt: data['version_updated_at'] as int?,
      sourceLocFile: data['source_loc_file'] as String?,
    );
  }

  ConflictSummary _buildSummary(List<CompilationConflict> conflicts) {
    int keyCollisionCount = 0;
    int resolvedCount = 0;

    for (final conflict in conflicts) {
      // All conflicts are now key collisions (different source text)
      keyCollisionCount++;
      if (conflict.isResolved) {
        resolvedCount++;
      }
    }

    return ConflictSummary(
      totalCount: conflicts.length,
      keyCollisionCount: keyCollisionCount,
      translationConflictCount: 0,
      duplicateCount: 0,
      resolvedCount: resolvedCount,
    );
  }

  ConflictAnalysisResult applyResolutions(
    ConflictAnalysisResult analysis,
    CompilationConflictResolutions resolutions,
  ) {
    final fullyResolved = analysis.conflicts.map((conflict) {
      if (conflict.isResolved) return conflict;

      final resolution = resolutions.getResolution(conflict.id);
      final projectId = resolutions.getResolutionProjectId(conflict.id);

      if (resolution != null) {
        return conflict.copyWith(
          resolution: resolution,
          resolvedWithProjectId: projectId,
        );
      }

      return conflict;
    }).toList();

    return ConflictAnalysisResult(
      conflicts: fullyResolved,
      summary: _buildSummary(fullyResolved),
      analyzedAt: analysis.analyzedAt,
      analyzedProjectIds: analysis.analyzedProjectIds,
      languageId: analysis.languageId,
    );
  }

  ConflictEntry? getWinningEntry(CompilationConflict conflict) {
    if (!conflict.isResolved) return null;

    switch (conflict.resolution!) {
      case CompilationConflictResolution.useFirst:
        return conflict.firstEntry;
      case CompilationConflictResolution.useSecond:
        return conflict.secondEntry;
      case CompilationConflictResolution.skip:
        return null;
    }
  }
}
