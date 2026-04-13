import 'package:riverpod_annotation/riverpod_annotation.dart';
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
