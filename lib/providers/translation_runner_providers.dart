import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/utils/translation_batch_helper.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/providers/translation_settings_provider.dart';
import 'package:twmt/services/translation/headless_batch_translation_runner.dart';

/// Provider for [HeadlessBatchTranslationRunner].
///
/// Resolves the runner's dependencies from Riverpod and injects them into the
/// pure runner constructor. Production delegates wire directly to
/// [TranslationBatchHelper], which accepts the generic `Reader` typedef (both
/// `Ref.read` and `WidgetRef.read` satisfy it). Tests construct the runner
/// directly with stub dependencies instead of going through this provider.
final headlessBatchTranslationRunnerProvider =
    Provider<HeadlessBatchTranslationRunner>((ref) {
  return HeadlessBatchTranslationRunner(
    orchestrator: ref.read(translationOrchestratorProvider),
    readSettings: () => ref.read(translationSettingsProvider),
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
      modelId,
      required skipTranslationMemory,
      required unitsPerBatch,
      required parallelBatches,
    }) =>
        TranslationBatchHelper.buildTranslationContext(
      read: ref.read,
      projectId: projectId,
      projectLanguageId: projectLanguageId,
      providerId: providerId,
      modelId: modelId,
      unitsPerBatch: unitsPerBatch,
      parallelBatches: parallelBatches,
      skipTranslationMemory: skipTranslationMemory,
    ),
  );
});
