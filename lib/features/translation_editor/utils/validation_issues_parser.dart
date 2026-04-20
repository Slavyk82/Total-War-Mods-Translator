import 'dart:convert';

import 'package:twmt/models/common/validation_issue_entry.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart' as batch;
import 'package:twmt/services/translation/models/translation_exceptions.dart';

/// Decoded validation issue ready for UI consumption.
class ParsedValidationIssue {
  /// Rule code (e.g. `variables`) or `'legacy'` when the payload predates
  /// structured persistence or fails to decode.
  final String type;
  final ValidationSeverity severity;
  final String description;

  const ParsedValidationIssue({
    required this.type,
    required this.severity,
    required this.description,
  });
}

/// Decode a row's `validation_issues` payload.
///
/// Any payload written by schema version >= 1 is a JSON array of
/// `{rule, severity, message}` objects. Anything else is treated as legacy
/// and surfaced as a single `type: 'legacy'` entry so the UI still shows
/// something actionable.
List<ParsedValidationIssue> parseValidationIssues(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];

  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      if (decoded.isEmpty) return const [];

      // Structured entries are maps; legacy entries are strings.
      if (decoded.first is Map) {
        return decoded
            .cast<Map>()
            .map((m) => ValidationIssueEntry.fromJson(
                Map<String, dynamic>.from(m)))
            .map((e) => ParsedValidationIssue(
                  type: e.rule?.codeName ?? 'legacy',
                  severity: e.severity,
                  description: e.message,
                ))
            .toList();
      }

      // Legacy `List<String>` — surface as a single lumped entry so the
      // user sees the pending rescan message until the startup gate
      // re-validates this row.
      return [
        ParsedValidationIssue(
          type: 'legacy',
          severity: ValidationSeverity.warning,
          description: decoded
              .map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .join(' • '),
        ),
      ];
    }
  } catch (_) {
    // fall through to legacy fallback
  }
  return [
    ParsedValidationIssue(
      type: 'legacy',
      severity: ValidationSeverity.warning,
      description: raw,
    ),
  ];
}

/// Coarse severity bucket used by the editor filter state and the inspector
/// when building a `batch.ValidationIssue`. The batch enum only has `error`
/// and `warning`, so `critical` folds into `error` — both surface in the
/// "Errors" pill.
batch.ValidationSeverity bucketSeverity(ValidationSeverity severity) {
  switch (severity) {
    case ValidationSeverity.error:
    case ValidationSeverity.critical:
      return batch.ValidationSeverity.error;
    case ValidationSeverity.warning:
      return batch.ValidationSeverity.warning;
  }
}
