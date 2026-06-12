/// Metadata for a single language code.
class LanguageCodeInfo {
  /// ISO-639-1 / DB `languages` table code.
  final String isoCode;

  /// Flag asset basename: `assets/flags/<flagCode>.png`
  final String flagCode;

  /// Human-readable English display name.
  final String displayName;

  const LanguageCodeInfo({
    required this.isoCode,
    required this.flagCode,
    required this.displayName,
  });
}

/// Single source of truth for language-code aliasing across the app.
///
/// Replaces three previously-duplicated tables:
/// - SourceLanguageResolver._packCodeToDbCode (pack code -> ISO/DB code)
/// - PackImageGeneratorService._flagCodeAliases (code -> flag asset basename)
/// - GameLocalizationService.languageCodeNames (code -> display name)
///
/// Total War packs are `local_xx.pack`; `xx` is a CA file code that does not
/// always equal ISO-639-1 (cn/tw -> zh, jp -> ja, kr -> ko, cz -> cs, br -> pt).
/// Lookups are case-insensitive. Portuguese: plain `pt` is European Portuguese
/// (flag pt), while `br`/`ptbr`/`pt-br`/`pt_br` are Brazilian (flag br); all map
/// to ISO `pt` because the DB models a single Portuguese language.
class GameLanguageRegistry {
  const GameLanguageRegistry._();

  static const Map<String, LanguageCodeInfo> _byCode = {
    'en':    LanguageCodeInfo(isoCode: 'en', flagCode: 'en', displayName: 'English'),
    'fr':    LanguageCodeInfo(isoCode: 'fr', flagCode: 'fr', displayName: 'French'),
    'de':    LanguageCodeInfo(isoCode: 'de', flagCode: 'de', displayName: 'German'),
    'es':    LanguageCodeInfo(isoCode: 'es', flagCode: 'es', displayName: 'Spanish'),
    'it':    LanguageCodeInfo(isoCode: 'it', flagCode: 'it', displayName: 'Italian'),
    'ru':    LanguageCodeInfo(isoCode: 'ru', flagCode: 'ru', displayName: 'Russian'),
    'pl':    LanguageCodeInfo(isoCode: 'pl', flagCode: 'pl', displayName: 'Polish'),
    'tr':    LanguageCodeInfo(isoCode: 'tr', flagCode: 'tr', displayName: 'Turkish'),
    'cz':    LanguageCodeInfo(isoCode: 'cs', flagCode: 'cs', displayName: 'Czech'),
    'cs':    LanguageCodeInfo(isoCode: 'cs', flagCode: 'cs', displayName: 'Czech'),
    'cn':    LanguageCodeInfo(isoCode: 'zh', flagCode: 'zh', displayName: 'Chinese (Simplified)'),
    'tw':    LanguageCodeInfo(isoCode: 'zh', flagCode: 'zh', displayName: 'Chinese (Traditional)'),
    'zh':    LanguageCodeInfo(isoCode: 'zh', flagCode: 'zh', displayName: 'Chinese'),
    'jp':    LanguageCodeInfo(isoCode: 'ja', flagCode: 'ja', displayName: 'Japanese'),
    'ja':    LanguageCodeInfo(isoCode: 'ja', flagCode: 'ja', displayName: 'Japanese'),
    'kr':    LanguageCodeInfo(isoCode: 'ko', flagCode: 'ko', displayName: 'Korean'),
    'ko':    LanguageCodeInfo(isoCode: 'ko', flagCode: 'ko', displayName: 'Korean'),
    'pt':    LanguageCodeInfo(isoCode: 'pt', flagCode: 'pt', displayName: 'Portuguese'),
    'br':    LanguageCodeInfo(isoCode: 'pt', flagCode: 'br', displayName: 'Brazilian Portuguese'),
    'ptbr':  LanguageCodeInfo(isoCode: 'pt', flagCode: 'br', displayName: 'Brazilian Portuguese'),
    'pt-br': LanguageCodeInfo(isoCode: 'pt', flagCode: 'br', displayName: 'Brazilian Portuguese'),
    'pt_br': LanguageCodeInfo(isoCode: 'pt', flagCode: 'br', displayName: 'Brazilian Portuguese'),
  };

  /// Full metadata for [code], or null if unknown. Case-insensitive.
  static LanguageCodeInfo? infoFor(String code) => _byCode[code.toLowerCase()];

  /// ISO/DB code for [code]; returns the lowercased input unchanged if unknown.
  static String isoCode(String code) =>
      _byCode[code.toLowerCase()]?.isoCode ?? code.toLowerCase();

  /// Flag asset basename for [code]; returns the lowercased input unchanged if unknown.
  static String flagCode(String code) =>
      _byCode[code.toLowerCase()]?.flagCode ?? code.toLowerCase();

  /// Display name for [code], or null if unknown (callers choose a fallback).
  static String? displayName(String code) => _byCode[code.toLowerCase()]?.displayName;
}
