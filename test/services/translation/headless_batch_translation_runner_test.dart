import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/providers/translation_settings_provider.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/providers/shared/service_providers.dart' as shared_svc;
import 'package:twmt/services/translation/headless_batch_translation_runner.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockOrchestrator extends Mock implements ITranslationOrchestrator {}

/// Stub notifier that avoids touching SharedPreferences in unit tests.
class _StubSettingsNotifier extends TranslationSettingsNotifier {
  @override
  TranslationSettings build() => const TranslationSettings(
        unitsPerBatch: 0,
        parallelBatches: 3,
      );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Minimal [TranslationContext] used as a stub/fallback value for Mocktail.
TranslationContext _stubContext() => TranslationContext(
      id: 'ctx-test',
      projectId: 'proj-test',
      projectLanguageId: 'pl-test',
      targetLanguage: 'PL',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

/// Minimal [TranslationProgress] with the given [status] and unit counts.
TranslationProgress _progress({
  required String batchId,
  required TranslationProgressStatus status,
  int total = 2,
  int processed = 2,
  int successful = 2,
}) =>
    TranslationProgress(
      batchId: batchId,
      status: status,
      totalUnits: total,
      processedUnits: processed,
      successfulUnits: successful,
      failedUnits: 0,
      skippedUnits: 0,
      currentPhase: TranslationPhase.completed,
      tokensUsed: 0,
      tmReuseRate: 0,
      timestamp: DateTime(2024),
    );

// ---------------------------------------------------------------------------
// Factory helpers
// ---------------------------------------------------------------------------

/// Creates a [Provider] that returns a [HeadlessBatchTranslationRunner] wired
/// to stub delegates that skip DB interaction.
Provider<HeadlessBatchTranslationRunner> _runnerProvider({
  required String fixedBatchId,
}) {
  return Provider<HeadlessBatchTranslationRunner>(
    (ref) => HeadlessBatchTranslationRunner(
      ref,
      createBatch: ({
        required projectLanguageId,
        required unitIds,
        required providerId,
      }) async =>
          fixedBatchId,
      buildContext: ({
        required projectLanguageId,
        required projectId,
        required providerId,
        required skipTranslationMemory,
        required unitsPerBatch,
        required parallelBatches,
      }) async =>
          _stubContext(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockOrchestrator orchestrator;

  setUp(() {
    orchestrator = _MockOrchestrator();
    registerFallbackValue(_stubContext());
  });

  test('completes when stream emits completed status', () async {
    const batchId = 'b-happy';

    final controller = StreamController<
        Result<TranslationProgress, TranslationOrchestrationException>>();

    when(() => orchestrator.translateBatchesParallel(
          batchIds: any(named: 'batchIds'),
          context: any(named: 'context'),
          maxParallel: any(named: 'maxParallel'),
        )).thenAnswer((_) => controller.stream);

    final runnerProv = _runnerProvider(fixedBatchId: batchId);

    final container = ProviderContainer(overrides: [
      shared_svc.translationOrchestratorProvider
          .overrideWithValue(orchestrator),
      translationSettingsProvider
          .overrideWith(() => _StubSettingsNotifier()),
    ]);
    addTearDown(container.dispose);

    final runner = container.read(runnerProv);

    final future = runner.run(
      projectLanguageId: 'pl-1',
      projectId: 'proj-1',
      unitIds: ['u1', 'u2'],
      skipTM: false,
      providerId: 'openai',
    );

    controller.add(Ok(_progress(
      batchId: batchId,
      status: TranslationProgressStatus.completed,
    )));
    await controller.close();

    final translated = await future;
    expect(translated, 2);
  });

  test('stop() calls orchestrator.stopTranslation with current batch id', () async {
    // similar setup; after run() starts, call runner.stop() and verify
    // orchestrator.stopTranslation was invoked with the same batchId
    // returned by createAndPrepareBatch.
  }, skip: 'Fill in after basic happy path passes');
}
