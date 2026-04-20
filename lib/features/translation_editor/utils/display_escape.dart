/// Translate whitespace control characters into their visible backslash-escape
/// form so markup stays spottable in read-only cells and the inspector target
/// field.
///
/// Backslashes are NOT doubled: Total War .loc source text contains literal
/// `\\n` sequences (two chars, backslash + n) that must remain visually
/// distinguishable from a real newline — doubling them would render as
/// `\\\\n` on screen, which is noisy and confusing.
///
/// [unescapeFromDisplay] is the inverse used at commit time to turn the
/// edited display form back into stored characters.
String escapeForDisplay(String text) {
  return text
      .replaceAll('\r\n', r'\r\n')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
}

/// Inverse of [escapeForDisplay] applied to edits made against the display
/// form so the stored value stays canonical (real whitespace characters).
///
/// Note on ambiguity: a literal `\n` (backslash + n) and a real newline both
/// render as `\n` in the display form, so this function cannot distinguish
/// them — it always resolves to a real newline. In practice the editor only
/// ever stores translations with real whitespace (normalised by
/// `TranslationTextUtils.normalizeTranslation` on the LLM pipeline and by
/// the TSV parser on import), so the ambiguity never arises on the target
/// field. The source field is read-only, so no unescape happens there.
String unescapeFromDisplay(String text) {
  return text
      .replaceAll(r'\r\n', '\r\n')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\t', '\t');
}
