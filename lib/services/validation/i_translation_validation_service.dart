import 'package:twmt/services/validation/models/validation_issue.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';

/// Service interface for validating translations
abstract class ITranslationValidationService {
  /// Validates a translation against its source text
  ///
  /// Returns a list of validation issues found. Empty list means no issues.
  Future<Result<List<ValidationIssue>, ServiceException>> validateTranslation({
    required String sourceText,
    required String translatedText,
    String? context,
  });

  /// Applies an auto-fix to a translation
  ///
  /// Returns the fixed translation text
  Future<Result<String, ServiceException>> applyAutoFix({
    required String translatedText,
    required ValidationIssue issue,
  });

  /// Applies all auto-fixable issues to a translation
  ///
  /// Returns the fixed translation text
  Future<Result<String, ServiceException>> applyAllAutoFixes({
    required String sourceText,
    required String translatedText,
    required List<ValidationIssue> issues,
  });
}
