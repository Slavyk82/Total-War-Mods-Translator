import 'package:flutter_test/flutter_test.dart';
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
      expect(issue.message, isNotEmpty);
    }
  });
}
