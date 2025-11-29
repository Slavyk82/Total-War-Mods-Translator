import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/glossary/utils/glossary_statistics.dart';

/// Service for glossary statistics calculations
///
/// Handles all statistics-related operations including:
/// - Calculating glossary statistics
/// - Generating usage reports
class GlossaryStatisticsService {
  final GlossaryRepository _repository;

  GlossaryStatisticsService(this._repository);

  /// Get comprehensive statistics for a glossary
  ///
  /// Returns statistics including:
  /// - Entry counts by language pair
  /// - Case sensitivity breakdown
  /// - Usage patterns
  Future<Result<Map<String, dynamic>, GlossaryException>> getGlossaryStats(
    String glossaryId,
  ) async {
    try {
      final glossary = await _repository.getGlossaryById(glossaryId);
      if (glossary == null) {
        return Err(GlossaryNotFoundException(glossaryId));
      }

      final entries = await _repository.getEntriesByGlossary(
        glossaryId: glossaryId,
      );

      // Get usage statistics from database
      final usageStats = await _repository.getUsageStats(glossaryId);
      final usedCount = usageStats['usedCount'] ?? 0;
      final unusedCount = usageStats['unusedCount'] ?? 0;
      final totalEntries = entries.length;

      // Calculate usage rate
      final usageRate = totalEntries > 0 ? usedCount / totalEntries : 0.0;

      // Count duplicates (same source term, same language)
      final termCounts = <String, int>{};
      for (final entry in entries) {
        final key = '${entry.targetLanguageCode}:${entry.sourceTerm.toLowerCase()}';
        termCounts[key] = (termCounts[key] ?? 0) + 1;
      }
      final duplicatesDetected = termCounts.values.where((c) => c > 1).length;

      // Count case-sensitive entries
      final caseSensitiveTerms = entries.where((e) => e.caseSensitive).length;

      // Count entries with missing translations (empty target term)
      final missingTranslations = entries.where((e) => e.targetTerm.isEmpty).length;

      // Forbidden terms count (from SQL since model doesn't map is_forbidden)
      // For now, set to 0 since the feature isn't fully implemented
      const forbiddenTerms = 0;

      // Use statistics utility for language pair counts
      final basicStats = GlossaryStatistics.calculateStats(entries);

      // Build comprehensive statistics map
      final stats = {
        'totalEntries': totalEntries,
        'entriesByLanguagePair': basicStats['entriesByLanguagePair'],
        'usedInTranslations': usedCount,
        'unusedEntries': unusedCount,
        'usageRate': usageRate,
        'consistencyScore': 1.0, // Placeholder for future implementation
        'duplicatesDetected': duplicatesDetected,
        'missingTranslations': missingTranslations,
        'forbiddenTerms': forbiddenTerms,
        'caseSensitiveTerms': caseSensitiveTerms,
      };

      return Ok(stats);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to get stats', e),
      );
    }
  }

  /// Get language pair statistics for a glossary
  ///
  /// Returns map of language pairs to entry counts
  Future<Result<Map<String, int>, GlossaryException>> getLanguagePairStats(
    String glossaryId,
  ) async {
    try {
      final entries = await _repository.getEntriesByGlossary(
        glossaryId: glossaryId,
      );

      final pairCounts = <String, int>{};
      for (final entry in entries) {
        final pair = entry.targetLanguageCode;
        pairCounts[pair] = (pairCounts[pair] ?? 0) + 1;
      }

      return Ok(pairCounts);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to get language pair stats', e),
      );
    }
  }

  /// Get case sensitivity statistics for a glossary
  ///
  /// Returns counts of case-sensitive vs case-insensitive entries
  Future<Result<Map<String, int>, GlossaryException>> getCaseSensitivityStats(
    String glossaryId,
  ) async {
    try {
      final entries = await _repository.getEntriesByGlossary(
        glossaryId: glossaryId,
      );

      final caseSensitiveCount = entries.where((e) => e.caseSensitive).length;
      final caseInsensitiveCount = entries.length - caseSensitiveCount;

      return Ok({
        'case_sensitive': caseSensitiveCount,
        'case_insensitive': caseInsensitiveCount,
      });
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to get case sensitivity stats', e),
      );
    }
  }
}
