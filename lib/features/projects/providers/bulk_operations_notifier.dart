import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/services/bulk_operations_handlers.dart';
import 'package:twmt/services/translation/headless_batch_translation_runner.dart';

/// Seam for testing: the default production instance delegates to the four
/// top-level handler functions; tests can override [bulkHandlersProvider]
/// with a double that captures calls or returns stubbed outcomes.
class BulkHandlers {
  const BulkHandlers();

  Future<ProjectOutcome> translate({
    required Ref ref,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    HandlerCallback? onProgress,
  }) =>
      runBulkTranslate(
        ref: ref,
        project: project,
        targetLanguageCode: targetLanguageCode,
        onProgress: onProgress,
      );

  Future<ProjectOutcome> rescan({
    required Ref ref,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    HandlerCallback? onProgress,
  }) =>
      runBulkRescan(
        ref: ref,
        project: project,
        targetLanguageCode: targetLanguageCode,
        onProgress: onProgress,
      );

  Future<ProjectOutcome> forceValidate({
    required Ref ref,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    HandlerCallback? onProgress,
  }) =>
      runBulkForceValidate(
        ref: ref,
        project: project,
        targetLanguageCode: targetLanguageCode,
        onProgress: onProgress,
      );

  Future<ProjectOutcome> generatePack({
    required Ref ref,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    HandlerCallback? onProgress,
  }) =>
      runBulkGeneratePack(
        ref: ref,
        project: project,
        targetLanguageCode: targetLanguageCode,
        onProgress: onProgress,
      );
}

final bulkHandlersProvider =
    Provider<BulkHandlers>((_) => const BulkHandlers());

class BulkOperationsNotifier extends Notifier<BulkOperationState> {
  @override
  BulkOperationState build() => BulkOperationState.idle();

  Future<void> run({
    required BulkOperationType type,
    required String targetLanguageCode,
    required List<ProjectWithDetails> projects,
  }) async {
    if (state.operationType != null && !state.isComplete) {
      throw StateError('A bulk operation is already in progress');
    }

    final ids = projects.map((p) => p.project.id).toList();
    final pendingResults = <String, ProjectOutcome>{
      for (final id in ids)
        id: const ProjectOutcome(status: ProjectResultStatus.pending),
    };
    state = BulkOperationState(
      operationType: type,
      targetLanguageCode: targetLanguageCode,
      projectIds: ids,
      results: pendingResults,
    );

    final handlers = ref.read(bulkHandlersProvider);
    final projectById = {for (final p in projects) p.project.id: p};

    for (var i = 0; i < ids.length; i++) {
      if (state.isCancelled) {
        final updated = {...state.results};
        for (final remaining in ids.sublist(i)) {
          updated[remaining] = const ProjectOutcome(
            status: ProjectResultStatus.cancelled,
          );
        }
        state = state.copyWith(results: updated);
        break;
      }

      final project = projectById[ids[i]]!;
      state = state.copyWith(
        currentIndex: i,
        currentProjectId: project.project.id,
        currentProjectName: project.project.name,
        currentStep: 'Starting...',
        currentProjectProgress: -1,
        results: {
          ...state.results,
          project.project.id: const ProjectOutcome(
            status: ProjectResultStatus.inProgress,
          ),
        },
      );

      ProjectOutcome outcome;
      try {
        outcome = await _runOne(
          handlers: handlers,
          type: type,
          project: project,
          targetLanguageCode: targetLanguageCode,
          onProgress: (step, progress) {
            state = state.copyWith(
              currentStep: step,
              currentProjectProgress: progress,
            );
          },
        );
      } catch (e) {
        outcome = ProjectOutcome(
          status: ProjectResultStatus.failed,
          message: e.toString(),
          error: e,
        );
      }

      state = state.copyWith(
        results: {...state.results, project.project.id: outcome},
      );

      ref.invalidate(projectsWithDetailsProvider);
    }

    state = state.copyWith(
      isComplete: true,
      clearCurrentStep: true,
      currentProjectProgress: -1,
    );
  }

  Future<ProjectOutcome> _runOne({
    required BulkHandlers handlers,
    required BulkOperationType type,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    required HandlerCallback onProgress,
  }) {
    switch (type) {
      case BulkOperationType.translate:
        return handlers.translate(
          ref: ref,
          project: project,
          targetLanguageCode: targetLanguageCode,
          onProgress: onProgress,
        );
      case BulkOperationType.rescan:
        return handlers.rescan(
          ref: ref,
          project: project,
          targetLanguageCode: targetLanguageCode,
          onProgress: onProgress,
        );
      case BulkOperationType.forceValidate:
        return handlers.forceValidate(
          ref: ref,
          project: project,
          targetLanguageCode: targetLanguageCode,
          onProgress: onProgress,
        );
      case BulkOperationType.generatePack:
        return handlers.generatePack(
          ref: ref,
          project: project,
          targetLanguageCode: targetLanguageCode,
          onProgress: onProgress,
        );
    }
  }

  Future<void> cancel() async {
    if (state.operationType == null || state.isComplete) return;
    state = state.copyWith(isCancelled: true);
    if (state.operationType == BulkOperationType.translate) {
      final runner = ref.read(headlessBatchTranslationRunnerProvider);
      await runner.stop();
    }
  }

  void reset() {
    state = BulkOperationState.idle();
  }
}

final bulkOperationsProvider =
    NotifierProvider<BulkOperationsNotifier, BulkOperationState>(
  BulkOperationsNotifier.new,
);
