import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/models/glossary_term_with_variants.dart';
import 'package:twmt/services/glossary/utils/glossary_matcher.dart';

/// Service for filtering glossary terms relevant to a specific translation batch
///
/// Optimizes token usage by only including glossary terms that actually appear
/// in the source texts being translated, rather than sending the entire glossary.
class GlossaryFilterService {
  final GlossaryRepository _repository;

  GlossaryFilterService(this._repository);

  /// Filter glossary entries to only those relevant for the given source texts
  ///
  /// [sourceTexts] - List of source texts to be translated
  /// [gameInstallationId] - Game installation ID for game-specific glossaries
  /// [targetLanguageId] - Target language ID to filter glossaries
  /// [targetLanguageCode] - Target language code for entries
  ///
  /// Returns list of glossary terms with variants, grouped by source term
  Future<List<GlossaryTermWithVariants>> filterRelevantTerms({
    required List<String> sourceTexts,
    required String gameInstallationId,
    required String targetLanguageId,
    required String targetLanguageCode,
  }) async {
    if (sourceTexts.isEmpty) return [];

    // Get all applicable glossaries
    final glossaries = await _repository.getAllGlossaries(
      gameInstallationId: gameInstallationId,
      includeUniversal: true,
    );

    // Filter by target language
    final applicableGlossaries = glossaries
        .where((g) => g.targetLanguageId == targetLanguageId)
        .toList();

    if (applicableGlossaries.isEmpty) return [];

    // Load all entries from applicable glossaries
    final allEntries = <GlossaryEntry>[];
    for (final glossary in applicableGlossaries) {
      final entries = await _repository.getEntriesByGlossary(
        glossaryId: glossary.id,
        targetLanguageCode: targetLanguageCode,
      );
      allEntries.addAll(entries);
    }

    if (allEntries.isEmpty) return [];

    // Concatenate all source texts for matching
    final combinedText = sourceTexts.join(' ');

    // Find matching terms in combined text
    final matches = GlossaryMatcher.findMatches(
      text: combinedText,
      entries: allEntries,
      wholeWordOnly: true,
    );

    if (matches.isEmpty) return [];

    // Get unique matched entry IDs
    final matchedEntryIds = matches.map((m) => m.entry.id).toSet();

    // Filter to only matched entries
    final matchedEntries = allEntries
        .where((e) => matchedEntryIds.contains(e.id))
        .toList();

    // Group by source term (case-insensitive for grouping)
    return _groupEntriesBySourceTerm(matchedEntries);
  }

  /// Load all glossary terms with variants for a game/language
  ///
  /// Use this when you need the full glossary (e.g., for post-processing validation)
  Future<List<GlossaryTermWithVariants>> loadAllTerms({
    required String gameInstallationId,
    required String targetLanguageId,
    required String targetLanguageCode,
  }) async {
    final glossaries = await _repository.getAllGlossaries(
      gameInstallationId: gameInstallationId,
      includeUniversal: true,
    );

    final applicableGlossaries = glossaries
        .where((g) => g.targetLanguageId == targetLanguageId)
        .toList();

    if (applicableGlossaries.isEmpty) return [];

    final allEntries = <GlossaryEntry>[];
    for (final glossary in applicableGlossaries) {
      final entries = await _repository.getEntriesByGlossary(
        glossaryId: glossary.id,
        targetLanguageCode: targetLanguageCode,
      );
      allEntries.addAll(entries);
    }

    return _groupEntriesBySourceTerm(allEntries);
  }

  /// Group glossary entries by source term, creating variants
  List<GlossaryTermWithVariants> _groupEntriesBySourceTerm(
    List<GlossaryEntry> entries,
  ) {
    // Group entries by lowercase source term
    final grouped = <String, List<GlossaryEntry>>{};
    for (final entry in entries) {
      final key = entry.sourceTerm.toLowerCase();
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    // Convert to GlossaryTermWithVariants
    return grouped.entries.map((group) {
      final entriesForTerm = group.value;
      // Use the original case from the first entry
      final sourceTerm = entriesForTerm.first.sourceTerm;
      // Use case sensitivity from first entry (could be enhanced to check all)
      final caseSensitive = entriesForTerm.any((e) => e.caseSensitive);

      final variants = entriesForTerm.map((e) => GlossaryVariant(
        targetTerm: e.targetTerm,
        notes: e.notes,
        entryId: e.id,
      )).toList();

      return GlossaryTermWithVariants(
        sourceTerm: sourceTerm,
        variants: variants,
        caseSensitive: caseSensitive,
      );
    }).toList();
  }

  /// Estimate token count for a list of glossary terms
  int estimateTokenCount(List<GlossaryTermWithVariants> terms) {
    if (terms.isEmpty) return 0;

    // Base overhead for "GLOSSARY (must use these translations):" header
    int tokens = 10;

    for (final term in terms) {
      tokens += term.estimatedTokens;
    }

    return tokens;
  }
}

