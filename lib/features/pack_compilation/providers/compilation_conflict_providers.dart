import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../providers/shared/repository_providers.dart';
import '../models/compilation_conflict.dart';
import '../models/conflict_analysis_result.dart';
import '../services/compilation_conflict_service.dart';

part 'compilation_conflict_providers.g.dart';

/// Provider for the conflict detection service.
@riverpod
CompilationConflictService compilationConflictService(Ref ref) {
  return CompilationConflictService(
    ref.watch(translationUnitRepositoryProvider),
  );
}

/// State for conflict analysis results.
@riverpod
class CompilationConflictAnalysis extends _$CompilationConflictAnalysis {
  @override
  AsyncValue<ConflictAnalysisResult?> build() => const AsyncData(null);

  /// Run conflict analysis for the specified projects.
  Future<void> analyze({
    required List<String> projectIds,
    required String languageId,
  }) async {
    state = const AsyncLoading();

    final service = ref.read(compilationConflictServiceProvider);
    final result = await service.analyzeConflicts(
      projectIds: projectIds,
      languageId: languageId,
    );

    result.when(
      ok: (analysis) => state = AsyncData(analysis),
      err: (error) => state = AsyncError(error, StackTrace.current),
    );
  }

  /// Clear analysis results.
  void clear() {
    state = const AsyncData(null);
  }

  /// Update with resolved conflicts.
  void updateWithResolutions(CompilationConflictResolutions resolutions) {
    final currentData = state.asData;
    if (currentData == null) return;

    final currentAnalysis = currentData.value;
    if (currentAnalysis == null) return;

    final service = ref.read(compilationConflictServiceProvider);
    final resolved = service.applyResolutions(currentAnalysis, resolutions);
    state = AsyncData(resolved);
  }
}

/// State for conflict resolutions.
@riverpod
class CompilationConflictResolutionsState
    extends _$CompilationConflictResolutionsState {
  @override
  CompilationConflictResolutions build() =>
      const CompilationConflictResolutions();

  /// Set resolution for a specific conflict.
  void setResolution(
    String conflictId,
    CompilationConflictResolution resolution,
    String? projectId,
  ) {
    state = state.setResolution(conflictId, resolution, projectId);
  }

  /// Set default resolution for all unresolved conflicts.
  void setDefaultResolution(
    CompilationConflictResolution resolution,
    String? projectId,
  ) {
    state = state.setDefaultResolution(resolution, projectId);
  }

  /// Clear all resolutions.
  void clear() {
    state = const CompilationConflictResolutions();
  }

  /// Check if conflict is resolved.
  bool isResolved(String conflictId) {
    return state.isResolved(conflictId);
  }

  /// Get resolution for conflict.
  CompilationConflictResolution? getResolution(String conflictId) {
    return state.getResolution(conflictId);
  }
}

/// Provider for checking if compilation can proceed.
@riverpod
bool canProceedWithCompilation(Ref ref) {
  final analysisAsync = ref.watch(compilationConflictAnalysisProvider);
  final resolutions = ref.watch(compilationConflictResolutionsStateProvider);

  return analysisAsync.when(
    data: (analysis) {
      if (analysis == null) {
        return true;
      }

      if (!analysis.hasConflicts) {
        return true;
      }

      for (final conflict in analysis.conflicts) {
        if (conflict.canAutoResolve) continue;

        if (!resolutions.isResolved(conflict.id)) {
          return false;
        }
      }

      return true;
    },
    loading: () => false,
    error: (e, s) => false,
  );
}

/// Provider for the count of unresolved conflicts.
@riverpod
int unresolvedConflictCount(Ref ref) {
  final analysisAsync = ref.watch(compilationConflictAnalysisProvider);
  final resolutions = ref.watch(compilationConflictResolutionsStateProvider);

  return analysisAsync.when(
    data: (analysis) {
      if (analysis == null) return 0;

      int count = 0;
      for (final conflict in analysis.conflicts) {
        if (conflict.canAutoResolve) continue;
        if (!resolutions.isResolved(conflict.id)) {
          count++;
        }
      }
      return count;
    },
    loading: () => 0,
    error: (e, s) => 0,
  );
}

/// Provider for conflicts that need manual resolution.
@riverpod
List<CompilationConflict> conflictsNeedingResolution(Ref ref) {
  final analysisAsync = ref.watch(compilationConflictAnalysisProvider);
  final resolutions = ref.watch(compilationConflictResolutionsStateProvider);

  return analysisAsync.when(
    data: (analysis) {
      if (analysis == null) return [];

      return analysis.conflicts.where((conflict) {
        if (conflict.canAutoResolve) return false;
        return !resolutions.isResolved(conflict.id);
      }).toList();
    },
    loading: () => [],
    error: (e, s) => [],
  );
}

/// Provider that indicates if conflict analysis is in progress.
@riverpod
bool isAnalyzingConflicts(Ref ref) {
  final analysisAsync = ref.watch(compilationConflictAnalysisProvider);
  return analysisAsync.isLoading;
}

/// Provider that indicates if there are any conflicts (resolved or not).
@riverpod
bool hasConflicts(Ref ref) {
  final analysisAsync = ref.watch(compilationConflictAnalysisProvider);
  return analysisAsync.when(
    data: (analysis) => analysis?.hasConflicts ?? false,
    loading: () => false,
    error: (e, s) => false,
  );
}

/// Provider for conflict summary.
@riverpod
ConflictSummary? conflictSummary(Ref ref) {
  final analysisAsync = ref.watch(compilationConflictAnalysisProvider);
  return analysisAsync.asData?.value?.summary;
}

/// Information about a project involved in conflicts.
class ConflictingProjectInfo {
  final String projectId;
  final String projectName;
  final int conflictCount;

  const ConflictingProjectInfo({
    required this.projectId,
    required this.projectName,
    required this.conflictCount,
  });
}

/// Provider for projects that have non-auto-resolvable conflicts.
/// Returns a list of projects with their conflict counts.
@riverpod
List<ConflictingProjectInfo> conflictingProjects(Ref ref) {
  final analysisAsync = ref.watch(compilationConflictAnalysisProvider);

  return analysisAsync.when(
    data: (analysis) {
      if (analysis == null) return [];

      // Count conflicts per project (excluding auto-resolvable duplicates)
      final projectConflicts = <String, int>{};
      final projectNames = <String, String>{};

      for (final conflict in analysis.conflicts) {
        // Skip auto-resolvable conflicts (duplicates)
        if (conflict.canAutoResolve) continue;

        // Count for first project
        projectConflicts[conflict.firstEntry.projectId] =
            (projectConflicts[conflict.firstEntry.projectId] ?? 0) + 1;
        projectNames[conflict.firstEntry.projectId] =
            conflict.firstEntry.projectName;

        // Count for second project
        projectConflicts[conflict.secondEntry.projectId] =
            (projectConflicts[conflict.secondEntry.projectId] ?? 0) + 1;
        projectNames[conflict.secondEntry.projectId] =
            conflict.secondEntry.projectName;
      }

      // Convert to list and sort by conflict count descending
      final result = projectConflicts.entries
          .map((e) => ConflictingProjectInfo(
                projectId: e.key,
                projectName: projectNames[e.key] ?? 'Unknown',
                conflictCount: e.value,
              ))
          .toList();

      result.sort((a, b) => b.conflictCount.compareTo(a.conflictCount));
      return result;
    },
    loading: () => [],
    error: (e, s) => [],
  );
}

/// Provider for checking if there are real conflicts (excluding auto-resolvable).
@riverpod
bool hasRealConflicts(Ref ref) {
  final conflictingProjectsList = ref.watch(conflictingProjectsProvider);
  return conflictingProjectsList.isNotEmpty;
}
