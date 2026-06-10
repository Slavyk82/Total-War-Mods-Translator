import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/translation/handlers/batch_progress_manager.dart'
    show CancelledException;
import 'package:twmt/services/translation/handlers/llm_token_estimator.dart';
import 'package:twmt/services/translation/handlers/translation_error_recovery.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';

import '../../../../helpers/mock_logging_service.dart';

// Tests for TranslationErrorRecovery.handleLlmError. Focus: the cancellation
// chain. When the user presses Stop, the provider maps the aborted Dio call
// to LlmCancelledException; recovery must rethrow it as CancelledException so
// translation_orchestrator_impl's `on CancelledException` clause persists the
// batch as cancelled - NOT as failed via the generic error path.

LlmRequest _buildRequest() {
  return LlmRequest(
    requestId: 'req-recovery-1',
    targetLanguage: 'fr',
    texts: const {'k1': 'Hello'},
    systemPrompt: 'Translate.',
    modelName: 'gpt-4o-mini',
    timestamp: DateTime(2026, 4, 14, 12, 0, 0),
  );
}

TranslationContext _buildContext() {
  return TranslationContext(
    id: 'ctx-1',
    projectId: 'project-1',
    projectLanguageId: 'pl-1',
    providerId: 'provider_openai',
    modelId: 'gpt-4o-mini',
    targetLanguage: 'fr',
    createdAt: DateTime(2026, 4, 14),
    updatedAt: DateTime(2026, 4, 14),
  );
}

TranslationProgress _buildProgress() {
  return TranslationProgress(
    batchId: 'batch-1',
    status: TranslationProgressStatus.inProgress,
    totalUnits: 1,
    processedUnits: 0,
    successfulUnits: 0,
    failedUnits: 0,
    skippedUnits: 0,
    currentPhase: TranslationPhase.initializing,
    tokensUsed: 0,
    tmReuseRate: 0.0,
    timestamp: DateTime(2026, 4, 14, 12, 0, 0),
  );
}

void main() {
  group('TranslationErrorRecovery.handleLlmError', () {
    Future<(TranslationProgress, Map<String, String>)> callHandleLlmError(
      TranslationErrorRecovery recovery,
      LlmServiceException error,
    ) {
      return recovery.handleLlmError(
        error: error,
        batchId: 'batch-1',
        rootBatchId: 'batch-1',
        unitsToTranslate: const [],
        llmRequest: _buildRequest(),
        context: _buildContext(),
        progress: _buildProgress(),
        currentProgress: _buildProgress(),
        getCancellationToken: (_) => null,
        onProgressUpdate: (_, _) {},
        checkPauseOrCancel: (_) async {},
        depth: 0,
        translateWithAutoSplit: ({
          required String batchId,
          required String rootBatchId,
          required List<dynamic> unitsToTranslate,
          required LlmRequest llmRequest,
          required TranslationContext context,
          required TranslationProgress progress,
          required TranslationProgress currentProgress,
          required Function(String batchId) getCancellationToken,
          required ProgressUpdateCallback onProgressUpdate,
          required Future<void> Function(String batchId) checkPauseOrCancel,
          SubBatchTranslatedCallback? onSubBatchTranslated,
          int depth = 0,
        }) async {
          throw StateError('translateWithAutoSplit must not be called');
        },
      );
    }

    test('rethrows LlmCancelledException as CancelledException so the '
        'orchestrator marks the batch cancelled instead of failed', () async {
      final recovery = TranslationErrorRecovery(
        tokenEstimator: LlmTokenEstimator(),
        logger: MockLoggingService(),
      );

      await expectLater(
        callHandleLlmError(
          recovery,
          const LlmCancelledException(
            'Request cancelled: stopped by user',
            providerCode: 'openai',
          ),
        ),
        throwsA(isA<CancelledException>()
            .having((e) => e.batchId, 'batchId', 'batch-1')),
      );
    });

    test('still maps non-cancellation fatal errors to the base '
        'TranslationOrchestrationException (NOT CancelledException)',
        () async {
      final recovery = TranslationErrorRecovery(
        tokenEstimator: LlmTokenEstimator(),
        logger: MockLoggingService(),
      );

      await expectLater(
        callHandleLlmError(
          recovery,
          const LlmNetworkException(
            'Connection reset',
            providerCode: 'openai',
          ),
        ),
        throwsA(allOf(
          isA<TranslationOrchestrationException>(),
          isNot(isA<CancelledException>()),
        )),
      );
    });
  });
}
