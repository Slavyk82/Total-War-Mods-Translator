import 'package:flutter_test/flutter_test.dart';
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

    test('missing ending punctuation -> ValidationRule.endPunctuation',
        () async {
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
  });
}
