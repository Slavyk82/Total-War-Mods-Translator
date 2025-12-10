import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../translation_editor/screens/progress/progress_widgets.dart';
import '../providers/pack_compilation_providers.dart';
import 'compilation_editor_sections.dart';
import 'compilation_project_selection.dart';
import 'compilation_bbcode_section.dart';

/// Widget for creating/editing a compilation.
class CompilationEditor extends ConsumerWidget {
  const CompilationEditor({
    super.key,
    this.onCancel,
    required this.onSaved,
  });

  final VoidCallback? onCancel;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(compilationEditorProvider);
    final languagesAsync = ref.watch(allLanguagesProvider);
    final currentGameAsync = ref.watch(currentGameInstallationProvider);

    // When compiling, show simplified layout with progress and stop button
    if (state.isCompiling) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left panel - Progress, Stop button, and Logs
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CompilationProgressSection(
                  state: state,
                  onStop: () => ref
                      .read(compilationEditorProvider.notifier)
                      .cancelCompilation(),
                ),
                const SizedBox(height: 16),
                const Expanded(
                  child: LogTerminal(expand: true),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Right panel - Project selection (read-only view)
          Expanded(
            flex: 2,
            child: CompilationProjectSelectionSection(
              state: state,
              currentGameAsync: currentGameAsync,
              onToggle: (_) {}, // Disabled during compilation
              onSelectAll: (_) {},
              onDeselectAll: () {},
            ),
          ),
        ],
      );
    }

    // Normal editing mode
    final configAndProjectsRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left panel - Configuration
        Expanded(
          flex: 1,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CompilationConfigSection(
                  state: state,
                  languagesAsync: languagesAsync,
                  onNameChanged: (v) => ref
                      .read(compilationEditorProvider.notifier)
                      .updateName(v),
                  onPrefixChanged: (v) => ref
                      .read(compilationEditorProvider.notifier)
                      .updatePrefix(v),
                  onPackNameChanged: (v) => ref
                      .read(compilationEditorProvider.notifier)
                      .updatePackName(v),
                  onLanguageChanged: (v) => ref
                      .read(compilationEditorProvider.notifier)
                      .updateLanguage(v),
                ),
                const SizedBox(height: 24),
                CompilationActionSection(
                  state: state,
                  currentGameAsync: currentGameAsync,
                  onSave: (gameInstallationId) async {
                    final saved = await ref
                        .read(compilationEditorProvider.notifier)
                        .saveCompilation(gameInstallationId);
                    if (saved) {
                      ref.invalidate(compilationsWithDetailsProvider);
                    }
                  },
                  onGenerate: (gameInstallationId) async {
                    final success = await ref
                        .read(compilationEditorProvider.notifier)
                        .generatePack(gameInstallationId);
                    if (success) {
                      ref.invalidate(compilationsWithDetailsProvider);
                    }
                  },
                  onCancel: onCancel,
                ),
                const SizedBox(height: 24),
                const CompilationBBCodeSection(),
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        // Right panel - Project selection
        Expanded(
          flex: 2,
          child: CompilationProjectSelectionSection(
            state: state,
            currentGameAsync: currentGameAsync,
            onToggle: (id) => ref
                .read(compilationEditorProvider.notifier)
                .toggleProject(id),
            onSelectAll: (ids) => ref
                .read(compilationEditorProvider.notifier)
                .selectAllProjects(ids),
            onDeselectAll: () => ref
                .read(compilationEditorProvider.notifier)
                .deselectAllProjects(),
          ),
        ),
      ],
    );

    return configAndProjectsRow;
  }
}
