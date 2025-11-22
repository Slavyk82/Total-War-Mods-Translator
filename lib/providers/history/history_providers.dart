import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../models/domain/translation_version_history.dart';
import '../../models/history/diff_models.dart';
import '../../repositories/translation_version_repository.dart';
import '../../services/history/i_history_service.dart';
import '../../services/history/undo_redo_manager.dart';
import '../../services/service_locator.dart';

part 'history_providers.g.dart';

/// History service provider
///
/// Provides access to the history service for recording and managing
/// translation version history.
@riverpod
IHistoryService historyService(Ref ref) {
  return ServiceLocator.get<IHistoryService>();
}

/// Provider for history entries of a specific translation version
///
/// Returns all history entries for a version, ordered by creation date (newest first).
@riverpod
Future<List<TranslationVersionHistory>> versionHistory(
  Ref ref,
  String versionId,
) async {
  final service = ref.watch(historyServiceProvider);
  final result = await service.getHistory(versionId);
  return result.when(
    ok: (history) => history,
    err: (error) => throw Exception('Failed to load history: $error'),
  );
}

/// Provider for a specific history entry
@riverpod
Future<TranslationVersionHistory> historyEntry(
  Ref ref,
  String historyId,
) async {
  final service = ref.watch(historyServiceProvider);
  final result = await service.getHistoryEntry(historyId);
  return result.when(
    ok: (entry) => entry,
    err: (error) => throw Exception('Failed to load history entry: $error'),
  );
}

/// Provider for comparing two history versions
@riverpod
Future<VersionComparison> versionComparison(
  Ref ref,
  String historyId1,
  String historyId2,
) async {
  final service = ref.watch(historyServiceProvider);
  final result = await service.compareVersions(
    historyId1: historyId1,
    historyId2: historyId2,
  );
  return result.when(
    ok: (comparison) => comparison,
    err: (error) => throw Exception('Failed to compare versions: $error'),
  );
}

/// Provider for history statistics
@riverpod
Future<HistoryStats> historyStatistics(Ref ref) async {
  final service = ref.watch(historyServiceProvider);
  final result = await service.getStatistics();
  return result.when(
    ok: (stats) => stats,
    err: (error) => throw Exception('Failed to load statistics: $error'),
  );
}

/// Provider for history statistics of a specific version
@riverpod
Future<HistoryStats> versionHistoryStatistics(
  Ref ref,
  String versionId,
) async {
  final service = ref.watch(historyServiceProvider);
  final result = await service.getStatisticsForVersion(versionId);
  return result.when(
    ok: (stats) => stats,
    err: (error) => throw Exception('Failed to load statistics: $error'),
  );
}

/// Undo/Redo Manager Provider
///
/// This is a singleton provider that maintains the undo/redo state
/// throughout the application lifecycle. It's kept alive to preserve
/// the undo/redo history even when widgets are disposed.
@Riverpod(keepAlive: true)
class UndoRedoManagerNotifier extends _$UndoRedoManagerNotifier {
  late UndoRedoManager _manager;
  late TranslationVersionRepository _repository;

  @override
  UndoRedoManagerState build() {
    _repository = ServiceLocator.get<TranslationVersionRepository>();
    _manager = UndoRedoManager();
    return _manager.state;
  }

  /// Record a new action
  void recordAction(HistoryAction action) {
    _manager.recordAction(action);
    state = _manager.state;
  }

  /// Record a translation edit action
  void recordEdit({
    required String versionId,
    required String oldValue,
    required String newValue,
  }) {
    final action = TranslationEditAction(
      versionId: versionId,
      oldValue: oldValue,
      newValue: newValue,
      timestamp: DateTime.now(),
      repository: _repository,
    );
    recordAction(action);
  }

  /// Undo the last action
  Future<bool> undo() async {
    final success = await _manager.undo();
    if (success) {
      state = _manager.state;
    }
    return success;
  }

  /// Redo the last undone action
  Future<bool> redo() async {
    final success = await _manager.redo();
    if (success) {
      state = _manager.state;
    }
    return success;
  }

  /// Check if undo is available
  bool get canUndo => state.canUndo;

  /// Check if redo is available
  bool get canRedo => state.canRedo;

  /// Clear all undo/redo history
  void clear() {
    _manager.clear();
    state = _manager.state;
  }

  /// Get the last undoable action (for tooltip/preview)
  HistoryAction? get lastUndoableAction => state.lastUndoableAction;

  /// Get the last redoable action (for tooltip/preview)
  HistoryAction? get lastRedoableAction => state.lastRedoableAction;
}

/// Provider for checking if undo is available
@riverpod
bool canUndo(Ref ref) {
  final state = ref.watch(undoRedoManagerProvider);
  return state.canUndo;
}

/// Provider for checking if redo is available
@riverpod
bool canRedo(Ref ref) {
  final state = ref.watch(undoRedoManagerProvider);
  return state.canRedo;
}
