import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/glossary/utils/glossary_matcher.dart';

/// Service for glossary term matching and substitution
///
/// Handles all matching-related operations including:
/// - Finding matching terms in source text
/// - Applying glossary substitutions to translations
/// - Checking translation consistency with glossary
class GlossaryMatchingService {
  final GlossaryRepository _repository;

  GlossaryMatchingService(this._repository);

  /// Find glossary terms that match in source text
  ///
  /// Searches applicable glossaries (game-specific + universal) for terms
  /// that appear in the source text.
  ///
  /// [sourceText]: Source text to search for matches
  /// [sourceLanguageCode]: Source language code
  /// [targetLanguageCode]: Target language code
  /// [glossaryIds]: Optional specific glossaries to search (null = all applicable)
  /// [gameInstallationId]: Game context for finding applicable glossaries
  ///
  /// Returns list of matching glossary entries
  Future<Result<List<GlossaryEntry>, GlossaryException>> findMatchingTerms({
    required String sourceText,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    List<String>? glossaryIds,
    String? gameInstallationId,
  }) async {
    try {
      // Get applicable glossaries
      final glossaries = glossaryIds != null && glossaryIds.isNotEmpty
          ? await _repository.getGlossariesByIds(glossaryIds)
          : await _repository.getAllGlossaries(
              gameInstallationId: gameInstallationId,
              includeUniversal: true,
            );

      // Get all entries from applicable glossaries
      final allEntries = <GlossaryEntry>[];
      for (final glossary in glossaries) {
        final entries = await _repository.getEntriesByGlossary(
          glossaryId: glossary.id,
          targetLanguageCode: targetLanguageCode,
        );
        allEntries.addAll(entries);
      }

      // Find matches in source text
      final matches = GlossaryMatcher.findMatches(
        text: sourceText,
        entries: allEntries,
        wholeWordOnly: true,
      );

      // Extract unique entries from matches
      final matchedEntries = matches.map((m) => m.entry).toSet().toList();

      return Ok(matchedEntries);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to find matching terms', e),
      );
    }
  }

  /// Apply glossary substitutions to target text
  ///
  /// Finds matching terms in source text and substitutes their
  /// translations in the target text.
  ///
  /// [sourceText]: Source text to find matches in
  /// [targetText]: Target text to apply substitutions to
  /// [sourceLanguageCode]: Source language code
  /// [targetLanguageCode]: Target language code
  /// [glossaryIds]: Optional specific glossaries to use (null = all applicable)
  /// [gameInstallationId]: Game context for finding applicable glossaries
  ///
  /// Returns target text with glossary substitutions applied
  Future<Result<String, GlossaryException>> applySubstitutions({
    required String sourceText,
    required String targetText,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    List<String>? glossaryIds,
    String? gameInstallationId,
  }) async {
    try {
      // Get applicable glossaries
      final glossaries = glossaryIds != null && glossaryIds.isNotEmpty
          ? await _repository.getGlossariesByIds(glossaryIds)
          : await _repository.getAllGlossaries(
              gameInstallationId: gameInstallationId,
              includeUniversal: true,
            );

      // Get all entries
      final allEntries = <GlossaryEntry>[];
      for (final glossary in glossaries) {
        final entries = await _repository.getEntriesByGlossary(
          glossaryId: glossary.id,
          targetLanguageCode: targetLanguageCode,
        );
        allEntries.addAll(entries);
      }

      // Find matches in source text
      final matches = GlossaryMatcher.findMatches(
        text: sourceText,
        entries: allEntries,
        wholeWordOnly: true,
      );

      // Apply substitutions to target text
      final result = GlossaryMatcher.applySubstitutions(
        sourceText: sourceText,
        targetText: targetText,
        matches: matches,
      );

      return Ok(result);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to apply substitutions', e),
      );
    }
  }

  /// Check translation consistency with glossary
  ///
  /// Verifies that glossary terms found in source text have their
  /// correct translations in the target text.
  ///
  /// [sourceText]: Source text to check
  /// [targetText]: Target text to verify
  /// [sourceLanguageCode]: Source language code
  /// [targetLanguageCode]: Target language code
  /// [glossaryIds]: Optional specific glossaries to check (null = all applicable)
  /// [gameInstallationId]: Game context for finding applicable glossaries
  ///
  /// Returns list of inconsistency error messages (empty if consistent)
  Future<Result<List<String>, GlossaryException>> checkConsistency({
    required String sourceText,
    required String targetText,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    List<String>? glossaryIds,
    String? gameInstallationId,
  }) async {
    try {
      final matchResult = await findMatchingTerms(
        sourceText: sourceText,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        glossaryIds: glossaryIds,
        gameInstallationId: gameInstallationId,
      );

      if (matchResult.isErr) {
        return Err(matchResult.error);
      }

      final matchedEntries = matchResult.value;
      final inconsistencies = <String>[];

      for (final entry in matchedEntries) {
        // Check if target term appears in target text
        final targetTermLower = entry.targetTerm.toLowerCase();
        final targetTextLower = targetText.toLowerCase();

        if (!targetTextLower.contains(targetTermLower)) {
          inconsistencies.add(
            'Term "${entry.sourceTerm}" should be translated as "${entry.targetTerm}" but not found in target',
          );
        }
      }

      return Ok(inconsistencies);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to check consistency', e),
      );
    }
  }
}
