import 'dart:convert';

import 'package:riverpod/riverpod.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';

/// Summary returned by [runHeadlessValidationRescan].
typedef RescanResult = ({
  int scanned,
  int newIssues,
  int cleared,
  int unchanged,
  int needsReviewTotal,
});

/// Headless port of the editor's `_performRescan` method.
///
/// Runs the validation service over every translated entry for
/// [projectLanguageId], writes back updated statuses in a single DB
/// transaction, and returns a five-field summary record. Unlike the
/// editor-scoped version, this function:
///
/// - accepts [projectLanguageId] as a plain parameter instead of
///   reading it from editor state,
/// - emits no progress-notifier updates and shows no dialogs,
/// - propagates errors via thrown exceptions instead of showing an
///   error dialog and returning `null`.
///
/// The algorithm mirrors `_performRescan` step-for-step:
///   1. Repair any legacy camelCase status values.
///   2. Fetch all versions for the project-language.
///   3. Filter to versions that have translated text.
///   4. For each version, run the validation engine.
///   5. Compare against stored status / issues to classify the change.
///   6. Batch-write all changed rows.
///   7. Return the five-counter summary.
Future<RescanResult> runHeadlessValidationRescan({
  required Ref ref,
  required String projectLanguageId,
}) async {
  final versionRepo = ref.read(translationVersionRepositoryProvider);

  // Step 1 – repair legacy status encoding (same as _performRescan).
  await versionRepo.normalizeStatusEncoding();

  // Step 2 – load all versions for this project-language.
  final versionsResult =
      await versionRepo.getByProjectLanguage(projectLanguageId);
  if (versionsResult.isErr) {
    throw Exception('Failed to load translations: ${versionsResult.error}');
  }
  final allVersions = versionsResult.unwrap();

  // Step 3 – keep only versions that have translated text.
  final translatedVersions = allVersions
      .where(
        (v) => v.translatedText != null && v.translatedText!.isNotEmpty,
      )
      .toList();

  if (translatedVersions.isEmpty) {
    return (
      scanned: 0,
      newIssues: 0,
      cleared: 0,
      unchanged: 0,
      needsReviewTotal: 0,
    );
  }

  // Lazy-read the unit repo and validation service only when there is
  // actual work to do (avoids ServiceLocator lookups on the early-exit path).
  final unitRepo = ref.read(translationUnitRepositoryProvider);
  final validationService = ref.read(validationServiceProvider);

  // Step 4 – load all units in a single batch query.
  final unitIds =
      translatedVersions.map((v) => v.unitId).toSet().toList();
  final unitsResult = await unitRepo.getByIds(unitIds);
  final unitsMap = <String, dynamic>{};
  if (unitsResult.isOk) {
    for (final unit in unitsResult.unwrap()) {
      unitsMap[unit.id] = unit;
    }
  }

  // Step 5 – scan each version and accumulate counters.
  var scanned = 0;
  var newIssues = 0;
  var cleared = 0;
  var unchanged = 0;
  var needsReviewTotal = 0;
  final pendingUpdates = <({
    String versionId,
    String status,
    String? validationIssues,
    int schemaVersion,
  })>[];

  for (final version in translatedVersions) {
    scanned++;

    final unit = unitsMap[version.unitId];
    if (unit == null) continue;

    // Run the same validation engine as the editor does.
    final validationResult = await validationService.validateTranslation(
      sourceText: unit.sourceText,
      translatedText: version.translatedText!,
      key: unit.key,
    );

    // Determine new status and issues JSON.
    TranslationVersionStatus newStatus = TranslationVersionStatus.translated;
    String? newValidationIssues;

    if (validationResult.isErr) {
      newStatus = TranslationVersionStatus.needsReview;
    } else {
      final result = validationResult.unwrap();
      if (result.hasErrors || result.hasWarnings) {
        newStatus = TranslationVersionStatus.needsReview;
        newValidationIssues = jsonEncode(
          result.issues.map((i) => i.toJson()).toList(),
        );
      }
    }

    // Classify the change relative to the stored state.
    final statusChanged = version.status != newStatus;
    final issuesChanged = version.validationIssues != newValidationIssues;

    if (statusChanged || issuesChanged) {
      pendingUpdates.add((
        versionId: version.id,
        status: newStatus.toDbValue,
        validationIssues: newValidationIssues,
        schemaVersion: 1,
      ));

      if (newStatus == TranslationVersionStatus.needsReview) {
        newIssues++;
      } else {
        cleared++;
      }
    } else {
      unchanged++;
    }

    if (newStatus == TranslationVersionStatus.needsReview) {
      needsReviewTotal++;
    }
  }

  // Step 6 – batch-write all updates in a single transaction.
  if (pendingUpdates.isNotEmpty) {
    await versionRepo.updateValidationBatch(pendingUpdates);
  }

  // Step 7 – return the summary.
  return (
    scanned: scanned,
    newIssues: newIssues,
    cleared: cleared,
    unchanged: unchanged,
    needsReviewTotal: needsReviewTotal,
  );
}
