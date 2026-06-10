import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/game_translation/widgets/create_game_translation/source_language_resolver.dart';

/// Regression tests for the pack-code → DB/ISO-code mapping used when persisting
/// a game-translation project's sourceLanguageCode. Total War pack codes
/// (cn/tw/jp/kr/cz/br) do NOT match the languages-table ISO codes, so storing
/// the raw pack code left downstream lookups (editor source lang, TM
/// resolveLanguageId) unable to resolve the language.
void main() {
  group('SourceLanguageResolver.mapPackCodeToDbCode', () {
    test('maps non-ISO Total War pack codes to ISO DB codes', () {
      expect(SourceLanguageResolver.mapPackCodeToDbCode('cn'), 'zh');
      expect(SourceLanguageResolver.mapPackCodeToDbCode('tw'), 'zh');
      expect(SourceLanguageResolver.mapPackCodeToDbCode('jp'), 'ja');
      expect(SourceLanguageResolver.mapPackCodeToDbCode('kr'), 'ko');
      expect(SourceLanguageResolver.mapPackCodeToDbCode('cz'), 'cs');
      expect(SourceLanguageResolver.mapPackCodeToDbCode('br'), 'pt');
    });

    test('is case-insensitive', () {
      expect(SourceLanguageResolver.mapPackCodeToDbCode('JP'), 'ja');
    });

    test('passes through codes that already match the ISO code', () {
      for (final code in ['en', 'de', 'fr', 'es', 'ru', 'it', 'pl', 'tr']) {
        expect(SourceLanguageResolver.mapPackCodeToDbCode(code), code);
      }
    });
  });
}
