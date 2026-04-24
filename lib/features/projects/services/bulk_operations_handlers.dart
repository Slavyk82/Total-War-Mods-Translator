import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
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
    return const ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: 'No target language configured',
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
      return const ProjectOutcome(
        status: ProjectResultStatus.skipped,
        message: 'No untranslated units',
      );
    }

    // Require a selected LLM model.
    final providerId = ref.read(selectedLlmModelProvider);
    if (providerId == null) {
      return const ProjectOutcome(
        status: ProjectResultStatus.failed,
        message: 'no LLM model selected',
      );
    }

    final settings = ref.read(translationSettingsProvider);
    final runner = ref.read(headlessBatchTranslationRunnerProvider);

    final translated = await runner.run(
      projectLanguageId: projectLanguageId,
      projectId: project.project.id,
      unitIds: unitIds,
      skipTM: settings.skipTranslationMemory,
      providerId: providerId,
      onProgress: onProgress,
    );

    // Post-translation rescan.
    final rescan = await runHeadlessValidationRescan(
      ref: ref,
      projectLanguageId: projectLanguageId,
    );

    return ProjectOutcome(
      status: ProjectResultStatus.succeeded,
      message: '$translated units translated · ${rescan.needsReviewTotal} flagged',
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
    return const ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: 'No target language configured',
    );
  }

  if (lang.translatedUnits == 0) {
    return const ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: 'No translated units to rescan',
    );
  }

  try {
    final rescan = await runHeadlessValidationRescan(
      ref: ref,
      projectLanguageId: lang.projectLanguage.id,
    );

    return ProjectOutcome(
      status: ProjectResultStatus.succeeded,
      message: '${rescan.needsReviewTotal} flagged for review',
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
    return const ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: 'No target language configured',
    );
  }

  if (lang.needsReviewUnits == 0) {
    return const ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: 'No units flagged for review',
    );
  }

  try {
    final versionRepo = ref.read(translationVersionRepositoryProvider);
    final idsResult = await versionRepo.getNeedsReviewIds(
      projectLanguageId: lang.projectLanguage.id,
    );
    final versionIds = idsResult.unwrap();

    if (versionIds.isEmpty) {
      return const ProjectOutcome(
        status: ProjectResultStatus.skipped,
        message: 'No units flagged for review',
      );
    }

    final countResult = await versionRepo.acceptBatch(versionIds);
    final cleared = countResult.unwrap();

    return ProjectOutcome(
      status: ProjectResultStatus.succeeded,
      message: '$cleared flags cleared',
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
/// `"<n> entries · <size> bytes"`.
Future<ProjectOutcome> runBulkGeneratePack({
  required Ref ref,
  required ProjectWithDetails project,
  required String targetLanguageCode,
  HandlerCallback? onProgress,
}) async {
  final lang = _findLanguage(project, targetLanguageCode);
  if (lang == null) {
    return const ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: 'No target language configured',
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
        message: '${exportResult.entryCount} entries · ${exportResult.fileSize} bytes',
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
