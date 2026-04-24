import 'package:flutter/foundation.dart';

enum BulkOperationType { translate, rescan, forceValidate, generatePack }

enum ProjectResultStatus {
  pending,
  inProgress,
  succeeded,
  skipped,
  failed,
  cancelled,
}

@immutable
class ProjectOutcome {
  final ProjectResultStatus status;
  final String? message;
  final Object? error;

  const ProjectOutcome({required this.status, this.message, this.error});
}

@immutable
class BulkOperationState {
  final BulkOperationType? operationType;
  final String? targetLanguageCode;
  final List<String> projectIds;
  final int currentIndex;
  final String? currentProjectId;
  final String? currentProjectName;
  final String? currentStep;
  final double currentProjectProgress;
  final Map<String, ProjectOutcome> results;
  final bool isCancelled;
  final bool isComplete;

  const BulkOperationState({
    this.operationType,
    this.targetLanguageCode,
    this.projectIds = const [],
    this.currentIndex = 0,
    this.currentProjectId,
    this.currentProjectName,
    this.currentStep,
    this.currentProjectProgress = -1,
    this.results = const {},
    this.isCancelled = false,
    this.isComplete = false,
  });

  factory BulkOperationState.idle() => const BulkOperationState();

  int countByStatus(ProjectResultStatus s) =>
      results.values.where((o) => o.status == s).length;

  List<String> get failedProjectIds => projectIds
      .where((id) => results[id]?.status == ProjectResultStatus.failed)
      .toList();

  BulkOperationState copyWith({
    BulkOperationType? operationType,
    String? targetLanguageCode,
    List<String>? projectIds,
    int? currentIndex,
    String? currentProjectId,
    String? currentProjectName,
    String? currentStep,
    double? currentProjectProgress,
    Map<String, ProjectOutcome>? results,
    bool? isCancelled,
    bool? isComplete,
    bool clearCurrentStep = false,
  }) {
    return BulkOperationState(
      operationType: operationType ?? this.operationType,
      targetLanguageCode: targetLanguageCode ?? this.targetLanguageCode,
      projectIds: projectIds ?? this.projectIds,
      currentIndex: currentIndex ?? this.currentIndex,
      currentProjectId: currentProjectId ?? this.currentProjectId,
      currentProjectName: currentProjectName ?? this.currentProjectName,
      currentStep: clearCurrentStep ? null : (currentStep ?? this.currentStep),
      currentProjectProgress:
          currentProjectProgress ?? this.currentProjectProgress,
      results: results ?? this.results,
      isCancelled: isCancelled ?? this.isCancelled,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}
