import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/translation_version_history.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/repositories/translation_version_history_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
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

part 'editor_providers.g.dart';

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
  bool get isManuallyEdited => version.isManuallyEdited;
  bool get hasValidationIssues => version.hasValidationIssues;

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
  final int translatingCount;
  final int translatedCount;
  final int reviewedCount;
  final int approvedCount;
  final int needsReviewCount;
  final double completionPercentage;

  const EditorStats({
    required this.totalUnits,
    required this.pendingCount,
    required this.translatingCount,
    required this.translatedCount,
    required this.reviewedCount,
    required this.approvedCount,
    required this.needsReviewCount,
    required this.completionPercentage,
  });

  static EditorStats empty() {
    return const EditorStats(
      totalUnits: 0,
      pendingCount: 0,
      translatingCount: 0,
      translatedCount: 0,
      reviewedCount: 0,
      approvedCount: 0,
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

/// Provider for TM suggestions for a specific unit
@riverpod
Future<List<TmMatch>> tmSuggestionsForUnit(
  Ref ref,
  String unitId,
  String sourceLanguageCode,
  String targetLanguageCode,
) async {
  final tmService = ref.watch(translationMemoryServiceProvider);

  // Get the translation unit to get source text
  final unitRepo = ref.watch(translationUnitRepositoryProvider);
  final unitResult = await unitRepo.getById(unitId);

  return unitResult.when(
    ok: (unit) async {
      final result = await tmService.findFuzzyMatches(
        sourceText: unit.sourceText,
        targetLanguageCode: targetLanguageCode,
        maxResults: 3,
        minSimilarity: 0.85,
      );

      return result.when(
        ok: (matches) => matches,
        err: (_) => <TmMatch>[],
      );
    },
    err: (_) => <TmMatch>[],
  );
}

/// Provider for editor statistics
@riverpod
Future<EditorStats> editorStats(
  Ref ref,
  String projectId,
  String languageId,
) async {
  // Get all translation rows to calculate statistics
  final rows = await ref.watch(translationRowsProvider(projectId, languageId).future);

  if (rows.isEmpty) {
    return EditorStats.empty();
  }

  // Count by status
  int pendingCount = 0;
  int translatingCount = 0;
  int translatedCount = 0;
  int reviewedCount = 0;
  int approvedCount = 0;
  int needsReviewCount = 0;

  for (final row in rows) {
    switch (row.status) {
      case TranslationVersionStatus.pending:
        pendingCount++;
        break;
      case TranslationVersionStatus.translating:
        translatingCount++;
        break;
      case TranslationVersionStatus.translated:
        translatedCount++;
        break;
      case TranslationVersionStatus.reviewed:
        reviewedCount++;
        break;
      case TranslationVersionStatus.approved:
        approvedCount++;
        break;
      case TranslationVersionStatus.needsReview:
        needsReviewCount++;
        break;
    }
  }

  // Calculate completion percentage
  // Consider translated, reviewed, and approved as "completed"
  final completedCount = translatedCount + reviewedCount + approvedCount;
  final totalUnits = rows.length;
  final completionPercentage =
      totalUnits > 0 ? (completedCount / totalUnits) * 100 : 0.0;

  return EditorStats(
    totalUnits: totalUnits,
    pendingCount: pendingCount,
    translatingCount: translatingCount,
    translatedCount: translatedCount,
    reviewedCount: reviewedCount,
    approvedCount: approvedCount,
    needsReviewCount: needsReviewCount,
    completionPercentage: completionPercentage,
  );
}

/// Provider for translation version history repository
@riverpod
TranslationVersionHistoryRepository translationVersionHistoryRepository(Ref ref) {
  return ServiceLocator.get<TranslationVersionHistoryRepository>();
}

/// Provider for validation service
@riverpod
ITranslationValidationService validationService(Ref ref) {
  return ServiceLocator.get<ITranslationValidationService>();
}

/// Provider for history entries for a specific version
@riverpod
Future<List<TranslationVersionHistory>> historyForVersion(
  Ref ref,
  String versionId,
) async {
  final repository = ref.watch(translationVersionHistoryRepositoryProvider);
  final result = await repository.getByVersion(versionId);

  return result.when(
    ok: (entries) => entries,
    err: (_) => <TranslationVersionHistory>[],
  );
}

/// Provider for validation issues
@riverpod
Future<List<ValidationIssue>> validationIssues(
  Ref ref,
  String sourceText,
  String translatedText,
) async {
  final service = ref.watch(validationServiceProvider);
  final result = await service.validateTranslation(
    sourceText: sourceText,
    translatedText: translatedText,
  );

  return result.when(
    ok: (issues) => issues,
    err: (_) => <ValidationIssue>[],
  );
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

/// Provider for currently selected translation version ID
/// This is used by the History and Validation panels to know which translation to display
@riverpod
class SelectedTranslationVersion extends _$SelectedTranslationVersion {
  @override
  String? build() => null;

  /// Set the currently selected translation version ID
  void select(String? versionId) {
    state = versionId;
  }

  /// Clear the selection
  void clear() {
    state = null;
  }
}

/// Provider for the full translation version data of the selected translation
@riverpod
Future<TranslationVersion?> selectedTranslationVersionData(
  Ref ref,
) async {
  final versionId = ref.watch(selectedTranslationVersionProvider);

  if (versionId == null) {
    return null;
  }

  final repository = ref.watch(translationVersionRepositoryProvider);
  final result = await repository.getById(versionId);

  return result.when(
    ok: (version) => version,
    err: (_) => null,
  );
}

/// Provider for the source text of the selected translation
@riverpod
Future<String?> selectedTranslationSourceText(
  Ref ref,
) async {
  final versionData = await ref.watch(selectedTranslationVersionDataProvider.future);

  if (versionData == null) {
    return null;
  }

  // Get the translation unit to get the source text
  final unitRepo = ref.watch(translationUnitRepositoryProvider);
  final unitResult = await unitRepo.getById(versionData.unitId);

  return unitResult.when(
    ok: (unit) => unit.sourceText,
    err: (_) => null,
  );
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
