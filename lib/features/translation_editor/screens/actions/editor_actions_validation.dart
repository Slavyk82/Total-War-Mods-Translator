import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../models/domain/translation_version.dart';
import '../../../../providers/batch/batch_operations_provider.dart' as batch;
import '../../../../services/service_locator.dart';
import '../../../../services/translation/i_validation_service.dart';
import '../../providers/editor_providers.dart';
import '../../widgets/editor_dialogs.dart';
import '../validation_review_screen.dart';
import 'editor_actions_base.dart';

/// Mixin handling validation operations
mixin EditorActionsValidation on EditorActionsBase {
  Future<void> handleValidate() async {
    try {
      final projectLanguageId = await getProjectLanguageId();
      final versionRepo = ref.read(translationVersionRepositoryProvider);
      final unitRepo = ref.read(translationUnitRepositoryProvider);

      // Get all versions for this project language
      final versionsResult =
          await versionRepo.getByProjectLanguage(projectLanguageId);
      if (versionsResult.isErr) {
        throw Exception('Failed to load translations');
      }

      final allVersions = versionsResult.unwrap();

      // Filter only versions with "needsReview" status
      final needsReviewVersions = allVersions
          .where((v) => v.status == TranslationVersionStatus.needsReview)
          .toList();

      // Count total translated for statistics
      final translatedCount = allVersions
          .where((v) =>
              v.translatedText != null && v.translatedText!.isNotEmpty)
          .length;

      ref.read(loggingServiceProvider).info(
        'Loading validation issues',
        {
          'totalVersions': allVersions.length,
          'translated': translatedCount,
          'needsReview': needsReviewVersions.length,
        },
      );

      if (needsReviewVersions.isEmpty) {
        if (!context.mounted) return;
        EditorDialogs.showInfoDialog(
          context,
          'No issues to review',
          'All translations have passed validation.',
        );
        return;
      }

      if (!context.mounted) return;

      // Build validation issues from needsReview versions
      final allIssues = <batch.ValidationIssue>[];

      for (final version in needsReviewVersions) {
        final unitResult = await unitRepo.getById(version.unitId);
        if (unitResult.isErr) continue;

        final unit = unitResult.unwrap();

        // Parse validation issues from the stored JSON
        final issues = _parseValidationIssues(version.validationIssues);

        for (final issue in issues) {
          allIssues.add(batch.ValidationIssue(
            unitKey: unit.key,
            unitId: unit.id,
            versionId: version.id,
            severity: issue.severity == 'error'
                ? batch.ValidationSeverity.error
                : batch.ValidationSeverity.warning,
            issueType: issue.type,
            description: issue.description,
            sourceText: unit.sourceText,
            translatedText: version.translatedText ?? '',
          ));
        }
      }

      final passedCount = translatedCount - needsReviewVersions.length;

      ref.read(batch.batchValidationResultsProvider.notifier).setResults(
        issues: allIssues,
        totalValidated: translatedCount,
        passedCount: passedCount,
      );

      if (!context.mounted) return;

      // Navigate to full-screen validation review
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (routeContext) => ValidationReviewScreen(
            issues: allIssues,
            totalValidated: translatedCount,
            passedCount: passedCount,
            onExportReport: (filePath, issues) async {
              await exportValidationReport(filePath, issues);
            },
            onRejectTranslation: (issue) => _handleRejectTranslation(issue),
            onAcceptTranslation: (issue) => _handleAcceptTranslation(issue),
            onEditTranslation: (issue, newText) =>
                _handleEditTranslation(issue, newText),
            onClose: () => Navigator.of(routeContext).pop(),
          ),
        ),
      );

      // Refresh providers after screen closes
      refreshProviders();
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to load validation issues',
        e,
        stackTrace,
      );
      if (!context.mounted) return;
      EditorDialogs.showErrorDialog(
          context, 'Failed to load validation issues', e.toString());
    }
  }

  /// Rescan all translations and update validation statuses.
  ///
  /// Re-runs the validation service on every translated entry,
  /// updating the status (translated / needsReview) and storing
  /// the validation issues JSON in the database.
  Future<void> handleRescanValidation() async {
    try {
      final projectLanguageId = await getProjectLanguageId();
      final versionRepo = ref.read(translationVersionRepositoryProvider);
      final unitRepo = ref.read(translationUnitRepositoryProvider);
      final validationService = ServiceLocator.get<IValidationService>();
      final logger = ref.read(loggingServiceProvider);

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
        if (!context.mounted) return;
        EditorDialogs.showInfoDialog(
          context,
          'Nothing to scan',
          'No translated entries found.',
        );
        return;
      }

      logger.info(
        'Starting full validation rescan',
        {'totalToScan': translatedVersions.length},
      );

      // Show progress dialog
      if (!context.mounted) return;
      final progressNotifier = ValueNotifier<String>(
        'Scanning 0/${translatedVersions.length}...',
      );

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Validation Rescan'),
              ],
            ),
            content: ValueListenableBuilder<String>(
              valueListenable: progressNotifier,
              builder: (_, message, _) => Text(message),
            ),
          ),
        ),
      );

      // Run the scan
      var scanned = 0;
      var newIssues = 0;
      var cleared = 0;
      var unchanged = 0;

      for (final version in translatedVersions) {
        scanned++;
        if (scanned % 50 == 0 || scanned == translatedVersions.length) {
          progressNotifier.value =
              'Scanning $scanned/${translatedVersions.length}...';
        }

        // Get the unit for source text
        final unitResult = await unitRepo.getById(version.unitId);
        if (unitResult.isErr) continue;
        final unit = unitResult.unwrap();

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
            newValidationIssues = result.allMessages.toString();
          }
        }

        // Check if status changed
        final statusChanged = version.status != newStatus;
        final issuesChanged =
            version.validationIssues != newValidationIssues;

        if (statusChanged || issuesChanged) {
          // Build updated version manually to allow setting null
          final updatedVersion = TranslationVersion(
            id: version.id,
            unitId: version.unitId,
            projectLanguageId: version.projectLanguageId,
            translatedText: version.translatedText,
            isManuallyEdited: version.isManuallyEdited,
            status: newStatus,
            translationSource: version.translationSource,
            validationIssues: newValidationIssues,
            createdAt: version.createdAt,
            updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
          await versionRepo.update(updatedVersion);

          if (newStatus == TranslationVersionStatus.needsReview) {
            newIssues++;
          } else {
            cleared++;
          }
        } else {
          unchanged++;
        }
      }

      logger.info(
        'Validation rescan complete',
        {
          'scanned': scanned,
          'newIssues': newIssues,
          'cleared': cleared,
          'unchanged': unchanged,
        },
      );

      // Close progress dialog and show results
      if (!context.mounted) return;
      Navigator.of(context).pop();
      progressNotifier.dispose();

      refreshProviders();

      if (!context.mounted) return;
      EditorDialogs.showInfoDialog(
        context,
        'Rescan Complete',
        'Scanned $scanned translations:\n'
            '  - $newIssues flagged as needs review\n'
            '  - $cleared cleared (now valid)\n'
            '  - $unchanged unchanged',
      );
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Validation rescan failed',
        e,
        stackTrace,
      );
      // Try to close progress dialog if still open
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      if (!context.mounted) return;
      EditorDialogs.showErrorDialog(
        context,
        'Rescan Failed',
        e.toString(),
      );
    }
  }

  /// Parse validation issues from stored JSON string
  List<_StoredValidationIssue> _parseValidationIssues(String? issuesJson) {
    if (issuesJson == null || issuesJson.isEmpty) {
      return [];
    }

    try {
      // The issues are stored as a list of maps in string format
      // Example: [{type: ..., severity: ..., description: ...}, ...]
      final issues = <_StoredValidationIssue>[];

      // Extract key info using regex
      // Match patterns like {type: missing_tags, severity: error, description: ...}
      final pattern = RegExp(
          r'\{[^}]*type:\s*([^,}]+)[^}]*severity:\s*([^,}]+)[^}]*description:\s*([^,}]+)');
      final matches = pattern.allMatches(issuesJson);

      for (final match in matches) {
        issues.add(_StoredValidationIssue(
          type: match.group(1)?.trim() ?? 'unknown',
          severity: match.group(2)?.trim().toLowerCase() ?? 'warning',
          description: match.group(3)?.trim() ?? '',
        ));
      }

      // Fallback: if no matches, create a generic issue
      if (issues.isEmpty && issuesJson.isNotEmpty) {
        issues.add(_StoredValidationIssue(
          type: 'validation_issue',
          severity: 'warning',
          description: 'Translation needs review',
        ));
      }

      return issues;
    } catch (e) {
      ref.read(loggingServiceProvider).warning(
        'Failed to parse validation issues',
        {'json': issuesJson, 'error': e.toString()},
      );
      return [
        _StoredValidationIssue(
          type: 'validation_issue',
          severity: 'warning',
          description: 'Translation needs review',
        ),
      ];
    }
  }

  /// Reject a translation by clearing it
  Future<void> _handleRejectTranslation(batch.ValidationIssue issue) async {
    final versionRepo = ref.read(translationVersionRepositoryProvider);

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
  }

  /// Accept a translation despite validation issues (clears the validation flag)
  Future<void> _handleAcceptTranslation(batch.ValidationIssue issue) async {
    final versionRepo = ref.read(translationVersionRepositoryProvider);

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
  }

  /// Edit a translation manually with corrected text
  Future<void> _handleEditTranslation(
    batch.ValidationIssue issue,
    String newText,
  ) async {
    final versionRepo = ref.read(translationVersionRepositoryProvider);

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
  }

  Future<void> exportValidationReport(
    String filePath,
    List<batch.ValidationIssue> issues,
  ) async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('Validation Report');
      buffer.writeln('=' * 80);
      buffer.writeln('Generated: ${DateTime.now()}');
      buffer.writeln('Total Issues: ${issues.length}');
      buffer.writeln();

      final errors =
          issues.where((i) => i.severity == batch.ValidationSeverity.error).toList();
      final warnings =
          issues.where((i) => i.severity == batch.ValidationSeverity.warning).toList();

      if (errors.isNotEmpty) {
        buffer.writeln('ERRORS (${errors.length})');
        buffer.writeln('-' * 80);
        for (final issue in errors) {
          _writeIssueToBuffer(buffer, issue);
        }
      }

      if (warnings.isNotEmpty) {
        buffer.writeln('WARNINGS (${warnings.length})');
        buffer.writeln('-' * 80);
        for (final issue in warnings) {
          _writeIssueToBuffer(buffer, issue);
        }
      }

      await File(filePath).writeAsString(buffer.toString());

      ref.read(loggingServiceProvider).info(
        'Validation report exported',
        {'filePath': filePath, 'issueCount': issues.length},
      );
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to export validation report',
        e,
        stackTrace,
      );
      if (!context.mounted) return;
      EditorDialogs.showErrorDialog(
        context,
        'Export Failed',
        'Failed to export validation report: ${e.toString()}',
      );
    }
  }

  void _writeIssueToBuffer(StringBuffer buffer, batch.ValidationIssue issue) {
    buffer.writeln('Key: ${issue.unitKey}');
    buffer.writeln('Type: ${issue.issueType}');
    buffer.writeln('Description: ${issue.description}');
    buffer.writeln();
    buffer.writeln('Source:');
    buffer.writeln(issue.sourceText);
    buffer.writeln();
    buffer.writeln('Translation:');
    buffer.writeln(issue.translatedText);
    buffer.writeln();
    buffer.writeln('-' * 40);
    buffer.writeln();
  }
}

/// Represents a stored validation issue parsed from the database
class _StoredValidationIssue {
  final String type;
  final String severity;
  final String description;

  _StoredValidationIssue({
    required this.type,
    required this.severity,
    required this.description,
  });
}
