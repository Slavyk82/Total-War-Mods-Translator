import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation/utils/text_parser_utils.dart';

void main() {
  group('extractVariables - printf grammar (H2)', () {
    test('extracts %u (unsigned)', () {
      expect(TextParserUtils.extractVariables('Gain %u renown'), contains('%u'));
    });

    test('extracts %i (signed int)', () {
      expect(TextParserUtils.extractVariables('Turn %i'), contains('%i'));
    });

    test('extracts %x and %X (hex)', () {
      expect(TextParserUtils.extractVariables('id %x'), contains('%x'));
      expect(TextParserUtils.extractVariables('id %X'), contains('%X'));
    });

    test('extracts length-modified %ld and %lu', () {
      expect(TextParserUtils.extractVariables('n=%ld'), contains('%ld'));
      expect(TextParserUtils.extractVariables('n=%lu'), contains('%lu'));
    });

    test('extracts width/flag/precision %02d and %.2f', () {
      expect(TextParserUtils.extractVariables('hp %02d'), contains('%02d'));
      expect(TextParserUtils.extractVariables('rate %.2f'), contains('%.2f'));
    });

    test('extracts positional %1\$s', () {
      expect(
        TextParserUtils.extractVariables(r'Move %1$s to %2$s'),
        containsAll(<String>[r'%1$s', r'%2$s']),
      );
    });

    test('extracts literal-percent token %%', () {
      expect(TextParserUtils.extractVariables('Chance: 50%%'), contains('%%'));
    });

    // --- Regressions: existing specifiers still work ---
    test('still extracts %s %d %f', () {
      final vars = TextParserUtils.extractVariables('a %s b %d c %f');
      expect(vars, containsAll(<String>['%s', '%d', '%f']));
    });
  });

  group('extractVariables - printf false positives (guard)', () {
    test('does NOT match a bare percent followed by a space ("50% off")', () {
      expect(TextParserUtils.extractVariables('50% off today'), isEmpty);
    });

    test('does NOT match spaced percent ("100 % done")', () {
      expect(TextParserUtils.extractVariables('100 % done'), isEmpty);
    });
  });
}
