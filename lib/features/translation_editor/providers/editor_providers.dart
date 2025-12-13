import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/services/validation/i_translation_validation_service.dart';
import 'package:twmt/services/validation/models/validation_issue.dart';
import 'package:twmt/services/search/i_search_service.dart';
import 'package:twmt/services/history/undo_redo_manager.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/repositories/translation_batch_repository.dart';
import 'package:twmt/repositories/translation_batch_unit_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/llm_provider_model_repository.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/services/file/export_orchestrator_service.dart';
import 'package:twmt/services/translation/utils/translation_skip_filter.dart';

part 'editor_providers.g.dart';

// =============================================================================
// GLOBAL TRANSLATION STATE
// =============================================================================

/// Global state tracking if a batch translation is in progress.
/// Used to block navigation while translation is running.
@Riverpod(keepAlive: true)
class TranslationInProgress extends _$TranslationInProgress {
  @override
  bool build() => false;

  void setInProgress(bool value) => state = value;
}

/// Combined view of translation unit and its version for display in DataGrid
class TranslationRow {
  final TranslationUnit unit;
  final TranslationVersion version;

  const TranslationRow({
    required this.unit,
    required this.version,
  });

  String get id => unit.id;
  String get key => unit.key;
  String get sourceText => unit.sourceText;
  String? get translatedText => version.translatedText;
  TranslationVersionStatus get status => version.status;
  TranslationSource get translationSource => version.translationSource;
  bool get isManuallyEdited => version.isManuallyEdited;
  bool get hasValidationIssues => version.hasValidationIssues;
  String? get sourceLocFile => unit.sourceLocFile;

  TranslationRow copyWith({
    TranslationUnit? unit,
    TranslationVersion? version,
  }) {
    return TranslationRow(
      unit: unit ?? this.unit,
      version: version ?? this.version,
    );
  }
}

/// Filter state for the translation editor
class EditorFilterState {
  final Set<TranslationVersionStatus> statusFilters;
  final Set<TmSourceType> tmSourceFilters;
  final String searchQuery;
  final bool showOnlyWithIssues;

  const EditorFilterState({
    this.statusFilters = const {},
    this.tmSourceFilters = const {},
    this.searchQuery = '',
    this.showOnlyWithIssues = false,
  });

  bool get hasActiveFilters =>
    statusFilters.isNotEmpty ||
    tmSourceFilters.isNotEmpty ||
    searchQuery.isNotEmpty ||
    showOnlyWithIssues;

  EditorFilterState copyWith({
    Set<TranslationVersionStatus>? statusFilters,
    Set<TmSourceType>? tmSourceFilters,
    String? searchQuery,
    bool? showOnlyWithIssues,
  }) {
    return EditorFilterState(
      statusFilters: statusFilters ?? this.statusFilters,
      tmSourceFilters: tmSourceFilters ?? this.tmSourceFilters,
      searchQuery: searchQuery ?? this.searchQuery,
      showOnlyWithIssues: showOnlyWithIssues ?? this.showOnlyWithIssues,
    );
  }
}

/// Type of TM source for filtering
enum TmSourceType {
  exactMatch,
  fuzzyMatch,
  llm,
  manual,
  none,
}

/// Selection state for multi-select operations
class EditorSelectionState {
  final Set<String> selectedUnitIds;

  const EditorSelectionState({
    this.selectedUnitIds = const {},
  });

  bool get hasSelection => selectedUnitIds.isNotEmpty;
  int get selectedCount => selectedUnitIds.length;

  bool isSelected(String unitId) => selectedUnitIds.contains(unitId);

  EditorSelectionState copyWith({
    Set<String>? selectedUnitIds,
  }) {
    return EditorSelectionState(
      selectedUnitIds: selectedUnitIds ?? this.selectedUnitIds,
    );
  }
}

/// Statistics for the current translation session
class EditorStats {
  final int totalUnits;
  final int pendingCount;
  final int translatedCount;
  final int needsReviewCount;
  final double completionPercentage;

  const EditorStats({
    required this.totalUnits,
    required this.pendingCount,
    required this.translatedCount,
    required this.needsReviewCount,
    required this.completionPercentage,
  });

  static EditorStats empty() {
    return const EditorStats(
      totalUnits: 0,
      pendingCount: 0,
      translatedCount: 0,
      needsReviewCount: 0,
      completionPercentage: 0.0,
    );
  }
}

/// Provider for project repository
@riverpod
ProjectRepository projectRepository(Ref ref) {
  return ServiceLocator.get<ProjectRepository>();
}

/// Provider for language repository
@riverpod
LanguageRepository languageRepository(Ref ref) {
  return ServiceLocator.get<LanguageRepository>();
}

/// Provider for translation unit repository
@riverpod
TranslationUnitRepository translationUnitRepository(Ref ref) {
  return ServiceLocator.get<TranslationUnitRepository>();
}

/// Provider for translation version repository
@riverpod
TranslationVersionRepository translationVersionRepository(Ref ref) {
  return ServiceLocator.get<TranslationVersionRepository>();
}

/// Provider for translation memory service
@riverpod
ITranslationMemoryService translationMemoryService(Ref ref) {
  return ServiceLocator.get<ITranslationMemoryService>();
}

/// Provider for search service
@riverpod
ISearchService searchService(Ref ref) {
  return ServiceLocator.get<ISearchService>();
}

/// Provider for undo/redo manager
@riverpod
UndoRedoManager undoRedoManager(Ref ref) {
  return UndoRedoManager();
}

/// Provider for current project
@riverpod
Future<Project> currentProject(
  Ref ref,
  String projectId,
) async {
  final repository = ref.watch(projectRepositoryProvider);
  final result = await repository.getById(projectId);

  return result.when(
    ok: (project) => project,
    err: (error) => throw Exception('Failed to load project: $error'),
  );
}

/// Provider for current language
@riverpod
Future<Language> currentLanguage(
  Ref ref,
  String languageId,
) async {
  final repository = ref.watch(languageRepositoryProvider);
  final result = await repository.getById(languageId);

  return result.when(
    ok: (language) => language,
    err: (error) => throw Exception('Failed to load language: $error'),
  );
}

/// Provider for filter state
@riverpod
class EditorFilter extends _$EditorFilter {
  @override
  EditorFilterState build() {
    return const EditorFilterState();
  }

  void setStatusFilters(Set<TranslationVersionStatus> filters) {
    state = state.copyWith(statusFilters: filters);
  }

  void setTmSourceFilters(Set<TmSourceType> filters) {
    state = state.copyWith(tmSourceFilters: filters);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setShowOnlyWithIssues(bool show) {
    state = state.copyWith(showOnlyWithIssues: show);
  }

  void clearFilters() {
    state = const EditorFilterState();
  }
}

/// Provider for selection state
@riverpod
class EditorSelection extends _$EditorSelection {
  @override
  EditorSelectionState build() {
    return const EditorSelectionState();
  }

  void toggleSelection(String unitId) {
    final selected = Set<String>.from(state.selectedUnitIds);
    if (selected.contains(unitId)) {
      selected.remove(unitId);
    } else {
      selected.add(unitId);
    }
    state = EditorSelectionState(selectedUnitIds: selected);
  }

  void selectAll(List<String> unitIds) {
    state = EditorSelectionState(selectedUnitIds: unitIds.toSet());
  }

  void clearSelection() {
    state = const EditorSelectionState();
  }

  void selectRange(String startId, String endId, List<String> allIds) {
    final startIndex = allIds.indexOf(startId);
    final endIndex = allIds.indexOf(endId);

    if (startIndex == -1 || endIndex == -1) return;

    final start = startIndex < endIndex ? startIndex : endIndex;
    final end = startIndex < endIndex ? endIndex : startIndex;

    final rangeIds = allIds.sublist(start, end + 1).toSet();
    state = EditorSelectionState(selectedUnitIds: rangeIds);
  }
}

/// Get the TM source type from a translation row based on translation source field
TmSourceType getTmSourceType(TranslationRow row) {
  if (row.isManuallyEdited) return TmSourceType.manual;

  // Use explicit translation source field
  switch (row.translationSource) {
    case TranslationSource.tmExact:
      return TmSourceType.exactMatch;
    case TranslationSource.tmFuzzy:
      return TmSourceType.fuzzyMatch;
    case TranslationSource.llm:
      return TmSourceType.llm;
    case TranslationSource.manual:
      return TmSourceType.manual;
    case TranslationSource.unknown:
      return TmSourceType.none;
  }
}

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
  final unitRepo = ref.watch(translationUnitRepositoryProvider);
  final projectLanguageRepo = ServiceLocator.get<ProjectLanguageRepository>();

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
      status: _parseStatus(map['status'] as String),
      translationSource: _parseTranslationSource(map['translation_source'] as String?),
      validationIssues: map['validation_issues'] as String?,
      createdAt: map['version_created_at'] as int,
      updatedAt: map['version_updated_at'] as int,
    );

    rows.add(TranslationRow(unit: unit, version: version));
  }

  return rows;
}

/// Parse status string to enum
TranslationVersionStatus _parseStatus(String status) {
  switch (status) {
    case 'pending':
      return TranslationVersionStatus.pending;
    case 'translated':
      return TranslationVersionStatus.translated;
    case 'needs_review':
    case 'needsReview':
      return TranslationVersionStatus.needsReview;
    default:
      return TranslationVersionStatus.pending;
  }
}

/// Parse translation source string to enum
TranslationSource _parseTranslationSource(String? source) {
  if (source == null) return TranslationSource.unknown;
  switch (source) {
    case 'manual':
      return TranslationSource.manual;
    case 'tm_exact':
      return TranslationSource.tmExact;
    case 'tm_fuzzy':
      return TranslationSource.tmFuzzy;
    case 'llm':
      return TranslationSource.llm;
    default:
      return TranslationSource.unknown;
  }
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
    
    return true;
  }).toList();
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

  final projectLanguageRepo = ref.watch(projectLanguageRepositoryProvider);
  final versionRepo = ref.watch(translationVersionRepositoryProvider);

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

/// Provider for validation service
@riverpod
ITranslationValidationService validationService(Ref ref) {
  return ServiceLocator.get<ITranslationValidationService>();
}

/// Provider for logging service
@riverpod
LoggingService loggingService(Ref ref) {
  return ServiceLocator.get<LoggingService>();
}

/// Provider for translation batch repository
@riverpod
TranslationBatchRepository translationBatchRepository(Ref ref) {
  return ServiceLocator.get<TranslationBatchRepository>();
}

/// Provider for translation batch unit repository
@riverpod
TranslationBatchUnitRepository translationBatchUnitRepository(Ref ref) {
  return ServiceLocator.get<TranslationBatchUnitRepository>();
}

/// Provider for project language repository
@riverpod
ProjectLanguageRepository projectLanguageRepository(Ref ref) {
  return ServiceLocator.get<ProjectLanguageRepository>();
}

/// Provider for translation orchestrator
@riverpod
ITranslationOrchestrator translationOrchestrator(Ref ref) {
  return ServiceLocator.get<ITranslationOrchestrator>();
}

/// Provider for export orchestrator service
@riverpod
ExportOrchestratorService exportOrchestratorService(Ref ref) {
  return ServiceLocator.get<ExportOrchestratorService>();
}

/// Provider for LLM provider model repository
@riverpod
LlmProviderModelRepository llmProviderModelRepository(Ref ref) {
  return ServiceLocator.get<LlmProviderModelRepository>();
}

/// Provider for available LLM models (enabled, non-archived)
/// Returns all enabled models across all providers
@riverpod
Future<List<LlmProviderModel>> availableLlmModels(Ref ref) async {
  final repository = ref.watch(llmProviderModelRepositoryProvider);

  // Query all enabled, non-archived models
  final result = await repository.executeQuery(() async {
    final maps = await repository.database.query(
      'llm_provider_models',
      where: 'is_enabled = 1 AND is_archived = 0',
      orderBy: 'provider_code ASC, display_name ASC',
    );
    return maps.map((map) => LlmProviderModel.fromJson(map)).toList();
  });

  return result.when(
    ok: (models) => models,
    err: (error) {
      // Log error and return empty list
      final logger = ref.read(loggingServiceProvider);
      logger.error('Failed to load available LLM models: $error');
      return <LlmProviderModel>[];
    },
  );
}

/// Provider for the currently selected LLM model ID
/// This is local state (not persisted), used when launching translation batches
/// keepAlive prevents the state from being disposed when there are no listeners
@Riverpod(keepAlive: true)
class SelectedLlmModel extends _$SelectedLlmModel {
  @override
  String? build() => null;

  /// Set the selected model ID
  void setModel(String? modelId) {
    state = modelId;
  }

  /// Clear the selection (will use default)
  void clear() {
    state = null;
  }
}

// =============================================================================
// TM SUGGESTIONS PROVIDER
// =============================================================================

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
  final unitRepo = ref.watch(translationUnitRepositoryProvider);
  final tmService = ref.watch(translationMemoryServiceProvider);

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

// =============================================================================
// VALIDATION ISSUES PROVIDER
// =============================================================================

/// Provider for validation issues for a specific translation
///
/// Validates the translation against the source text and returns
/// any issues found (errors, warnings, info).
@riverpod
Future<List<ValidationIssue>> validationIssues(
  Ref ref,
  String sourceText,
  String translatedText,
) async {
  final validationSvc = ref.watch(validationServiceProvider);

  final result = await validationSvc.validateTranslation(
    sourceText: sourceText,
    translatedText: translatedText,
  );

  return result.when(
    ok: (issues) => issues,
    err: (error) {
      // Log error and return empty list
      final logger = ref.read(loggingServiceProvider);
      logger.error('Failed to validate translation: $error');
      return <ValidationIssue>[];
    },
  );
}
