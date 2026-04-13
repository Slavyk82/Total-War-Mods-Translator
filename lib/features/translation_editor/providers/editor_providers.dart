import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/services/history/undo_redo_manager.dart';
import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;

// Re-exports: extracted provider files.
export 'editor_row_models.dart';
export 'editor_filter_notifier.dart';
export 'editor_selection_notifier.dart';
export 'grid_data_providers.dart';
export 'llm_model_providers.dart';
export 'tm_suggestions_provider.dart';
export 'validation_issues_provider.dart';

part 'editor_providers.g.dart';

/// Global state tracking if a batch translation is in progress.
/// Used to block navigation while translation is running.
@Riverpod(keepAlive: true)
class TranslationInProgress extends _$TranslationInProgress {
  @override
  bool build() => false;

  void setInProgress(bool value) => state = value;
}

/// Provider for undo/redo manager.
/// Not a bridge wrapper — creates a fresh instance per project editor session.
@riverpod
UndoRedoManager undoRedoManager(Ref ref) {
  return UndoRedoManager();
}

/// Provider for current project (async single-record fetch).
@riverpod
Future<Project> currentProject(
  Ref ref,
  String projectId,
) async {
  final repository = ref.watch(shared_repo.projectRepositoryProvider);
  final result = await repository.getById(projectId);

  return result.when(
    ok: (project) => project,
    err: (error) => throw Exception('Failed to load project: $error'),
  );
}

/// Provider for current language (async single-record fetch).
@riverpod
Future<Language> currentLanguage(
  Ref ref,
  String languageId,
) async {
  final repository = ref.watch(shared_repo.languageRepositoryProvider);
  final result = await repository.getById(languageId);

  return result.when(
    ok: (language) => language,
    err: (error) => throw Exception('Failed to load language: $error'),
  );
}
