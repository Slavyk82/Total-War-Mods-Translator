import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/validation_rule.dart';
import 'package:twmt/services/translation/i_validation_service.dart';
import 'package:twmt/services/translation/validation_service_impl.dart';

import '../../../helpers/noop_logger.dart';

void main() {
  late ValidationServiceImpl svc;

  setUp(() {
    svc = ValidationServiceImpl(logger: NoopLogger());
  });

  group('checkCompleteness', () {
    test('non-empty -> null', () async {
      expect(await svc.checkCompleteness(translatedText: 'Bonjour', key: 'k'),
          isNull);
    });

    test('empty -> error', () async {
      final err = await svc.checkCompleteness(translatedText: '   ', key: 'k');
      expect(err?.rule, ValidationRule.completeness);
      expect(err?.severity, ValidationSeverity.error);
    });
  });

  group('checkLength', () {
    test('within ratio -> null', () async {
      final err = await svc.checkLength(
        sourceText: 'Hello world',
        translatedText: 'Bonjour monde',
        key: 'k',
      );
      expect(err, isNull);
    });

    test('exceeds hard maxLength -> error', () async {
      final err = await svc.checkLength(
        sourceText: 'Hello',
        translatedText: 'x' * 50,
        key: 'k',
        maxLength: 10,
      );
      expect(err?.rule, ValidationRule.length);
      expect(err?.severity, ValidationSeverity.error);
      expect(err?.message, contains('exceeds maximum length'));
    });

    test('within maxLength but ratio fine -> null', () async {
      final err = await svc.checkLength(
        sourceText: 'Hello world',
        translatedText: 'Bonjour',
        key: 'k',
        maxLength: 100,
      );
      expect(err, isNull);
    });

    test('source length 0 -> null', () async {
      final err = await svc.checkLength(
        sourceText: '',
        translatedText: 'something',
        key: 'k',
      );
      expect(err, isNull);
    });

    test('translation too long (ratio) -> warning', () async {
      final err = await svc.checkLength(
        sourceText: 'short',
        translatedText: 'x' * 200,
        key: 'k',
      );
      expect(err?.rule, ValidationRule.length);
      expect(err?.severity, ValidationSeverity.warning);
      expect(err?.message, contains('differs significantly'));
    });

    test('translation too short (ratio) -> warning', () async {
      final err = await svc.checkLength(
        sourceText: 'x' * 200,
        translatedText: 'ab',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.length);
      expect(err?.severity, ValidationSeverity.warning);
    });
  });

  group('checkVariablePreservation', () {
    test('all preserved -> null', () async {
      final err = await svc.checkVariablePreservation(
        sourceText: 'Hello {0} %s',
        translatedText: 'Bonjour {0} %s',
        key: 'k',
      );
      expect(err, isNull);
    });

    test('missing simple variable -> error', () async {
      final err = await svc.checkVariablePreservation(
        sourceText: 'Hello {0}',
        translatedText: 'Bonjour',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.variables);
      expect(err?.severity, ValidationSeverity.error);
      expect(err?.message, contains('Missing variables'));
    });

    test('missing double-brace template -> warning (and triggers logging)',
        () async {
      final err = await svc.checkVariablePreservation(
        sourceText: 'Hello {{Cco:GetName()}}',
        translatedText: 'Bonjour',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.variables);
      expect(err?.severity, ValidationSeverity.warning);
      expect(err?.message, contains('Template expressions modified'));
    });

    test('extra variable in translation -> error', () async {
      final err = await svc.checkVariablePreservation(
        sourceText: 'Bonjour',
        translatedText: 'Bonjour {0}',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.variables);
      expect(err?.severity, ValidationSeverity.error);
      expect(err?.message, contains('Extra variables'));
    });

    test('double-brace preserved logs but returns null', () async {
      // Source has double-brace templates that ARE preserved -> exercises the
      // debug-logging branch while still returning null.
      final err = await svc.checkVariablePreservation(
        sourceText: 'Hello {{Cco:GetName()}}',
        translatedText: 'Bonjour {{Cco:GetName()}}',
        key: 'k',
      );
      expect(err, isNull);
    });
  });

  group('checkMarkupPreservation', () {
    test('balanced tags preserved -> null', () async {
      final err = await svc.checkMarkupPreservation(
        sourceText: '<b>Hi</b>',
        translatedText: '<b>Salut</b>',
        key: 'k',
      );
      expect(err, isNull);
    });

    test('source unbalanced but identical to target -> null', () async {
      final err = await svc.checkMarkupPreservation(
        sourceText: '[PH] Insert Text',
        translatedText: '[PH] Inserer le texte',
        key: 'k',
      );
      expect(err, isNull);
    });

    test('source unbalanced and differs -> warning', () async {
      final err = await svc.checkMarkupPreservation(
        sourceText: '<b>Insert Text',
        translatedText: 'Inserer le texte',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.markup);
      expect(err?.severity, ValidationSeverity.warning);
      expect(err?.message, contains('unbalanced markup tags'));
    });

    test('tag count mismatch -> error', () async {
      final err = await svc.checkMarkupPreservation(
        sourceText: '<b>Hi</b>',
        translatedText: 'Salut',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.markup);
      expect(err?.severity, ValidationSeverity.error);
      expect(err?.message, contains('tag count mismatch'));
    });

    test('balanced source, same count, unbalanced translation -> error',
        () async {
      // Source: <b></b> balanced. Translation: </b><b> same count (2) but
      // unbalanced ordering.
      final err = await svc.checkMarkupPreservation(
        sourceText: '<b>Hi</b>',
        translatedText: '</b>Salut<b>',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.markup);
      expect(err?.severity, ValidationSeverity.error);
      expect(err?.message, contains('Unbalanced markup tags in translation'));
    });
  });

  group('checkEncoding', () {
    test('clean text -> null', () async {
      expect(
        await svc.checkEncoding(translatedText: 'normal text\n\t', key: 'k'),
        isNull,
      );
    });

    test('replacement char -> error', () async {
      final err =
          await svc.checkEncoding(translatedText: 'bad �', key: 'k');
      expect(err?.rule, ValidationRule.encoding);
      expect(err?.severity, ValidationSeverity.error);
    });

    test('control character -> warning', () async {
      final err =
          await svc.checkEncoding(translatedText: 'bad\x01char', key: 'k');
      expect(err?.rule, ValidationRule.encoding);
      expect(err?.severity, ValidationSeverity.warning);
    });
  });

  group('checkGlossaryConsistency', () {
    test('term used -> null', () async {
      final err = await svc.checkGlossaryConsistency(
        sourceText: 'Use Empire',
        translatedText: 'Utilisez Empire',
        key: 'k',
        glossaryTerms: {'Empire': 'Empire'},
      );
      expect(err, isNull);
    });

    test('term not in source -> null', () async {
      final err = await svc.checkGlossaryConsistency(
        sourceText: 'Hello',
        translatedText: 'Bonjour',
        key: 'k',
        glossaryTerms: {'Empire': 'Empire'},
      );
      expect(err, isNull);
    });

    test('term in source but translation missing -> warning', () async {
      final err = await svc.checkGlossaryConsistency(
        sourceText: 'Use Empire',
        translatedText: 'Utilisez Reich',
        key: 'k',
        glossaryTerms: {'Empire': 'Empire'},
      );
      expect(err?.rule, ValidationRule.glossary);
      expect(err?.severity, ValidationSeverity.warning);
      expect(err?.message, contains('Glossary terms not used'));
    });
  });

  group('checkSecurity', () {
    test('clean text -> null', () async {
      expect(await svc.checkSecurity(translatedText: 'Bonjour', key: 'k'),
          isNull);
    });

    test('SQL injection pattern -> error', () async {
      final err = await svc.checkSecurity(
        translatedText: "' OR '1'='1",
        key: 'k',
      );
      expect(err?.rule, ValidationRule.security);
      expect(err?.severity, ValidationSeverity.error);
      expect(err?.message, contains('SQL injection'));
    });

    test('SQL token present but no injection shape -> null', () async {
      // Contains an apostrophe / OR keyword but not the quote-OR-quote shape.
      final err = await svc.checkSecurity(
        translatedText: "It's a choice",
        key: 'k',
      );
      expect(err, isNull);
    });

    test('script injection -> error', () async {
      final err = await svc.checkSecurity(
        translatedText: 'hello <script>alert(1)</script>',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.security);
      expect(err?.severity, ValidationSeverity.error);
      expect(err?.message, contains('script injection'));
    });

    test('javascript: scheme -> error', () async {
      final err = await svc.checkSecurity(
        translatedText: 'click javascript:void(0)',
        key: 'k',
      );
      expect(err?.severity, ValidationSeverity.error);
    });

    test('path traversal forward slash -> warning', () async {
      final err = await svc.checkSecurity(
        translatedText: 'go to ../secret',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.security);
      expect(err?.severity, ValidationSeverity.warning);
      expect(err?.message, contains('path traversal'));
    });

    test('path traversal backslash -> warning', () async {
      final err = await svc.checkSecurity(
        translatedText: r'go to ..\secret',
        key: 'k',
      );
      expect(err?.severity, ValidationSeverity.warning);
    });
  });

  group('checkTruncation', () {
    test('matching content -> null', () async {
      final err = await svc.checkTruncation(
        sourceText: 'A full sentence here',
        translatedText: 'Une phrase complete ici',
        key: 'k',
      );
      expect(err, isNull);
    });

    test('translation ellipsis not in source -> warning', () async {
      final err = await svc.checkTruncation(
        sourceText: 'A full sentence here',
        translatedText: 'A full sentence...',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.truncation);
      expect(err?.severity, ValidationSeverity.warning);
      expect(err?.message, contains('ends with ...'));
    });

    test('both end with ellipsis -> no truncation from ellipsis branch',
        () async {
      // Both end with ... so ellipsis branch is skipped; lengths comparable so
      // short branch also skipped -> null.
      final err = await svc.checkTruncation(
        sourceText: 'Loading data...',
        translatedText: 'Chargement des donnees...',
        key: 'k',
      );
      expect(err, isNull);
    });

    test('significantly shorter -> warning', () async {
      final err = await svc.checkTruncation(
        sourceText: 'This is a fairly long source sentence with detail',
        translatedText: 'Court',
        key: 'k',
      );
      expect(err?.rule, ValidationRule.truncation);
      expect(err?.severity, ValidationSeverity.warning);
      expect(err?.message, contains('significantly shorter'));
    });
  });

  group('checkCommonMistakes', () {
    test('punctuation preserved -> empty', () async {
      final mistakes = await svc.checkCommonMistakes(
        sourceText: 'Hello.',
        translatedText: 'Bonjour.',
        key: 'k',
      );
      expect(mistakes, isEmpty);
    });

    test('missing ending punctuation -> warning', () async {
      final mistakes = await svc.checkCommonMistakes(
        sourceText: 'Hello.',
        translatedText: 'Bonjour',
        key: 'k',
      );
      expect(mistakes, hasLength(1));
      expect(mistakes.first.rule, ValidationRule.endPunctuation);
      expect(mistakes.first.severity, ValidationSeverity.warning);
    });
  });

  group('validateTranslation aggregate', () {
    test('clean translation -> valid, no issues', () async {
      final result = await svc.validateTranslation(
        sourceText: 'Hello world.',
        translatedText: 'Bonjour le monde.',
        key: 'k',
      );
      expect(result.isOk, isTrue);
      final r = result.unwrap();
      expect(r.isValid, isTrue);
      expect(r.issues, isEmpty);
    });

    test('empty translation -> invalid with completeness error', () async {
      final result = await svc.validateTranslation(
        sourceText: 'Hello {0}',
        translatedText: '',
        key: 'k',
      );
      final r = result.unwrap();
      expect(r.isValid, isFalse);
      expect(r.issues.map((i) => i.rule), contains(ValidationRule.completeness));
    });

    test('warning-only issues -> still valid (default non-strict)', () async {
      // Truncation ellipsis is a warning; default strictMode = false.
      final result = await svc.validateTranslation(
        sourceText: 'A complete sentence here.',
        translatedText: 'A complete sentence...',
        key: 'k',
      );
      final r = result.unwrap();
      expect(r.isValid, isTrue);
      expect(r.issues, isNotEmpty);
      expect(r.issues.every((i) => i.severity == ValidationSeverity.warning),
          isTrue);
    });

    test('variable error path -> invalid', () async {
      final result = await svc.validateTranslation(
        sourceText: 'Hello {0}.',
        translatedText: 'Bonjour.',
        key: 'k',
      );
      final r = result.unwrap();
      expect(r.isValid, isFalse);
      expect(r.issues.map((i) => i.rule), contains(ValidationRule.variables));
    });

    test('security error path -> invalid', () async {
      final result = await svc.validateTranslation(
        sourceText: 'Login form text here.',
        translatedText: "Texte ' OR '1'='1 ici.",
        key: 'k',
      );
      final r = result.unwrap();
      expect(r.isValid, isFalse);
      expect(r.issues.map((i) => i.rule), contains(ValidationRule.security));
    });

    test('glossary check runs only when glossaryTerms provided', () async {
      final result = await svc.validateTranslation(
        sourceText: 'Use Empire today.',
        translatedText: 'Utilisez Reich aujourdhui.',
        key: 'k',
        glossaryTerms: {'Empire': 'Empire'},
      );
      final r = result.unwrap();
      expect(r.issues.map((i) => i.rule), contains(ValidationRule.glossary));
      // glossary is a warning -> still valid in non-strict mode.
      expect(r.isValid, isTrue);
    });

    test('length check runs when enabled via config and flags hard limit',
        () async {
      await svc.updateValidationRules(
        config: const ValidationRulesConfig(checkLength: true),
      );
      final result = await svc.validateTranslation(
        sourceText: 'Hi',
        translatedText: 'x' * 50,
        key: 'k',
        maxLength: 10,
      );
      final r = result.unwrap();
      expect(r.isValid, isFalse);
      expect(r.issues.map((i) => i.rule), contains(ValidationRule.length));
    });

    test('strict mode promotes warnings to errors -> invalid', () async {
      await svc.updateValidationRules(
        config: ValidationRulesConfig.strictConfig,
      );
      // Truncation ellipsis is normally a warning; strict mode -> error.
      final result = await svc.validateTranslation(
        sourceText: 'A complete sentence here.',
        translatedText: 'A complete sentence...',
        key: 'k',
      );
      final r = result.unwrap();
      expect(r.isValid, isFalse);
      expect(
        r.issues.any((i) => i.severity == ValidationSeverity.error),
        isTrue,
      );
    });

    test('encoding error path -> invalid', () async {
      final result = await svc.validateTranslation(
        sourceText: 'Some source text here.',
        translatedText: 'Texte avec � probleme.',
        key: 'k',
      );
      final r = result.unwrap();
      expect(r.isValid, isFalse);
      expect(r.issues.map((i) => i.rule), contains(ValidationRule.encoding));
    });

    test('markup error path -> invalid', () async {
      final result = await svc.validateTranslation(
        sourceText: '<b>Hello there friend</b>',
        translatedText: 'Bonjour cher ami sans balise',
        key: 'k',
      );
      final r = result.unwrap();
      expect(r.isValid, isFalse);
      expect(r.issues.map((i) => i.rule), contains(ValidationRule.markup));
    });

    test('common mistakes (punctuation) appears as issue', () async {
      final result = await svc.validateTranslation(
        sourceText: 'A normal sentence here.',
        translatedText: 'Une phrase normale ici',
        key: 'k',
      );
      final r = result.unwrap();
      expect(
        r.issues.map((i) => i.rule),
        contains(ValidationRule.endPunctuation),
      );
    });
  });

  group('validateBatch', () {
    test('validates each entry', () async {
      final result = await svc.validateBatch(
        translations: {
          'a': 'Bonjour le monde.',
          'b': '',
        },
        sourcesMap: {
          'a': 'Hello world.',
          'b': 'Hello.',
        },
      );
      expect(result.isOk, isTrue);
      final map = result.unwrap();
      expect(map['a']!.isValid, isTrue);
      expect(map['b']!.isValid, isFalse);
    });

    test('missing source for key -> invalid entry with completeness error',
        () async {
      final result = await svc.validateBatch(
        translations: {'a': 'Bonjour.'},
        sourcesMap: {},
      );
      final map = result.unwrap();
      expect(map['a']!.isValid, isFalse);
      expect(
        map['a']!.issues.first.message,
        contains('Source text not found'),
      );
    });
  });

  group('validateLlmResponse', () {
    test('valid response -> map', () async {
      final result = await svc.validateLlmResponse(
        jsonResponse:
            '{"translations":[{"key":"k1","translation":"Bonjour"}]}',
        expectedKeys: ['k1'],
      );
      expect(result.isOk, isTrue);
      expect(result.unwrap()['k1'], 'Bonjour');
    });

    test('invalid JSON -> error', () async {
      final result = await svc.validateLlmResponse(
        jsonResponse: 'not json',
        expectedKeys: ['k1'],
      );
      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Invalid JSON'));
    });

    test('missing translations field -> error', () async {
      final result = await svc.validateLlmResponse(
        jsonResponse: '{"foo":"bar"}',
        expectedKeys: ['k1'],
      );
      expect(result.isErr, isTrue);
      expect(result.error.message, contains('missing "translations"'));
    });

    test('translations not a list -> error', () async {
      final result = await svc.validateLlmResponse(
        jsonResponse: '{"translations":"oops"}',
        expectedKeys: ['k1'],
      );
      expect(result.isErr, isTrue);
      expect(result.error.message, contains('is not a list'));
    });

    test('non-map / null entries skipped, missing keys -> error', () async {
      final result = await svc.validateLlmResponse(
        jsonResponse:
            '{"translations":[123,{"key":"k1","translation":"Bonjour"},{"key":null}]}',
        expectedKeys: ['k1', 'k2'],
      );
      expect(result.isErr, isTrue);
      expect(result.error.message, contains('missing translations for keys'));
      expect(result.error.message, contains('k2'));
    });

    test('all expected keys present including extra entries -> ok', () async {
      final result = await svc.validateLlmResponse(
        jsonResponse: '{"translations":['
            '{"key":"k1","translation":"A"},'
            '{"key":"k2","translation":"B"},'
            '{"key":"k3","translation":"C"}]}',
        expectedKeys: ['k1', 'k2'],
      );
      expect(result.isOk, isTrue);
      expect(result.unwrap().length, 3);
    });
  });

  group('config getters/setters', () {
    test('getValidationRules returns default initially', () async {
      final cfg = await svc.getValidationRules();
      expect(cfg.checkCompleteness, isTrue);
      expect(cfg.checkLength, isFalse);
      expect(cfg.strictMode, isFalse);
    });

    test('updateValidationRules replaces config', () async {
      await svc.updateValidationRules(
        config: ValidationRulesConfig.lenientConfig,
      );
      final cfg = await svc.getValidationRules();
      expect(cfg.checkTruncation, isFalse);
      expect(cfg.checkCommonMistakes, isFalse);
      expect(cfg.maxLengthDifferenceRatio, 3.0);
    });
  });
}
