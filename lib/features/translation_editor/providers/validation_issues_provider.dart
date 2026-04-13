import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/services/validation/models/validation_issue.dart';
import 'package:twmt/providers/shared/service_providers.dart' as shared_svc;
import 'package:twmt/providers/shared/logging_providers.dart';

part 'validation_issues_provider.g.dart';

/// Provider for validation issues for a specific translation
///
/// Validates the translation against the source text and returns
/// any issues found (errors, warnings, info).
@riverpod
Future<List<ValidationIssue>> validationIssues(
  Ref ref,
  String sourceText,
  String translatedText,
) async {
  final validationSvc = ref.watch(shared_svc.translationValidationServiceProvider);

  final result = await validationSvc.validateTranslation(
    sourceText: sourceText,
    translatedText: translatedText,
  );

  return result.when(
    ok: (issues) => issues,
    err: (error) {
      // Log error and return empty list
      final logger = ref.read(loggingServiceProvider);
      logger.error('Failed to validate translation: $error');
      return <ValidationIssue>[];
    },
  );
}
