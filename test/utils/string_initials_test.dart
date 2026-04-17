import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/utils/string_initials.dart';

void main() {
  group('initials', () {
    test('empty input returns empty string', () {
      expect(initials(''), '');
      expect(initials('   '), '');
    });

    test('single word uses first letters up to max', () {
      expect(initials('Warhammer'), 'WA');
      expect(initials('Warhammer', max: 3), 'WAR');
      expect(initials('a'), 'A');
    });

    test('multi-word takes first letter of each word', () {
      expect(initials('Three Kingdoms'), 'TK');
      expect(initials('Total War Warhammer III'), 'TW');
      expect(initials('Total War Warhammer III', max: 3), 'TWW');
    });

    test('uppercases and strips non-alphanumerics', () {
      expect(initials('  sigmars heirs  '), 'SH');
      expect(initials('project #42'), 'P4');
      // Single-word input (no whitespace): diacritic is preserved via
      // Latin-1 uppercase mapping. Implementation only splits on whitespace,
      // so 'été-automne' is one word and the first two alphanumeric chars
      // are taken: É + T.
      expect(initials('été-automne'), 'ÉT');
    });
  });
}
