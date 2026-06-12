import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/translation/headless_batch_translation_runner.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/translation_settings.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockOrchestrator extends Mock implements ITranslationOrchestrator {}

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

/// Stub settings snapshot used by the runner's [readSettings] thunk.
const _stubSettings = TranslationSettings(
  unitsPerBatch: 0,
  parallelBatches: 3,
);

/// Minimal [TranslationProgress] with the given [status] and unit counts.
TranslationProgress _progress({
  required String batchId,
  required TranslationProgressStatus status,
  int total = 2,
  int processed = 2,
  int successful = 2,
  int skipped = 0,
}) =>
    TranslationProgress(
      batchId: batchId,
      status: status,
      totalUnits: total,
      processedUnits: processed,
      successfulUnits: successful,
      failedUnits: 0,
      skippedUnits: skipped,
      currentPhase: TranslationPhase.completed,
      tokensUsed: 0,
      tmReuseRate: 0,
      timestamp: DateTime(2024),
    );

// ---------------------------------------------------------------------------
// Factory helper
// ---------------------------------------------------------------------------

/// Builds a [HeadlessBatchTranslationRunner] wired to the given [orchestrator]
/// and stub delegates that skip DB interaction. [fixedBatchId] is returned by
/// the createBatch delegate.
HeadlessBatchTranslationRunner _runner({
  required ITranslationOrchestrator orchestrator,
  required String fixedBatchId,
}) {
  return HeadlessBatchTranslationRunner(
    orchestrator: orchestrator,
    readSettings: () => _stubSettings,
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
      modelId,
      required skipTranslationMemory,
      required unitsPerBatch,
      required parallelBatches,
    }) async =>
        _stubContext(),
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

    final runner = _runner(orchestrator: orchestrator, fixedBatchId: batchId);

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

  test(
      'counts TM-satisfied units as translated: a fully TM-covered run '
      '(successfulUnits=0, skippedUnits=3) must report 3, not 0', () async {
    // TM exact/fuzzy matches applied by TmLookupHandler bump skippedUnits,
    // never successfulUnits (only the LLM/cache path does). The runner used
    // to return progress.successfulUnits alone, so a run whose units were
    // all satisfied from Translation Memory reported '0 units translated'
    // to the user despite being fully successful. The runner must return
    // successfulUnits + skippedUnits.
    const batchId = 'b-tm-only';

    final controller = StreamController<
        Result<TranslationProgress, TranslationOrchestrationException>>();

    when(() => orchestrator.translateBatchesParallel(
          batchIds: any(named: 'batchIds'),
          context: any(named: 'context'),
          maxParallel: any(named: 'maxParallel'),
        )).thenAnswer((_) => controller.stream);

    final runner = _runner(orchestrator: orchestrator, fixedBatchId: batchId);

    final future = runner.run(
      projectLanguageId: 'pl-1',
      projectId: 'proj-1',
      unitIds: ['u1', 'u2', 'u3'],
      skipTM: false,
      providerId: 'openai',
    );

    controller.add(Ok(_progress(
      batchId: batchId,
      status: TranslationProgressStatus.completed,
      total: 3,
      processed: 3,
      successful: 0,
      skipped: 3,
    )));
    await controller.close();

    final translated = await future;
    expect(translated, 3,
        reason: 'units satisfied from TM (skippedUnits) received a '
            'translation and must count as translated');
  });

  test(
      'sums LLM-translated and TM-skipped units in a mixed run '
      '(successful=2, skipped=1 → 3)', () async {
    const batchId = 'b-mixed';

    final controller = StreamController<
        Result<TranslationProgress, TranslationOrchestrationException>>();

    when(() => orchestrator.translateBatchesParallel(
          batchIds: any(named: 'batchIds'),
          context: any(named: 'context'),
          maxParallel: any(named: 'maxParallel'),
        )).thenAnswer((_) => controller.stream);

    final runner = _runner(orchestrator: orchestrator, fixedBatchId: batchId);

    final future = runner.run(
      projectLanguageId: 'pl-1',
      projectId: 'proj-1',
      unitIds: ['u1', 'u2', 'u3'],
      skipTM: false,
      providerId: 'openai',
    );

    controller.add(Ok(_progress(
      batchId: batchId,
      status: TranslationProgressStatus.completed,
      total: 3,
      processed: 3,
      successful: 2,
      skipped: 1,
    )));
    await controller.close();

    expect(await future, 3);
  });

  test('throws when stream emits failed status', () async {
    const batchId = 'b-fail';

    final controller = StreamController<
        Result<TranslationProgress, TranslationOrchestrationException>>();

    when(() => orchestrator.translateBatchesParallel(
          batchIds: any(named: 'batchIds'),
          context: any(named: 'context'),
          maxParallel: any(named: 'maxParallel'),
        )).thenAnswer((_) => controller.stream);

    final runner = _runner(orchestrator: orchestrator, fixedBatchId: batchId);

    final future = runner.run(
      projectLanguageId: 'pl-1',
      projectId: 'proj-1',
      unitIds: ['u1', 'u2'],
      skipTM: false,
      providerId: 'openai',
    );

    controller.add(Ok(_progress(
      batchId: batchId,
      status: TranslationProgressStatus.failed,
    )));
    await controller.close();

    await expectLater(future, throwsA(isA<StateError>()));
  });

  test('stop() calls orchestrator.stopTranslation with current batch id',
      () async {
    const batchId = 'b-stop';

    final controller = StreamController<
        Result<TranslationProgress, TranslationOrchestrationException>>();

    when(() => orchestrator.translateBatchesParallel(
          batchIds: any(named: 'batchIds'),
          context: any(named: 'context'),
          maxParallel: any(named: 'maxParallel'),
        )).thenAnswer((_) => controller.stream);
    when(() => orchestrator.stopTranslation(batchId: any(named: 'batchId')))
        .thenAnswer((_) async => const Ok(null));

    final runner = _runner(orchestrator: orchestrator, fixedBatchId: batchId);

    final future = runner.run(
      projectLanguageId: 'pl-1',
      projectId: 'proj-1',
      unitIds: ['u1', 'u2'],
      skipTM: false,
      providerId: 'openai',
    );

    // Wait until the batch is registered as current.
    while (runner.currentBatchId == null) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(runner.currentBatchId, batchId);

    await runner.stop();
    verify(() => orchestrator.stopTranslation(batchId: batchId)).called(1);

    controller.add(Ok(_progress(
      batchId: batchId,
      status: TranslationProgressStatus.completed,
    )));
    await controller.close();
    await future;
  });
}
