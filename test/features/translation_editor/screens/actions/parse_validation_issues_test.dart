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

    test('malformed JSON falls back to a legacy entry with the raw payload',
        () {
      const raw = '{not json';
      final parsed = parseValidationIssues(raw);
      expect(parsed.single.type, 'legacy');
      expect(parsed.single.description, raw);
    });
  });
}
