/// Text preprocessing and postprocessing utilities for DeepL translations.
///
/// DeepL requires special handling for certain text patterns:
/// - Literal `\n` sequences need to be converted to XML placeholders
///   to prevent DeepL from interpreting them as newlines.
///
/// This processor is used by both [DeepLProvider] for translations
/// and can be reused by other DeepL-related services.
class DeepLTextProcessor {
  /// XML placeholder for literal \n sequences.
  /// DeepL preserves XML tags when tag_handling: 'xml' is enabled.
  static const newlinePlaceholder = '<x id="nl"/>';

  /// Pattern to match the XML placeholder (handles variations in whitespace).
  static final newlinePlaceholderPattern = RegExp(r'<x\s+id="nl"\s*/?>');

  const DeepLTextProcessor();

  /// Preprocess text before sending to DeepL.
  ///
  /// DeepL requests use `tag_handling: 'xml'`, so DeepL parses the source as
  /// XML and any `<...>`/`&` is treated as markup. Game strings legitimately
  /// contain stray angle brackets (e.g. `HP < 50`) and bare ampersands
  /// (e.g. `Tom & Jerry`); left unescaped, DeepL's XML parser can silently
  /// drop/reorder/alter them, corrupting the value written back to .loc/.pack.
  ///
  /// To make the round-trip lossless we:
  ///   1. Escape the XML metacharacters `&`, `<`, `>` in the raw text.
  ///   2. THEN inject the newline placeholder (real markup) so its own angle
  ///      brackets are not escaped.
  /// [postprocessText] reverses this exactly.
  ///
  /// Example:
  /// ```dart
  /// preprocessText(r'Hello\nWorld') // Returns 'Hello<x id="nl"/>World'
  /// preprocessText('HP < 50 & MP > 10') // Returns 'HP &lt; 50 &amp; MP &gt; 10'
  /// ```
  String preprocessText(String text) {
    // Escape XML metacharacters first. `&` must be escaped before `<`/`>`
    // so we don't double-escape the ampersands we introduce.
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    // Inject the newline placeholder as genuine XML markup (after escaping so
    // its brackets survive).
    return escaped.replaceAll(r'\n', newlinePlaceholder);
  }

  /// Postprocess text after receiving from DeepL.
  ///
  /// Reverses [preprocessText]: restores literal `\n` from the XML placeholder
  /// and un-escapes the XML metacharacters that were escaped before sending.
  ///
  /// Example:
  /// ```dart
  /// postprocessText('Hello<x id="nl"/>World') // Returns r'Hello\nWorld'
  /// postprocessText('HP &lt; 50 &amp; MP &gt; 10') // Returns 'HP < 50 & MP > 10'
  /// ```
  String postprocessText(String text) {
    // Restore literal \n from XML placeholder first.
    var result = text.replaceAll(newlinePlaceholderPattern, r'\n');
    // Un-escape XML entities. `&amp;` is restored LAST so an escaped literal
    // like `&amp;lt;` round-trips back to `&lt;` rather than `<`.
    result = result
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
    return result;
  }

  /// Preprocess a batch of texts.
  ///
  /// Useful when translating multiple texts at once.
  List<String> preprocessBatch(Iterable<String> texts) {
    return texts.map(preprocessText).toList();
  }

  /// Postprocess a batch of texts.
  ///
  /// Useful when receiving multiple translations at once.
  List<String> postprocessBatch(Iterable<String> texts) {
    return texts.map(postprocessText).toList();
  }

  /// Postprocess a map of translations.
  ///
  /// Applies postprocessing to all values in the map.
  Map<String, String> postprocessTranslations(Map<String, String> translations) {
    return translations.map((key, value) => MapEntry(key, postprocessText(value)));
  }
}
