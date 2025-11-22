import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/glossary/utils/glossary_statistics.dart';

/// Service for glossary statistics calculations
///
/// Handles all statistics-related operations including:
/// - Calculating glossary statistics
/// - Managing categories
/// - Generating usage reports
class GlossaryStatisticsService {
  final GlossaryRepository _repository;

  GlossaryStatisticsService(this._repository);

  /// Get comprehensive statistics for a glossary
  ///
  /// Returns statistics including:
  /// - Entry counts by language pair
  /// - Category distribution
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

      // Use statistics utility
      final stats = GlossaryStatistics.calculateStats(entries);

      return Ok(stats);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to get stats', e),
      );
    }
  }

  /// Get all unique categories across all glossaries
  ///
  /// Returns sorted list of category names
  Future<Result<List<String>, GlossaryException>> getAllCategories() async {
    try {
      final categories = await _repository.getAllCategories();
      return Ok(categories);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to get categories', e),
      );
    }
  }

  /// Get categories for a specific glossary
  ///
  /// [glossaryId]: ID of the glossary
  ///
  /// Returns sorted list of category names used in this glossary
  Future<Result<List<String>, GlossaryException>> getGlossaryCategories(
    String glossaryId,
  ) async {
    try {
      final entries = await _repository.getEntriesByGlossary(
        glossaryId: glossaryId,
      );

      final categories = entries
          .where((e) => e.category != null && e.category!.isNotEmpty)
          .map((e) => e.category!)
          .toSet()
          .toList()
        ..sort();

      return Ok(categories);
    } catch (e) {
      return Err(
        GlossaryDatabaseException('Failed to get glossary categories', e),
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
