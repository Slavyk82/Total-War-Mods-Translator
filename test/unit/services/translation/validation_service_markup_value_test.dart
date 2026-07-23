import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/validation_rule.dart';
import 'package:twmt/services/translation/validation_service_impl.dart';

import '../../../helpers/noop_logger.dart';

/// Markup preservation must compare tag IDENTITY, not just tag count. Changing
/// a tag's value (e.g. a colour code) keeps the count/balance intact but
/// silently alters the rendered in-game text, so it must be flagged.
void main() {
  late ValidationServiceImpl svc;

  setUp(() {
    svc = ValidationServiceImpl(logger: NoopLogger());
  });

  group('checkMarkupPreservation - tag identity', () {
    test('changed colour tag value (same count, balanced) -> error', () async {
      final err = await svc.checkMarkupPreservation(
        sourceText: '[[col:red]]Warning[[/col]]',
        translatedText: '[[col:green]]Attention[[/col]]',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.markup);
      expect(err?.severity, ValidationSeverity.error);
    });

    test('identical tags preserved -> null (guard, no false positive)',
        () async {
      final err = await svc.checkMarkupPreservation(
        sourceText: '[[col:red]]Warning[[/col]]',
        translatedText: '[[col:red]]Attention[[/col]]',
        key: 'k',
      );
      expect(err, isNull);
    });
  });
}
