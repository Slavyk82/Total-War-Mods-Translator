import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/providers/shared/service_providers.dart' as shared_svc;
import 'package:twmt/providers/shared/logging_providers.dart';

part 'llm_model_providers.g.dart';

/// Provider for available LLM models (enabled, non-archived)
/// Returns all enabled models across all providers
@riverpod
Future<List<LlmProviderModel>> availableLlmModels(Ref ref) async {
  final repository = ref.watch(shared_svc.llmProviderModelRepositoryProvider);

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

/// Provider for the currently selected LLM model ID.
///
/// The selection is persisted across app restarts via [SettingsService] under
/// [SettingsKeys.editorSelectedLlmModelId]. The in-memory state is hydrated
/// asynchronously on [build]; until the load resolves, callers see `null`
/// and the toolbar pre-fills a sensible default via [seedDefaultIfEmpty]
/// without touching persistent storage. User-driven [setModel] / [clear]
/// calls write through to the settings service.
///
/// keepAlive prevents the state from being disposed when there are no
/// listeners.
@Riverpod(keepAlive: true)
class SelectedLlmModel extends _$SelectedLlmModel {
  @override
  String? build() {
    unawaited(_loadPersisted());
    return null;
  }

  Future<void> _loadPersisted() async {
    try {
      final service = ref.read(shared_svc.settingsServiceProvider);
      final stored = await service.getString(
        SettingsKeys.editorSelectedLlmModelId,
      );
      // Only restore the persisted value if no other code path has
      // already populated state — protects against a race with the
      // toolbar's seed/set calls firing while the load is in flight.
      if (stored.isNotEmpty && state == null) {
        state = stored;
      }
    } catch (_) {
      // Settings service may be unavailable in tests; the editor still
      // works with the in-memory default.
    }
  }

  /// Set the selected model ID and persist it.
  void setModel(String? modelId) {
    state = modelId;
    unawaited(_persist(modelId));
  }

  /// Pre-fill the in-memory state with a sensible default without writing
  /// to persistent storage. Call only when the user has not yet made a
  /// choice — it never overwrites an existing selection.
  void seedDefaultIfEmpty(String modelId) {
    if (state == null) {
      state = modelId;
    }
  }

  /// Clear the selection (will use default) and remove it from storage.
  void clear() {
    state = null;
    unawaited(_persist(null));
  }

  Future<void> _persist(String? modelId) async {
    try {
      final service = ref.read(shared_svc.settingsServiceProvider);
      // The settings service has no remove(); an empty string is treated
      // as "unset" by the load path (`stored.isNotEmpty` check).
      await service.setString(
        SettingsKeys.editorSelectedLlmModelId,
        modelId ?? '',
      );
    } catch (_) {
      // Best-effort persistence; ignore failures (e.g. missing service in
      // tests). The in-memory state still reflects the user's choice.
    }
  }
}
