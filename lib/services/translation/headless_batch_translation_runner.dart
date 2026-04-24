import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/providers/translation_settings_provider.dart';
import 'package:twmt/features/translation_editor/utils/translation_batch_helper.dart';
import 'package:twmt/providers/shared/service_providers.dart' as shared_svc;
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';

// ---------------------------------------------------------------------------
// Delegate typedefs
// ---------------------------------------------------------------------------

/// Creates and persists a translation batch.
/// Returns the new [batchId] or null on failure.
typedef CreateBatchDelegate = Future<String?> Function({
  required String projectLanguageId,
  required List<String> unitIds,
  required String providerId,
});

/// Builds the [TranslationContext] used by the orchestrator.
typedef BuildContextDelegate = Future<TranslationContext> Function({
  required String projectLanguageId,
  required String projectId,
  required String providerId,
  required bool skipTranslationMemory,
  required int unitsPerBatch,
  required int parallelBatches,
});

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

/// Runs a single translation batch end-to-end without any UI involvement.
///
/// The [createBatch] and [buildContext] delegates decouple the runner from
/// [TranslationBatchHelper], which requires a [WidgetRef]. Production callers
/// that hold a [WidgetRef] supply thin lambdas wrapping the helper; tests
/// supply pure-Dart stubs.
class HeadlessBatchTranslationRunner {
  HeadlessBatchTranslationRunner(
    this._ref, {
    required CreateBatchDelegate createBatch,
    required BuildContextDelegate buildContext,
  })  : _createBatch = createBatch,
        _buildContext = buildContext;

  final Ref _ref;
  final CreateBatchDelegate _createBatch;
  final BuildContextDelegate _buildContext;

  String? _currentBatchId;

  /// Non-null while a batch is running.
  String? get currentBatchId => _currentBatchId;

  /// Runs a single batch end-to-end.
  ///
  /// Completes when the orchestrator emits a terminal event.
  /// Throws on failure; returns the count of successfully translated units on
  /// success.
  Future<int> run({
    required String projectLanguageId,
    required String projectId,
    required List<String> unitIds,
    required bool skipTM,
    required String providerId,
    void Function(String step, double progress)? onProgress,
  }) async {
    final batchId = await _createBatch(
      projectLanguageId: projectLanguageId,
      unitIds: unitIds,
      providerId: providerId,
    );
    if (batchId == null) {
      throw StateError('createBatch returned null — batch preparation failed');
    }
    _currentBatchId = batchId;

    final settings = _ref.read(translationSettingsProvider);

    final context = await _buildContext(
      projectLanguageId: projectLanguageId,
      projectId: projectId,
      providerId: providerId,
      skipTranslationMemory: skipTM,
      unitsPerBatch: settings.unitsPerBatch,
      parallelBatches: settings.parallelBatches,
    );

    final orchestrator = _ref.read(shared_svc.translationOrchestratorProvider);

    final stream = orchestrator.translateBatchesParallel(
      batchIds: [batchId],
      context: context,
      maxParallel: settings.parallelBatches,
    );

    int translated = 0;
    try {
      await for (final event in stream) {
        if (event.isErr) {
          throw event.unwrapErr();
        }
        final progress = event.unwrap();
        onProgress?.call(
          'Translating (${progress.processedUnits}/${progress.totalUnits})',
          progress.totalUnits == 0
              ? -1.0
              : progress.processedUnits / progress.totalUnits,
        );
        if (progress.status == TranslationProgressStatus.completed) {
          translated = progress.successfulUnits;
          break;
        }
        if (progress.status == TranslationProgressStatus.failed) {
          throw StateError('Batch failed: batchId=$batchId');
        }
      }
    } finally {
      _currentBatchId = null;
    }
    return translated;
  }

  /// Aggressively stops any currently running batch.
  /// Safe to call even if nothing is running.
  Future<void> stop() async {
    final id = _currentBatchId;
    if (id == null) return;
    final orchestrator = _ref.read(shared_svc.translationOrchestratorProvider);
    await orchestrator.stopTranslation(batchId: id);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider for [HeadlessBatchTranslationRunner].
///
/// Production instance wires delegates directly to
/// [TranslationBatchHelper], which accepts the generic `Reader` typedef
/// (both `Ref.read` and `WidgetRef.read` satisfy it). Tests can override
/// this provider with custom delegates (stubs).
final headlessBatchTranslationRunnerProvider =
    Provider<HeadlessBatchTranslationRunner>((ref) {
  return HeadlessBatchTranslationRunner(
    ref,
    createBatch: ({
      required projectLanguageId,
      required unitIds,
      required providerId,
    }) =>
        TranslationBatchHelper.createAndPrepareBatch(
      read: ref.read,
      projectLanguageId: projectLanguageId,
      unitIds: unitIds,
      providerId: providerId,
      onError: () => throw StateError('Batch preparation failed'),
    ),
    buildContext: ({
      required projectLanguageId,
      required projectId,
      required providerId,
      required skipTranslationMemory,
      required unitsPerBatch,
      required parallelBatches,
    }) =>
        TranslationBatchHelper.buildTranslationContext(
      read: ref.read,
      projectId: projectId,
      projectLanguageId: projectLanguageId,
      providerId: providerId,
      unitsPerBatch: unitsPerBatch,
      parallelBatches: parallelBatches,
      skipTranslationMemory: skipTranslationMemory,
    ),
  );
});
