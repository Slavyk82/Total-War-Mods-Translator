import '../../../../models/domain/language.dart';
import '../../../../services/game/game_language_registry.dart';
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

  /// Returns the DB (ISO) code for a pack/file [packCode]. Maps Total War
  /// variant codes (cn/tw -> zh, jp -> ja, kr -> ko, cz -> cs, br -> pt, ...)
  /// to their ISO-639-1 DB code; codes that already match ISO are returned
  /// lowercased and unchanged.
  ///
  /// Delegates to [GameLanguageRegistry], the single source of truth for
  /// language-code aliasing across the app.
  static String mapPackCodeToDbCode(String packCode) =>
      GameLanguageRegistry.isoCode(packCode);

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
