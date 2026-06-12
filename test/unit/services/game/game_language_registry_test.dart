import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/game/game_language_registry.dart';

/// Pins the consolidated language-alias behavior for [GameLanguageRegistry],
/// the single source of truth that replaced three previously-duplicated tables
/// (pack code -> ISO/DB code, code -> flag asset basename, code -> display
/// name).
void main() {
  group('GameLanguageRegistry.isoCode', () {
    test('maps Total War variant codes to ISO/DB codes', () {
      expect(GameLanguageRegistry.isoCode('cn'), 'zh');
      expect(GameLanguageRegistry.isoCode('tw'), 'zh');
      expect(GameLanguageRegistry.isoCode('jp'), 'ja');
      expect(GameLanguageRegistry.isoCode('kr'), 'ko');
      expect(GameLanguageRegistry.isoCode('cz'), 'cs');
      expect(GameLanguageRegistry.isoCode('br'), 'pt');
    });

    test('is case-insensitive', () {
      expect(GameLanguageRegistry.isoCode('PT'), 'pt');
      expect(GameLanguageRegistry.isoCode('EN'), 'en');
    });

    test('returns lowercased input unchanged for unknown codes', () {
      expect(GameLanguageRegistry.isoCode('xx'), 'xx');
      expect(GameLanguageRegistry.isoCode('XX'), 'xx');
    });
  });

  group('GameLanguageRegistry.flagCode', () {
    test('maps Brazilian Portuguese variants to br flag', () {
      expect(GameLanguageRegistry.flagCode('ptbr'), 'br');
      expect(GameLanguageRegistry.flagCode('pt-br'), 'br');
      expect(GameLanguageRegistry.flagCode('pt_br'), 'br');
      expect(GameLanguageRegistry.flagCode('br'), 'br');
    });

    test('plain pt uses the Portugal flag', () {
      expect(GameLanguageRegistry.flagCode('pt'), 'pt');
    });

    test('maps Total War pack codes to their flag file names', () {
      expect(GameLanguageRegistry.flagCode('cn'), 'zh');
      expect(GameLanguageRegistry.flagCode('tw'), 'zh');
      expect(GameLanguageRegistry.flagCode('jp'), 'ja');
      expect(GameLanguageRegistry.flagCode('kr'), 'ko');
      expect(GameLanguageRegistry.flagCode('cz'), 'cs');
    });

    test('passes plain codes through unchanged', () {
      expect(GameLanguageRegistry.flagCode('fr'), 'fr');
      expect(GameLanguageRegistry.flagCode('de'), 'de');
    });

    test('returns lowercased input unchanged for unknown codes', () {
      expect(GameLanguageRegistry.flagCode('xx'), 'xx');
    });
  });

  group('GameLanguageRegistry.displayName', () {
    test('returns English display names for known codes', () {
      expect(GameLanguageRegistry.displayName('pt'), 'Portuguese');
      expect(GameLanguageRegistry.displayName('br'), 'Brazilian Portuguese');
      expect(GameLanguageRegistry.displayName('ptbr'), 'Brazilian Portuguese');
      expect(GameLanguageRegistry.displayName('cn'), 'Chinese (Simplified)');
      expect(GameLanguageRegistry.displayName('tw'), 'Chinese (Traditional)');
      expect(GameLanguageRegistry.displayName('zh'), 'Chinese');
    });

    test('is case-insensitive', () {
      expect(GameLanguageRegistry.displayName('PT'), 'Portuguese');
    });

    test('returns null for unknown codes', () {
      expect(GameLanguageRegistry.displayName('xx'), isNull);
    });
  });

  group('Portuguese split consistency', () {
    test('pt -> European Portuguese (iso pt, flag pt)', () {
      final info = GameLanguageRegistry.infoFor('pt');
      expect(info, isNotNull);
      expect(info!.isoCode, 'pt');
      expect(info.flagCode, 'pt');
      expect(info.displayName, 'Portuguese');
    });

    test('ptbr -> Brazilian Portuguese (iso pt, flag br)', () {
      final info = GameLanguageRegistry.infoFor('ptbr');
      expect(info, isNotNull);
      expect(info!.isoCode, 'pt');
      expect(info.flagCode, 'br');
      expect(info.displayName, 'Brazilian Portuguese');
    });
  });
}
