import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/features/translation_editor/providers/llm_model_providers.dart';
import 'package:twmt/features/translation_editor/providers/translation_settings_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation/headless_batch_translation_runner.dart';
import 'package:twmt/services/translation/headless_validation_rescan_service.dart';

/// Progress callback type used by all bulk operation handlers.
typedef HandlerCallback = void Function(String step, double progress);

// ---------------------------------------------------------------------------
// Private helper
// ---------------------------------------------------------------------------

/// Returns the [ProjectLanguageWithInfo] whose language code matches [code],
/// or null if no matching language is configured on the project.
ProjectLanguageWithInfo? _findLanguage(
  ProjectWithDetails project,
  String code,
) {
  for (final l in project.languages) {
    if (l.language?.code == code) return l;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Shared provider/model resolution
// ---------------------------------------------------------------------------

/// Resolves the current "selected LLM" state into the `(providerId, modelId)`
/// shape expected by the translation batch schema.
///
/// Preference order — mirrors the editor's translate action:
/// 1. A row in `llm_provider_models` referenced by `selectedLlmModelProvider`
///    (provider code + per-provider model id).
/// 2. The global `active_llm_provider` setting (provider only, no modelId).
///
/// Returns `null` if nothing is selected and no active provider is set.
Future<({String providerId, String? modelId})?> _resolveSelectedProvider(
  Ref ref,
) async {
  final selectedModelId = ref.read(selectedLlmModelProvider);
  if (selectedModelId != null) {
    final modelRepo = ref.read(llmProviderModelRepositoryProvider);
    final modelResult = await modelRepo.getById(selectedModelId);
    if (modelResult.isOk) {
      final model = modelResult.unwrap();
      return (
        providerId: 'provider_${model.providerCode}',
        modelId: model.modelId,
      );
    }
  }
  final settings = await ref.read(llmProviderSettingsProvider.future);
  final activeCode = settings['active_llm_provider'] ?? '';
  if (activeCode.isEmpty) return null;
  return (providerId: 'provider_$activeCode', modelId: null);
}

// ---------------------------------------------------------------------------
// runBulkTranslate
// ---------------------------------------------------------------------------

/// Translates all untranslated units for [targetLanguageCode] in [project].
///
/// Skip conditions:
/// - Project has no target language configured for [targetLanguageCode].
/// - No untranslated units exist for that language.
///
/// On success, runs a headless validation rescan and returns a summary message
/// of the form `"<n> units translated · <k> flagged"`.
Future<ProjectOutcome> runBulkTranslate({
  required Ref ref,
  required ProjectWithDetails project,
  required String targetLanguageCode,
  HandlerCallback? onProgress,
}) async {
  final lang = _findLanguage(project, targetLanguageCode);
  if (lang == null) {
    return ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: t.projects.bulk.outcomes.noTargetLanguage,
    );
  }

  final projectLanguageId = lang.projectLanguage.id;
  final versionRepo = ref.read(translationVersionRepositoryProvider);

  try {
    // Fetch untranslated unit IDs directly via the repo (Ref-safe, no WidgetRef).
    final untranslatedResult =
        await versionRepo.getUntranslatedIds(projectLanguageId: projectLanguageId);
    final unitIds = untranslatedResult.unwrap();

    if (unitIds.isEmpty) {
      return ProjectOutcome(
        status: ProjectResultStatus.skipped,
        message: t.projects.bulk.outcomes.noUntranslatedUnits,
      );
    }

    // Resolve the selected LLM model into the `(providerId, modelId)` pair
    // expected by the batch schema. `translation_batches.provider_id` is a
    // foreign key onto `translation_providers(id)` which uses the
    // `'provider_<code>'` format (e.g. `'provider_anthropic'`). The raw
    // `selectedLlmModelProvider` value is a model PK, not a provider id, so
    // we look the model up to recover its provider code — same path the
    // editor's translate action uses.
    final resolved = await _resolveSelectedProvider(ref);
    if (resolved == null) {
      return ProjectOutcome(
        status: ProjectResultStatus.failed,
        message: t.projects.bulk.outcomes.noLlmModel,
      );
    }

    final settings = ref.read(translationSettingsProvider);
    final runner = ref.read(headlessBatchTranslationRunnerProvider);

    final translated = await runner.run(
      projectLanguageId: projectLanguageId,
      projectId: project.project.id,
      unitIds: unitIds,
      skipTM: settings.skipTranslationMemory,
      providerId: resolved.providerId,
      modelId: resolved.modelId,
      onProgress: onProgress,
    );

    // Post-translation rescan.
    final rescan = await runHeadlessValidationRescan(
      ref: ref,
      projectLanguageId: projectLanguageId,
    );

    return ProjectOutcome(
      status: ProjectResultStatus.succeeded,
      message: t.projects.bulk.outcomes.unitsTranslated(count: translated, flagged: rescan.needsReviewTotal),
    );
  } catch (e) {
    return ProjectOutcome(
      status: ProjectResultStatus.failed,
      message: e.toString(),
      error: e,
    );
  }
}

// ---------------------------------------------------------------------------
// runBulkTranslateReviews
// ---------------------------------------------------------------------------

/// Retranslates every `needsReview` unit for [targetLanguageCode] in
/// [project], forcing the LLM path (skipTranslationMemory = true).
///
/// Skip conditions:
/// - Project has no target language configured for [targetLanguageCode].
/// - 0 `needsReview` units for that language.
Future<ProjectOutcome> runBulkTranslateReviews({
  required Ref ref,
  required ProjectWithDetails project,
  required String targetLanguageCode,
  HandlerCallback? onProgress,
}) async {
  final lang = _findLanguage(project, targetLanguageCode);
  if (lang == null) {
    return ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: t.projects.bulk.outcomes.noTargetLanguage,
    );
  }
  if (lang.needsReviewUnits == 0) {
    return ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: t.projects.bulk.outcomes.noFlaggedUnits,
    );
  }

  final projectLanguageId = lang.projectLanguage.id;
  final versionRepo = ref.read(translationVersionRepositoryProvider);

  try {
    final rowsResult = await versionRepo.getNeedsReviewRows(
      projectLanguageId: projectLanguageId,
    );
    final unitIds = rowsResult.unwrap().map((r) => r.unitId).toList();
    if (unitIds.isEmpty) {
      return ProjectOutcome(
        status: ProjectResultStatus.skipped,
        message: t.projects.bulk.outcomes.noFlaggedUnits,
      );
    }

    final resolved = await _resolveSelectedProvider(ref);
    if (resolved == null) {
      return ProjectOutcome(
        status: ProjectResultStatus.failed,
        message: t.projects.bulk.outcomes.noLlmModel,
      );
    }

    final runner = ref.read(headlessBatchTranslationRunnerProvider);
    final translated = await runner.run(
      projectLanguageId: projectLanguageId,
      projectId: project.project.id,
      unitIds: unitIds,
      // Force the LLM path: review flags exist precisely because the prior
      // translation is suspect, so hitting TM would likely return the same
      // suspect answer.
      skipTM: true,
      providerId: resolved.providerId,
      modelId: resolved.modelId,
      onProgress: onProgress,
    );

    return ProjectOutcome(
      status: ProjectResultStatus.succeeded,
      message: t.projects.bulk.outcomes.unitsRetranslated(count: translated),
    );
  } catch (e) {
    return ProjectOutcome(
      status: ProjectResultStatus.failed,
      message: e.toString(),
      error: e,
    );
  }
}

// ---------------------------------------------------------------------------
// runBulkRescan
// ---------------------------------------------------------------------------

/// Rescans all translated units for [targetLanguageCode] in [project].
///
/// Skip conditions:
/// - Project has no target language configured for [targetLanguageCode].
/// - 0 translated units for that language.
///
/// On success returns a summary message of the form `"<k> flagged for review"`.
Future<ProjectOutcome> runBulkRescan({
  required Ref ref,
  required ProjectWithDetails project,
  required String targetLanguageCode,
  HandlerCallback? onProgress,
}) async {
  final lang = _findLanguage(project, targetLanguageCode);
  if (lang == null) {
    return ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: t.projects.bulk.outcomes.noTargetLanguage,
    );
  }

  if (lang.translatedUnits == 0) {
    return ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: t.projects.bulk.outcomes.noUnitsToRescan,
    );
  }

  try {
    final rescan = await runHeadlessValidationRescan(
      ref: ref,
      projectLanguageId: lang.projectLanguage.id,
    );

    return ProjectOutcome(
      status: ProjectResultStatus.succeeded,
      message: t.projects.bulk.outcomes.unitsFlagged(count: rescan.needsReviewTotal),
    );
  } catch (e) {
    return ProjectOutcome(
      status: ProjectResultStatus.failed,
      message: e.toString(),
      error: e,
    );
  }
}

// ---------------------------------------------------------------------------
// runBulkForceValidate
// ---------------------------------------------------------------------------

/// Accepts (clears) all `needsReview` units for [targetLanguageCode] in [project].
///
/// Skip conditions:
/// - Project has no target language configured for [targetLanguageCode].
/// - 0 `needsReview` units for that language.
///
/// On success returns a summary message of the form `"<n> flags cleared"`.
Future<ProjectOutcome> runBulkForceValidate({
  required Ref ref,
  required ProjectWithDetails project,
  required String targetLanguageCode,
  HandlerCallback? onProgress,
}) async {
  final lang = _findLanguage(project, targetLanguageCode);
  if (lang == null) {
    return ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: t.projects.bulk.outcomes.noTargetLanguage,
    );
  }

  if (lang.needsReviewUnits == 0) {
    return ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: t.projects.bulk.outcomes.noFlaggedUnits,
    );
  }

  try {
    final versionRepo = ref.read(translationVersionRepositoryProvider);
    final idsResult = await versionRepo.getNeedsReviewIds(
      projectLanguageId: lang.projectLanguage.id,
    );
    final versionIds = idsResult.unwrap();

    if (versionIds.isEmpty) {
      return ProjectOutcome(
        status: ProjectResultStatus.skipped,
        message: t.projects.bulk.outcomes.noFlaggedUnits,
      );
    }

    final countResult = await versionRepo.acceptBatch(versionIds);
    final cleared = countResult.unwrap();

    return ProjectOutcome(
      status: ProjectResultStatus.succeeded,
      message: t.projects.bulk.outcomes.flagsCleared(count: cleared),
    );
  } catch (e) {
    return ProjectOutcome(
      status: ProjectResultStatus.failed,
      message: e.toString(),
      error: e,
    );
  }
}

// ---------------------------------------------------------------------------
// runBulkGeneratePack
// ---------------------------------------------------------------------------

/// Generates an export pack for [targetLanguageCode] in [project].
///
/// Skip condition:
/// - Project has no target language configured for [targetLanguageCode].
///
/// On success returns a summary message of the form
/// `"<n> entries · <size> MB"`.
Future<ProjectOutcome> runBulkGeneratePack({
  required Ref ref,
  required ProjectWithDetails project,
  required String targetLanguageCode,
  HandlerCallback? onProgress,
}) async {
  final lang = _findLanguage(project, targetLanguageCode);
  if (lang == null) {
    return ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: t.projects.bulk.outcomes.noTargetLanguage,
    );
  }

  try {
    final exportService = ref.read(exportOrchestratorServiceProvider);
    final result = await exportService.exportToPack(
      projectId: project.project.id,
      languageCodes: [targetLanguageCode],
      outputPath: 'exports', // Dummy — pack goes to game data folder.
      validatedOnly: false,
      generatePackImage: true,
      onProgress: onProgress != null
          ? (step, progress, {currentLanguage, currentIndex, total}) {
              onProgress(step, progress);
            }
          : null,
    );

    return result.when(
      ok: (exportResult) => ProjectOutcome(
        status: ProjectResultStatus.succeeded,
        message: t.projects.bulk.outcomes.packGenerated(
          entries: exportResult.entryCount,
          size: (exportResult.fileSize / (1024 * 1024)).toStringAsFixed(2),
        ),
      ),
      err: (error) => ProjectOutcome(
        status: ProjectResultStatus.failed,
        message: error.toString(),
        error: error,
      ),
    );
  } catch (e) {
    return ProjectOutcome(
      status: ProjectResultStatus.failed,
      message: e.toString(),
      error: e,
    );
  }
}
