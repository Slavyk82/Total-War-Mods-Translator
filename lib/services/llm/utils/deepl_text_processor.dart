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
  /// Converts literal `\n` sequences (backslash + n) to XML placeholders
  /// to prevent DeepL from interpreting them as actual newlines.
  ///
  /// Example:
  /// ```dart
  /// preprocessText(r'Hello\nWorld') // Returns 'Hello<x id="nl"/>World'
  /// ```
  String preprocessText(String text) {
    // Replace literal \n (backslash + n) with XML placeholder
    return text.replaceAll(r'\n', newlinePlaceholder);
  }

  /// Postprocess text after receiving from DeepL.
  ///
  /// Restores literal `\n` sequences from XML placeholders.
  ///
  /// Example:
  /// ```dart
  /// postprocessText('Hello<x id="nl"/>World') // Returns r'Hello\nWorld'
  /// ```
  String postprocessText(String text) {
    // Restore literal \n from XML placeholder
    return text.replaceAll(newlinePlaceholderPattern, r'\n');
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
