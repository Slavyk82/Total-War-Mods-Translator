import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/domain/glossary_entry.dart';
import '../../../providers/shared/logging_providers.dart';
import '../../../services/glossary/models/glossary_term_with_variants.dart';
import '../../../services/translation/models/translation_context.dart';
import '../../../providers/shared/repository_providers.dart' as shared_repo;
import '../../../providers/shared/service_providers.dart' as shared_svc;
import '../../settings/providers/settings_providers.dart';
import '../providers/editor_providers.dart';

/// Builds a [TranslationContext] for prompt preview in the translation editor.
///
/// Chooses provider/model from the toolbar's [selectedLlmModelProvider] first,
/// and falls back to settings if no model is selected.
class TranslationContextBuilder {
  /// Build a translation context for prompt preview.
  ///
  /// Returns null if required data (project language, target language) cannot
  /// be resolved, or if any unexpected error occurs.
  static Future<TranslationContext?> build(
    WidgetRef ref,
    String projectId,
    String languageId,
  ) async {
    try {
      final projectLanguageRepo = ref.read(shared_repo.projectLanguageRepositoryProvider);
      final glossaryRepo = ref.read(shared_repo.glossaryRepositoryProvider);

      // Get LLM provider from the toolbar's model selector dropdown
      String providerCode;
      String? modelId;

      final selectedModelId = ref.read(selectedLlmModelProvider);
      if (selectedModelId != null) {
        final modelRepo = ref.read(shared_svc.llmProviderModelRepositoryProvider);
        final modelResult = await modelRepo.getById(selectedModelId);
        if (modelResult.isOk) {
          final model = modelResult.unwrap();
          providerCode = model.providerCode;
          modelId = model.modelId;
        } else {
          // Fallback to settings if model not found
          final llmSettings = await ref.read(llmProviderSettingsProvider.future);
          providerCode = llmSettings[SettingsKeys.activeProvider] ?? 'openai';
        }
      } else {
        // Fallback to settings if no model selected
        final llmSettings = await ref.read(llmProviderSettingsProvider.future);
        providerCode = llmSettings[SettingsKeys.activeProvider] ?? 'openai';
      }

      // Get project language
      final projectLanguagesResult =
          await projectLanguageRepo.getByProject(projectId);
      if (projectLanguagesResult.isErr) return null;

      final projectLanguages = projectLanguagesResult.unwrap();
      final projectLanguage = projectLanguages.firstWhere(
        (pl) => pl.languageId == languageId,
        orElse: () => throw Exception('Project language not found'),
      );

      // Get target language
      final langRepo = ref.read(shared_repo.languageRepositoryProvider);
      final langResult = await langRepo.getById(languageId);
      if (langResult.isErr) return null;
      final language = langResult.unwrap();

      // Load glossary entries for this project (global + game-installation
      // scoped), filtered to the target language.
      List<GlossaryTermWithVariants>? glossaryEntries;
      final entriesResult = await glossaryRepo.getByProjectAndLanguage(
        projectId: projectId,
        targetLanguageCode: language.code,
      );
      if (entriesResult.isOk) {
        final entries = entriesResult.unwrap();
        // Group entries by source term for variant support
        glossaryEntries = _groupEntriesBySourceTerm(entries, language.code);
      }

      return TranslationContext(
        id: 'preview-${DateTime.now().millisecondsSinceEpoch}',
        projectId: projectId,
        projectLanguageId: projectLanguage.id,
        providerId: providerCode,
        modelId: modelId,
        targetLanguage: language.code,
        glossaryEntries: glossaryEntries,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to build translation context for prompt preview',
        e,
        stackTrace,
      );
      return null;
    }
  }
}

/// Group glossary entries by source term for variant support.
///
/// Case-insensitive grouping; filters to target-language entries only.
List<GlossaryTermWithVariants> _groupEntriesBySourceTerm(
  List<GlossaryEntry> entries,
  String targetLanguageCode,
) {
  // Filter to target language entries only
  final targetEntries = entries
      .where((e) => e.targetLanguageCode == targetLanguageCode)
      .toList();

  // Group by source term (case-insensitive)
  final grouped = <String, List<GlossaryEntry>>{};
  for (final entry in targetEntries) {
    final key = entry.sourceTerm.toLowerCase();
    grouped.putIfAbsent(key, () => []).add(entry);
  }

  // Convert to GlossaryTermWithVariants
  return grouped.entries.map((entry) {
    final first = entry.value.first;
    return GlossaryTermWithVariants(
      sourceTerm: first.sourceTerm,
      caseSensitive: first.caseSensitive,
      variants: entry.value
          .map((e) => GlossaryVariant(
                entryId: e.id,
                targetTerm: e.targetTerm,
                notes: e.notes,
              ))
          .toList(),
    );
  }).toList();
}
