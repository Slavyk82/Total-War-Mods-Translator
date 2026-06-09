import '../../../../models/domain/language.dart';
import '../../../../services/game/game_localization_service.dart';

/// Resolves a detected game pack to the seeded/DB [Language] it represents.
///
/// Game localization packs are named `local_xx.pack`, where `xx` follows the
/// Total War file-code scheme (e.g. `cn`, `tw`, `jp`, `kr`, `cz`, `br`). The
/// `languages` table, however, is keyed on ISO-639-1 codes (`zh`, `ja`, `ko`,
/// `cs`, ...). Comparing the raw pack code to DB codes is therefore unsafe:
/// e.g. a Chinese pack's `cn` does not equal the DB's `zh`, so naive filtering
/// leaves the source language selectable as a translation target
/// (Chinese -> Chinese).
///
/// This resolver maps the pack/file code to its DB code and looks up the
/// matching [Language] so the source can be excluded by a stable identity
/// ([Language.id]) rather than by a comparison of mismatched code schemes.
class SourceLanguageResolver {
  const SourceLanguageResolver._();

  /// Maps a Total War pack/file code to the ISO-639-1 code used by the DB
  /// `languages` table. Codes that already match ISO (en, de, es, fr, ru, it,
  /// pl, tr, ...) are returned unchanged by the caller via the fallback in
  /// [mapPackCodeToDbCode].
  ///
  /// Mirrors the alias table in
  /// `lib/services/file/pack_image_generator_service.dart`
  /// (`_flagCodeAliases`), kept local here to avoid depending on a
  /// `@visibleForTesting` API in a shared service.
  static const Map<String, String> _packCodeToDbCode = {
    'cn': 'zh', // Chinese (Simplified) -> Chinese
    'tw': 'zh', // Chinese (Traditional) -> Chinese
    'jp': 'ja', // Japanese
    'kr': 'ko', // Korean
    'cz': 'cs', // Czech
    'br': 'pt', // Brazilian Portuguese -> Portuguese
    'pt-br': 'pt',
    'pt_br': 'pt',
    'ptbr': 'pt',
  };

  /// Returns the DB (ISO) code for a pack/file [packCode], applying
  /// [_packCodeToDbCode] for variant codes and otherwise returning the
  /// lowercased input unchanged.
  static String mapPackCodeToDbCode(String packCode) {
    final normalized = packCode.toLowerCase();
    return _packCodeToDbCode[normalized] ?? normalized;
  }

  /// Resolves the source [pack] to its DB [Language] within [languages].
  ///
  /// Matches on the mapped DB code (case-insensitive). Returns `null` when the
  /// pack is `null` or no language matches (e.g. the user has not added that
  /// language) — callers must then fall back to a code-based comparison.
  static Language? resolve(
    List<Language> languages,
    DetectedLocalPack? pack,
  ) {
    if (pack == null) return null;
    final dbCode = mapPackCodeToDbCode(pack.languageCode);
    for (final lang in languages) {
      if (lang.code.toLowerCase() == dbCode) return lang;
    }
    return null;
  }
}
