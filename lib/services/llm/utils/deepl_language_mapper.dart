/// Language code mapping utility for DeepL API.
///
/// DeepL uses specific language codes that may differ from standard ISO 639-1 codes.
/// This utility provides consistent language code mapping across all DeepL-related
/// services (translation provider, glossary service, etc.).
///
/// API Documentation: https://developers.deepl.com/docs/resources/supported-languages
class DeepLLanguageMapper {
  const DeepLLanguageMapper();

  /// Language code mapping from ISO 639-1/BCP 47 to DeepL format.
  ///
  /// DeepL uses uppercase codes with optional region variants.
  /// Some languages have mandatory region variants for target (e.g., EN-US, PT-BR).
  static const Map<String, String> _languageMapping = {
    // European languages
    'en': 'EN', // English (will use EN-US by default for target)
    'en-us': 'EN-US', // American English
    'en-gb': 'EN-GB', // British English
    'de': 'DE', // German
    'fr': 'FR', // French
    'es': 'ES', // Spanish
    'it': 'IT', // Italian
    'nl': 'NL', // Dutch
    'pl': 'PL', // Polish
    'pt': 'PT-BR', // Portuguese (Brazilian by default)
    'pt-br': 'PT-BR', // Brazilian Portuguese
    'pt-pt': 'PT-PT', // European Portuguese
    'ru': 'RU', // Russian

    // Nordic languages
    'da': 'DA', // Danish
    'fi': 'FI', // Finnish
    'sv': 'SV', // Swedish
    'nb': 'NB', // Norwegian (Bokmal)

    // Eastern European languages
    'bg': 'BG', // Bulgarian
    'cs': 'CS', // Czech
    'et': 'ET', // Estonian
    'hu': 'HU', // Hungarian
    'lv': 'LV', // Latvian
    'lt': 'LT', // Lithuanian
    'ro': 'RO', // Romanian
    'sk': 'SK', // Slovak
    'sl': 'SL', // Slovenian

    // Other European languages
    'el': 'EL', // Greek
    'uk': 'UK', // Ukrainian
    'tr': 'TR', // Turkish

    // Asian languages
    'ja': 'JA', // Japanese
    'zh': 'ZH', // Chinese (Simplified)
    'zh-hans': 'ZH', // Chinese (Simplified) - explicit simplified
    'ko': 'KO', // Korean
    'id': 'ID', // Indonesian

    // Arabic
    'ar': 'AR', // Arabic
  };

  /// Map an ISO language code to DeepL format.
  ///
  /// [isoCode] can be:
  /// - ISO 639-1 code (e.g., 'en', 'de', 'fr')
  /// - BCP 47 code with region (e.g., 'en-US', 'pt-BR')
  ///
  /// If the code is not in the mapping, returns the uppercase version.
  ///
  /// Example:
  /// ```dart
  /// mapLanguageCode('en')    // Returns 'EN'
  /// mapLanguageCode('pt-br') // Returns 'PT-BR'
  /// mapLanguageCode('xx')    // Returns 'XX' (fallback)
  /// ```
  String mapLanguageCode(String isoCode) {
    final lowerCode = isoCode.toLowerCase();
    return _languageMapping[lowerCode] ?? isoCode.toUpperCase();
  }

  /// Check if a language code is supported by DeepL.
  ///
  /// Note: This only checks against the known mapping. DeepL may support
  /// additional languages not included here.
  bool isKnownLanguage(String isoCode) {
    final lowerCode = isoCode.toLowerCase();
    return _languageMapping.containsKey(lowerCode);
  }

  /// Get all known language codes.
  ///
  /// Returns the ISO codes (keys) from the mapping.
  Set<String> get knownLanguageCodes => _languageMapping.keys.toSet();

  /// Get all DeepL language codes.
  ///
  /// Returns the DeepL codes (values) from the mapping.
  /// Note: Some codes may be duplicated (e.g., 'en' and 'en-us' both map to EN variants).
  Set<String> get deeplLanguageCodes => _languageMapping.values.toSet();
}
