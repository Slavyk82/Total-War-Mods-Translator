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
import 'package:twmt/services/validation/i_translation_validation_service.dart';
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
  double? get confidence => version.confidenceScore;
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
  
  // Use explicit translation source field if available
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
      // Fallback for legacy data: use confidence-based detection
      if (row.confidence != null) {
        if (row.confidence! >= 0.999) return TmSourceType.exactMatch;
        if (row.confidence! >= 0.85) return TmSourceType.fuzzyMatch;
        return TmSourceType.llm;
      }
      return TmSourceType.none;
  }
}

/// Provider for translation rows (units + versions)
@riverpod
Future<List<TranslationRow>> translationRows(
  Ref ref,
  String projectId,
  String languageId,
) async {
  final unitRepo = ref.watch(translationUnitRepositoryProvider);
  final versionRepo = ref.watch(translationVersionRepositoryProvider);
  final projectLanguageRepo = ServiceLocator.get<ProjectLanguageRepository>();

  // Get all units for this project
  final unitsResult = await unitRepo.getByProject(projectId);
  if (unitsResult.isErr) {
    throw Exception('Failed to load translation units: ${unitsResult.unwrapErr()}');
  }

  final units = unitsResult.unwrap();

  // First, find the project_language_id for this project and language
  final projectLanguagesResult = await projectLanguageRepo.getByProject(projectId);
  if (projectLanguagesResult.isErr) {
    throw Exception('Failed to load project languages: ${projectLanguagesResult.unwrapErr()}');
  }

  final projectLanguages = projectLanguagesResult.unwrap();
  final projectLanguage = projectLanguages.firstWhere(
    (pl) => pl.languageId == languageId,
    orElse: () => throw Exception('Project language not found for languageId: $languageId'),
  );

  // Get all versions for this project language using the correct project_language_id
  final versionsResult = await versionRepo.getByProjectLanguage(projectLanguage.id);
  if (versionsResult.isErr) {
    throw Exception('Failed to load translation versions: ${versionsResult.unwrapErr()}');
  }

  final versions = versionsResult.unwrap();

  // Create a map of unit_id -> version for quick lookup
  final versionMap = <String, TranslationVersion>{};
  for (final version in versions) {
    versionMap[version.unitId] = version;
  }

  // Join units with their versions
  final rows = <TranslationRow>[];
  for (final unit in units) {
    // Skip obsolete units
    if (unit.isObsolete) continue;

    // Find the version for this unit
    final version = versionMap[unit.id];
    if (version != null) {
      rows.add(TranslationRow(unit: unit, version: version));
    }
  }

  // Sort by key for consistent ordering
  rows.sort((a, b) => a.key.compareTo(b.key));

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
