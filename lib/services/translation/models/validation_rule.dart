/// Identifier of the specific validation rule that produced an issue.
///
/// Persisted alongside each validation issue so the UI can show which rule
/// triggered the flag and downstream consumers can filter by rule.
enum ValidationRule {
  completeness,
  length,
  variables,
  markup,
  encoding,
  glossary,
  security,
  truncation,
  endPunctuation,
  numbers;

  /// Stable code name used for JSON persistence. Identical to the Dart
  /// enum name; declared explicitly so consumers do not accidentally rely
  /// on `toString()` output, which is compiler-dependent.
  String get codeName => name;

  /// Inverse of [codeName]. Returns null for unknown inputs so callers can
  /// decide how to react (e.g. surface as a `legacy` row instead of crashing).
  static ValidationRule? fromCodeName(String value) {
    for (final r in values) {
      if (r.codeName == value) return r;
    }
    return null;
  }
}

extension ValidationRuleDisplay on ValidationRule {
  /// Short English label for the "Issue Type" column.
  String get label {
    switch (this) {
      case ValidationRule.completeness:
        return 'Completeness';
      case ValidationRule.length:
        return 'Length';
      case ValidationRule.variables:
        return 'Variables';
      case ValidationRule.markup:
        return 'Markup tags';
      case ValidationRule.encoding:
        return 'Encoding';
      case ValidationRule.glossary:
        return 'Glossary';
      case ValidationRule.security:
        return 'Security';
      case ValidationRule.truncation:
        return 'Truncation';
      case ValidationRule.endPunctuation:
        return 'Punctuation';
      case ValidationRule.numbers:
        return 'Numbers';
    }
  }
}
