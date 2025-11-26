import '../../../../models/domain/translation_version.dart';
import '../../../../services/history/undo_redo_manager.dart';
import '../../providers/editor_providers.dart';
import '../../widgets/editor_dialogs.dart';
import 'editor_actions_base.dart';

/// Mixin handling cell editing operations
mixin EditorActionsCellEdit on EditorActionsBase {
  Future<void> handleCellEdit(String unitId, String newText) async {
    try {
      final versionRepo = ref.read(translationVersionRepositoryProvider);
      final unitRepo = ref.read(translationUnitRepositoryProvider);
      final undoRedoManager = ref.read(undoRedoManagerProvider);

      // Get current version and unit
      final versionsResult = await versionRepo.getByUnit(unitId);
      if (versionsResult.isErr) {
        throw Exception('Failed to get translation version');
      }

      final versions = versionsResult.unwrap();
      if (versions.isEmpty) {
        throw Exception('No translation version found for unit');
      }

      final currentVersion = versions.first;
      final oldText = currentVersion.translatedText ?? '';

      // Don't update if text hasn't changed
      if (oldText == newText) return;

      final unitResult = await unitRepo.getById(unitId);
      if (unitResult.isErr) {
        throw Exception('Failed to get translation unit');
      }

      final unit = unitResult.unwrap();

      // Update version with new text
      final updatedVersion = currentVersion.copyWith(
        translatedText: newText,
        isManuallyEdited: true,
        status: newText.isEmpty
            ? TranslationVersionStatus.pending
            : TranslationVersionStatus.translated,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final updateResult = await versionRepo.update(updatedVersion);
      if (updateResult.isErr) {
        throw Exception('Failed to update translation version');
      }

      // Record undo action
      final historyAction = TranslationEditAction(
        versionId: currentVersion.id,
        oldValue: oldText,
        newValue: newText,
        timestamp: DateTime.now(),
        repository: versionRepo,
      );
      undoRedoManager.recordAction(historyAction);
      refreshProviders();

      // Update TM with new translation (if not empty)
      if (newText.isNotEmpty) {
        await _updateTranslationMemory(
          unit.sourceText,
          newText,
        );
      }

      refreshProviders();
      _logCellEdit(unitId, newText);
    } catch (e, stackTrace) {
      _handleCellEditError(e, stackTrace, 'Failed to update translation');
    }
  }

  Future<void> handleApplySuggestion(String unitId, String targetText, double qualityScore, bool isExactMatch) async {
    try {
      final versionRepo = ref.read(translationVersionRepositoryProvider);
      final unitRepo = ref.read(translationUnitRepositoryProvider);
      final undoRedoManager = ref.read(undoRedoManagerProvider);

      // Get current version and unit
      final versionsResult = await versionRepo.getByUnit(unitId);
      if (versionsResult.isErr) {
        throw Exception('Failed to get translation version');
      }

      final versions = versionsResult.unwrap();
      if (versions.isEmpty) {
        throw Exception('No translation version found for unit');
      }

      final currentVersion = versions.first;
      final oldText = currentVersion.translatedText ?? '';

      // Don't update if text hasn't changed
      if (oldText == targetText) return;

      final unitResult = await unitRepo.getById(unitId);
      if (unitResult.isErr) {
        throw Exception('Failed to get translation unit');
      }

      final unit = unitResult.unwrap();

      // Determine translation source
      final translationSource = isExactMatch
          ? TranslationSource.tmExact
          : TranslationSource.tmFuzzy;

      // Update version with suggested text (mark as TM-sourced, not manually edited)
      // Use the TM quality score as confidence score
      final updatedVersion = currentVersion.copyWith(
        translatedText: targetText,
        isManuallyEdited: false,
        status: TranslationVersionStatus.translated,
        confidenceScore: qualityScore,
        translationSource: translationSource,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final updateResult = await versionRepo.update(updatedVersion);
      if (updateResult.isErr) {
        throw Exception('Failed to update translation version');
      }

      // Record undo action
      final historyAction = TranslationEditAction(
        versionId: currentVersion.id,
        oldValue: oldText,
        newValue: targetText,
        timestamp: DateTime.now(),
        repository: versionRepo,
      );
      undoRedoManager.recordAction(historyAction);
      refreshProviders();

      // Increment TM usage count
      await _incrementTmUsageCount(unit.sourceText);

      refreshProviders();
      _logSuggestionApplied(unitId, targetText);
    } catch (e, stackTrace) {
      _handleCellEditError(e, stackTrace, 'Failed to apply TM suggestion');
    }
  }

  Future<void> _updateTranslationMemory(
    String sourceText,
    String targetText,
  ) async {
    final projectLanguageId = await getProjectLanguageId();
    final projectLanguageRepo = ref.read(projectLanguageRepositoryProvider);
    final plResult = await projectLanguageRepo.getById(projectLanguageId);

    if (plResult.isOk) {
      final projectLanguage = plResult.unwrap();
      final languageRepo = ref.read(languageRepositoryProvider);
      final langResult = await languageRepo.getById(projectLanguage.languageId);

      if (langResult.isOk) {
        final language = langResult.unwrap();
        final tmService = ref.read(translationMemoryServiceProvider);
        await tmService.addTranslation(
          sourceText: sourceText,
          targetText: targetText,
          targetLanguageCode: language.code,
        );
      }
    }
  }

  Future<void> _incrementTmUsageCount(
    String sourceText,
  ) async {
    final projectLanguageId = await getProjectLanguageId();
    final projectLanguageRepo = ref.read(projectLanguageRepositoryProvider);
    final plResult = await projectLanguageRepo.getById(projectLanguageId);

    if (plResult.isOk) {
      final projectLanguage = plResult.unwrap();
      final languageRepo = ref.read(languageRepositoryProvider);
      final langResult = await languageRepo.getById(projectLanguage.languageId);

      if (langResult.isOk) {
        final language = langResult.unwrap();
        final tmService = ref.read(translationMemoryServiceProvider);

        final matchResult = await tmService.findExactMatch(
          sourceText: sourceText,
          targetLanguageCode: language.code,
        );

        if (matchResult.isOk) {
          final match = matchResult.unwrap();
          if (match != null) {
            await tmService.incrementUsageCount(entryId: match.entryId);
          }
        }
      }
    }
  }

  void _logCellEdit(String unitId, String newText) {
    ref.read(loggingServiceProvider).info(
      'Translation updated',
      {
        'unitId': unitId,
        'newText': newText.substring(0, newText.length > 50 ? 50 : newText.length)
      },
    );
  }

  void _logSuggestionApplied(String unitId, String targetText) {
    ref.read(loggingServiceProvider).info(
      'TM suggestion applied',
      {
        'unitId': unitId,
        'targetText': targetText.substring(
            0, targetText.length > 50 ? 50 : targetText.length)
      },
    );
  }

  void _handleCellEditError(Object e, StackTrace stackTrace, String title) {
    ref.read(loggingServiceProvider).error(title, e, stackTrace);
    if (mounted) {
      EditorDialogs.showErrorDialog(context, title, e.toString());
    }
  }
}
