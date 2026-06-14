import 'dart:convert';

/// Language-code shape: `xx` or `xx_YY` (e.g. `fr`, `pt_BR`).
final RegExp _languageCodePattern = RegExp(r'^[a-z]{2}(_[A-Z]{2})?$');

/// Resolve a Workshop title/description template that may have been stored as a
/// localized JSON map (`{"fr":"...","en":"..."}`) instead of plain text.
///
/// Background: a localized map saved as a template injects escaped quotes
/// (`\"`) into the generated workshop VDF, which breaks steamcmd's KeyValues
/// parser (BBCode `[h1]` is then read as a platform conditional) and crashes
/// the publish with exit code 9. This unwraps such a map to the text for the
/// requested [languageCode] so the publish receives plain text.
///
/// A value is only treated as a localized map when it is a JSON object whose
/// keys all look like language codes and whose values are all strings — so a
/// description that legitimately *is* JSON-shaped (or that merely starts with a
/// brace) is returned unchanged. When [languageCode] is null or absent from the
/// map, the first value is used.
String resolveLocalizedTemplate(String raw, {String? languageCode}) {
  if (raw.isEmpty || !raw.trimLeft().startsWith('{')) return raw;

  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return raw;
  }

  if (decoded is! Map || decoded.isEmpty) return raw;
  final isLocalizedMap = decoded.keys.every(
        (k) => k is String && _languageCodePattern.hasMatch(k),
      ) &&
      decoded.values.every((v) => v is String);
  if (!isLocalizedMap) return raw;

  final map = decoded.cast<String, String>();
  if (languageCode != null && map.containsKey(languageCode)) {
    return map[languageCode]!;
  }
  return map.values.first;
}
