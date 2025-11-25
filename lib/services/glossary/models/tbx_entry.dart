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

  /// Whether matching should be case-sensitive
  final bool caseSensitive;

  /// Optional notes providing context for the LLM
  final String? notes;

  const TbxEntry({
    required this.id,
    required this.targetLanguage,
    required this.sourceTerm,
    required this.targetTerm,
    this.caseSensitive = false,
    this.notes,
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
        other.caseSensitive == caseSensitive &&
        other.notes == notes;
  }

  @override
  int get hashCode => Object.hash(
        id,
        targetLanguage,
        sourceTerm,
        targetTerm,
        caseSensitive,
        notes,
      );
}
