import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/batch_pack_export_notifier.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/file/export_orchestrator_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';

import '../../../helpers/fakes/fake_logger.dart';

/// Fake export service whose [exportToPack] can be held open via [gate] so
/// tests can cancel/reset/restart the notifier while an export is in flight.
class _FakeExportService extends Fake implements ExportOrchestratorService {
  /// Project ids passed to [exportToPack], in call order.
  final List<String> calls = [];

  /// When non-null, every call suspends on this gate before returning.
  Completer<void>? gate;

  int _activeCalls = 0;

  /// Highest number of simultaneously in-flight [exportToPack] calls.
  /// Must stay at 1 — two interleaved batch loops would push it to 2.
  int maxConcurrentCalls = 0;

  @override
  Future<Result<ExportResult, FileServiceException>> exportToPack({
    required String projectId,
    required List<String> languageCodes,
    required String outputPath,
    required bool validatedOnly,
    bool generatePackImage = true,
    ExportProgressCallback? onProgress,
  }) async {
    calls.add(projectId);
    _activeCalls++;
    if (_activeCalls > maxConcurrentCalls) {
      maxConcurrentCalls = _activeCalls;
    }
    final currentGate = gate;
    if (currentGate != null) {
      await currentGate.future;
    }
    _activeCalls--;
    return Ok(ExportResult(
      outputPath: '$projectId.pack',
      entryCount: 1,
      fileSize: 10,
      languageCodes: languageCodes,
    ));
  }
}

void main() {
  late _FakeExportService exportService;
  late ProviderContainer container;

  ProviderContainer makeContainer() {
    final c = ProviderContainer(
      overrides: [
        loggingServiceProvider.overrideWithValue(FakeLogger()),
        exportOrchestratorServiceProvider.overrideWithValue(exportService),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  List<ProjectExportInfo> projects(List<String> ids) =>
      [for (final id in ids) ProjectExportInfo(id: id, name: 'Project $id')];

  setUp(() {
    exportService = _FakeExportService();
    container = makeContainer();
  });

  group('BatchPackExportNotifier', () {
    test('exports all projects and completes', () async {
      final notifier = container.read(batchPackExportProvider.notifier);

      await notifier.exportBatch(
        projects: projects(['p1', 'p2']),
        languageCode: 'fr',
      );

      final state = container.read(batchPackExportProvider);
      expect(exportService.calls, ['p1', 'p2']);
      expect(state.isExporting, isFalse);
      expect(state.isComplete, isTrue);
      expect(state.isCancelled, isFalse);
      expect(state.completedProjects, 2);
      expect(state.totalProjects, 2);
      expect(state.projectStatuses['p1'], BatchProjectStatus.success);
      expect(state.projectStatuses['p2'], BatchProjectStatus.success);
    });

    test('cancel mid-loop stops further exports and cleans up terminal state',
        () async {
      final notifier = container.read(batchPackExportProvider.notifier);
      exportService.gate = Completer<void>();

      final exportFuture = notifier.exportBatch(
        projects: projects(['p1', 'p2', 'p3']),
        languageCode: 'fr',
      );
      // First project is in flight, held open by the gate.
      expect(exportService.calls, ['p1']);

      notifier.cancel();
      expect(container.read(batchPackExportProvider).isCancelled, isTrue);

      exportService.gate!.complete();
      await exportFuture;

      final state = container.read(batchPackExportProvider);
      // No further project was exported after cancellation.
      expect(exportService.calls, ['p1']);
      expect(state.isExporting, isFalse);
      expect(state.isCancelled, isTrue);
      expect(state.projectStatuses['p1'], BatchProjectStatus.success);
      expect(state.projectStatuses['p2'], BatchProjectStatus.cancelled);
      expect(state.projectStatuses['p3'], BatchProjectStatus.cancelled);
      expect(state.currentProjectId, isNull);
    });

    test('reset while exporting cancels instead of clearing state, '
        'and the loop never resurrects inconsistent state', () async {
      final notifier = container.read(batchPackExportProvider.notifier);
      exportService.gate = Completer<void>();

      final emitted = <BatchPackExportState>[];
      container.listen(
        batchPackExportProvider,
        (_, next) => emitted.add(next),
      );

      final exportFuture = notifier.exportBatch(
        projects: projects(['p1', 'p2', 'p3']),
        languageCode: 'fr',
      );
      expect(exportService.calls, ['p1']);

      // Screen dispose path: reset() while the loop is running.
      notifier.reset();

      // State must not have been wiped under the running loop.
      var state = container.read(batchPackExportProvider);
      expect(state.totalProjects, 3);
      expect(state.isCancelled, isTrue,
          reason: 'reset during a run must request cancellation');

      exportService.gate!.complete();
      await exportFuture;

      state = container.read(batchPackExportProvider);
      expect(exportService.calls, ['p1'],
          reason: 'loop must stop at the next cancellation checkpoint');
      expect(state.isExporting, isFalse);
      expect(state.projectStatuses['p2'], BatchProjectStatus.cancelled);
      expect(state.projectStatuses['p3'], BatchProjectStatus.cancelled);

      // The original bug resurrected totalProjects=0 with climbing
      // completedProjects; assert no emitted state was ever inconsistent.
      expect(
        emitted.any((s) =>
            s.totalProjects == 0 && (s.completedProjects > 0 || s.isExporting)),
        isFalse,
        reason: 'no state write may resurrect reset/inconsistent state',
      );
    });

    test('re-entry guard: exportBatch is a no-op while a run is active',
        () async {
      final notifier = container.read(batchPackExportProvider.notifier);
      exportService.gate = Completer<void>();

      final firstRun = notifier.exportBatch(
        projects: projects(['a1', 'a2']),
        languageCode: 'fr',
      );
      expect(exportService.calls, ['a1']);

      // Second call while running and not cancelled must be ignored.
      await notifier.exportBatch(
        projects: projects(['b1', 'b2']),
        languageCode: 'fr',
      );
      expect(exportService.calls, ['a1']);

      exportService.gate!.complete();
      await firstRun;

      final state = container.read(batchPackExportProvider);
      expect(exportService.calls, ['a1', 'a2']);
      expect(state.projectStatuses.keys, unorderedEquals(['a1', 'a2']));
    });

    test('re-entry after reset waits for the cancelled loop to drain and '
        'never interleaves two loops', () async {
      final notifier = container.read(batchPackExportProvider.notifier);
      exportService.gate = Completer<void>();

      final runA = notifier.exportBatch(
        projects: projects(['a1', 'a2']),
        languageCode: 'fr',
      );
      expect(exportService.calls, ['a1']);

      // Leave the screen (cancel via reset), then re-enter and start a new
      // batch while a1's export is still in flight.
      notifier.reset();
      final runB = notifier.exportBatch(
        projects: projects(['b1', 'b2']),
        languageCode: 'fr',
      );

      // Run B must not start while run A is still draining.
      await Future<void>.delayed(Duration.zero);
      expect(exportService.calls, ['a1']);

      exportService.gate!.complete();
      await runA;
      await runB;

      final state = container.read(batchPackExportProvider);
      expect(exportService.calls, ['a1', 'b1', 'b2']);
      expect(exportService.maxConcurrentCalls, 1,
          reason: 'two batch loops must never export concurrently');
      // Final state belongs entirely to run B.
      expect(state.totalProjects, 2);
      expect(state.completedProjects, 2);
      expect(state.isExporting, isFalse);
      expect(state.isCancelled, isFalse);
      expect(state.isComplete, isTrue);
      expect(state.projectStatuses.keys, unorderedEquals(['b1', 'b2']));
      expect(state.projectStatuses['b1'], BatchProjectStatus.success);
      expect(state.projectStatuses['b2'], BatchProjectStatus.success);
    });

    test('cancel while a queued run waits for drain aborts the queued run',
        () async {
      final notifier = container.read(batchPackExportProvider.notifier);
      exportService.gate = Completer<void>();

      final runA = notifier.exportBatch(
        projects: projects(['a1', 'a2']),
        languageCode: 'fr',
      );
      expect(exportService.calls, ['a1']);

      notifier.cancel();
      // Re-enter the screen: run B queues behind the draining loop...
      final runB = notifier.exportBatch(
        projects: projects(['b1', 'b2']),
        languageCode: 'fr',
      );
      // ...then the user leaves again before run A has drained.
      notifier.cancel();

      exportService.gate!.complete();
      await runA;
      await runB;

      final state = container.read(batchPackExportProvider);
      expect(exportService.calls, ['a1'],
          reason: 'queued run must not start after being cancelled');
      expect(state.isExporting, isFalse);
    });

    test('reset when idle clears state', () async {
      final notifier = container.read(batchPackExportProvider.notifier);

      await notifier.exportBatch(
        projects: projects(['p1']),
        languageCode: 'fr',
      );
      expect(container.read(batchPackExportProvider).results, isNotEmpty);

      notifier.reset();

      final state = container.read(batchPackExportProvider);
      expect(state.isExporting, isFalse);
      expect(state.isCancelled, isFalse);
      expect(state.totalProjects, 0);
      expect(state.results, isEmpty);
      expect(state.projectStatuses, isEmpty);
    });

    test('cancel when idle is a no-op', () {
      final notifier = container.read(batchPackExportProvider.notifier);

      notifier.cancel();

      final state = container.read(batchPackExportProvider);
      expect(state.isCancelled, isFalse);
      expect(state.isExporting, isFalse);
    });
  });
}
