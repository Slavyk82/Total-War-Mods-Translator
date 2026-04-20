import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/features/translation_editor/utils/validation_issues_parser.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart' as batch;
import 'package:twmt/services/translation/models/translation_exceptions.dart'
    as v_exc;
import 'package:twmt/services/translation/utils/translation_skip_filter.dart';
import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;
import 'editor_row_models.dart';
import 'editor_filter_notifier.dart';

part 'grid_data_providers.g.dart';

/// Provider for translation rows (units + versions)
///
/// Uses optimized SQL JOIN query to fetch all data in a single database round-trip.
/// This eliminates the N+1 query pattern and reduces memory overhead from in-memory joins.
@riverpod
Future<List<TranslationRow>> translationRows(
  Ref ref,
  String projectId,
  String languageId,
) async {
  final unitRepo = ref.watch(shared_repo.translationUnitRepositoryProvider);
  final projectLanguageRepo = ref.watch(shared_repo.projectLanguageRepositoryProvider);

  // First, find the project_language_id for this project and language
  final projectLanguagesResult = await projectLanguageRepo.getByProject(projectId);
  if (projectLanguagesResult.isErr) {
    throw Exception('Failed to load project languages: ${projectLanguagesResult.unwrapErr()}');
  }

  final projectLanguages = projectLanguagesResult.unwrap();
  final projectLanguage = projectLanguages.where(
    (pl) => pl.languageId == languageId,
  ).firstOrNull;

  if (projectLanguage == null) {
    throw Exception('Project language not found for languageId: $languageId');
  }

  // Use optimized JOIN query to fetch all translation rows in a single query
  // This eliminates:
  // - 2 separate database queries (units + versions)
  // - O(n) Map insertions for version lookup
  // - O(n) Map lookups during join
  // - Memory holding duplicate data during join operation
  final joinedResult = await unitRepo.getTranslationRowsJoined(
    projectId: projectId,
    projectLanguageId: projectLanguage.id,
  );

  if (joinedResult.isErr) {
    throw Exception('Failed to load translation rows: ${joinedResult.unwrapErr()}');
  }

  final joinedMaps = joinedResult.unwrap();

  // Convert joined maps to TranslationRow objects
  // Data is already sorted by key ASC from the SQL query
  // Filter out placeholder/skip units that should not be displayed in the editor
  final rows = <TranslationRow>[];
  for (final map in joinedMaps) {
    final sourceText = map['source_text'] as String;

    // Skip placeholder units (e.g., "[placeholder]", "[unseen]", "[do not localise]")
    // These are filtered out entirely from the editor display
    // If the source_text changes during a mod update, the unit will reappear
    if (TranslationSkipFilter.shouldSkip(sourceText)) {
      continue;
    }

    // Build TranslationUnit from the joined data
    final unit = TranslationUnit(
      id: map['id'] as String,
      projectId: map['project_id'] as String,
      key: map['key'] as String,
      sourceText: sourceText,
      context: map['context'] as String?,
      notes: map['notes'] as String?,
      sourceLocFile: map['source_loc_file'] as String?,
      isObsolete: (map['is_obsolete'] as int) == 1,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
    );

    // Build TranslationVersion from the joined data (version columns are aliased)
    final version = TranslationVersion(
      id: map['version_id'] as String,
      unitId: map['unit_id'] as String,
      projectLanguageId: map['project_language_id'] as String,
      translatedText: map['translated_text'] as String?,
      isManuallyEdited: (map['is_manually_edited'] as int) == 1,
      status: parseStatus(map['status'] as String),
      translationSource: parseTranslationSource(map['translation_source'] as String?),
      validationIssues: map['validation_issues'] as String?,
      createdAt: map['version_created_at'] as int,
      updatedAt: map['version_updated_at'] as int,
    );

    rows.add(TranslationRow(unit: unit, version: version));
  }

  return rows;
}

/// Provider for filtered translation rows
/// Applies status filters, TM source filters, and search query from EditorFilterState
@riverpod
Future<List<TranslationRow>> filteredTranslationRows(
  Ref ref,
  String projectId,
  String languageId,
) async {
  // Get all rows
  final allRows = await ref.watch(translationRowsProvider(projectId, languageId).future);

  // Get filter state
  final filterState = ref.watch(editorFilterProvider);

  // If no filters active, return all rows
  if (!filterState.hasActiveFilters) {
    return allRows;
  }

  // Apply filters
  return allRows.where((row) {
    // Status filter
    if (filterState.statusFilters.isNotEmpty) {
      if (!filterState.statusFilters.contains(row.status)) {
        return false;
      }
    }

    // TM source filter
    if (filterState.tmSourceFilters.isNotEmpty) {
      final tmSourceType = getTmSourceType(row);
      if (!filterState.tmSourceFilters.contains(tmSourceType)) {
        return false;
      }
    }

    // Search query filter
    if (filterState.searchQuery.isNotEmpty) {
      final query = filterState.searchQuery.toLowerCase();
      final matchesKey = row.key.toLowerCase().contains(query);
      final matchesSource = row.sourceText.toLowerCase().contains(query);
      final matchesTranslated = row.translatedText?.toLowerCase().contains(query) ?? false;

      if (!matchesKey && !matchesSource && !matchesTranslated) {
        return false;
      }
    }

    // Show only with issues filter
    if (filterState.showOnlyWithIssues) {
      if (!row.hasValidationIssues) {
        return false;
      }
    }

    // Severity filter (only meaningful when statusFilters contains needsReview;
    // applied unconditionally because an empty set short-circuits).
    if (!_matchesSeverity(row, filterState.severityFilters)) {
      return false;
    }

    return true;
  }).toList();
}

/// Bucket a `v_exc.ValidationSeverity` into the coarser `batch.ValidationSeverity`
/// used by the editor filter state and pill group. `critical` folds into `error`
/// because the batch enum has no separate critical bucket — both surface in
/// the "Errors" pill.
batch.ValidationSeverity _bucketSeverity(v_exc.ValidationSeverity severity) {
  switch (severity) {
    case v_exc.ValidationSeverity.error:
    case v_exc.ValidationSeverity.critical:
      return batch.ValidationSeverity.error;
    case v_exc.ValidationSeverity.warning:
      return batch.ValidationSeverity.warning;
  }
}

/// Returns true when the row has at least one parsed validation issue whose
/// severity is in [severities]. An empty [severities] set is a no-op.
bool _matchesSeverity(
    TranslationRow row, Set<batch.ValidationSeverity> severities) {
  if (severities.isEmpty) return true;
  final parsed = parseValidationIssues(row.version.validationIssues);
  if (parsed.isEmpty) return false;
  for (final issue in parsed) {
    if (severities.contains(_bucketSeverity(issue.severity))) return true;
  }
  return false;
}

/// Provider for editor statistics
/// Uses database statistics for consistency with project list (excludes bracket-only units)
@riverpod
Future<EditorStats> editorStats(
  Ref ref,
  String projectId,
  String languageId,
) async {
  // Watch translation rows to trigger refresh when translations change
  await ref.watch(translationRowsProvider(projectId, languageId).future);

  final projectLanguageRepo = ref.watch(shared_repo.projectLanguageRepositoryProvider);
  final versionRepo = ref.watch(shared_repo.translationVersionRepositoryProvider);

  // Get project language ID
  final projectLanguagesResult = await projectLanguageRepo.getByProject(projectId);
  if (projectLanguagesResult.isErr) {
    return EditorStats.empty();
  }

  final projectLanguages = projectLanguagesResult.unwrap();
  final projectLanguage = projectLanguages.where((pl) => pl.languageId == languageId).firstOrNull;
  if (projectLanguage == null) {
    return EditorStats.empty();
  }

  // Get statistics from repository (excludes bracket-only units)
  final statsResult = await versionRepo.getLanguageStatistics(projectLanguage.id);
  if (statsResult.isErr) {
    return EditorStats.empty();
  }

  final stats = statsResult.unwrap();
  final totalUnits = stats.totalCount;
  final translatedCount = stats.translatedCount;
  final pendingCount = stats.pendingCount;
  final needsReviewCount = stats.errorCount;

  // Calculate completion percentage
  final completionPercentage =
      totalUnits > 0 ? (translatedCount / totalUnits) * 100 : 0.0;

  return EditorStats(
    totalUnits: totalUnits,
    pendingCount: pendingCount,
    translatedCount: translatedCount,
    needsReviewCount: needsReviewCount,
    completionPercentage: completionPercentage,
  );
}
