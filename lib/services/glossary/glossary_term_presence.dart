/// Whether [targetTerm] appears in [targetText], honoring [caseSensitive].
///
/// A case-sensitive glossary term must appear in its exact prescribed casing to
/// count as present; otherwise the comparison is case-insensitive.
///
/// Shared by both [GlossaryServiceImpl.checkConsistency] and
/// [GlossaryMatchingService.checkConsistency] so the two implementations cannot
/// drift on case handling.
bool glossaryTermPresentInTarget({
  required String targetText,
  required String targetTerm,
  required bool caseSensitive,
}) {
  return caseSensitive
      ? targetText.contains(targetTerm)
      : targetText.toLowerCase().contains(targetTerm.toLowerCase());
}
