import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/models/localization_file.dart';

void main() {
  group('generatePrefixedFileName', () {
    test('uses the default prefix when none is provided', () {
      expect(
        LocalizationFile.generatePrefixedFileName('units.loc', 'fr'),
        '!!!!!!!!!!_FR_units.loc',
      );
    });

    test('uses a custom prefix when provided', () {
      expect(
        LocalizationFile.generatePrefixedFileName('units.loc', 'fr',
            prefix: 'zzz'),
        'zzz_FR_units.loc',
      );
    });

    test('strips an existing standard prefix before re-prefixing', () {
      expect(
        LocalizationFile.generatePrefixedFileName(
            '!!!!!!!!!!_EN_units.loc', 'fr',
            prefix: 'zzz'),
        'zzz_FR_units.loc',
      );
    });

    test('strips an existing custom prefix before re-prefixing', () {
      expect(
        LocalizationFile.generatePrefixedFileName('zzz_EN_units.loc', 'fr',
            prefix: 'zzz'),
        'zzz_FR_units.loc',
      );
    });

    test('strips a custom prefix that contains underscores', () {
      expect(
        LocalizationFile.generatePrefixedFileName(
            'zzz_grp_EN_units.loc', 'fr',
            prefix: 'zzz_grp'),
        'zzz_grp_FR_units.loc',
      );
    });

    test('generates with an empty prefix', () {
      expect(
        LocalizationFile.generatePrefixedFileName('units.loc', 'fr',
            prefix: ''),
        '_FR_units.loc',
      );
    });
  });

  group('extractLanguageCode (detection unchanged)', () {
    test('still detects the standard prefix even with custom generation', () {
      expect(
        LocalizationFile.extractLanguageCode('!!!!!!!!!!_FR_units.loc'),
        'fr',
      );
    });
  });
}
