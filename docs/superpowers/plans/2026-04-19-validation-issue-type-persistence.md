# Validation Issue Type Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist the specific validation rule that triggered each issue so the Validation Review screen's "Issue Type" column finally shows meaningful per-rule labels, plus run a one-shot blocking rescan at app startup to migrate all existing validation data to the new structured format.

**Architecture:** Introduce a `ValidationRule` enum carried through `ValidationError` → a new `ValidationIssueEntry` → `ValidationResult.issues` → JSON-encoded payloads in `translation_versions.validation_issues`. Add a `validation_schema_version` column as the resume-safe progress marker. Run the rescan from a new `ValidationRescanDialog` gated off the existing startup-tasks widget, with paged scans, 100-unit commit batches, moving-average ETA, and auto-resume on next launch if interrupted.

**Tech Stack:** Flutter Desktop Windows, Riverpod, sqflite_common_ffi, syncfusion_flutter_datagrid, existing `Migration` / `MigrationRegistry` infrastructure, existing `ValidationServiceImpl` check architecture.

**Related spec:** `docs/superpowers/specs/2026-04-19-validation-issue-type-persistence-design.md`

---

## File Map

**Create**
- `lib/services/translation/models/validation_rule.dart` — enum + humanised label extension
- `lib/models/common/validation_issue_entry.dart` — `{rule, severity, message}` value object
- `lib/services/database/migrations/migration_validation_schema_version.dart` — `ALTER TABLE` adding `validation_schema_version`
- `lib/services/validation/validation_rescan_service.dart` — paged + batched rescan orchestrator
- `lib/features/bootstrap/providers/validation_rescan_provider.dart` — Riverpod state for the rescan dialog
- `lib/features/bootstrap/widgets/validation_rescan_dialog.dart` — blocking progress dialog
- Tests mirroring each new production file

**Modify**
- `lib/services/translation/models/translation_exceptions.dart` — add `rule` to `ValidationError`
- `lib/services/translation/validation_service_impl.dart` — pass `rule` on every `ValidationError`; populate `ValidationResult.issues`
- `lib/models/common/validation_result.dart` — add `issues` field; derive `errors`/`warnings`/`allMessages` from it
- `lib/services/translation/handlers/validation_persistence_handler.dart` — write structured JSON + `schema_version = 1`
- `lib/features/translation_editor/screens/actions/editor_actions_validation.dart` — same writer change; replace regex reader with `jsonDecode`
- `lib/features/translation_editor/widgets/validation_review_data_source.dart` — humanised label cell
- `lib/repositories/translation_version_repository.dart` (+ batch mixin) — new paging / counting / schema-bump methods
- `lib/services/database/migrations/migration_registry.dart` — register new migration
- `lib/main.dart` — run `ValidationRescanDialog.showAndRun` between data migrations and `_continueStartupTasks`

---

## Task 1: Introduce `ValidationRule` enum

**Files:**
- Create: `lib/services/translation/models/validation_rule.dart`
- Test: `test/unit/services/translation/models/validation_rule_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/services/translation/models/validation_rule_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';

void main() {
  group('ValidationRule.label', () {
    test('humanises every rule', () {
      const expected = {
        ValidationRule.completeness: 'Completeness',
        ValidationRule.length: 'Length',
        ValidationRule.variables: 'Variables',
        ValidationRule.markup: 'Markup tags',
        ValidationRule.encoding: 'Encoding',
        ValidationRule.glossary: 'Glossary',
        ValidationRule.security: 'Security',
        ValidationRule.truncation: 'Truncation',
        ValidationRule.repeatedWord: 'Repeated word',
        ValidationRule.endPunctuation: 'Punctuation',
        ValidationRule.numbers: 'Numbers',
      };
      for (final entry in expected.entries) {
        expect(entry.key.label, entry.value,
            reason: 'Label mismatch for ${entry.key}');
      }
      // Guard: if the enum grows, this will fail and force the label update.
      expect(ValidationRule.values.length, expected.length);
    });

    test('codeName is the enum name for JSON persistence', () {
      expect(ValidationRule.variables.codeName, 'variables');
      expect(ValidationRule.repeatedWord.codeName, 'repeatedWord');
    });

    test('fromCodeName round-trips every value', () {
      for (final r in ValidationRule.values) {
        expect(ValidationRule.fromCodeName(r.codeName), r);
      }
    });

    test('fromCodeName returns null for unknown values', () {
      expect(ValidationRule.fromCodeName('no_such_rule'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation/models/validation_rule_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Create the enum**

```dart
// lib/services/translation/models/validation_rule.dart

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
  repeatedWord,
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
      case ValidationRule.repeatedWord:
        return 'Repeated word';
      case ValidationRule.endPunctuation:
        return 'Punctuation';
      case ValidationRule.numbers:
        return 'Numbers';
    }
  }
}
```

- [ ] **Step 4: Run test**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation/models/validation_rule_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/translation/models/validation_rule.dart test/unit/services/translation/models/validation_rule_test.dart
git commit -m "feat: add ValidationRule enum with humanised labels"
```

---

## Task 2: Add `rule` field to `ValidationError`

**Files:**
- Modify: `lib/services/translation/models/translation_exceptions.dart:70-85`
- Test: `test/unit/services/translation/models/translation_exceptions_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/services/translation/models/translation_exceptions_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';

void main() {
  group('ValidationError', () {
    test('stores the rule identifier', () {
      const error = ValidationError(
        rule: ValidationRule.variables,
        field: 'unit.title',
        message: 'Missing variables: {0}',
        severity: ValidationSeverity.error,
      );
      expect(error.rule, ValidationRule.variables);
      expect(error.severity, ValidationSeverity.error);
      expect(error.message, 'Missing variables: {0}');
      expect(error.field, 'unit.title');
    });

    test('toString includes the rule name', () {
      const error = ValidationError(
        rule: ValidationRule.length,
        field: 'unit.body',
        message: 'Translation length differs significantly',
      );
      expect(error.toString(), contains('length'));
      expect(error.toString(), contains('Translation length'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation/models/translation_exceptions_test.dart`
Expected: FAIL — `The named parameter 'rule' isn't defined`.

- [ ] **Step 3: Add the field**

Replace the `ValidationError` class body at `lib/services/translation/models/translation_exceptions.dart:70-85`:

```dart
class ValidationError {
  final ValidationRule rule;
  final String field;
  final String message;
  final String? value;
  final ValidationSeverity severity;

  const ValidationError({
    required this.rule,
    required this.field,
    required this.message,
    this.value,
    this.severity = ValidationSeverity.error,
  });

  @override
  String toString() =>
      '[${rule.codeName}] $field: $message${value != null ? ' (value: $value)' : ''}';
}
```

Add the import at the top of the file:

```dart
import 'validation_rule.dart';
```

- [ ] **Step 4: Run the test**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation/models/translation_exceptions_test.dart`
Expected: PASS (2 tests). The rest of the codebase now fails to compile — that is fixed in the next task.

- [ ] **Step 5: Commit**

```bash
git add lib/services/translation/models/translation_exceptions.dart test/unit/services/translation/models/translation_exceptions_test.dart
git commit -m "feat: add rule field to ValidationError"
```

---

## Task 3: Wire `ValidationRule` into every check in `ValidationServiceImpl`

**Files:**
- Modify: `lib/services/translation/validation_service_impl.dart`
- Test: `test/unit/services/translation/validation_service_impl_rules_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/services/translation/validation_service_impl_rules_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';
import 'package:twmt/services/translation/validation_service_impl.dart';

import '../../../helpers/noop_logger.dart';

void main() {
  late ValidationServiceImpl svc;

  setUp(() {
    svc = ValidationServiceImpl(logger: NoopLogger());
  });

  group('each check tags its rule', () {
    test('completeness -> ValidationRule.completeness', () async {
      final err = await svc.checkCompleteness(translatedText: '  ', key: 'k');
      expect(err?.rule, ValidationRule.completeness);
    });

    test('length (ratio) -> ValidationRule.length', () async {
      final err = await svc.checkLength(
        sourceText: 'short',
        translatedText: 'x' * 200,
        key: 'k',
      );
      expect(err?.rule, ValidationRule.length);
    });

    test('missing variables -> ValidationRule.variables', () async {
      final err = await svc.checkVariablePreservation(
        sourceText: 'Hello {0}',
        translatedText: 'Bonjour',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.variables);
    });

    test('extra variables -> ValidationRule.variables', () async {
      final err = await svc.checkVariablePreservation(
        sourceText: 'Bonjour',
        translatedText: 'Bonjour {0}',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.variables);
    });

    test('markup tag count mismatch -> ValidationRule.markup', () async {
      final err = await svc.checkMarkupPreservation(
        sourceText: '<b>Hi</b>',
        translatedText: 'Salut',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.markup);
    });

    test('encoding replacement char -> ValidationRule.encoding', () async {
      final err = await svc.checkEncoding(
        translatedText: 'bad \uFFFD char',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.encoding);
    });

    test('glossary miss -> ValidationRule.glossary', () async {
      final err = await svc.checkGlossaryConsistency(
        sourceText: 'Use Empire',
        translatedText: 'Utilisez Reich',
        key: 'k',
        glossaryTerms: {'Empire': 'Empire'},
      );
      expect(err?.rule, ValidationRule.glossary);
    });

    test('security <script> -> ValidationRule.security', () async {
      final err = await svc.checkSecurity(
        translatedText: 'hello <script>',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.security);
    });

    test('truncation ellipsis -> ValidationRule.truncation', () async {
      final err = await svc.checkTruncation(
        sourceText: 'A full sentence here',
        translatedText: 'A full sentence...',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.truncation);
    });

    test('repeated word -> ValidationRule.repeatedWord', () async {
      final mistakes = await svc.checkCommonMistakes(
        sourceText: 'The cat sat.',
        translatedText: 'Le le chat est assis.',
        key: 'k',
      );
      expect(
        mistakes.map((m) => m.rule),
        contains(ValidationRule.repeatedWord),
      );
    });

    test('missing ending punctuation -> ValidationRule.endPunctuation', () async {
      final mistakes = await svc.checkCommonMistakes(
        sourceText: 'Hello.',
        translatedText: 'Bonjour',
        key: 'k',
      );
      expect(
        mistakes.map((m) => m.rule),
        contains(ValidationRule.endPunctuation),
      );
    });

    test('numbers mismatch -> ValidationRule.numbers', () async {
      final mistakes = await svc.checkCommonMistakes(
        sourceText: 'There are 3 cats',
        translatedText: 'Il y a 4 chats',
        key: 'k',
      );
      expect(
        mistakes.map((m) => m.rule),
        contains(ValidationRule.numbers),
      );
    });
  });
}
```

If `test/helpers/noop_logger.dart` does not exist, create it:

```dart
// test/helpers/noop_logger.dart
import 'package:twmt/services/shared/i_logging_service.dart';

class NoopLogger implements ILoggingService {
  @override
  void debug(String message, [Map<String, dynamic>? context]) {}
  @override
  void info(String message, [Map<String, dynamic>? context]) {}
  @override
  void warning(String message, [Map<String, dynamic>? context]) {}
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}
  // Add any other ILoggingService methods here with empty bodies.
  @override
  noSuchMethod(Invocation i) => null;
}
```

> If the `ILoggingService` interface has more methods, the `noSuchMethod` catch-all keeps the helper compiling — preferred over brittle copies.

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation/validation_service_impl_rules_test.dart`
Expected: FAIL — compile errors on every `ValidationError(...)` in the service because `rule` is now required.

- [ ] **Step 3: Add `rule` to every `ValidationError` call site**

In `lib/services/translation/validation_service_impl.dart`, add the import at the top:

```dart
import 'package:twmt/services/translation/models/validation_rule.dart';
```

Then pass `rule:` on every `return ValidationError(...)` site. Mapping table (line numbers from current file; values may shift slightly):

| Method | Site | Rule |
|---|---|---|
| `checkCompleteness` | empty check | `ValidationRule.completeness` |
| `checkLength` | exceeds max | `ValidationRule.length` |
| `checkLength` | ratio | `ValidationRule.length` |
| `checkVariablePreservation` | missing simple vars | `ValidationRule.variables` |
| `checkVariablePreservation` | missing templates | `ValidationRule.variables` |
| `checkVariablePreservation` | extra vars | `ValidationRule.variables` |
| `checkMarkupPreservation` | source unbalanced | `ValidationRule.markup` |
| `checkMarkupPreservation` | count mismatch | `ValidationRule.markup` |
| `checkMarkupPreservation` | translation unbalanced | `ValidationRule.markup` |
| `checkEncoding` | replacement char | `ValidationRule.encoding` |
| `checkEncoding` | control chars | `ValidationRule.encoding` |
| `checkGlossaryConsistency` | violations | `ValidationRule.glossary` |
| `checkSecurity` | SQL | `ValidationRule.security` |
| `checkSecurity` | script | `ValidationRule.security` |
| `checkSecurity` | path traversal | `ValidationRule.security` |
| `checkTruncation` | ellipsis | `ValidationRule.truncation` |
| `checkTruncation` | too short | `ValidationRule.truncation` |
| `checkCommonMistakes` | repeated word | `ValidationRule.repeatedWord` |
| `checkCommonMistakes` | missing end punct | `ValidationRule.endPunctuation` |
| `checkCommonMistakes` | numbers | `ValidationRule.numbers` |

Example pattern for each existing site:

```dart
// BEFORE
return ValidationError(
  severity: ValidationSeverity.error,
  message: 'Translation is empty',
  field: key,
);

// AFTER
return ValidationError(
  rule: ValidationRule.completeness,
  severity: ValidationSeverity.error,
  message: 'Translation is empty',
  field: key,
);
```

- [ ] **Step 4: Run the test**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation/validation_service_impl_rules_test.dart`
Expected: PASS (12 tests).

- [ ] **Step 5: Run the full translation service suite**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation/`
Expected: PASS. Fix any previously-passing tests that now fail (they will likely be creating `ValidationError` without a `rule`; add one).

- [ ] **Step 6: Commit**

```bash
git add lib/services/translation/validation_service_impl.dart test/unit/services/translation/validation_service_impl_rules_test.dart test/helpers/noop_logger.dart
git commit -m "feat: tag each validation check with its ValidationRule"
```

---

## Task 4: Introduce `ValidationIssueEntry` value object

**Files:**
- Create: `lib/models/common/validation_issue_entry.dart`
- Test: `test/unit/models/common/validation_issue_entry_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/models/common/validation_issue_entry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/validation_issue_entry.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';

void main() {
  group('ValidationIssueEntry', () {
    test('toJson produces canonical shape', () {
      const entry = ValidationIssueEntry(
        rule: ValidationRule.variables,
        severity: ValidationSeverity.error,
        message: 'Missing variables: {0}',
      );
      expect(entry.toJson(), {
        'rule': 'variables',
        'severity': 'error',
        'message': 'Missing variables: {0}',
      });
    });

    test('fromJson round-trips a known entry', () {
      final json = {
        'rule': 'markup',
        'severity': 'warning',
        'message': 'Source text has unbalanced markup tags',
      };
      final entry = ValidationIssueEntry.fromJson(json);
      expect(entry.rule, ValidationRule.markup);
      expect(entry.severity, ValidationSeverity.warning);
      expect(entry.message, 'Source text has unbalanced markup tags');
      expect(entry.toJson(), json);
    });

    test('fromJson surfaces an unknown rule as null to let callers fallback', () {
      final entry = ValidationIssueEntry.fromJson({
        'rule': 'future_rule_code',
        'severity': 'warning',
        'message': 'unknown',
      });
      expect(entry.rule, isNull);
      expect(entry.severity, ValidationSeverity.warning);
      expect(entry.message, 'unknown');
    });

    test('equality is value-based', () {
      const a = ValidationIssueEntry(
        rule: ValidationRule.length,
        severity: ValidationSeverity.warning,
        message: 'Too long',
      );
      const b = ValidationIssueEntry(
        rule: ValidationRule.length,
        severity: ValidationSeverity.warning,
        message: 'Too long',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/unit/models/common/validation_issue_entry_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Create the class**

```dart
// lib/models/common/validation_issue_entry.dart
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';

/// Structured representation of a single validation issue, persisted in
/// `translation_versions.validation_issues` as JSON.
///
/// [rule] is nullable on decode only: JSON written by a future version may
/// reference a rule code this binary does not know yet. In that case the
/// caller is expected to surface the entry with a "legacy"/"unknown" label
/// rather than discard it.
class ValidationIssueEntry {
  final ValidationRule? rule;
  final ValidationSeverity severity;
  final String message;

  const ValidationIssueEntry({
    required this.rule,
    required this.severity,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'rule': rule?.codeName,
        'severity': severity.name,
        'message': message,
      };

  factory ValidationIssueEntry.fromJson(Map<String, dynamic> json) {
    final ruleCode = json['rule'] as String?;
    final severityCode = (json['severity'] as String?) ?? 'warning';
    return ValidationIssueEntry(
      rule: ruleCode == null ? null : ValidationRule.fromCodeName(ruleCode),
      severity: ValidationSeverity.values.firstWhere(
        (s) => s.name == severityCode,
        orElse: () => ValidationSeverity.warning,
      ),
      message: (json['message'] as String?) ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ValidationIssueEntry &&
          other.rule == rule &&
          other.severity == severity &&
          other.message == message);

  @override
  int get hashCode => Object.hash(rule, severity, message);

  @override
  String toString() =>
      'ValidationIssueEntry(rule: ${rule?.codeName ?? '<unknown>'}, '
      'severity: ${severity.name}, message: $message)';
}
```

- [ ] **Step 4: Run the test**

Run: `C:/src/flutter/bin/flutter test test/unit/models/common/validation_issue_entry_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/models/common/validation_issue_entry.dart test/unit/models/common/validation_issue_entry_test.dart
git commit -m "feat: add ValidationIssueEntry value object"
```

---

## Task 5: Add `issues` field to `ValidationResult`

**Files:**
- Modify: `lib/models/common/validation_result.dart`
- Test: `test/unit/models/common/validation_result_issues_test.dart`

> Note: `ValidationResult` currently uses `json_serializable` via `validation_result.g.dart`. After the change, run `build_runner` to regenerate.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/models/common/validation_result_issues_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/validation_issue_entry.dart';
import 'package:twmt/models/common/validation_result.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';

void main() {
  group('ValidationResult.issues', () {
    test('derives errors / warnings / allMessages from issues', () {
      const result = ValidationResult(
        isValid: false,
        issues: [
          ValidationIssueEntry(
            rule: ValidationRule.variables,
            severity: ValidationSeverity.error,
            message: 'Missing variable {0}',
          ),
          ValidationIssueEntry(
            rule: ValidationRule.length,
            severity: ValidationSeverity.warning,
            message: 'Length differs',
          ),
        ],
      );
      expect(result.errors, ['Missing variable {0}']);
      expect(result.warnings, ['Length differs']);
      expect(result.allMessages, ['Missing variable {0}', 'Length differs']);
      expect(result.hasErrors, isTrue);
      expect(result.hasWarnings, isTrue);
    });

    test('combine concatenates issues from both results', () {
      const a = ValidationResult(
        isValid: false,
        issues: [
          ValidationIssueEntry(
            rule: ValidationRule.encoding,
            severity: ValidationSeverity.error,
            message: 'enc',
          ),
        ],
      );
      const b = ValidationResult(
        isValid: true,
        issues: [
          ValidationIssueEntry(
            rule: ValidationRule.length,
            severity: ValidationSeverity.warning,
            message: 'len',
          ),
        ],
      );
      final c = a.combine(b);
      expect(c.issues.length, 2);
      expect(c.issues.map((i) => i.rule),
          [ValidationRule.encoding, ValidationRule.length]);
      expect(c.isValid, isFalse);
    });

    test('success factory produces an empty-issues, valid result', () {
      final r = ValidationResult.success();
      expect(r.isValid, isTrue);
      expect(r.issues, isEmpty);
      expect(r.allMessages, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/unit/models/common/validation_result_issues_test.dart`
Expected: FAIL — the `issues` named parameter is unknown.

- [ ] **Step 3: Rewrite `ValidationResult`**

Replace `lib/models/common/validation_result.dart` with:

```dart
import 'package:json_annotation/json_annotation.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'validation_issue_entry.dart';

part 'validation_result.g.dart';

/// Result of a validation operation.
///
/// Canonical state is [issues]: the structured list of validation findings.
/// [errors] / [warnings] / [allMessages] are kept as derived views for
/// consumers that only care about message strings.
@JsonSerializable(explicitToJson: true)
class ValidationResult {
  final bool isValid;
  final List<ValidationIssueEntry> issues;

  const ValidationResult({
    required this.isValid,
    this.issues = const [],
  });

  List<String> get errors => issues
      .where((i) => i.severity == ValidationSeverity.error)
      .map((i) => i.message)
      .toList(growable: false);

  List<String> get warnings => issues
      .where((i) => i.severity == ValidationSeverity.warning)
      .map((i) => i.message)
      .toList(growable: false);

  List<String> get allMessages =>
      issues.map((i) => i.message).toList(growable: false);

  bool get isInvalid => !isValid;
  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  String? get firstError => errors.isEmpty ? null : errors.first;

  ValidationResult combine(ValidationResult other) {
    return ValidationResult(
      isValid: isValid && other.isValid,
      issues: [...issues, ...other.issues],
    );
  }

  factory ValidationResult.success({List<ValidationIssueEntry> issues = const []}) {
    return ValidationResult(isValid: true, issues: issues);
  }

  factory ValidationResult.failure({
    required List<ValidationIssueEntry> issues,
  }) {
    return ValidationResult(isValid: false, issues: issues);
  }

  ValidationResult copyWith({
    bool? isValid,
    List<ValidationIssueEntry>? issues,
  }) {
    return ValidationResult(
      isValid: isValid ?? this.isValid,
      issues: issues ?? this.issues,
    );
  }

  factory ValidationResult.fromJson(Map<String, dynamic> json) =>
      _$ValidationResultFromJson(json);
  Map<String, dynamic> toJson() => _$ValidationResultToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ValidationResult) return false;
    if (isValid != other.isValid) return false;
    if (issues.length != other.issues.length) return false;
    for (var i = 0; i < issues.length; i++) {
      if (issues[i] != other.issues[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(isValid, issues.length);

  @override
  String toString() =>
      'ValidationResult(isValid: $isValid, issues: ${issues.length})';
}
```

Keep `FieldValidationResult` below unchanged (it lives in the same file).

- [ ] **Step 4: Regenerate `*.g.dart`**

Run: `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs`
Expected: SUCCESS — new `validation_result.g.dart` written.

- [ ] **Step 5: Fix any remaining call-sites**

Some production/test code may construct `ValidationResult(errors: [...], warnings: [...])`. Search and convert to the `issues:` form:

Run: `C:/src/flutter/bin/flutter analyze`
Fix each error by migrating to `ValidationIssueEntry` + `issues:`. The `ValidationResult.error(String)` factory is removed — replace callers with `ValidationResult.failure(issues: [...])`.

- [ ] **Step 6: Run the test**

Run: `C:/src/flutter/bin/flutter test test/unit/models/common/validation_result_issues_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 7: Run the full suite**

Run: `C:/src/flutter/bin/flutter test`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/models/common/validation_result.dart lib/models/common/validation_result.g.dart test/unit/models/common/validation_result_issues_test.dart
git add -u
git commit -m "feat: carry structured issues through ValidationResult"
```

---

## Task 6: `ValidationServiceImpl` populates `ValidationResult.issues`

**Files:**
- Modify: `lib/services/translation/validation_service_impl.dart`
- Test: `test/unit/services/translation/validation_service_impl_issues_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/services/translation/validation_service_impl_issues_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';
import 'package:twmt/services/translation/validation_service_impl.dart';

import '../../../helpers/noop_logger.dart';

void main() {
  test('validateTranslation returns structured issues, not just messages',
      () async {
    final svc = ValidationServiceImpl(logger: NoopLogger());
    final result = await svc.validateTranslation(
      sourceText: 'Hello {0}',
      translatedText: '',
      key: 'greeting',
    );

    expect(result.isOk, isTrue);
    final r = result.unwrap();
    expect(r.isValid, isFalse);
    expect(r.issues, isNotEmpty);

    // Completeness fires first on empty text.
    expect(
      r.issues.map((i) => i.rule),
      contains(ValidationRule.completeness),
    );
    for (final issue in r.issues) {
      expect(issue.rule, isNotNull);
      expect(issue.severity, isNotNull);
      expect(issue.message, isNotEmpty);
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation/validation_service_impl_issues_test.dart`
Expected: FAIL — the current implementation populates `errors`/`warnings` lists; `issues` is empty.

- [ ] **Step 3: Replace `_addError` with `_appendIssue` and build `issues`**

In `lib/services/translation/validation_service_impl.dart`:

Add at the top:

```dart
import 'package:twmt/models/common/validation_issue_entry.dart';
```

Replace the body of `validateTranslation` so it accumulates entries instead of strings:

```dart
Future<Result<common.ValidationResult, ValidationException>>
    validateTranslation({
  required String sourceText,
  required String translatedText,
  required String key,
  Map<String, String>? glossaryTerms,
  int? maxLength,
}) async {
  try {
    final issues = <ValidationIssueEntry>[];

    // completeness
    if (_config.checkCompleteness) {
      final r = await checkCompleteness(translatedText: translatedText, key: key);
      if (r != null) _appendIssue(issues, r, _config.strictMode);
    }
    // length
    if (_config.checkLength) {
      final r = await checkLength(
        sourceText: sourceText,
        translatedText: translatedText,
        key: key,
        maxLength: maxLength,
      );
      if (r != null) _appendIssue(issues, r, _config.strictMode);
    }
    // variables (always-error)
    if (_config.checkVariables) {
      final r = await checkVariablePreservation(
        sourceText: sourceText, translatedText: translatedText, key: key,
      );
      if (r != null) _appendIssue(issues, r, false);
    }
    // markup (always-error)
    if (_config.checkMarkup) {
      final r = await checkMarkupPreservation(
        sourceText: sourceText, translatedText: translatedText, key: key,
      );
      if (r != null) _appendIssue(issues, r, false);
    }
    // encoding (always-error)
    if (_config.checkEncoding) {
      final r = await checkEncoding(translatedText: translatedText, key: key);
      if (r != null) _appendIssue(issues, r, false);
    }
    // glossary
    if (_config.checkGlossary && glossaryTerms != null) {
      final r = await checkGlossaryConsistency(
        sourceText: sourceText,
        translatedText: translatedText,
        key: key,
        glossaryTerms: glossaryTerms,
      );
      if (r != null) _appendIssue(issues, r, _config.strictMode);
    }
    // security (always-error)
    if (_config.checkSecurity) {
      final r = await checkSecurity(translatedText: translatedText, key: key);
      if (r != null) _appendIssue(issues, r, false);
    }
    // truncation
    if (_config.checkTruncation) {
      final r = await checkTruncation(
        sourceText: sourceText, translatedText: translatedText, key: key,
      );
      if (r != null) _appendIssue(issues, r, _config.strictMode);
    }
    // common mistakes (already returns a list)
    if (_config.checkCommonMistakes) {
      final list = await checkCommonMistakes(
        sourceText: sourceText, translatedText: translatedText, key: key,
      );
      for (final m in list) {
        _appendIssue(issues, m, _config.strictMode);
      }
    }

    final hasErrors =
        issues.any((i) => i.severity == ValidationSeverity.error);
    return Ok(common.ValidationResult(
      isValid: !hasErrors,
      issues: issues,
    ));
  } catch (e, stackTrace) {
    return Err(ValidationException(
      'Validation failed for key $key: ${e.toString()}',
      [],
      error: e,
      stackTrace: stackTrace,
    ));
  }
}
```

Replace `_addError` with `_appendIssue`:

```dart
void _appendIssue(
  List<ValidationIssueEntry> acc,
  ValidationError error,
  bool treatWarningsAsErrors,
) {
  final effective =
      (treatWarningsAsErrors && error.severity == ValidationSeverity.warning)
          ? ValidationSeverity.error
          : error.severity;
  acc.add(ValidationIssueEntry(
    rule: error.rule,
    severity: effective,
    message: error.message,
  ));
}
```

Delete the old `_addError` helper.

Update `validateBatch`'s error-result construction to also use `issues`:

```dart
} else {
  results[key] = common.ValidationResult(
    isValid: false,
    issues: [
      ValidationIssueEntry(
        rule: ValidationRule.completeness, // defensive default for process-level failure
        severity: ValidationSeverity.error,
        message: result.error.message,
      ),
    ],
  );
}
```

- [ ] **Step 4: Run the test**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation/validation_service_impl_issues_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full suite**

Run: `C:/src/flutter/bin/flutter test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/translation/validation_service_impl.dart test/unit/services/translation/validation_service_impl_issues_test.dart
git commit -m "feat: populate ValidationResult.issues with structured entries"
```

---

## Task 7: Schema migration — add `validation_schema_version` column

**Files:**
- Create: `lib/services/database/migrations/migration_validation_schema_version.dart`
- Modify: `lib/services/database/migrations/migration_registry.dart`
- Test: `test/unit/services/database/migrations/migration_validation_schema_version_test.dart`

- [ ] **Step 1: Inspect how other column-adding migrations are tested**

Run: `C:/src/flutter/bin/grep --include="*.dart" -l "ALTER TABLE" test/unit/services/database/migrations/ 2>/dev/null || ls test/unit/services/database/migrations/ 2>/dev/null`

If no migration tests exist, still write the test below — it will be the first.

- [ ] **Step 2: Write the failing test**

```dart
// test/unit/services/database/migrations/migration_validation_schema_version_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_validation_schema_version.dart';

import '../../../../helpers/noop_logger.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseService.initializeInMemoryForTests();
    await DatabaseService.database.execute('''
      CREATE TABLE IF NOT EXISTS translation_versions (
        id TEXT PRIMARY KEY,
        validation_issues TEXT
      )
    ''');
  });

  tearDown(() async {
    await DatabaseService.closeForTests();
  });

  test('adds validation_schema_version column with default 0', () async {
    final migration =
        ValidationSchemaVersionMigration(logger: NoopLogger());

    expect(await migration.isApplied(), isFalse);
    expect(await migration.execute(), isTrue);
    expect(await migration.isApplied(), isTrue);

    final cols = await DatabaseService.database.rawQuery(
        'PRAGMA table_info(translation_versions)');
    final col = cols.firstWhere(
      (c) => c['name'] == 'validation_schema_version',
      orElse: () => <String, Object?>{},
    );
    expect(col['name'], 'validation_schema_version');
    expect(col['dflt_value'], '0');
  });

  test('is idempotent — second execute is a no-op', () async {
    final m1 = ValidationSchemaVersionMigration(logger: NoopLogger());
    await m1.execute();

    final m2 = ValidationSchemaVersionMigration(logger: NoopLogger());
    expect(await m2.isApplied(), isTrue);
    // execute() on an already-applied migration must not throw
    expect(await m2.execute(), isFalse);
  });
}
```

> If `DatabaseService.initializeInMemoryForTests()` / `closeForTests()` helpers do not exist, create a minimal `test/helpers/in_memory_database.dart` that opens an in-memory DB and assigns it to `DatabaseService.database`. Reuse whatever pattern existing tests use (search for a passing migration or repository test to copy).

- [ ] **Step 3: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/unit/services/database/migrations/migration_validation_schema_version_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 4: Implement the migration**

```dart
// lib/services/database/migrations/migration_validation_schema_version.dart
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'migration_base.dart';

/// Adds `validation_schema_version` to `translation_versions`.
///
/// Rows written with the pre-structured (`List<String>`) format keep the
/// default value 0; any row re-validated after this release is bumped to 1
/// by the persistence layer. The forced rescan at app startup migrates all
/// remaining version-0 rows; see `ValidationRescanService`.
class ValidationSchemaVersionMigration extends Migration {
  final ILoggingService _logger;

  ValidationSchemaVersionMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'validation_schema_version_column';

  @override
  String get description =>
      'Add validation_schema_version column to translation_versions';

  // Must run before ValidationIssuesJsonMigration (priority 110) so the
  // column exists when other migrations inspect rows, but after basic
  // table creation. 105 is unused upstream.
  @override
  int get priority => 105;

  @override
  Future<bool> isApplied() async {
    final cols = await DatabaseService.database
        .rawQuery('PRAGMA table_info(translation_versions)');
    return cols.any((c) => c['name'] == 'validation_schema_version');
  }

  @override
  Future<bool> execute() async {
    if (await isApplied()) {
      _logger.debug('validation_schema_version column already present');
      return false;
    }
    await DatabaseService.database.execute('''
      ALTER TABLE translation_versions
      ADD COLUMN validation_schema_version INTEGER NOT NULL DEFAULT 0
    ''');
    _logger.info('Added validation_schema_version column');
    return true;
  }
}
```

- [ ] **Step 5: Register the migration**

Modify `lib/services/database/migrations/migration_registry.dart`:

Add the import:

```dart
import 'migration_validation_schema_version.dart';
```

Insert the registration before `ValidationIssuesJsonMigration()` in `getAllMigrations()`:

```dart
ValidationSchemaVersionMigration(),
ValidationIssuesJsonMigration(),
```

- [ ] **Step 6: Run the migration test**

Run: `C:/src/flutter/bin/flutter test test/unit/services/database/migrations/migration_validation_schema_version_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/services/database/migrations/migration_validation_schema_version.dart lib/services/database/migrations/migration_registry.dart test/unit/services/database/migrations/migration_validation_schema_version_test.dart
git commit -m "feat: add validation_schema_version column migration"
```

---

## Task 8: Repository — paging, counting, and schema-version-aware batch update

**Files:**
- Modify: `lib/repositories/translation_version_repository.dart` (+ `mixins/` if used)
- Test: `test/unit/repositories/translation_version_repository_rescan_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/repositories/translation_version_repository_rescan_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/database/database_service.dart';
// Use whatever test-schema helper the codebase provides, e.g.
// import '../../helpers/test_schema.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late TranslationVersionRepository repo;

  setUp(() async {
    // Use the codebase's canonical in-memory test DB bootstrap, which must
    // run the full MigrationRegistry so validation_schema_version exists.
    await initTestDatabase();
    repo = TranslationVersionRepository();
    // Insert 250 versions: 180 legacy (schema_version = 0), 70 migrated (= 1)
    // ...use whatever seed helper the codebase provides.
  });

  tearDown(() async {
    await closeTestDatabase();
  });

  test('countLegacyValidationRows returns only schema_version < 1 translated rows',
      () async {
    final result = await repo.countLegacyValidationRows();
    expect(result.unwrap(), 180);
  });

  test('countMigratedValidationRows returns schema_version = 1', () async {
    final result = await repo.countMigratedValidationRows();
    expect(result.unwrap(), 70);
  });

  test('getLegacyValidationPage returns pages in stable id order', () async {
    final page1 = (await repo.getLegacyValidationPage(limit: 100)).unwrap();
    final page2 = (await repo.getLegacyValidationPage(
      limit: 100,
      afterId: page1.last.id,
    )).unwrap();
    expect(page1.length, 100);
    expect(page2.length, 80);
    expect(
      {...page1.map((v) => v.id), ...page2.map((v) => v.id)}.length,
      180,
      reason: 'pages must not overlap',
    );
  });

  test('updateValidationBatch bumps validation_schema_version to 1', () async {
    final page = (await repo.getLegacyValidationPage(limit: 10)).unwrap();
    final updates = page
        .map((v) => (
              versionId: v.id,
              status: 'translated',
              validationIssues: '[]',
              schemaVersion: 1,
            ))
        .toList();

    final result = await repo.updateValidationBatch(updates);
    expect(result.unwrap(), 10);

    // Legacy count dropped by exactly 10.
    expect((await repo.countLegacyValidationRows()).unwrap(), 170);
    expect((await repo.countMigratedValidationRows()).unwrap(), 80);
  });
}
```

> If no `initTestDatabase` helper exists, use whatever in-memory bootstrap other repository tests already use (grep for `TranslationVersionRepository` in `test/`). The plan assumes there is one; if not, create a small helper that runs `MigrationRegistry.getAllMigrations()` against an in-memory DB.

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/unit/repositories/translation_version_repository_rescan_test.dart`
Expected: FAIL — methods do not exist yet; `updateValidationBatch` does not accept `schemaVersion`.

- [ ] **Step 3: Extend the existing `updateValidationBatch` signature**

In `lib/repositories/translation_version_repository.dart`, update the record type of the `updates` parameter at line ~718 to include `schemaVersion`:

```dart
Future<Result<int, TWMTDatabaseException>> updateValidationBatch(
  List<({
    String versionId,
    String status,
    String? validationIssues,
    int schemaVersion,
  })> updates,
) async {
  if (updates.isEmpty) {
    return const Ok(0);
  }
  return executeTransaction((txn) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    int totalAffected = 0;

    final disableTriggers = updates.length > 50;
    if (disableTriggers) {
      await txn.execute('DROP TRIGGER IF EXISTS trg_update_project_language_progress');
      await txn.execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_update');
      await txn.execute('DROP TRIGGER IF EXISTS trg_update_cache_on_version_change');
    }
    try {
      for (final update in updates) {
        final rowsAffected = await txn.rawUpdate(
          '''
          UPDATE $tableName
          SET status = ?,
              validation_issues = ?,
              validation_schema_version = ?,
              updated_at = ?
          WHERE id = ?
          ''',
          [
            update.status,
            update.validationIssues,
            update.schemaVersion,
            now,
            update.versionId,
          ],
        );
        totalAffected += rowsAffected;
      }
      // ... (rest of the existing trigger/FTS/cache bulk update block unchanged)
    } finally {
      if (disableTriggers) {
        await _recreateTriggers(txn);
      }
    }
    return totalAffected;
  });
}
```

> Update every existing call site (`handleRescanValidation`, `ValidationPersistenceHandler.validateAndSave` is not a caller — it uses direct upsert) to pass `schemaVersion: 1`. Compile errors will surface them; fix in the appropriate downstream tasks (9, 10).

- [ ] **Step 4: Add counting methods**

Add after `updateValidationBatch` in the same file:

```dart
/// Count translation_versions rows that still use the pre-structured
/// validation_issues format. Bounded to rows that have a translation so
/// the rescan only walks rows the validation service can act on.
Future<Result<int, TWMTDatabaseException>> countLegacyValidationRows() async {
  return executeQuery(() async {
    final rows = await database.rawQuery('''
      SELECT COUNT(*) AS c FROM $tableName
      WHERE validation_schema_version < 1
        AND translated_text IS NOT NULL
        AND TRIM(translated_text) <> ''
    ''');
    return (rows.first['c'] as int?) ?? 0;
  });
}

/// Count rows already migrated to the structured format.
Future<Result<int, TWMTDatabaseException>> countMigratedValidationRows() async {
  return executeQuery(() async {
    final rows = await database.rawQuery('''
      SELECT COUNT(*) AS c FROM $tableName
      WHERE validation_schema_version >= 1
    ''');
    return (rows.first['c'] as int?) ?? 0;
  });
}
```

- [ ] **Step 5: Add paging method**

```dart
/// Return the next page of legacy rows, ordered by id for deterministic
/// resume. Pass the last returned id as [afterId] to get the next page.
Future<Result<List<TranslationVersion>, TWMTDatabaseException>>
    getLegacyValidationPage({
  required int limit,
  String? afterId,
}) async {
  return executeQuery(() async {
    final maps = await database.rawQuery(
      '''
      SELECT * FROM $tableName
      WHERE validation_schema_version < 1
        AND translated_text IS NOT NULL
        AND TRIM(translated_text) <> ''
        ${afterId == null ? '' : 'AND id > ?'}
      ORDER BY id ASC
      LIMIT ?
      ''',
      [if (afterId != null) afterId, limit],
    );
    return maps.map(fromMap).toList();
  });
}
```

- [ ] **Step 6: Run the test**

Run: `C:/src/flutter/bin/flutter test test/unit/repositories/translation_version_repository_rescan_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 7: Run the full suite**

Run: `C:/src/flutter/bin/flutter test`
Expected: PASS (any existing `updateValidationBatch` callers that previously passed a record without `schemaVersion` now fail to compile — fix them by passing `schemaVersion: 0` for legacy writes or `schemaVersion: 1` for new writes; the next two tasks will migrate the two real call sites).

- [ ] **Step 8: Commit**

```bash
git add lib/repositories/translation_version_repository.dart test/unit/repositories/translation_version_repository_rescan_test.dart
git add -u
git commit -m "feat: expose rescan paging + schema-version updates on version repo"
```

---

## Task 9: `ValidationPersistenceHandler` writes structured JSON

**Files:**
- Modify: `lib/services/translation/handlers/validation_persistence_handler.dart:132`
- Test: `test/unit/services/translation/handlers/validation_persistence_handler_test.dart` (existing)

- [ ] **Step 1: Update the existing handler test**

Open `test/unit/services/translation/handlers/validation_persistence_handler_test.dart`. Locate the test that asserts on the saved `validationIssues` string (search for `'validation_issues'` or `allMessages`). Replace that assertion with:

```dart
// Expect structured JSON
final saved = savedVersion.validationIssues;
expect(saved, isNotNull);
final decoded = jsonDecode(saved!) as List;
expect(decoded, isNotEmpty);
for (final entry in decoded) {
  final map = entry as Map<String, dynamic>;
  expect(map, containsPair('rule', isA<String>()));
  expect(map, containsPair('severity', isA<String>()));
  expect(map, containsPair('message', isA<String>()));
}
```

Add `import 'dart:convert';` if missing. Add a test dedicated to round-trip:

```dart
test('validation_issues round-trips as structured JSON', () async {
  // Arrange a unit+translation where the validation service reports at
  // least one issue (e.g., length mismatch).
  // Act: validateAndSave.
  // Assert: the saved validation_issues decodes into a List<Map> where
  // each map has rule/severity/message keys.
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation/handlers/validation_persistence_handler_test.dart`
Expected: FAIL — the handler still writes `jsonEncode(result.allMessages)`, so entries are strings, not maps.

- [ ] **Step 3: Rewrite the write site**

In `lib/services/translation/handlers/validation_persistence_handler.dart` at line 132, replace:

```dart
validationIssuesJson = jsonEncode(result.allMessages);
```

with:

```dart
validationIssuesJson = jsonEncode(
  result.issues.map((i) => i.toJson()).toList(),
);
```

- [ ] **Step 4: Bump `validation_schema_version` on the saved row**

The handler creates a `TranslationVersion` via `upsert`. The `TranslationVersion` domain model must carry the new field. Find its definition and add `validationSchemaVersion` (default `1`):

Search: `grep -rn "class TranslationVersion" lib/models/`

In `lib/models/domain/translation_version.dart`, add `final int validationSchemaVersion;` (default `1`) with constructor param, `copyWith`, `fromMap`, `toMap` wired to the `validation_schema_version` SQLite column.

Then in the handler:

```dart
final version = TranslationVersion(
  ...
  validationSchemaVersion: 1, // new structured format
  ...
);
```

- [ ] **Step 5: Regenerate JSON/Riverpod codegen**

Run: `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs`
Expected: SUCCESS.

- [ ] **Step 6: Run the handler test**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation/handlers/validation_persistence_handler_test.dart`
Expected: PASS.

- [ ] **Step 7: Run the full suite**

Run: `C:/src/flutter/bin/flutter test`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/services/translation/handlers/validation_persistence_handler.dart lib/models/domain/translation_version.dart
git add -u
git commit -m "feat: persist validation issues as structured JSON (schema v1)"
```

---

## Task 10: Editor `handleRescanValidation` writes structured JSON

**Files:**
- Modify: `lib/features/translation_editor/screens/actions/editor_actions_validation.dart:300`
- Test: add scenario to the editor validation test or to the rescan service test in Task 13

- [ ] **Step 1: Update the write site**

In `handleRescanValidation`, find the block that builds `newValidationIssues`:

```dart
} else {
  final result = validationResult.unwrap();
  if (result.hasErrors || result.hasWarnings) {
    newStatus = TranslationVersionStatus.needsReview;
    newValidationIssues = result.allMessages.toString();
  }
}
```

Replace with:

```dart
} else {
  final result = validationResult.unwrap();
  if (result.hasErrors || result.hasWarnings) {
    newStatus = TranslationVersionStatus.needsReview;
    newValidationIssues = jsonEncode(
      result.issues.map((i) => i.toJson()).toList(),
    );
  }
}
```

Add `import 'dart:convert';` at the top if missing.

Update the `pendingUpdates` record construction to include `schemaVersion: 1`:

```dart
pendingUpdates.add((
  versionId: version.id,
  status: newStatus.toDbValue,
  validationIssues: newValidationIssues,
  schemaVersion: 1,
));
```

- [ ] **Step 2: Build the app to verify it compiles**

Run: `C:/src/flutter/bin/flutter analyze lib/features/translation_editor/screens/actions/editor_actions_validation.dart`
Expected: No errors.

- [ ] **Step 3: Run the full suite**

Run: `C:/src/flutter/bin/flutter test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/features/translation_editor/screens/actions/editor_actions_validation.dart
git commit -m "refactor: write structured validation issues from editor rescan"
```

---

## Task 11: Replace the regex reader with structured `jsonDecode`

**Files:**
- Modify: `lib/features/translation_editor/screens/actions/editor_actions_validation.dart:382-429`
- Test: `test/features/translation_editor/screens/actions/parse_validation_issues_test.dart`

- [ ] **Step 1: Extract the parser to a testable free function**

Move `_parseValidationIssues` out of the mixin into a top-level function in a new file `lib/features/translation_editor/utils/validation_issues_parser.dart`:

```dart
// lib/features/translation_editor/utils/validation_issues_parser.dart
import 'dart:convert';
import 'package:twmt/models/common/validation_issue_entry.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';

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
      // Legacy `List<String>` — surface as a single lumped entry so the user
      // sees "Pending rescan" until the startup gate re-validates this row.
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
```

- [ ] **Step 2: Write the failing test**

```dart
// test/features/translation_editor/screens/actions/parse_validation_issues_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/utils/validation_issues_parser.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';

void main() {
  group('parseValidationIssues', () {
    test('returns empty list on null / blank input', () {
      expect(parseValidationIssues(null), isEmpty);
      expect(parseValidationIssues(''), isEmpty);
      expect(parseValidationIssues('   '), isEmpty);
    });

    test('decodes structured entries', () {
      final raw =
          '[{"rule":"variables","severity":"error","message":"Missing {0}"},'
          '{"rule":"length","severity":"warning","message":"Too long"}]';
      final parsed = parseValidationIssues(raw);
      expect(parsed.length, 2);
      expect(parsed[0].type, 'variables');
      expect(parsed[0].severity, ValidationSeverity.error);
      expect(parsed[0].description, 'Missing {0}');
      expect(parsed[1].type, 'length');
      expect(parsed[1].severity, ValidationSeverity.warning);
    });

    test('surfaces unknown rule code as "legacy" but keeps message', () {
      final raw =
          '[{"rule":"future_rule","severity":"error","message":"oops"}]';
      final parsed = parseValidationIssues(raw);
      expect(parsed.single.type, 'legacy');
      expect(parsed.single.description, 'oops');
    });

    test('treats a legacy JSON List<String> as a single lumped entry', () {
      final raw = '["Missing variable {0}","Length differs"]';
      final parsed = parseValidationIssues(raw);
      expect(parsed.single.type, 'legacy');
      expect(parsed.single.description,
          'Missing variable {0} • Length differs');
    });

    test('malformed JSON falls back to a legacy entry with the raw payload', () {
      const raw = '{not json';
      final parsed = parseValidationIssues(raw);
      expect(parsed.single.type, 'legacy');
      expect(parsed.single.description, raw);
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/screens/actions/parse_validation_issues_test.dart`
Expected: FAIL — parser file doesn't exist until Step 1 was saved. If already passing, move on.

- [ ] **Step 4: Wire the parser into the mixin**

In `lib/features/translation_editor/screens/actions/editor_actions_validation.dart`:

1. Add:

```dart
import '../../utils/validation_issues_parser.dart';
```

2. Delete the private `_parseValidationIssues` method and `_StoredValidationIssue` class at the bottom of the file.
3. Replace the call:

```dart
final issues = _parseValidationIssues(version.validationIssues);

for (final issue in issues) {
  allIssues.add(batch.ValidationIssue(
    ...
    issueType: issue.type,
    description: issue.description,
    ...
  ));
}
```

with:

```dart
final parsed = parseValidationIssues(version.validationIssues);

for (final p in parsed) {
  allIssues.add(batch.ValidationIssue(
    unitKey: unit.key,
    unitId: unit.id,
    versionId: version.id,
    severity: p.severity == ValidationSeverity.error
        ? batch.ValidationSeverity.error
        : batch.ValidationSeverity.warning,
    issueType: p.type,
    description: p.description,
    sourceText: unit.sourceText,
    translatedText: version.translatedText ?? '',
  ));
}
```

- [ ] **Step 5: Run the parser test**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/screens/actions/parse_validation_issues_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Run the editor actions tests**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/translation_editor/utils/validation_issues_parser.dart lib/features/translation_editor/screens/actions/editor_actions_validation.dart test/features/translation_editor/screens/actions/parse_validation_issues_test.dart
git commit -m "refactor: decode validation_issues as structured JSON"
```

---

## Task 12: Humanised label in the Validation Review DataGrid

**Files:**
- Modify: `lib/features/translation_editor/widgets/validation_review_data_source.dart:152-178`
- Test: `test/features/translation_editor/widgets/validation_review_data_source_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/translation_editor/widgets/validation_review_data_source_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/features/translation_editor/widgets/validation_review_data_source.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';

void main() {
  testWidgets('Issue Type cell shows humanised label for known rule',
      (tester) async {
    final ds = ValidationReviewDataSource(
      issues: [
        const ValidationIssue(
          unitKey: 'k',
          unitId: 'u',
          versionId: 'v',
          severity: ValidationSeverity.error,
          issueType: 'variables',
          description: 'Missing {0}',
          sourceText: 'Hello {0}',
          translatedText: 'Bonjour',
        ),
      ],
      isRowSelected: (_) => false,
      isProcessing: (_) => false,
      onCheckboxTap: (_) {},
    );

    await tester.pumpWidget(MaterialApp(
      home: SfDataGrid(
        source: ds,
        columns: [
          GridColumn(columnName: 'issueType', label: const SizedBox.shrink()),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Variables'), findsOneWidget);
    expect(find.text('variables'), findsNothing);
  });

  testWidgets('Legacy rows show "Legacy" as a safe fallback', (tester) async {
    final ds = ValidationReviewDataSource(
      issues: [
        const ValidationIssue(
          unitKey: 'k',
          unitId: 'u',
          versionId: 'v',
          severity: ValidationSeverity.warning,
          issueType: 'legacy',
          description: 'Pending rescan',
          sourceText: 's',
          translatedText: 't',
        ),
      ],
      isRowSelected: (_) => false,
      isProcessing: (_) => false,
      onCheckboxTap: (_) {},
    );

    await tester.pumpWidget(MaterialApp(
      home: SfDataGrid(
        source: ds,
        columns: [
          GridColumn(columnName: 'issueType', label: const SizedBox.shrink()),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Legacy'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/validation_review_data_source_test.dart`
Expected: FAIL — the cell currently shows `variables` as-is.

- [ ] **Step 3: Map rule codes to labels in the cell**

In `lib/features/translation_editor/widgets/validation_review_data_source.dart`, add the import:

```dart
import 'package:twmt/services/translation/models/validation_rule.dart';
```

Replace `_buildIssueTypeCell`:

```dart
Widget _buildIssueTypeCell(String issueType, ValidationSeverity severity) {
  final label = _labelForIssueType(issueType);
  final isError = severity == ValidationSeverity.error;
  final color = isError ? Colors.red[700]! : Colors.orange[700]!;

  return Builder(builder: (context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  });
}

String _labelForIssueType(String code) {
  if (code == 'legacy') return 'Legacy';
  final rule = ValidationRule.fromCodeName(code);
  return rule?.label ?? code;
}
```

- [ ] **Step 4: Run the test**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/validation_review_data_source_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/translation_editor/widgets/validation_review_data_source.dart test/features/translation_editor/widgets/validation_review_data_source_test.dart
git commit -m "feat: humanise issue type labels in Validation Review grid"
```

---

## Task 13: `ValidationRescanService` — paged scan with ETA

**Files:**
- Create: `lib/services/validation/validation_rescan_service.dart`
- Test: `test/unit/services/validation/validation_rescan_service_test.dart`

- [ ] **Step 1: Define the service contract**

```dart
// lib/services/validation/validation_rescan_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/translation/i_validation_service.dart';

/// Snapshot of the rescan's current progress. Re-emitted ~every commit.
class RescanProgress {
  final int done;
  final int total;
  final Duration? eta;
  final bool isCalibrating;

  const RescanProgress({
    required this.done,
    required this.total,
    required this.eta,
    this.isCalibrating = false,
  });
}

class RescanPlan {
  final int total;     // legacy rows to process
  final int already;   // rows already at schema_version >= 1
  final bool isResume; // already > 0
  final Duration estimated;

  const RescanPlan({
    required this.total,
    required this.already,
    required this.isResume,
    required this.estimated,
  });
}

class ValidationRescanService {
  static const int pageSize = 500;
  static const int commitBatchSize = 100;
  static const int calibrationSamples = 20;
  static const int _etaWindow = 50;

  final TranslationVersionRepository _versionRepo;
  final TranslationUnitRepository _unitRepo;
  final IValidationService _validation;
  final ILoggingService _logger;

  ValidationRescanService({
    required TranslationVersionRepository versionRepo,
    required TranslationUnitRepository unitRepo,
    required IValidationService validation,
    required ILoggingService logger,
  })  : _versionRepo = versionRepo,
        _unitRepo = unitRepo,
        _validation = validation,
        _logger = logger;

  /// Query the DB and build a RescanPlan with a calibrated estimate.
  /// Returns null if there is nothing to do.
  Future<RescanPlan?> buildPlan() async {
    final legacyResult = await _versionRepo.countLegacyValidationRows();
    final migratedResult = await _versionRepo.countMigratedValidationRows();
    final legacy = legacyResult.unwrap();
    final migrated = migratedResult.unwrap();

    if (legacy == 0) return null;

    // Calibration: validate N sample rows to measure ms/unit on this machine.
    final sample =
        (await _versionRepo.getLegacyValidationPage(limit: calibrationSamples))
            .unwrap();
    final unitMap = await _fetchUnits(sample);

    final swatch = Stopwatch()..start();
    var sampled = 0;
    for (final v in sample) {
      final u = unitMap[v.unitId];
      if (u == null) continue;
      await _validation.validateTranslation(
        sourceText: u.sourceText,
        translatedText: v.translatedText ?? '',
        key: u.key,
      );
      sampled++;
    }
    swatch.stop();

    final msPerUnit =
        sampled == 0 ? 8.0 : swatch.elapsedMilliseconds / sampled;
    final estimated = Duration(milliseconds: (msPerUnit * legacy).round());

    return RescanPlan(
      total: legacy,
      already: migrated,
      isResume: migrated > 0,
      estimated: estimated,
    );
  }

  /// Stream rescan progress. The caller subscribes and should drain the
  /// stream to completion; on completion all legacy rows are at schema
  /// version 1. Cancelling the subscription pauses the rescan mid-batch —
  /// a subsequent call picks up where it left off.
  Stream<RescanProgress> run() async* {
    var done = 0;
    var total = (await _versionRepo.countLegacyValidationRows()).unwrap();
    if (total == 0) {
      yield const RescanProgress(done: 0, total: 0, eta: Duration.zero);
      return;
    }

    final times = <int>[]; // elapsed ms per commit, trailing window
    final sw = Stopwatch();
    String? afterId;

    while (true) {
      final page = (await _versionRepo
              .getLegacyValidationPage(limit: pageSize, afterId: afterId))
          .unwrap();
      if (page.isEmpty) break;
      afterId = page.last.id;

      final unitsMap = await _fetchUnits(page);

      final pending = <({
        String versionId,
        String status,
        String? validationIssues,
        int schemaVersion,
      })>[];

      sw
        ..reset()
        ..start();

      for (final v in page) {
        final u = unitsMap[v.unitId];
        if (u == null) continue;

        final validationResult = await _validation.validateTranslation(
          sourceText: u.sourceText,
          translatedText: v.translatedText ?? '',
          key: u.key,
        );

        String status = 'translated';
        String? issuesJson;
        if (validationResult.isErr) {
          status = 'needs_review';
        } else {
          final result = validationResult.unwrap();
          if (result.hasErrors || result.hasWarnings) {
            status = 'needs_review';
            issuesJson = jsonEncode(
              result.issues.map((i) => i.toJson()).toList(),
            );
          }
        }

        pending.add((
          versionId: v.id,
          status: status,
          validationIssues: issuesJson,
          schemaVersion: 1,
        ));

        if (pending.length >= commitBatchSize) {
          await _commit(pending);
          sw.stop();
          times.add(sw.elapsedMilliseconds);
          if (times.length > _etaWindow) times.removeAt(0);
          done += pending.length;
          pending.clear();
          yield RescanProgress(
            done: done,
            total: total,
            eta: _eta(times, total - done),
          );
          sw
            ..reset()
            ..start();
        }
      }

      if (pending.isNotEmpty) {
        await _commit(pending);
        sw.stop();
        times.add(sw.elapsedMilliseconds);
        if (times.length > _etaWindow) times.removeAt(0);
        done += pending.length;
        yield RescanProgress(
          done: done,
          total: total,
          eta: _eta(times, total - done),
        );
      }
    }

    _logger.info('Validation rescan complete', {'processed': done});
  }

  Future<void> _commit(
    List<({
      String versionId,
      String status,
      String? validationIssues,
      int schemaVersion,
    })> updates,
  ) async {
    final res = await _versionRepo.updateValidationBatch(updates);
    if (res.isErr) {
      _logger.error(
          'Rescan commit failed', res.error, StackTrace.current);
      throw Exception('Rescan commit failed: ${res.error}');
    }
  }

  Future<Map<String, TranslationUnit>> _fetchUnits(
      List<TranslationVersion> versions) async {
    final ids = versions.map((v) => v.unitId).toSet().toList();
    final res = await _unitRepo.getByIds(ids);
    if (res.isErr) return const {};
    return {for (final u in res.unwrap()) u.id: u};
  }

  Duration? _eta(List<int> windowMs, int remaining) {
    if (windowMs.isEmpty || remaining <= 0) return Duration.zero;
    final avgMsPerBatch =
        windowMs.reduce((a, b) => a + b) / windowMs.length;
    final avgMsPerUnit = avgMsPerBatch / commitBatchSize;
    return Duration(milliseconds: (avgMsPerUnit * remaining).round());
  }
}
```

- [ ] **Step 2: Write the failing test**

```dart
// test/unit/services/validation/validation_rescan_service_test.dart
import 'package:flutter_test/flutter_test.dart';
// plus fakes / in-memory DB bootstrap as in task 8

void main() {
  group('ValidationRescanService.run', () {
    test('processes every legacy row in paged commits', () async {
      // seed 250 legacy rows; run().toList(); expect all done, count == 250
      // and that countLegacyValidationRows() == 0 afterwards.
    });

    test('second run is a no-op when no legacy rows remain', () async {
      // seed 0 legacy rows; run() emits one (0,0) event and ends.
    });

    test('yields monotonically increasing progress', () async {
      // collect events; ensure each event.done >= previous.done.
    });

    test('commits in 100-unit batches', () async {
      // seed 250; collect events; expect done values: 100, 200, 250.
    });

    test('eta is non-null and positive after the first commit', () async {
      // seed 250; take second event; expect eta != null && > Duration.zero.
    });
  });
}
```

Fill in the seeds / fakes using whatever pattern the codebase uses for in-memory DB tests. Keep fakes minimal.

- [ ] **Step 3: Run test to verify it fails**

Run: `C:/src/flutter/bin/flutter test test/unit/services/validation/validation_rescan_service_test.dart`
Expected: FAIL (file missing) — then after creating, FAIL until the seed helpers match the service's SQL.

- [ ] **Step 4: Fix the service until tests pass**

Run: `C:/src/flutter/bin/flutter test test/unit/services/validation/validation_rescan_service_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/validation/validation_rescan_service.dart test/unit/services/validation/validation_rescan_service_test.dart
git commit -m "feat: add ValidationRescanService with paged scan and ETA"
```

---

## Task 14: Rescan dialog + Riverpod provider

**Files:**
- Create: `lib/features/bootstrap/providers/validation_rescan_provider.dart`
- Create: `lib/features/bootstrap/widgets/validation_rescan_dialog.dart`
- Test: `test/features/bootstrap/widgets/validation_rescan_dialog_test.dart`

- [ ] **Step 1: Provider**

```dart
// lib/features/bootstrap/providers/validation_rescan_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/validation/validation_rescan_service.dart';

part 'validation_rescan_provider.g.dart';

class RescanState {
  final RescanPlan? plan;
  final RescanProgress? progress;
  final bool isRunning;
  final bool isDone;
  final Object? error;

  const RescanState({
    this.plan,
    this.progress,
    this.isRunning = false,
    this.isDone = false,
    this.error,
  });

  RescanState copyWith({
    RescanPlan? plan,
    RescanProgress? progress,
    bool? isRunning,
    bool? isDone,
    Object? error,
  }) =>
      RescanState(
        plan: plan ?? this.plan,
        progress: progress ?? this.progress,
        isRunning: isRunning ?? this.isRunning,
        isDone: isDone ?? this.isDone,
        error: error,
      );
}

@riverpod
ValidationRescanService validationRescanService(Ref ref) {
  return ValidationRescanService(
    versionRepo: ref.read(translationVersionRepositoryProvider),
    unitRepo: ref.read(translationUnitRepositoryProvider),
    validation: ref.read(validationServiceProvider),
    logger: ref.read(loggingServiceProvider),
  );
}

@riverpod
class ValidationRescanController extends _$ValidationRescanController {
  StreamSubscription<RescanProgress>? _sub;

  @override
  RescanState build() => const RescanState();

  Future<void> prepare() async {
    final svc = ref.read(validationRescanServiceProvider);
    try {
      final plan = await svc.buildPlan();
      state = state.copyWith(plan: plan, isDone: plan == null);
    } catch (e) {
      state = state.copyWith(error: e, isDone: true);
    }
  }

  void start() {
    if (state.isRunning || state.plan == null) return;
    final svc = ref.read(validationRescanServiceProvider);
    state = state.copyWith(isRunning: true);
    _sub = svc.run().listen(
      (p) => state = state.copyWith(progress: p),
      onError: (Object e) =>
          state = state.copyWith(error: e, isRunning: false, isDone: true),
      onDone: () => state = state.copyWith(isRunning: false, isDone: true),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
  }
}
```

- [ ] **Step 2: Dialog**

```dart
// lib/features/bootstrap/widgets/validation_rescan_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../providers/validation_rescan_provider.dart';

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

String _n(int v) {
  final s = v.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

class ValidationRescanDialog extends ConsumerStatefulWidget {
  const ValidationRescanDialog({super.key});

  /// Prepares a plan; if there is work to do, shows the dialog and blocks
  /// until the rescan completes. Returns normally if nothing to do.
  static Future<void> showAndRun(BuildContext context, WidgetRef ref) async {
    await ref.read(validationRescanControllerProvider.notifier).prepare();
    final state = ref.read(validationRescanControllerProvider);
    if (state.plan == null) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ValidationRescanDialog(),
    );
  }

  @override
  ConsumerState<ValidationRescanDialog> createState() =>
      _ValidationRescanDialogState();
}

class _ValidationRescanDialogState
    extends ConsumerState<ValidationRescanDialog> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final s = ref.watch(validationRescanControllerProvider);
    final plan = s.plan;
    if (plan == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    if (s.isDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop();
          FluentToast.success(
            context,
            'Validation data update complete.',
          );
        }
      });
    }

    return PopScope(
      canPop: false,
      child: TokenDialog(
        icon: FluentIcons.shield_checkmark_24_regular,
        title: s.isRunning || s.progress != null
            ? 'Updating validation data'
            : (plan.isResume
                ? 'Resuming validation update'
                : 'Validation data update required'),
        width: 520,
        body: s.progress != null ? _progressBody(tokens, s) : _planBody(tokens, plan),
      ),
    );
  }

  Widget _planBody(TwmtThemeTokens tokens, plan) {
    final bodyText = plan.isResume
        ? 'A previous update was interrupted. '
            '${_n(plan.already)} of ${_n(plan.total + plan.already)} '
            'units already processed. Remaining: ${_n(plan.total)} units • '
            'Estimated: ~${_fmt(plan.estimated)}.'
        : 'This release uses a new, richer format for translation validation '
            'diagnostics. All existing translations need to be rescanned once '
            'to benefit from it.\n\n'
            '${_n(plan.total)} units to rescan • Estimated: ~${_fmt(plan.estimated)}\n\n'
            'This will only run once. Do not close the app until it completes — '
            'if interrupted, the update will resume on next launch.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(bodyText, style: tokens.fontBody.copyWith(color: tokens.textDim)),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: SmallTextButton(
            label: plan.isResume ? 'Continue' : 'Start rescan',
            icon: FluentIcons.play_24_regular,
            filled: true,
            onTap: () => ref
                .read(validationRescanControllerProvider.notifier)
                .start(),
          ),
        ),
      ],
    );
  }

  Widget _progressBody(TwmtThemeTokens tokens, state) {
    final done = state.progress!.done as int;
    final total = state.progress!.total as int;
    final eta = state.progress!.eta as Duration?;
    final value = total == 0 ? 1.0 : done / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Rescanned ${_n(done)} of ${_n(total)}'
          '${eta == null ? '' : ' — ETA ${_fmt(eta)}'}',
          style: tokens.fontBody,
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: value),
        ),
        const SizedBox(height: 12),
        Text(
          'Closing the app will pause the update; it will resume on next launch.',
          style: tokens.fontBody.copyWith(
            fontSize: 11,
            color: tokens.textDim,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Regenerate providers**

Run: `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs`
Expected: SUCCESS.

- [ ] **Step 4: Write a widget test**

```dart
// test/features/bootstrap/widgets/validation_rescan_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/bootstrap/providers/validation_rescan_provider.dart';
import 'package:twmt/features/bootstrap/widgets/validation_rescan_dialog.dart';
import 'package:twmt/services/validation/validation_rescan_service.dart';

class _FakeRescanService extends ValidationRescanService {
  _FakeRescanService(this.plan, this.events)
      : super(
          versionRepo: null as dynamic,
          unitRepo: null as dynamic,
          validation: null as dynamic,
          logger: null as dynamic,
        );
  final RescanPlan? plan;
  final List<RescanProgress> events;

  @override
  Future<RescanPlan?> buildPlan() async => plan;

  @override
  Stream<RescanProgress> run() async* {
    for (final e in events) {
      yield e;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}

void main() {
  Widget _host({required ValidationRescanService svc, required Widget child}) {
    return ProviderScope(
      overrides: [
        validationRescanServiceProvider.overrideWithValue(svc),
      ],
      child: MaterialApp(home: child),
    );
  }

  testWidgets('first-run dialog shows totals and estimated time',
      (tester) async {
    final svc = _FakeRescanService(
      const RescanPlan(
        total: 12000,
        already: 0,
        isResume: false,
        estimated: Duration(minutes: 3, seconds: 20),
      ),
      const [],
    );
    await tester.pumpWidget(_host(svc: svc, child: Builder(builder: (ctx) {
      return Scaffold(
        body: Consumer(builder: (ctx, ref, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ValidationRescanDialog.showAndRun(ctx, ref);
          });
          return const SizedBox.shrink();
        }),
      );
    })));
    await tester.pumpAndSettle();

    expect(find.text('Validation data update required'), findsOneWidget);
    expect(find.textContaining('12,000 units to rescan'), findsOneWidget);
    expect(find.textContaining('~3m 20s'), findsOneWidget);
    expect(find.text('Start rescan'), findsOneWidget);
  });

  testWidgets('resume dialog wording kicks in when some rows are migrated',
      (tester) async {
    final svc = _FakeRescanService(
      const RescanPlan(
        total: 1000,
        already: 5000,
        isResume: true,
        estimated: Duration(seconds: 30),
      ),
      const [],
    );
    await tester.pumpWidget(_host(svc: svc, child: Builder(builder: (ctx) {
      return Scaffold(
        body: Consumer(builder: (ctx, ref, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ValidationRescanDialog.showAndRun(ctx, ref);
          });
          return const SizedBox.shrink();
        }),
      );
    })));
    await tester.pumpAndSettle();

    expect(find.text('Resuming validation update'), findsOneWidget);
    expect(
      find.textContaining('5,000 of 6,000 units already processed'),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('no plan → dialog closes without blocking', (tester) async {
    final svc = _FakeRescanService(null, const []);
    bool opened = true;
    await tester.pumpWidget(_host(svc: svc, child: Builder(builder: (ctx) {
      return Scaffold(
        body: Consumer(builder: (ctx, ref, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await ValidationRescanDialog.showAndRun(ctx, ref);
            opened = false;
          });
          return const SizedBox.shrink();
        }),
      );
    })));
    await tester.pumpAndSettle();
    expect(opened, isFalse);
  });
}
```

- [ ] **Step 5: Run the widget test**

Run: `C:/src/flutter/bin/flutter test test/features/bootstrap/widgets/validation_rescan_dialog_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/bootstrap/ test/features/bootstrap/
git add -u
git commit -m "feat: add blocking ValidationRescanDialog with first-run and resume modes"
```

---

## Task 15: Mount the dialog in `main.dart` startup

**Files:**
- Modify: `lib/main.dart:148-176`

- [ ] **Step 1: Wire the dialog into `_triggerStartupTasks`**

At the top of `main.dart`, add:

```dart
import 'package:twmt/features/bootstrap/widgets/validation_rescan_dialog.dart';
```

Replace the body of `_runDataMigrations` so it hands off to the rescan dialog after data migrations complete, before the rest of the startup tasks:

```dart
Future<void> _runDataMigrations() async {
  if (!mounted) return;

  final needsMigration =
      await ref.read(dataMigrationProvider.notifier).needsMigration();

  if (needsMigration) {
    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext != null && navigatorContext.mounted) {
      await showDialog<void>(
        context: navigatorContext,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        builder: (context) => const DataMigrationDialog(),
      );
    }
  }

  // After schema migrations, force a one-shot structured rescan.
  if (!mounted) return;
  final rescanContext = rootNavigatorKey.currentContext;
  if (rescanContext != null && rescanContext.mounted) {
    await ValidationRescanDialog.showAndRun(rescanContext, ref);
  }

  if (!mounted) return;
  unawaited(_continueStartupTasks());
}
```

- [ ] **Step 2: Smoke-run the app**

Run: `C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs` (if codegen stale)
Run: `C:/src/flutter/bin/flutter analyze`
Expected: No errors.

- [ ] **Step 3: Manual smoke test**

Run: `C:/src/flutter/bin/flutter run -d windows`

Verify:
1. On a DB with pre-existing `needs_review` rows (legacy format), the blocking dialog appears showing the totals and estimate.
2. Clicking **Start rescan** switches to the progress dialog with a determinate bar and live ETA.
3. Forcibly killing the app mid-scan, then relaunching, shows the **Resuming validation update** dialog with a correct `M of N already processed` count.
4. On a fresh / already-migrated DB, no dialog appears and the router loads normally.
5. After completion, opening the Validation Review screen shows per-rule labels (`Variables`, `Markup tags`, `Length`, etc.) and real descriptions instead of `validation_issue` / `Translation needs review`.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: run structured validation rescan at app startup"
```

---

## Task 16: End-to-end integration test

**Files:**
- Test: `test/integration/validation_rescan_integration_test.dart`

- [ ] **Step 1: Write the integration test**

```dart
// test/integration/validation_rescan_integration_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// + repository / service imports and whatever in-memory DB bootstrap the
// codebase already uses.

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await initTestDatabase(); // runs the full MigrationRegistry
    // Seed: 100 translation_versions + units with legacy List<String> payloads
    // and validation_schema_version = 0. At least one should trigger each
    // rule (empty, missing variable, markup mismatch, encoding, etc.).
  });

  tearDown(() => closeTestDatabase());

  test('full rescan migrates legacy rows and produces structured issues',
      () async {
    final svc = buildRescanService(); // wire repos + ValidationServiceImpl

    final plan = await svc.buildPlan();
    expect(plan, isNotNull);
    expect(plan!.total, 100);
    expect(plan.isResume, isFalse);

    await for (final _ in svc.run()) {}

    // Every row migrated
    expect(
      (await buildVersionRepo().countLegacyValidationRows()).unwrap(),
      0,
    );

    // Payload is structured JSON with proper rule codes
    final rows = await DatabaseService.database.rawQuery(
      'SELECT validation_issues FROM translation_versions '
      "WHERE validation_issues IS NOT NULL AND TRIM(validation_issues) <> ''",
    );
    for (final r in rows) {
      final payload = r['validation_issues'] as String;
      final decoded = jsonDecode(payload) as List;
      for (final entry in decoded) {
        final map = entry as Map<String, dynamic>;
        expect(map, containsPair('rule', isA<String>()));
        expect(map, containsPair('severity', isA<String>()));
        expect(map, containsPair('message', isA<String>()));
      }
    }
  });

  test('interrupted rescan resumes from where it stopped', () async {
    // Seed 100 rows.
    final svc = buildRescanService();

    // Drain only the first event (covers 100-unit batch).
    final firstEvent = await svc.run().first;
    expect(firstEvent.done, 100);

    // Simulate reopen: a fresh plan should report 0 legacy remaining.
    final plan = await buildRescanService().buildPlan();
    expect(plan, isNull);
  });
}
```

- [ ] **Step 2: Run the integration test**

Run: `C:/src/flutter/bin/flutter test test/integration/validation_rescan_integration_test.dart`
Expected: PASS.

- [ ] **Step 3: Run the full suite**

Run: `C:/src/flutter/bin/flutter test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add test/integration/validation_rescan_integration_test.dart
git commit -m "test: end-to-end rescan migrates legacy data to structured format"
```

---

## Self-Review Checklist (for the executor, not the plan author)

After completing all tasks, verify against the spec:

1. **Issue Type column** shows per-rule English labels (`Variables`, `Markup tags`, etc.), not `validation_issue`.
2. **Description column** shows the actual validator message, not `Translation needs review`.
3. **Startup dialog** appears on a legacy DB with correct counts and a calibrated ETA.
4. **Resume dialog** appears after killing the app mid-scan, with correct `M of N` counts.
5. **No cancel button** is exposed in the progress dialog.
6. **All UI strings** are in English.
7. **`validation_schema_version = 1`** on every row with a translation after rescan completes.
8. **`flutter test`** is green.
9. **`flutter analyze`** reports no issues in the modified files.
