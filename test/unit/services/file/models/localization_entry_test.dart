import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/models/localization_entry.dart';

void main() {
  group('fromTsvLine', () {
    test('throws on blank or comment lines', () {
      expect(() => LocalizationEntry.fromTsvLine('   '), throwsFormatException);
      expect(() => LocalizationEntry.fromTsvLine('# comment'),
          throwsFormatException);
    });

    test('throws when there is no tab separator', () {
      expect(() => LocalizationEntry.fromTsvLine('nokeyvalue'),
          throwsFormatException);
    });

    test('parses key/value and processes escape sequences', () {
      final e = LocalizationEntry.fromTsvLine('my_key\tline1\\nline2');
      expect(e.key, 'my_key');
      expect(e.value, 'line1\nline2'); // \n unescaped to a real newline
      expect(e.rawValue, 'line1\\nline2');
    });
  });

  group('toTsvLine', () {
    test('escapes special characters back to TSV form', () {
      const e = LocalizationEntry(key: 'k', value: 'a\nb\tc');
      expect(e.toTsvLine(), r'k' '\t' r'a\nb\tc');
    });
  });

  group('isValid', () {
    test('a normal entry is valid', () {
      expect(const LocalizationEntry(key: 'unit_x', value: 'Bonjour').isValid(),
          isTrue);
    });

    test('an empty key or a key with control chars is invalid', () {
      expect(const LocalizationEntry(key: '  ', value: 'v').isValid(), isFalse);
      expect(const LocalizationEntry(key: 'a\tb', value: 'v').isValid(), isFalse);
      expect(const LocalizationEntry(key: 'a\nb', value: 'v').isValid(), isFalse);
    });
  });

  group('copyWith / equality / json', () {
    test('copyWith overrides only the targeted field', () {
      const e = LocalizationEntry(key: 'k', value: 'v');
      expect(e.copyWith(value: 'w').value, 'w');
      expect(e.copyWith(value: 'w').key, 'k');
    });

    test('value equality + json round-trip', () {
      const e = LocalizationEntry(key: 'k', value: 'v', lineNumber: 3);
      expect(e, equals(const LocalizationEntry(key: 'k', value: 'v', lineNumber: 3)));
      final restored = LocalizationEntry.fromJson(e.toJson());
      expect(restored.key, 'k');
      expect(restored.lineNumber, 3);
    });
  });
}
