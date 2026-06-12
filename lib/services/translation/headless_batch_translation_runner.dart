import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/translation_settings.dart';

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
  String? modelId,
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
  HeadlessBatchTranslationRunner({
    required CreateBatchDelegate createBatch,
    required BuildContextDelegate buildContext,
    required ITranslationOrchestrator orchestrator,
    required TranslationSettings Function() readSettings,
  })  : _createBatch = createBatch,
        _buildContext = buildContext,
        _orchestrator = orchestrator,
        _readSettings = readSettings;

  final CreateBatchDelegate _createBatch;
  final BuildContextDelegate _buildContext;
  final ITranslationOrchestrator _orchestrator;
  final TranslationSettings Function() _readSettings;

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
    String? modelId,
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

    final settings = _readSettings();

    final context = await _buildContext(
      projectLanguageId: projectLanguageId,
      projectId: projectId,
      providerId: providerId,
      modelId: modelId,
      skipTranslationMemory: skipTM,
      unitsPerBatch: settings.unitsPerBatch,
      parallelBatches: settings.parallelBatches,
    );

    final stream = _orchestrator.translateBatchesParallel(
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
          // `successfulUnits` only counts LLM/cache translations; units
          // satisfied from Translation Memory (exact/fuzzy matches applied
          // by TmLookupHandler) are counted in `skippedUnits` and never bump
          // `successfulUnits`. Both kinds received a translation, so report
          // their sum - otherwise a fully TM-covered run reports 0.
          translated = progress.successfulUnits + progress.skippedUnits;
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
    await _orchestrator.stopTranslation(batchId: id);
  }
}
