import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/validation_rule.dart';
import 'package:twmt/services/translation/validation_service_impl.dart';

import '../../../helpers/noop_logger.dart';

/// Regression tests for H1: variable preservation must be sensitive to the
/// NUMBER of occurrences of a placeholder, not just its presence. Dropping one
/// of two identical `%s` (or adding an extra one) corrupts the runtime string
/// substitution and must be flagged, not silently accepted.
void main() {
  late ValidationServiceImpl svc;

  setUp(() {
    svc = ValidationServiceImpl(logger: NoopLogger());
  });

  group('checkVariablePreservation - occurrence count (H1)', () {
    test('dropping one of two identical %s -> error', () async {
      final err = await svc.checkVariablePreservation(
        sourceText: 'Move %s to %s',
        translatedText: 'Deplacer %s',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.variables);
      expect(err?.severity, ValidationSeverity.error);
      expect(err?.message, contains('Missing'));
    });

    test('adding an extra %s -> error', () async {
      final err = await svc.checkVariablePreservation(
        sourceText: 'Value %s',
        translatedText: 'Valeur %s %s',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.variables);
      expect(err?.severity, ValidationSeverity.error);
      expect(err?.message, contains('Extra'));
    });

    test('dropping one of two identical {0} placeholders -> error', () async {
      final err = await svc.checkVariablePreservation(
        sourceText: 'From {0} to {0}',
        translatedText: 'Depuis {0}',
        key: 'k',
      );
      expect(err?.severity, ValidationSeverity.error);
    });

    test('equal count preserved -> null (guard, no false positive)', () async {
      final err = await svc.checkVariablePreservation(
        sourceText: 'Move %s to %s',
        translatedText: 'Deplacer %s vers %s',
        key: 'k',
      );
      expect(err, isNull);
    });
  });
}
