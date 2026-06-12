/// Translation batch settings
///
/// [unitsPerBatch]: Number of units per batch. 0 = auto (calculated based on tokens)
/// [skipTranslationMemory]: If true, skip TM lookup during translation (use LLM only)
///
/// Plain value object (no Riverpod dependency) so that pure services can
/// accept it as an injected snapshot. The Riverpod provider that produces it
/// lives in `lib/providers/translation_settings_provider.dart`.
class TranslationSettings {
  final int unitsPerBatch;
  final int parallelBatches;
  final bool skipTranslationMemory;

  const TranslationSettings({
    required this.unitsPerBatch,
    required this.parallelBatches,
    this.skipTranslationMemory = false,
  });

  /// Whether auto mode is enabled (unitsPerBatch = 0)
  bool get isAutoMode => unitsPerBatch == 0;

  @override
  String toString() =>
      'TranslationSettings(units: ${isAutoMode ? "auto" : unitsPerBatch}, parallel: $parallelBatches, skipTM: $skipTranslationMemory)';
}
