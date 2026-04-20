import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/utils/display_escape.dart';

void main() {
  group('escapeForDisplay', () {
    test('renders control whitespace as literal backslash sequences', () {
      expect(escapeForDisplay('a\nb'), r'a\nb');
      expect(escapeForDisplay('a\tb'), r'a\tb');
      expect(escapeForDisplay('a\rb'), r'a\rb');
      expect(escapeForDisplay('a\r\nb'), r'a\r\nb');
    });

    test('leaves backslashes untouched so literal `\\n` stays visible', () {
      // Total War .loc source text often contains literal backslashes in
      // front of `n`; they must NOT be doubled up at display time.
      expect(escapeForDisplay(r'Forest\n(0-19)'), r'Forest\n(0-19)');
      expect(escapeForDisplay(r'Forest\\n(0-19)'), r'Forest\\n(0-19)');
    });

    test('no-op on plain text', () {
      expect(escapeForDisplay('Bonjour le monde'), 'Bonjour le monde');
    });
  });

  group('unescapeFromDisplay', () {
    test('converts backslash sequences back to control whitespace', () {
      expect(unescapeFromDisplay(r'a\nb'), 'a\nb');
      expect(unescapeFromDisplay(r'a\tb'), 'a\tb');
      expect(unescapeFromDisplay(r'a\rb'), 'a\rb');
      expect(unescapeFromDisplay(r'a\r\nb'), 'a\r\nb');
    });

    test('round-trips real-whitespace payloads with escapeForDisplay', () {
      // Target translations are always stored with real whitespace
      // (normalised by the LLM pipeline and TSV parser), so these are the
      // round-trips that matter in practice.
      const samples = [
        'plain',
        'with\nnewline',
        'with\ttab',
        'mixed\r\nCRLF\nLF',
      ];
      for (final raw in samples) {
        expect(unescapeFromDisplay(escapeForDisplay(raw)), raw,
            reason: 'Round-trip broke for ${raw.codeUnits}');
      }
    });
  });
}
