/// Normalize a raw language code into the repository's `lang_<code>` ID format.
///
/// Idempotent: if [code] is already prefixed (e.g. `'lang_fr'`, `'lang_FR'`),
/// returns the lowercased form to avoid a `'lang_lang_fr'` double-prefix.
/// Non-prefixed inputs (e.g. `'FR'`) are lowercased and prefixed.
///
/// Returns null when [code] is null.
String? normalizeLanguageId(String? code) {
  if (code == null) return null;
  final lower = code.toLowerCase();
  if (lower.startsWith('lang_')) return lower;
  return 'lang_$lower';
}

/// Strip the `lang_` prefix from a language ID if present.
String stripLanguagePrefix(String langId) {
  return langId.startsWith('lang_') ? langId.substring(5) : langId;
}
