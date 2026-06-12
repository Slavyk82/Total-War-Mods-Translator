import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/models/localization_entry.dart';
import 'package:twmt/services/file/models/localization_file.dart';

LocalizationEntry _e(String key, [String value = 'v']) =>
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
  group('lookup helpers', () {
    final file = _file([_e('a', 'Alpha'), _e('b', 'Beta')]);

    test('getEntry returns the matching entry or null', () {
      expect(file.getEntry('a')?.value, 'Alpha');
      expect(file.getEntry('missing'), isNull);
    });

    test('containsKey / keys / counts / emptiness', () {
      expect(file.containsKey('b'), isTrue);
      expect(file.containsKey('z'), isFalse);
      expect(file.keys, ['a', 'b']);
      expect(file.entryCount, 2);
      expect(file.isEmpty, isFalse);
      expect(file.isNotEmpty, isTrue);
      expect(_file([]).isEmpty, isTrue);
    });
  });

  group('static filename helpers', () {
    test('generatePrefixedFileName adds the prefix, lang and .loc', () {
      expect(LocalizationFile.generatePrefixedFileName('units', 'fr'),
          '!!!!!!!!!!_FR_units.loc');
    });

    test('generatePrefixedFileName strips an existing prefix', () {
      expect(
        LocalizationFile.generatePrefixedFileName('!!!!!!!!!!_EN_units.loc', 'fr'),
        '!!!!!!!!!!_FR_units.loc',
      );
    });

    test('extractLanguageCode reads the lang or returns null', () {
      expect(LocalizationFile.extractLanguageCode('!!!!!!!!!!_FR_units.loc'), 'fr');
      expect(LocalizationFile.extractLanguageCode('plain.loc'), isNull);
    });

    test('extractBaseName strips the prefix and lang', () {
      expect(LocalizationFile.extractBaseName('!!!!!!!!!!_FR_units.loc'),
          'units.loc');
      expect(LocalizationFile.extractBaseName('plain.loc'), 'plain.loc');
    });
  });

  group('validate', () {
    test('a clean file is valid with no errors', () {
      final r = _file([_e('a'), _e('b')]).validate();
      expect(r.isValid, isTrue);
      expect(r.hasErrors, isFalse);
    });

    test('an unsupported encoding is an error', () {
      final r = _file([_e('a')], encoding: 'latin-1').validate();
      expect(r.isValid, isFalse);
      expect(r.errors.any((e) => e.contains('Unsupported encoding')), isTrue);
    });

    test('duplicate keys are an error; empty entries are a warning', () {
      final dup = _file([_e('k'), _e('k')]).validate();
      expect(dup.errors.any((e) => e.contains('Duplicate keys')), isTrue);

      final empty = _file([]).validate();
      expect(empty.warnings.any((w) => w.contains('no entries')), isTrue);
      expect(empty.hasWarnings, isTrue);
    });
  });

  group('copyWith / json (scalar) ', () {
    test('copyWith overrides the targeted field', () {
      final f = _file([_e('a')]);
      expect(f.copyWith(languageCode: 'de').languageCode, 'de');
      expect(f.copyWith(languageCode: 'de').fileName, 'text.loc');
    });

    test('json round-trip on an entry-less file', () {
      // Nested LocalizationEntry objects are not converted by the generated
      // toJson, so round-trip with no entries.
      final f = _file([]);
      final restored = LocalizationFile.fromJson(f.toJson());
      expect(restored.fileName, 'text.loc');
      expect(restored.languageCode, 'fr');
      expect(restored.encoding, 'utf-8');
    });
  });

  group('FileValidationResult', () {
    test('hasErrors / hasWarnings / issueCount', () {
      const r = FileValidationResult(
        isValid: false,
        errors: ['e1', 'e2'],
        warnings: ['w1'],
      );
      expect(r.hasErrors, isTrue);
      expect(r.hasWarnings, isTrue);
      expect(r.issueCount, 3);
    });
  });

  group('LocalizationFileMetadata', () {
    test('equality + json round-trip', () {
      final m = LocalizationFileMetadata(
        createdAt: DateTime(2026, 1, 1),
        modifiedAt: DateTime(2026, 1, 2),
        sizeBytes: 1024,
        totalLines: 10,
      );
      expect(
        m,
        equals(LocalizationFileMetadata(
          createdAt: DateTime(2026, 1, 1),
          modifiedAt: DateTime(2026, 1, 2),
          sizeBytes: 1024,
          totalLines: 10,
        )),
      );
      final restored = LocalizationFileMetadata.fromJson(m.toJson());
      expect(restored.sizeBytes, 1024);
      expect(restored.totalLines, 10);
    });
  });
}
