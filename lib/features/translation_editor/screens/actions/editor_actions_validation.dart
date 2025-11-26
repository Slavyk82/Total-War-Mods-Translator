import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../models/domain/translation_version.dart';
import '../../../../providers/batch/batch_operations_provider.dart' as batch;
import '../../../../services/validation/models/validation_issue.dart'
    as validation;
import '../../../translation/widgets/batch_validation_dialog.dart';
import '../../providers/editor_providers.dart';
import '../../widgets/editor_dialogs.dart';
import 'editor_actions_base.dart';

/// Mixin handling validation operations
mixin EditorActionsValidation on EditorActionsBase {
  Future<void> handleValidate() async {
    try {
      final projectLanguageId = await getProjectLanguageId();
      final versionRepo = ref.read(translationVersionRepositoryProvider);
      final unitRepo = ref.read(translationUnitRepositoryProvider);
      final validationService = ref.read(validationServiceProvider);

      final versionsResult =
          await versionRepo.getByProjectLanguage(projectLanguageId);
      if (versionsResult.isErr) {
        throw Exception('Failed to load translations');
      }

      final versions = versionsResult.unwrap();

      ref.read(loggingServiceProvider).info(
        'Validation starting',
        {'totalVersions': versions.length},
      );

      if (versions.isEmpty) {
        if (mounted) {
          EditorDialogs.showInfoDialog(
            context,
            'No translations to validate',
            'Please add some translations first.',
          );
        }
        return;
      }

      if (!mounted) return;

      final validationResults = await _validateAllVersions(
        versions: versions,
        versionRepo: versionRepo,
        unitRepo: unitRepo,
        validationService: validationService,
      );

      refreshProviders();

      if (mounted) {
        await _showValidationResults(validationResults);
      }

      _logValidationComplete(versions.length, validationResults);
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to validate translations',
        e,
        stackTrace,
      );
      if (mounted) {
        EditorDialogs.showErrorDialog(context, 'Validation failed', e.toString());
      }
    }
  }

  Future<_ValidationResults> _validateAllVersions({
    required List<dynamic> versions,
    required dynamic versionRepo,
    required dynamic unitRepo,
    required dynamic validationService,
  }) async {
    int validatedCount = 0;
    int skippedCount = 0;
    int totalIssuesCount = 0;
    final allIssues = <batch.ValidationIssue>[];

    for (final version in versions) {
      if (version.translatedText == null || version.translatedText!.isEmpty) {
        skippedCount++;
        continue;
      }

      final unitResult = await unitRepo.getById(version.unitId);
      if (unitResult.isErr) {
        ref.read(loggingServiceProvider).warning(
          'Failed to load unit for validation',
          {'versionId': version.id, 'unitId': version.unitId},
        );
        skippedCount++;
        continue;
      }

      final unit = unitResult.unwrap();

      final validationResult = await validationService.validateTranslation(
        sourceText: unit.sourceText,
        translatedText: version.translatedText!,
        context: unit.context,
      );

      if (validationResult.isOk) {
        final issues = validationResult.unwrap();

        if (issues.isNotEmpty) {
          await _updateVersionWithIssues(versionRepo, version, issues);
          totalIssuesCount += (issues.length as int);

          for (final issue in issues) {
            allIssues.add(batch.ValidationIssue(
              unitKey: unit.key,
              unitId: unit.id,
              versionId: version.id,
              severity: toBatchSeverity(issue.severity),
              issueType: getIssueTypeLabel(issue.type),
              description: issue.description,
              sourceText: unit.sourceText,
              translatedText: version.translatedText!,
            ));
          }
        } else {
          await _clearVersionIssues(versionRepo, version);
        }

        validatedCount++;
      }
    }

    return _ValidationResults(
      validatedCount: validatedCount,
      skippedCount: skippedCount,
      totalIssuesCount: totalIssuesCount,
      allIssues: allIssues,
    );
  }

  Future<void> _updateVersionWithIssues(
    dynamic versionRepo,
    dynamic version,
    List<validation.ValidationIssue> issues,
  ) async {
    final issuesJson = issues
        .map((issue) => {
              'type': issue.type,
              'severity': issue.severity.toString(),
              'description': issue.description,
              'suggestion': issue.suggestion,
              'autoFixable': issue.autoFixable,
              'autoFixValue': issue.autoFixValue,
            })
        .toList();

    // Set status to needsReview when there are validation issues (errors or warnings)
    final updatedVersion = version.copyWith(
      status: TranslationVersionStatus.needsReview,
      validationIssues: issuesJson.toString(),
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    await versionRepo.update(updatedVersion);
  }

  Future<void> _clearVersionIssues(dynamic versionRepo, dynamic version) async {
    // If version had issues before (needsReview status) or has validation issues,
    // clear them and set status to translated
    if (version.validationIssues != null || 
        version.status == TranslationVersionStatus.needsReview) {
      final updatedVersion = version.copyWith(
        status: TranslationVersionStatus.translated,
        validationIssues: null,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      await versionRepo.update(updatedVersion);
    }
  }

  Future<void> _showValidationResults(_ValidationResults results) async {
    final passedCount = results.validatedCount -
        results.allIssues.map((i) => i.unitId).toSet().length;

    ref.read(loggingServiceProvider).debug(
      'Setting validation results',
      {
        'issuesCount': results.allIssues.length,
        'validatedCount': results.validatedCount,
        'passedCount': passedCount,
      },
    );

    ref.read(batch.batchValidationResultsProvider.notifier).setResults(
      issues: results.allIssues,
      totalValidated: results.validatedCount,
      passedCount: passedCount,
    );

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => BatchValidationDialog(
        issues: results.allIssues,
        totalValidated: results.validatedCount,
        passedCount: passedCount,
        onExportReport: (filePath) async {
          await exportValidationReport(filePath, results.allIssues);
        },
        onRejectTranslation: (issue) => _handleRejectTranslation(issue),
        onAcceptTranslation: (issue) => _handleAcceptTranslation(issue),
      ),
    );

    // Refresh providers after dialog closes to reflect any changes
    refreshProviders();
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
      confidenceScore: null,
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
      validationIssues: null,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    await versionRepo.update(acceptedVersion);

    ref.read(loggingServiceProvider).info(
      'Translation accepted despite issues',
      {'unitKey': issue.unitKey, 'versionId': issue.versionId},
    );
  }

  void _logValidationComplete(int totalVersions, _ValidationResults results) {
    ref.read(loggingServiceProvider).info(
      'Validation completed',
      {
        'totalVersions': totalVersions,
        'validatedCount': results.validatedCount,
        'skippedCount': results.skippedCount,
        'issuesCount': results.totalIssuesCount,
        'affectedUnits': results.allIssues.map((i) => i.unitId).toSet().length,
      },
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
      if (mounted) {
        EditorDialogs.showErrorDialog(
          context,
          'Export Failed',
          'Failed to export validation report: ${e.toString()}',
        );
      }
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

class _ValidationResults {
  final int validatedCount;
  final int skippedCount;
  final int totalIssuesCount;
  final List<batch.ValidationIssue> allIssues;

  _ValidationResults({
    required this.validatedCount,
    required this.skippedCount,
    required this.totalIssuesCount,
    required this.allIssues,
  });
}
