import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/llm/utils/cl100k_base_ranks.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';

// Guards the vendored cl100k_base ranks table that TokenCalculator parses
// instead of tiktoken's own ~100k-entry map literal (see TokenCalculator's
// class doc for why). Two failure modes matter and neither is caught by the
// loose envelopes in token_calculator_test.dart:
//
//  1. A regeneration that silently drops entries. In tiktoken's source, 152
//     long tokens are wrapped across two lines by dartfmt, so any scrape that
//     reads the file line-by-line loses exactly those. They encode long runs
//     of repeated punctuation, so the golden counts below would explode.
//  2. A truncated or reordered table, caught by the integrity checks.

void main() {
  group('cl100kBaseRanksData integrity', () {
    late List<String> lines;

    setUpAll(() {
      lines = const LineSplitter()
          .convert(cl100kBaseRanksData)
          .where((l) => l.isNotEmpty)
          .toList();
    });

    test('holds the full cl100k_base vocabulary (100,256 entries)', () {
      expect(lines, hasLength(100256));
    });

    test('every line is a decodable "<base64> <rank>" pair', () {
      for (final line in lines) {
        final separator = line.indexOf(' ');
        expect(separator, greaterThan(0), reason: 'malformed line: $line');
        expect(
          () => base64Decode(line.substring(0, separator)),
          returnsNormally,
          reason: 'undecodable token in line: $line',
        );
        expect(int.tryParse(line.substring(separator + 1)), isNotNull,
            reason: 'non-numeric rank in line: $line');
      }
    });

    test('ranks are unique and cover 0..100255 with no gaps', () {
      final ranks = <int>{};
      for (final line in lines) {
        ranks.add(int.parse(line.substring(line.indexOf(' ') + 1)));
      }
      expect(ranks, hasLength(lines.length), reason: 'duplicate ranks present');
      expect(ranks.reduce((a, b) => a < b ? a : b), 0);
      expect(ranks.reduce((a, b) => a > b ? a : b), 100255);
    });

    test('tokens are unique', () {
      final tokens = <String>{};
      for (final line in lines) {
        tokens.add(line.substring(0, line.indexOf(' ')));
      }
      expect(tokens, hasLength(lines.length), reason: 'duplicate tokens');
    });
  });

  group('TokenCalculator golden counts (parity with tiktoken cl100k_base)', () {
    late TokenCalculator calc;

    setUpAll(() => calc = TokenCalculator());

    // Captured from tiktoken's own getEncoding('cl100k_base'). Exact values,
    // not envelopes: the point is to detect drift, not merely non-emptiness.
    const golden = <String, int>{
      'hello world': 2,
      '[[col:red]]Attack![[/col]] [%s]': 13,
      '中文测试文本': 5,
      '👋 hello ß привет': 9,
    };

    golden.forEach((text, expected) {
      test('encodes ${jsonEncode(text)} as $expected tokens', () {
        expect(calc.calculateTokens(text), expected);
      });
    });

    // These collapse long runs into very few tokens ONLY if the long
    // multi-line-wrapped entries survived regeneration.
    const runs = <String, (String, int)>{
      '120 dashes': ('-', 3),
      '120 asterisks': ('*', 2),
      '90 equals': ('=', 2),
    };

    runs.forEach((name, spec) {
      test('$name collapse to ${spec.$2} tokens (long-token coverage)', () {
        final text = spec.$1 * (name.startsWith('90') ? 90 : 120);
        expect(calc.calculateTokens(text), spec.$2);
      });
    });

    test('96 spaces collapse to 2 tokens', () {
      expect(calc.calculateTokens(' ' * 96), 2);
    });
  });
}
