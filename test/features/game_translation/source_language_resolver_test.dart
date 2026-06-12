import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/game_translation/widgets/create_game_translation/source_language_resolver.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/services/game/game_localization_service.dart';

Language _lang(String id, String code) => Language(
      id: id,
      code: code,
      name: code,
      nativeName: code,
    );

DetectedLocalPack _pack(String languageCode) => DetectedLocalPack(
      languageCode: languageCode,
      languageName: languageCode,
      packFilePath: 'local_$languageCode.pack',
      fileSizeBytes: 0,
      lastModified: DateTime(2026, 1, 1),
    );

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

  group('SourceLanguageResolver.resolve', () {
    final languages = [
      _lang('id-zh', 'zh'),
      _lang('id-en', 'en'),
      _lang('id-de', 'DE'), // stored upper-case to exercise case-insensitivity
    ];

    test('returns null when the pack is null', () {
      expect(SourceLanguageResolver.resolve(languages, null), isNull);
    });

    test('resolves a non-ISO pack code to its DB language by identity', () {
      // Chinese pack 'cn' must resolve to the DB 'zh' language, not stay 'cn'.
      final result = SourceLanguageResolver.resolve(languages, _pack('cn'));

      expect(result, isNotNull);
      expect(result!.id, 'id-zh');
    });

    test('matches case-insensitively against the DB code', () {
      final result = SourceLanguageResolver.resolve(languages, _pack('de'));

      expect(result?.id, 'id-de');
    });

    test('returns null when no language matches the mapped code', () {
      // 'kr' maps to 'ko', which is absent from the list.
      expect(SourceLanguageResolver.resolve(languages, _pack('kr')), isNull);
    });
  });
}
