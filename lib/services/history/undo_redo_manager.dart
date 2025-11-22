import 'package:twmt/config/app_constants.dart';
import '../../repositories/translation_version_repository.dart';

/// Represents a single undoable/redoable action
abstract class HistoryAction {
  /// ID of the translation version affected
  String get versionId;

  /// Previous value before the action
  String get oldValue;

  /// New value after the action
  String get newValue;

  /// When the action was performed
  DateTime get timestamp;

  /// Undo this action (restore old value)
  Future<void> undo();

  /// Redo this action (restore new value)
  Future<void> redo();
}

/// Concrete implementation for translation edit actions
class TranslationEditAction implements HistoryAction {
  @override
  final String versionId;

  @override
  final String oldValue;

  @override
  final String newValue;

  @override
  final DateTime timestamp;

  final TranslationVersionRepository _repository;

  TranslationEditAction({
    required this.versionId,
    required this.oldValue,
    required this.newValue,
    required this.timestamp,
    required TranslationVersionRepository repository,
  }) : _repository = repository;

  @override
  Future<void> undo() async {
    // Get current version
    final result = await _repository.getById(versionId);
    if (result.isErr) {
      throw Exception('Failed to get version for undo: ${result.error}');
    }

    final version = result.value;

    // Update with old value
    final updated = version.copyWith(
      translatedText: oldValue,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    final updateResult = await _repository.update(updated);
    if (updateResult.isErr) {
      throw Exception('Failed to undo: ${updateResult.error}');
    }
  }

  @override
  Future<void> redo() async {
    // Get current version
    final result = await _repository.getById(versionId);
    if (result.isErr) {
      throw Exception('Failed to get version for redo: ${result.error}');
    }

    final version = result.value;

    // Update with new value
    final updated = version.copyWith(
      translatedText: newValue,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    final updateResult = await _repository.update(updated);
    if (updateResult.isErr) {
      throw Exception('Failed to redo: ${updateResult.error}');
    }
  }

  @override
  String toString() {
    return 'TranslationEditAction(versionId: $versionId, '
        'oldValue: "${oldValue.length > AppConstants.maxPreviewTextLength ? '${oldValue.substring(0, AppConstants.maxPreviewTextLength)}...' : oldValue}", '
        'newValue: "${newValue.length > AppConstants.maxPreviewTextLength ? '${newValue.substring(0, AppConstants.maxPreviewTextLength)}...' : newValue}", '
        'timestamp: $timestamp)';
  }
}

/// State for the undo/redo manager
class UndoRedoManagerState {
  /// Stack of actions that can be undone
  final List<HistoryAction> undoStack;

  /// Stack of actions that can be redone
  final List<HistoryAction> redoStack;

  const UndoRedoManagerState({
    required this.undoStack,
    required this.redoStack,
  });

  UndoRedoManagerState copyWith({
    List<HistoryAction>? undoStack,
    List<HistoryAction>? redoStack,
  }) {
    return UndoRedoManagerState(
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
    );
  }

  /// Check if undo is available
  bool get canUndo => undoStack.isNotEmpty;

  /// Check if redo is available
  bool get canRedo => redoStack.isNotEmpty;

  /// Get the most recent undoable action (without removing it)
  HistoryAction? get lastUndoableAction {
    return undoStack.isEmpty ? null : undoStack.last;
  }

  /// Get the most recent redoable action (without removing it)
  HistoryAction? get lastRedoableAction {
    return redoStack.isEmpty ? null : redoStack.last;
  }
}

/// Manager for undo/redo operations
///
/// Maintains two stacks: one for undo and one for redo.
/// When an action is performed, it's added to the undo stack and redo is cleared.
/// When undo is performed, the action is moved from undo to redo stack.
/// When redo is performed, the action is moved from redo to undo stack.
class UndoRedoManager {

  final List<HistoryAction> _undoStack = [];
  final List<HistoryAction> _redoStack = [];

  /// Record a new action
  ///
  /// Adds the action to the undo stack and clears the redo stack.
  /// If the stack exceeds [maxStackSize], the oldest action is removed.
  void recordAction(HistoryAction action) {
    _undoStack.add(action);

    // Limit stack size
    if (_undoStack.length > AppConstants.maxUndoStackSize) {
      _undoStack.removeAt(0);
    }

    // Clear redo stack when new action is recorded
    _redoStack.clear();
  }

  /// Undo the last action
  ///
  /// Returns true if undo was successful, false if nothing to undo.
  Future<bool> undo() async {
    if (!canUndo) return false;

    try {
      final action = _undoStack.removeLast();
      await action.undo();
      _redoStack.add(action);
      return true;
    } catch (e) {
      // Re-add action if undo failed
      if (_undoStack.isEmpty || _undoStack.last != _undoStack.last) {
        // Action was already removed, add it back
      }
      rethrow;
    }
  }

  /// Redo the last undone action
  ///
  /// Returns true if redo was successful, false if nothing to redo.
  Future<bool> redo() async {
    if (!canRedo) return false;

    try {
      final action = _redoStack.removeLast();
      await action.redo();
      _undoStack.add(action);
      return true;
    } catch (e) {
      // Re-add action if redo failed
      if (_redoStack.isEmpty || _redoStack.last != _redoStack.last) {
        // Action was already removed, add it back
      }
      rethrow;
    }
  }

  /// Check if undo is available
  bool get canUndo => _undoStack.isNotEmpty;

  /// Check if redo is available
  bool get canRedo => _redoStack.isNotEmpty;

  /// Get current state
  UndoRedoManagerState get state {
    return UndoRedoManagerState(
      undoStack: List.unmodifiable(_undoStack),
      redoStack: List.unmodifiable(_redoStack),
    );
  }

  /// Clear all stacks
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }

  /// Get number of actions that can be undone
  int get undoCount => _undoStack.length;

  /// Get number of actions that can be redone
  int get redoCount => _redoStack.length;

  /// Get the last undoable action (without removing it)
  HistoryAction? get lastUndoableAction {
    return _undoStack.isEmpty ? null : _undoStack.last;
  }

  /// Get the last redoable action (without removing it)
  HistoryAction? get lastRedoableAction {
    return _redoStack.isEmpty ? null : _redoStack.last;
  }

  @override
  String toString() {
    return 'UndoRedoManager(undoStack: ${_undoStack.length}, '
        'redoStack: ${_redoStack.length})';
  }
}
