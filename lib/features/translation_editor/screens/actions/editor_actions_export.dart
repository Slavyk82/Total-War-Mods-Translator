import 'package:flutter/material.dart';
import '../../providers/editor_providers.dart';
import '../../widgets/editor_dialogs.dart';
import '../export_progress_screen.dart';
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

      if (!context.mounted) return;

      // Navigate to export progress screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ExportProgressScreen(
            exportService: exportService,
            projectId: projectId,
            languageCodes: languageCodes,
            onComplete: (result) {
              if (result != null) {
                ref.read(loggingServiceProvider).info(
                  'Pack generation completed',
                  {'format': 'pack', 'languageCodes': languageCodes},
                );
              }
            },
          ),
        ),
      );
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to generate pack',
        e,
        stackTrace,
      );
      if (!context.mounted) return;
      EditorDialogs.showErrorDialog(context, 'Pack generation failed', e.toString());
    }
  }
}
