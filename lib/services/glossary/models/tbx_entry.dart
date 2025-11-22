/// Represents a term entry from a TBX (TermBase eXchange) file.
///
/// Used as an intermediate format when importing TBX files before
/// converting to GlossaryEntry instances.
class TbxEntry {
  /// Entry ID from the TBX file
  final String id;

  /// Target language code (e.g., 'en', 'fr')
  final String targetLanguage;

  /// Source term in the original language
  final String sourceTerm;

  /// Target term in the translation language
  final String targetTerm;

  /// Description or definition of the term
  final String? description;

  /// Category or subject field (e.g., 'Computing', 'Military')
  final String? category;

  /// Part of speech (e.g., 'noun', 'verb', 'adjective')
  final String? partOfSpeech;

  /// Whether matching should be case-sensitive
  final bool caseSensitive;

  const TbxEntry({
    required this.id,
    required this.targetLanguage,
    required this.sourceTerm,
    required this.targetTerm,
    this.description,
    this.category,
    this.partOfSpeech,
    this.caseSensitive = false,
  });

  @override
  String toString() {
    return 'TbxEntry(id: $id, $sourceTerm → $targetLanguage:$targetTerm)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TbxEntry &&
        other.id == id &&
        other.targetLanguage == targetLanguage &&
        other.sourceTerm == sourceTerm &&
        other.targetTerm == targetTerm &&
        other.description == description &&
        other.category == category &&
        other.partOfSpeech == partOfSpeech &&
        other.caseSensitive == caseSensitive;
  }

  @override
  int get hashCode => Object.hash(
        id,
        targetLanguage,
        sourceTerm,
        targetTerm,
        description,
        category,
        partOfSpeech,
        caseSensitive,
      );
}
