import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/models/localization_entry.dart';
import 'package:twmt/services/file/models/localization_file.dart';
import 'package:twmt/services/file/utils/file_validator.dart';

LocalizationEntry _entry(String key, String value) =>
    LocalizationEntry(key: key, value: value);

LocalizationFile _file(
  List<LocalizationEntry> entries, {
  String encoding = 'utf-8',
}) =>
    LocalizationFile(
      fileName: 'text.loc',
      filePath: 'C:/x/text.loc',
      languageCode: 'fr',
      encoding: encoding,
      entries: entries,
    );

void main() {
  final v = FileValidator();

  group('validateTsvLine', () {
    test('rejects blank lines and lines without a tab', () {
      expect(v.validateTsvLine('   '), isFalse);
      expect(v.validateTsvLine('no-tab-here'), isFalse);
    });

    test('accepts comment lines', () {
      expect(v.validateTsvLine('# a comment'), isTrue);
    });

    test('rejects a tab line with an empty key', () {
      expect(v.validateTsvLine('\tvalue'), isFalse);
    });

    test('accepts a well-formed key\\tvalue line', () {
      expect(v.validateTsvLine('my_key\tmy value'), isTrue);
    });
  });

  group('validateEntry', () {
    test('a normal entry is valid with no errors', () {
      final r = v.validateEntry(_entry('unit_name_x', 'Bonjour'));
      expect(r.isValid, isTrue);
      expect(r.errors, isEmpty);
    });

    test('empty key, tab and newline in key are errors', () {
      expect(v.validateEntry(_entry('   ', 'v')).errors,
          contains('Entry has empty key'));
      expect(
        v.validateEntry(_entry('a\tb', 'v')).errors.any((e) => e.contains('tab')),
        isTrue,
      );
      expect(
        v
            .validateEntry(_entry('a\nb', 'v'))
            .errors
            .any((e) => e.contains('newline')),
        isTrue,
      );
    });

    test('empty value is an error when requireNonEmptyValues (default)', () {
      final r = v.validateEntry(_entry('key_a', '   '));
      expect(r.errors.any((e) => e.contains('empty value')), isTrue);
    });

    test('an unusual key format produces a warning', () {
      // No underscore/hyphen -> _isValidKeyFormat false -> warning.
      final r = v.validateEntry(_entry('plainkey', 'v'));
      expect(r.warnings.any((w) => w.contains('unusual format')), isTrue);
    });

    test('a literal tab in the value warns about unescaped characters', () {
      final r = v.validateEntry(_entry('key_a', 'has\ttab'));
      expect(r.warnings.any((w) => w.contains('unescaped')), isTrue);
    });

    test('a value over maxValueLength warns', () {
      final r = v.validateEntry(
        _entry('key_a', 'x' * 11),
        options: const ValidationOptions(maxValueLength: 10),
      );
      expect(r.warnings.any((w) => w.contains('Very long value')), isTrue);
    });
  });

  group('validateLocalizationFile', () {
    test('a clean file is valid', () {
      final r = v.validateLocalizationFile(
        _file([_entry('key_a', 'Alpha'), _entry('key_b', 'Beta')]),
      );
      expect(r.isValid, isTrue);
      expect(r.errors, isEmpty);
    });

    test('an invalid encoding is an error', () {
      final r = v.validateLocalizationFile(
        _file([_entry('key_a', 'Alpha')], encoding: 'latin-1'),
      );
      expect(r.errors.any((e) => e.contains('Invalid encoding')), isTrue);
      expect(r.isValid, isFalse);
    });

    test('empty entries error under strict, warn under default', () {
      final strict = v.validateLocalizationFile(_file([]),
          options: ValidationOptions.strict);
      expect(strict.errors, contains('File contains no entries'));

      final lenient = v.validateLocalizationFile(_file([]));
      expect(lenient.warnings, contains('File contains no entries'));
    });

    test('duplicate keys are reported', () {
      final r = v.validateLocalizationFile(
        _file([_entry('dup_key', 'a'), _entry('dup_key', 'b')]),
      );
      expect(r.errors.any((e) => e.contains('Duplicate keys')), isTrue);
    });

    test('a replacement character flags a possible encoding issue', () {
      final r = v.validateLocalizationFile(
        _file([_entry('key_a', 'café �')]),
      );
      expect(r.warnings.any((w) => w.contains('encoding issues')), isTrue);
    });

    test('very short values produce a warning', () {
      final r = v.validateLocalizationFile(
        _file([_entry('key_a', 'ok'), _entry('key_b', 'fine')]),
      );
      expect(r.warnings.any((w) => w.contains('very short values')), isTrue);
    });
  });

  group('validatePath', () {
    test('an empty path is invalid', () {
      final r = v.validatePath('   ');
      expect(r.isValid, isFalse);
      expect(r.errors, contains('File path is empty'));
    });

    test('a relative, non-.loc path warns on both counts', () {
      final r = v.validatePath('relative/file.txt');
      expect(r.warnings.any((w) => w.contains('Relative path')), isTrue);
      expect(r.warnings.any((w) => w.contains('.loc extension')), isTrue);
    });

    test('an absolute .loc path in an existing directory is valid', () {
      final dir = Directory.systemTemp.path;
      final r = v.validatePath('$dir${Platform.pathSeparator}sample.loc');
      expect(r.isValid, isTrue);
      expect(r.errors, isEmpty);
    });
  });
}
