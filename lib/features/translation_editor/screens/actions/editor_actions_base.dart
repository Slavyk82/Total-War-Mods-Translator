import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/i18n/strings.g.dart';
import '../../../../services/validation/models/validation_issue.dart' as validation;
import '../../../../providers/batch/batch_operations_provider.dart' as batch;
import '../../../projects/providers/projects_screen_providers.dart'
    show projectsWithDetailsProvider, translationStatsVersionProvider;
import '../../../../providers/shared/repository_providers.dart' as shared_repo;
import '../../providers/editor_providers.dart';

/// Base mixin providing common functionality for editor actions
mixin EditorActionsBase {
  WidgetRef get ref;
  BuildContext get context;
  String get projectId;
  String get languageId;

  bool get mounted => context.mounted;

  /// Get the project_language_id from project_id and language_id
  Future<String> getProjectLanguageId() async {
    final projectLanguageRepo = ref.read(shared_repo.projectLanguageRepositoryProvider);
    final projectLanguagesResult =
        await projectLanguageRepo.getByProject(projectId);

    if (projectLanguagesResult.isErr) {
      throw Exception('Failed to load project languages');
    }

    final projectLanguages = projectLanguagesResult.unwrap();
    final projectLanguage = projectLanguages.firstWhere(
      (pl) => pl.languageId == languageId,
      orElse: () => throw Exception('Project language not found'),
    );

    return projectLanguage.id;
  }

  /// Refresh all relevant providers after data changes
  void refreshProviders() {
    if (!mounted) return;
    ref.invalidate(translationRowsProvider(projectId, languageId));
    ref.invalidate(editorStatsProvider(projectId, languageId));
    ref.invalidate(projectsWithDetailsProvider);
    // Increment version to trigger refresh of pack compilation stats
    ref.read(translationStatsVersionProvider.notifier).increment();
  }

  /// Convert validation issue type to readable label
  String getIssueTypeLabel(validation.ValidationIssueType type) {
    final types = t.translationEditor.issueTypes;
    switch (type) {
      case validation.ValidationIssueType.emptyTranslation:
        return types.emptyTranslation;
      case validation.ValidationIssueType.lengthDifference:
        return types.lengthDifference;
      case validation.ValidationIssueType.missingVariables:
        return types.missingVariables;
      case validation.ValidationIssueType.whitespaceIssue:
        return types.whitespaceIssue;
      case validation.ValidationIssueType.punctuationMismatch:
        return types.punctuationMismatch;
      case validation.ValidationIssueType.caseMismatch:
        return types.caseMismatch;
      case validation.ValidationIssueType.missingNumbers:
        return types.missingNumbers;
      case validation.ValidationIssueType.modifiedNumbers:
        return types.modifiedNumbers;
    }
  }

  /// Convert internal validation severity to batch severity
  batch.ValidationSeverity toBatchSeverity(
      validation.ValidationSeverity severity) {
    return severity == validation.ValidationSeverity.error
        ? batch.ValidationSeverity.error
        : batch.ValidationSeverity.warning;
  }
}
