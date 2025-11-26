import '../../providers/editor_providers.dart';
import '../../widgets/editor_dialogs.dart';
import 'editor_actions_base.dart';

/// Mixin handling export operations
mixin EditorActionsExport on EditorActionsBase {
  Future<void> handleExport() async {
    try {
      final projectLanguageId = await getProjectLanguageId();
      final exportService = ref.read(exportOrchestratorServiceProvider);
      final languageRepo = ref.read(languageRepositoryProvider);
      final projectLanguageRepo = ref.read(projectLanguageRepositoryProvider);

      final plResult = await projectLanguageRepo.getById(projectLanguageId);
      if (plResult.isErr) {
        throw Exception('Failed to load project language');
      }

      final projectLanguage = plResult.unwrap();
      final langResult = await languageRepo.getById(projectLanguage.languageId);
      if (langResult.isErr) {
        throw Exception('Failed to load language');
      }

      final language = langResult.unwrap();
      final languageCodes = [language.code];
      final outputPath = 'exports';

      if (!mounted) return;

      final result = await exportService.exportToPack(
        projectId: projectId,
        languageCodes: languageCodes,
        outputPath: outputPath,
        validatedOnly: false,
        onProgress: (step, progress, {currentLanguage, currentIndex, total}) {},
      );

      result.when(
        ok: (exportResult) {
          if (mounted) {
            EditorDialogs.showInfoDialog(
              context,
              'Export Complete',
              'Exported ${exportResult.entryCount} translations to:\n${exportResult.outputPath}',
            );
          }
        },
        err: (error) => throw Exception(error.message),
      );

      ref.read(loggingServiceProvider).info(
        'Export completed',
        {'format': 'pack', 'languageCodes': languageCodes},
      );
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to export translations',
        e,
        stackTrace,
      );
      if (mounted) {
        EditorDialogs.showErrorDialog(context, 'Export failed', e.toString());
      }
    }
  }
}
