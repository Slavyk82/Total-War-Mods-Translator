import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import '../../../../models/domain/translation_version.dart';
import '../../../../providers/batch/batch_operations_provider.dart' as batch;
import '../../../../providers/shared/logging_providers.dart';
import '../../../../providers/shared/repository_providers.dart' as shared_repo;
import '../../../../providers/shared/service_providers.dart' as shared_svc;
import '../../../../services/validation/validation_schema.dart';
import '../../providers/editor_providers.dart';
import '../../widgets/editor_dialogs.dart';
import 'editor_actions_base.dart';

/// Mixin handling validation operations.
///
/// The user-facing entry point is [handleValidate], which now unifies the
/// old "load needs-review issues → open review screen" path with the
/// former rescan flow: it re-runs the validation service over every
/// translated row (reusing [_performRescan]) and then pivots the editor's
/// status filter to `needsReview` so the grid itself becomes the review
/// surface. Per-row Accept/Reject/Edit and bulk Accept/Reject helpers are
/// exposed as public methods so the inspector panel can drive them — both
/// the single-selection issue buttons and the multi-selection bulk row.
mixin EditorActionsValidation on EditorActionsBase {
  /// Rescans all translations then focuses the grid on rows needing review.
  ///
  /// Runs the validation service over every translated entry
  /// ([_performRescan]), updates statuses in a single transaction, then —
  /// only if the rescan left at least one row in `needsReview` — sets the
  /// status filter to `{needsReview}` and clears the severity filter so
  /// the SEVERITY pill group surfaces fresh counts. When zero rows need
  /// review, the filter state is left untouched and the legacy "No issues
  /// to review" info dialog surfaces instead — pivoting to an empty grid
  /// would just hide the user's translations for no reason.
  Future<void> handleValidate() async {
    final outcome = await _performRescan();
    if (outcome == null) return;
    refreshProviders();

    if (outcome.needsReviewTotal == 0) {
      if (!context.mounted) return;
      EditorDialogs.showInfoDialog(
        context,
        t.translationEditor.dialogs.noIssues.title,
        t.translationEditor.dialogs.noIssues.message,
      );
      return;
    }

    // Apply the review filter. The SEVERITY pill group will appear because
    // the filter state now contains `needsReview`.
    ref
        .read(editorFilterProvider.notifier)
        .setStatusFilter(TranslationVersionStatus.needsReview);
    ref
        .read(editorFilterProvider.notifier)
        .setSeverityFilter(null);
  }

  /// Re-runs the validation service on every translated entry and writes
  /// back the resulting status + validation_issues JSON in a single
  /// transaction.
  ///
  /// Shows a progress dialog while scanning and returns a summary tuple
  /// `(scanned, newIssues, cleared, unchanged, needsReviewTotal)` for the
  /// caller to act on. `needsReviewTotal` is the count of rows whose
  /// post-rescan status is `needsReview` (whether they just flipped to
  /// that state or were already there and stayed) — the caller uses it
  /// to decide whether to pivot the grid filter. Returns `null` when
  /// there is nothing to scan (no translated entries) — the caller
  /// should treat that as an early exit.
  Future<
      ({
        int scanned,
        int newIssues,
        int cleared,
        int unchanged,
        int needsReviewTotal,
      })?> _performRescan() async {
    BuildContext? progressDialogContext;
    // Created up front so the `finally` block can always dispose it, even
    // on early-exit paths (e.g. "Nothing to scan") or thrown errors.
    final progressNotifier = ValueNotifier<String>(t.translationEditor.dialogs.validationRescan.scanning(current: 0, total: 0));
    // Completes when the dialog's builder fires for the first time. We
    // await this before starting the rescan so that fast paths (clean
    // dataset → no `updateValidationBatch` await) cannot finish before
    // the dialog mounts. Without it, `progressDialogContext` stays null
    // when `Navigator.pop` runs and the dialog later builds against an
    // already-disposed `progressNotifier`, leaving the spinner on screen
    // forever.
    final dialogShown = Completer<void>();
    try {
      final projectLanguageId = await getProjectLanguageId();
      final versionRepo =
          ref.read(shared_repo.translationVersionRepositoryProvider);
      final unitRepo = ref.read(shared_repo.translationUnitRepositoryProvider);
      final validationService = ref.read(shared_svc.validationServiceProvider);
      final logger = ref.read(loggingServiceProvider);

      // Repair any rows that were previously written with the Dart
      // identifier `'needsReview'` instead of the schema value
      // `'needs_review'`. Silently fixes legacy data from a prior bug so the
      // stats query (which matches on the canonical value) sees them again.
      final repairResult = await versionRepo.normalizeStatusEncoding();
      if (repairResult.isOk) {
        final repaired = repairResult.unwrap();
        if (repaired > 0) {
          logger.info('Repaired legacy status values',
              {'rowsAffected': repaired});
        }
      }

      // Get all versions for this project language
      final versionsResult =
          await versionRepo.getByProjectLanguage(projectLanguageId);
      if (versionsResult.isErr) {
        throw Exception('Failed to load translations');
      }

      final allVersions = versionsResult.unwrap();

      // Keep only versions that have translated text
      final translatedVersions = allVersions
          .where((v) =>
              v.translatedText != null && v.translatedText!.isNotEmpty)
          .toList();

      if (translatedVersions.isEmpty) {
        if (!context.mounted) return null;
        EditorDialogs.showInfoDialog(
          context,
          t.translationEditor.dialogs.nothingToScan.title,
          t.translationEditor.dialogs.nothingToScan.message,
        );
        return null;
      }

      logger.info(
        'Starting full validation rescan',
        {'totalToScan': translatedVersions.length},
      );

      // Show progress dialog
      if (!context.mounted) return null;
      progressNotifier.value =
          t.translationEditor.dialogs.validationRescan.scanning(
        current: 0,
        total: translatedVersions.length,
      );

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          progressDialogContext = dialogContext;
          if (!dialogShown.isCompleted) {
            dialogShown.complete();
          }
          final tokens = dialogContext.tokens;
          return TokenDialog(
            icon: FluentIcons.shield_checkmark_24_regular,
            title: t.translationEditor.dialogs.validationRescan.title,
            width: 460,
            body: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: progressNotifier,
                    builder: (_, message, _) => Text(
                      message,
                      style: tokens.fontBody.copyWith(
                        fontSize: 13,
                        color: tokens.textDim,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );

      // Wait for the dialog's builder to fire so `progressDialogContext`
      // is set and the `ValueListenableBuilder` has registered its
      // listener BEFORE the rescan starts. Skipping this would let a
      // fast rescan (clean dataset, no save batch) finish before the
      // dialog mounts — `Navigator.pop` would run with a null context,
      // the dialog would later build against a disposed notifier, and
      // the spinner would stay on screen until the editor is closed.
      await dialogShown.future;

      // Load all units in batch
      final unitIds =
          translatedVersions.map((v) => v.unitId).toSet().toList();
      final unitsResult = await unitRepo.getByIds(unitIds);
      final unitsMap = <String, dynamic>{};
      if (unitsResult.isOk) {
        for (final unit in unitsResult.unwrap()) {
          unitsMap[unit.id] = unit;
        }
      }

      // Run the scan and collect updates
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
        if (scanned % 100 == 0 || scanned == translatedVersions.length) {
          progressNotifier.value =
              t.translationEditor.dialogs.validationRescan.scanning(
            current: scanned,
            total: translatedVersions.length,
          );
          // Yield to UI thread for progress updates
          await Future<void>.delayed(Duration.zero);
        }

        // Get the unit for source text from pre-loaded map
        final unit = unitsMap[version.unitId];
        if (unit == null) continue;

        // Run validation
        final validationResult = await validationService.validateTranslation(
          sourceText: unit.sourceText,
          translatedText: version.translatedText!,
          key: unit.key,
        );

        // Determine new status
        TranslationVersionStatus newStatus =
            TranslationVersionStatus.translated;
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

        // Check if status changed
        final statusChanged = version.status != newStatus;
        final issuesChanged =
            version.validationIssues != newValidationIssues;

        if (statusChanged || issuesChanged) {
          pendingUpdates.add((
            versionId: version.id,
            status: newStatus.toDbValue,
            validationIssues: newValidationIssues,
            // Stamp the current schema version so the startup rescan
            // doesn't re-classify these freshly-validated rows as legacy.
            schemaVersion: kCurrentValidationSchemaVersion,
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

      // Batch write all updates in a single transaction
      if (pendingUpdates.isNotEmpty) {
        progressNotifier.value =
            t.translationEditor.dialogs.validationRescan.saving(
          count: pendingUpdates.length,
        );
        await versionRepo.updateValidationBatch(pendingUpdates);
      }

      logger.info(
        'Validation rescan complete',
        {
          'scanned': scanned,
          'newIssues': newIssues,
          'cleared': cleared,
          'unchanged': unchanged,
          'needsReviewTotal': needsReviewTotal,
        },
      );

      // Close progress dialog before returning the summary
      final dialogCtx = progressDialogContext;
      if (dialogCtx != null && dialogCtx.mounted) {
        Navigator.of(dialogCtx).pop();
      }

      return (
        scanned: scanned,
        newIssues: newIssues,
        cleared: cleared,
        unchanged: unchanged,
        needsReviewTotal: needsReviewTotal,
      );
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Validation rescan failed',
        e,
        stackTrace,
      );
      // Try to close progress dialog if still open
      final dialogCtx = progressDialogContext;
      if (dialogCtx != null && dialogCtx.mounted) {
        Navigator.of(dialogCtx).pop();
      }
      if (!context.mounted) return null;
      EditorDialogs.showErrorDialog(
        context,
        t.translationEditor.dialogs.validationRescan.failedTitle,
        e.toString(),
      );
      return null;
    } finally {
      progressNotifier.dispose();
    }
  }

  /// Batch accept every row in [rows] in a single transaction.
  ///
  /// Called from the inspector's multi-select bulk row. The caller hands us
  /// full [TranslationRow] instances so we can pull `version.id` directly;
  /// the repository entry point only needs version ids. Refreshes editor
  /// providers on success so the grid re-renders without the accepted rows.
  Future<void> handleBulkAcceptTranslation(List<TranslationRow> rows) async {
    final versionRepo =
        ref.read(shared_repo.translationVersionRepositoryProvider);
    final versionIds = rows.map((r) => r.version.id).toSet().toList();

    final result = await versionRepo.acceptBatch(versionIds);

    if (result.isErr) {
      ref.read(loggingServiceProvider).error(
        'Failed to batch accept translations',
        {'count': versionIds.length, 'error': result.error},
      );
      return;
    }
    ref.read(loggingServiceProvider).info(
      'Batch accepted translations',
      {'count': result.value},
    );
    refreshProviders();
  }

  /// Batch reject every row in [rows] in a single transaction.
  ///
  /// Mirror of [handleBulkAcceptTranslation]: clears the translation on
  /// each selected row and refreshes editor providers so the grid updates
  /// immediately.
  Future<void> handleBulkRejectTranslation(List<TranslationRow> rows) async {
    final versionRepo =
        ref.read(shared_repo.translationVersionRepositoryProvider);
    final versionIds = rows.map((r) => r.version.id).toSet().toList();

    final result = await versionRepo.rejectBatch(versionIds);

    if (result.isErr) {
      ref.read(loggingServiceProvider).error(
        'Failed to batch reject translations',
        {'count': versionIds.length, 'error': result.error},
      );
      return;
    }
    ref.read(loggingServiceProvider).info(
      'Batch rejected translations',
      {'count': result.value},
    );
    refreshProviders();
  }

  /// Reject a translation by clearing it (sets status back to `pending`).
  Future<void> handleRejectTranslation(batch.ValidationIssue issue) async {
    final versionRepo =
        ref.read(shared_repo.translationVersionRepositoryProvider);

    final versionResult = await versionRepo.getById(issue.versionId);
    if (versionResult.isErr) {
      ref.read(loggingServiceProvider).error(
        'Failed to load version for rejection',
        {'versionId': issue.versionId},
      );
      return;
    }

    final version = versionResult.unwrap();
    final clearedVersion = version.copyWith(
      translatedText: null,
      status: TranslationVersionStatus.pending,
      validationIssues: null,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    await versionRepo.update(clearedVersion);

    ref.read(loggingServiceProvider).info(
      'Translation rejected and cleared',
      {'unitKey': issue.unitKey, 'versionId': issue.versionId},
    );
    refreshProviders();
  }

  /// Accept a translation despite validation issues (clears the flag).
  Future<void> handleAcceptTranslation(batch.ValidationIssue issue) async {
    final versionRepo =
        ref.read(shared_repo.translationVersionRepositoryProvider);

    final versionResult = await versionRepo.getById(issue.versionId);
    if (versionResult.isErr) {
      ref.read(loggingServiceProvider).error(
        'Failed to load version for acceptance',
        {'versionId': issue.versionId},
      );
      return;
    }

    final version = versionResult.unwrap();
    final acceptedVersion = version.copyWith(
      status: TranslationVersionStatus.translated,
      validationIssues: null,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    await versionRepo.update(acceptedVersion);

    ref.read(loggingServiceProvider).info(
      'Translation accepted despite issues',
      {'unitKey': issue.unitKey, 'versionId': issue.versionId},
    );
    refreshProviders();
  }

  /// Replace the translation text, mark as manually edited and clear issues.
  Future<void> handleEditTranslation(
    batch.ValidationIssue issue,
    String newText,
  ) async {
    final versionRepo =
        ref.read(shared_repo.translationVersionRepositoryProvider);

    final versionResult = await versionRepo.getById(issue.versionId);
    if (versionResult.isErr) {
      ref.read(loggingServiceProvider).error(
        'Failed to load version for editing',
        {'versionId': issue.versionId},
      );
      return;
    }

    final version = versionResult.unwrap();
    final editedVersion = version.copyWith(
      translatedText: newText,
      status: TranslationVersionStatus.translated,
      validationIssues: null,
      isManuallyEdited: true,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    await versionRepo.update(editedVersion);

    ref.read(loggingServiceProvider).info(
      'Translation manually corrected',
      {'unitKey': issue.unitKey, 'versionId': issue.versionId},
    );
    refreshProviders();
  }
}
