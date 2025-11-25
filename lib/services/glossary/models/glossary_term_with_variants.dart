/// Represents a glossary source term with all its translation variants
///
/// Supports multiple translations for the same source term with contextual notes.
/// Example: "Bretonnian" can translate to:
/// - "Bretonnien" (masculine)
/// - "Bretonnienne" (feminine)
class GlossaryTermWithVariants {
  /// The source term (e.g., "Bretonnian")
  final String sourceTerm;

  /// All translation variants for this source term
  final List<GlossaryVariant> variants;

  /// Whether matching should be case-sensitive
  final bool caseSensitive;

  const GlossaryTermWithVariants({
    required this.sourceTerm,
    required this.variants,
    this.caseSensitive = false,
  });

  /// Returns true if this term has multiple translation variants
  bool get hasMultipleVariants => variants.length > 1;

  /// Returns true if any variant has contextual notes
  bool get hasNotes => variants.any((v) => v.notes != null && v.notes!.isNotEmpty);

  /// Format for LLM prompt inclusion
  ///
  /// Single variant: "Bretonnia" → "Bretonnie"
  /// Multiple variants: "Bretonnian" → "Bretonnien" (masculine) / "Bretonnienne" (feminine)
  String formatForPrompt() {
    if (variants.isEmpty) return '';

    if (variants.length == 1) {
      final variant = variants.first;
      if (variant.notes != null && variant.notes!.isNotEmpty) {
        return '"$sourceTerm" → "${variant.targetTerm}" (${variant.notes})';
      }
      return '"$sourceTerm" → "${variant.targetTerm}"';
    }

    // Multiple variants - format with context
    final variantStrings = variants.map((v) {
      if (v.notes != null && v.notes!.isNotEmpty) {
        return '"${v.targetTerm}" (${v.notes})';
      }
      return '"${v.targetTerm}"';
    }).join(' / ');

    return '"$sourceTerm" → $variantStrings';
  }

  /// Estimated token count for this entry
  int get estimatedTokens {
    var tokens = (sourceTerm.length / 4).ceil();
    for (final variant in variants) {
      tokens += (variant.targetTerm.length / 4).ceil();
      if (variant.notes != null) {
        tokens += (variant.notes!.length / 4).ceil();
      }
    }
    // Add overhead for formatting
    return tokens + 5;
  }
}

/// A single translation variant with optional contextual notes
class GlossaryVariant {
  /// The translated term
  final String targetTerm;

  /// Contextual notes (e.g., "masculine", "feminine", "plural")
  final String? notes;

  /// Original glossary entry ID for reference
  final String entryId;

  const GlossaryVariant({
    required this.targetTerm,
    this.notes,
    required this.entryId,
  });
}

