import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/file/export_orchestrator_service.dart';
import '../../../services/service_locator.dart';
import '../../../services/shared/logging_service.dart';

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
  @override
  BatchPackExportState build() => const BatchPackExportState();

  /// Start batch export
  Future<void> exportBatch({
    required List<ProjectExportInfo> projects,
    required String languageCode,
  }) async {
    if (state.isExporting) return;

    final logging = ServiceLocator.get<LoggingService>();
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

    final exportService = ServiceLocator.get<ExportOrchestratorService>();
    final results = <ProjectExportResult>[];

    for (var i = 0; i < projects.length; i++) {
      // Check for cancellation before starting each project
      if (state.isCancelled) {
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
            if (!state.isCancelled) {
              state = state.copyWith(
                currentProjectProgress: progress,
                currentStep: step,
              );
            }
          },
        );

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
        updatedStatuses[project.id] = BatchProjectStatus.failed;
        results.add(ProjectExportResult(
          projectId: project.id,
          projectName: project.name,
          success: false,
          errorMessage: e.toString(),
        ));
        logging.error('Project export exception: ${project.name}', e, stack);
      }

      // Update completed count
      state = state.copyWith(
        completedProjects: i + 1,
        projectStatuses: updatedStatuses,
        results: List.from(results),
      );
    }

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

  /// Cancel the batch export
  void cancel() {
    if (state.isExporting && !state.isCancelled) {
      state = state.copyWith(isCancelled: true);
    }
  }

  /// Reset state for a new export
  void reset() {
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
