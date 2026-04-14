import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;
import 'package:twmt/providers/shared/service_providers.dart' as shared_svc;

part 'tm_suggestions_provider.g.dart';

/// Provider for TM suggestions for a specific translation unit
///
/// Fetches both exact and fuzzy matches from Translation Memory
/// for the given unit's source text.
@riverpod
Future<List<TmMatch>> tmSuggestionsForUnit(
  Ref ref,
  String unitId,
  String sourceLanguageCode,
  String targetLanguageCode,
) async {
  final unitRepo = ref.watch(shared_repo.translationUnitRepositoryProvider);
  final tmService = ref.watch(shared_svc.translationMemoryServiceProvider);

  // First get the translation unit to get its source text
  final unitResult = await unitRepo.getById(unitId);
  if (unitResult.isErr) {
    throw Exception('Failed to load translation unit: ${unitResult.unwrapErr()}');
  }
  final unit = unitResult.unwrap();

  // Collect all matches
  final matches = <TmMatch>[];

  // Try exact match first
  final exactResult = await tmService.findExactMatch(
    sourceText: unit.sourceText,
    targetLanguageCode: targetLanguageCode,
  );
  if (exactResult.isOk) {
    final exactMatch = exactResult.unwrap();
    if (exactMatch != null) {
      matches.add(exactMatch);
    }
  }

  // Get fuzzy matches
  final fuzzyResult = await tmService.findFuzzyMatches(
    sourceText: unit.sourceText,
    targetLanguageCode: targetLanguageCode,
    minSimilarity: 0.70, // Lower threshold to show more suggestions
    maxResults: 5,
  );
  if (fuzzyResult.isOk) {
    final fuzzyMatches = fuzzyResult.unwrap();
    // Add fuzzy matches that aren't duplicates of exact match
    for (final match in fuzzyMatches) {
      if (!matches.any((m) => m.entryId == match.entryId)) {
        matches.add(match);
      }
    }
  }

  // Sort by similarity score descending
  matches.sort((a, b) => b.similarityScore.compareTo(a.similarityScore));

  return matches;
}
