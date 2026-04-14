import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation/utils/translation_skip_filter.dart';

void main() {
  // Note: these tests exercise the fallback branch of [shouldSkip] where
  // [TranslationSkipFilter._service] is null. The database-backed path is
  // covered by separate integration tests for [IgnoredSourceTextService].
  // We deliberately do NOT call [TranslationSkipFilter.initialize] here so
  // the fallback behaviour is deterministic.

  group('TranslationSkipFilter.startsWithHidden', () {
    test('matches the literal [HIDDEN] prefix', () {
      expect(TranslationSkipFilter.startsWithHidden('[HIDDEN]foo'), isTrue);
    });

    test('matches case-insensitively', () {
      expect(TranslationSkipFilter.startsWithHidden('[hidden] bar'), isTrue);
      expect(TranslationSkipFilter.startsWithHidden('[Hidden]X'), isTrue);
    });

    test('matches when surrounded by whitespace', () {
      expect(TranslationSkipFilter.startsWithHidden('   [HIDDEN] foo'), isTrue);
    });

    test('does not match when prefix is absent or embedded', () {
      expect(TranslationSkipFilter.startsWithHidden('foo [HIDDEN]'), isFalse);
      expect(TranslationSkipFilter.startsWithHidden('plain text'), isFalse);
      expect(TranslationSkipFilter.startsWithHidden(''), isFalse);
    });
  });

  group('TranslationSkipFilter.isFullyBracketedText', () {
    test('recognises simple single-bracket placeholders', () {
      expect(
        TranslationSkipFilter.isFullyBracketedText('[PLACEHOLDER]'),
        isTrue,
      );
      expect(
        TranslationSkipFilter.isFullyBracketedText('[unit_name]'),
        isTrue,
      );
    });

    test('tolerates surrounding whitespace', () {
      expect(
        TranslationSkipFilter.isFullyBracketedText('  [token]  '),
        isTrue,
      );
    });

    test('rejects BBCode / Total War double-bracket tags', () {
      expect(
        TranslationSkipFilter.isFullyBracketedText(
          '[[col:yellow]]text[[/col]]',
        ),
        isFalse,
      );
      expect(
        TranslationSkipFilter.isFullyBracketedText('[[something]]'),
        isFalse,
      );
    });

    test('rejects strings with extra brackets inside', () {
      expect(
        TranslationSkipFilter.isFullyBracketedText('[a[b]c]'),
        isFalse,
      );
      expect(
        TranslationSkipFilter.isFullyBracketedText('[foo] [bar]'),
        isFalse,
      );
    });

    test('rejects strings that do not start or end with brackets', () {
      expect(
        TranslationSkipFilter.isFullyBracketedText('prefix [PLACEHOLDER]'),
        isFalse,
      );
      expect(
        TranslationSkipFilter.isFullyBracketedText('[PLACEHOLDER] suffix'),
        isFalse,
      );
      expect(
        TranslationSkipFilter.isFullyBracketedText('plain text'),
        isFalse,
      );
    });

    test('rejects empty brackets and strings shorter than 3 chars', () {
      // Length <= 2 short-circuits the function.
      expect(TranslationSkipFilter.isFullyBracketedText('[]'), isFalse);
      expect(TranslationSkipFilter.isFullyBracketedText(''), isFalse);
      expect(TranslationSkipFilter.isFullyBracketedText('['), isFalse);
    });
  });

  group('TranslationSkipFilter.shouldSkip', () {
    test('skips text starting with [HIDDEN] prefix', () {
      expect(TranslationSkipFilter.shouldSkip('[HIDDEN]secret'), isTrue);
      expect(TranslationSkipFilter.shouldSkip('  [hidden] foo'), isTrue);
    });

    test('does not skip text that merely contains HIDDEN', () {
      expect(TranslationSkipFilter.shouldSkip('This is HIDDEN data'), isFalse);
      expect(TranslationSkipFilter.shouldSkip('foo [HIDDEN]'), isFalse);
    });

    test('skips fully bracketed placeholders', () {
      expect(TranslationSkipFilter.shouldSkip('[PLACEHOLDER]'), isTrue);
      expect(TranslationSkipFilter.shouldSkip('[unit_name]'), isTrue);
      expect(TranslationSkipFilter.shouldSkip('  [token]  '), isTrue);
    });

    test('does not skip BBCode double-bracket tags', () {
      expect(
        TranslationSkipFilter.shouldSkip('[[col:yellow]]text[[/col]]'),
        isFalse,
      );
    });

    test('skips default fallback tokens (case-insensitive, trimmed)', () {
      expect(TranslationSkipFilter.shouldSkip('placeholder'), isTrue);
      expect(TranslationSkipFilter.shouldSkip('PLACEHOLDER'), isTrue);
      expect(TranslationSkipFilter.shouldSkip('  Dummy  '), isTrue);
      expect(TranslationSkipFilter.shouldSkip('dummy'), isTrue);
    });

    test('does not skip arbitrary translatable text', () {
      expect(TranslationSkipFilter.shouldSkip('Hello world'), isFalse);
      expect(TranslationSkipFilter.shouldSkip('Unit name: soldier'), isFalse);
      expect(TranslationSkipFilter.shouldSkip('dummy text'), isFalse);
    });

    test('does not skip empty or whitespace-only strings by itself', () {
      // Empty strings are NOT in the default set and are not bracketed,
      // so shouldSkip returns false. This guards against regressions that
      // would incorrectly blanket-skip empty inputs.
      expect(TranslationSkipFilter.shouldSkip(''), isFalse);
      expect(TranslationSkipFilter.shouldSkip('   '), isFalse);
    });
  });

  group('TranslationSkipFilter.isInitialized', () {
    test('reports false when no service has been registered', () {
      // Relies on static state: no test in this file calls initialize().
      expect(TranslationSkipFilter.isInitialized, isFalse);
    });
  });

  group('TranslationSkipFilter.getSqlCondition', () {
    test('builds fallback SQL listing default skip tokens', () {
      final sql = TranslationSkipFilter.getSqlCondition();
      expect(sql, contains('LOWER(TRIM(tu.source_text)) IN'));
      expect(sql, contains("'placeholder'"));
      expect(sql, contains("'dummy'"));
    });
  });
}
