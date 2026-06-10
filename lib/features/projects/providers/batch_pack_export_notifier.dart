import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/shared/logging_providers.dart';
import '../../../providers/shared/service_providers.dart';

/// Result of a single project export
class ProjectExportResult {
  final String projectId;
  final String projectName;
  final bool success;
  final String? outputPath;
  final String? errorMessage;
  final int entryCount;

  const ProjectExportResult({
    required this.projectId,
    required this.projectName,
    required this.success,
    this.outputPath,
    this.errorMessage,
    this.entryCount = 0,
  });
}

/// Status of a project in the batch export
enum BatchProjectStatus {
  pending,
  inProgress,
  success,
  failed,
  cancelled,
}

/// State for batch pack export
class BatchPackExportState {
  final bool isExporting;
  final bool isCancelled;
  final int totalProjects;
  final int completedProjects;
  final double currentProjectProgress;
  final String? currentProjectId;
  final String? currentProjectName;
  final String? currentStep;
  final Map<String, BatchProjectStatus> projectStatuses;
  final List<ProjectExportResult> results;

  const BatchPackExportState({
    this.isExporting = false,
    this.isCancelled = false,
    this.totalProjects = 0,
    this.completedProjects = 0,
    this.currentProjectProgress = 0.0,
    this.currentProjectId,
    this.currentProjectName,
    this.currentStep,
    this.projectStatuses = const {},
    this.results = const [],
  });

  BatchPackExportState copyWith({
    bool? isExporting,
    bool? isCancelled,
    int? totalProjects,
    int? completedProjects,
    double? currentProjectProgress,
    String? currentProjectId,
    String? currentProjectName,
    String? currentStep,
    Map<String, BatchProjectStatus>? projectStatuses,
    List<ProjectExportResult>? results,
    bool clearCurrentProject = false,
  }) {
    return BatchPackExportState(
      isExporting: isExporting ?? this.isExporting,
      isCancelled: isCancelled ?? this.isCancelled,
      totalProjects: totalProjects ?? this.totalProjects,
      completedProjects: completedProjects ?? this.completedProjects,
      currentProjectProgress: currentProjectProgress ?? this.currentProjectProgress,
      currentProjectId: clearCurrentProject ? null : (currentProjectId ?? this.currentProjectId),
      currentProjectName: clearCurrentProject ? null : (currentProjectName ?? this.currentProjectName),
      currentStep: clearCurrentProject ? null : (currentStep ?? this.currentStep),
      projectStatuses: projectStatuses ?? this.projectStatuses,
      results: results ?? this.results,
    );
  }

  /// Overall progress (0.0 to 1.0)
  double get overallProgress {
    if (totalProjects == 0) return 0.0;
    return (completedProjects + currentProjectProgress) / totalProjects;
  }

  /// Number of successful exports
  int get successCount => results.where((r) => r.success).length;

  /// Number of failed exports
  int get failedCount => results.where((r) => !r.success).length;

  /// Check if export is complete
  bool get isComplete => !isExporting && results.isNotEmpty;
}

/// Project info for export
class ProjectExportInfo {
  final String id;
  final String name;

  const ProjectExportInfo({required this.id, required this.name});
}

/// Notifier for batch pack export
class BatchPackExportNotifier extends Notifier<BatchPackExportState> {
  /// Token identifying the current export run. The loop captures the value
  /// at start and stops touching [state] as soon as it no longer matches,
  /// so a superseded loop can never resurrect stale state.
  int _generation = 0;

  /// Set by [cancel]. Instance-level (not part of [state]) so it cannot be
  /// defeated by a state reset while the loop is still running.
  bool _cancelRequested = false;

  /// Completes when the currently running export loop has fully exited.
  /// Non-null means a loop is alive (running or draining after cancel);
  /// this is the re-entry guard, immune to state resets.
  Future<void>? _activeRun;

  @override
  BatchPackExportState build() => const BatchPackExportState();

  /// Start batch export
  Future<void> exportBatch({
    required List<ProjectExportInfo> projects,
    required String languageCode,
  }) async {
    // Re-entry guard: an export is running and has not been cancelled.
    // Instance-level so it stays sound even if state were reset.
    if (_activeRun != null && !_cancelRequested) return;

    // Supersede any cancelled loop that is still draining its current
    // await, then wait for it to fully exit so two loops can never
    // interleave state writes or export the same project concurrently.
    final previousRun = _activeRun;
    final runId = ++_generation;
    _cancelRequested = false;
    if (previousRun != null) {
      await previousRun;
    }
    if (runId != _generation) return; // Superseded by a newer run.
    if (_cancelRequested) {
      // Cancelled while waiting for the previous loop to drain.
      if (state.isExporting) {
        state = state.copyWith(isExporting: false, clearCurrentProject: true);
      }
      return;
    }

    final completer = Completer<void>();
    _activeRun = completer.future;
    try {
      await _runExport(
        runId: runId,
        projects: projects,
        languageCode: languageCode,
      );
    } finally {
      if (identical(_activeRun, completer.future)) {
        _activeRun = null;
      }
      completer.complete();
    }
  }

  Future<void> _runExport({
    required int runId,
    required List<ProjectExportInfo> projects,
    required String languageCode,
  }) async {
    final logging = ref.read(loggingServiceProvider);
    logging.info('Starting batch pack export', {
      'projectCount': projects.length,
      'languageCode': languageCode,
    });

    // Initialize statuses
    final statuses = <String, BatchProjectStatus>{};
    for (final project in projects) {
      statuses[project.id] = BatchProjectStatus.pending;
    }

    state = BatchPackExportState(
      isExporting: true,
      isCancelled: false,
      totalProjects: projects.length,
      completedProjects: 0,
      projectStatuses: statuses,
      results: const [],
    );

    final exportService = ref.read(exportOrchestratorServiceProvider);
    final results = <ProjectExportResult>[];

    for (var i = 0; i < projects.length; i++) {
      // Superseded by a newer run or screen lifecycle reset: exit without
      // touching state (the newer run owns it now).
      if (runId != _generation) return;

      // Check for cancellation before starting each project. Terminal
      // cleanup is done here, by the loop itself, so callers never have to
      // reset state while the loop is still running.
      if (_cancelRequested) {
        logging.info('Batch export cancelled', {
          'completedProjects': i,
          'totalProjects': projects.length,
        });

        // Mark remaining projects as cancelled
        final updatedStatuses = Map<String, BatchProjectStatus>.from(state.projectStatuses);
        for (var j = i; j < projects.length; j++) {
          updatedStatuses[projects[j].id] = BatchProjectStatus.cancelled;
        }

        state = state.copyWith(
          isExporting: false,
          isCancelled: true,
          projectStatuses: updatedStatuses,
          clearCurrentProject: true,
        );
        return;
      }

      final project = projects[i];

      // Update state for current project
      final updatedStatuses = Map<String, BatchProjectStatus>.from(state.projectStatuses);
      updatedStatuses[project.id] = BatchProjectStatus.inProgress;

      state = state.copyWith(
        currentProjectId: project.id,
        currentProjectName: project.name,
        currentProjectProgress: 0.0,
        currentStep: 'preparingData',
        projectStatuses: updatedStatuses,
      );

      try {
        final result = await exportService.exportToPack(
          projectId: project.id,
          languageCodes: [languageCode],
          outputPath: 'exports', // Not used, pack goes to game data folder
          validatedOnly: false,
          generatePackImage: true,
          onProgress: (step, progress, {currentLanguage, currentIndex, total}) {
            if (runId == _generation && !_cancelRequested) {
              state = state.copyWith(
                currentProjectProgress: progress,
                currentStep: step,
              );
            }
          },
        );

        // Superseded while awaiting the export: stop, do not write state.
        if (runId != _generation) return;

        result.when(
          ok: (exportResult) {
            updatedStatuses[project.id] = BatchProjectStatus.success;
            results.add(ProjectExportResult(
              projectId: project.id,
              projectName: project.name,
              success: true,
              outputPath: exportResult.outputPath,
              entryCount: exportResult.entryCount,
            ));
            logging.info('Project exported successfully', {
              'projectId': project.id,
              'projectName': project.name,
              'outputPath': exportResult.outputPath,
            });
          },
          err: (error) {
            updatedStatuses[project.id] = BatchProjectStatus.failed;
            results.add(ProjectExportResult(
              projectId: project.id,
              projectName: project.name,
              success: false,
              errorMessage: error.message,
            ));
            logging.error('Project export failed: ${project.name}', error);
          },
        );
      } catch (e, stack) {
        logging.error('Project export exception: ${project.name}', e, stack);
        if (runId != _generation) return;
        updatedStatuses[project.id] = BatchProjectStatus.failed;
        results.add(ProjectExportResult(
          projectId: project.id,
          projectName: project.name,
          success: false,
          errorMessage: e.toString(),
        ));
      }

      // Update completed count
      state = state.copyWith(
        completedProjects: i + 1,
        projectStatuses: updatedStatuses,
        results: List.from(results),
      );
    }

    if (runId != _generation) return;

    // Export complete
    state = state.copyWith(
      isExporting: false,
      clearCurrentProject: true,
    );

    logging.info('Batch export complete', {
      'totalProjects': projects.length,
      'successCount': state.successCount,
      'failedCount': state.failedCount,
    });
  }

  /// Cancel the batch export.
  ///
  /// The running loop stops at its next checkpoint (it cannot abort an
  /// in-flight pack export) and performs its own terminal state cleanup,
  /// marking the remaining projects as cancelled.
  void cancel() {
    // Set the flag unconditionally: a run queued behind a draining loop
    // re-checks it after the drain, during which _activeRun is briefly
    // null. Harmless when idle — exportBatch clears it at run start.
    _cancelRequested = true;
    if (state.isExporting && !state.isCancelled) {
      state = state.copyWith(isCancelled: true);
    }
  }

  /// Reset state for a new export.
  ///
  /// While a loop is still alive this defers to [cancel] instead of
  /// clearing state under it: a mid-run reset would defeat the cancellation
  /// flag and let the loop resurrect inconsistent state. [exportBatch]
  /// reinitializes state at the start of every run, so the next run always
  /// begins clean either way.
  void reset() {
    if (_activeRun != null) {
      cancel();
      return;
    }
    state = const BatchPackExportState();
  }
}

/// Provider for batch pack export
final batchPackExportProvider =
    NotifierProvider<BatchPackExportNotifier, BatchPackExportState>(
  BatchPackExportNotifier.new,
);

/// Staging data for the batch export screen.
class BatchExportStagingData {
  final List<ProjectExportInfo> projects;
  final String languageCode;
  final String languageName;

  const BatchExportStagingData({
    required this.projects,
    required this.languageCode,
    required this.languageName,
  });
}

/// Set before navigating to the batch export screen, read in initState.
class _BatchExportStagingNotifier extends Notifier<BatchExportStagingData?> {
  @override
  BatchExportStagingData? build() => null;

  void set(BatchExportStagingData? data) => state = data;
}

final batchExportStagingProvider =
    NotifierProvider<_BatchExportStagingNotifier, BatchExportStagingData?>(
  _BatchExportStagingNotifier.new,
);
