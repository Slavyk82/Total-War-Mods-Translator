import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../translation_editor/screens/progress/progress_widgets.dart';
import '../providers/compilation_conflict_providers.dart';
import '../providers/pack_compilation_providers.dart';
import 'compilation_editor_sections.dart';
import 'compilation_project_selection.dart';
import 'compilation_bbcode_section.dart';
import 'conflicting_projects_panel.dart';

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

    // Show conflict panel when 2+ projects selected and language is set
    final showConflictPanel = state.selectedProjectIds.length >= 2 &&
        state.selectedLanguageId != null;

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
                  onAnalyze: () async {
                    if (state.selectedProjectIds.length >= 2 &&
                        state.selectedLanguageId != null) {
                      // Clear previous resolutions
                      ref
                          .read(compilationConflictResolutionsStateProvider
                              .notifier)
                          .clear();

                      // Run analysis
                      await ref
                          .read(compilationConflictAnalysisProvider.notifier)
                          .analyze(
                            projectIds: state.selectedProjectIds.toList(),
                            languageId: state.selectedLanguageId!,
                          );
                    }
                  },
                  onGenerate: (gameInstallationId, {bool forceWithConflicts = false}) async {
                    // Run conflict analysis first (unless forcing)
                    if (!forceWithConflicts &&
                        state.selectedProjectIds.length >= 2 &&
                        state.selectedLanguageId != null) {
                      // Clear previous resolutions
                      ref
                          .read(compilationConflictResolutionsStateProvider
                              .notifier)
                          .clear();

                      // Run analysis
                      await ref
                          .read(compilationConflictAnalysisProvider.notifier)
                          .analyze(
                            projectIds: state.selectedProjectIds.toList(),
                            languageId: state.selectedLanguageId!,
                          );

                      // Check if there are real conflicts
                      final hasConflicts =
                          ref.read(hasRealConflictsProvider);
                      if (hasConflicts) {
                        // Don't generate - conflicts panel will show
                        return;
                      }
                    }

                    // Proceed with generation
                    final success = await ref
                        .read(compilationEditorProvider.notifier)
                        .generatePack(gameInstallationId);
                    if (success) {
                      ref.invalidate(compilationsWithDetailsProvider);
                    }
                  },
                  onTogglePackImage: () => ref
                      .read(compilationEditorProvider.notifier)
                      .toggleGeneratePackImage(),
                  onCancel: onCancel,
                ),
                const SizedBox(height: 24),
                const CompilationBBCodeSection(),
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        // Center panel - Project selection
        Expanded(
          flex: showConflictPanel ? 2 : 2,
          child: CompilationProjectSelectionSection(
            state: state,
            currentGameAsync: currentGameAsync,
            onToggle: (id) async {
              final wasSelected = state.selectedProjectIds.contains(id);
              ref.read(compilationEditorProvider.notifier).toggleProject(id);

              // If adding a project and will have 2+ projects, run analysis
              if (!wasSelected && state.selectedLanguageId != null) {
                final newCount = state.selectedProjectIds.length + 1;
                if (newCount >= 2) {
                  // Small delay to let state update
                  await Future.delayed(const Duration(milliseconds: 100));
                  final currentState = ref.read(compilationEditorProvider);
                  if (currentState.selectedProjectIds.length >= 2) {
                    ref
                        .read(compilationConflictResolutionsStateProvider
                            .notifier)
                        .clear();
                    await ref
                        .read(compilationConflictAnalysisProvider.notifier)
                        .analyze(
                          projectIds: currentState.selectedProjectIds.toList(),
                          languageId: currentState.selectedLanguageId!,
                        );
                  }
                }
              }
            },
            onSelectAll: (ids) async {
              ref.read(compilationEditorProvider.notifier).selectAllProjects(ids);

              // Run analysis if 2+ projects and language set
              if (state.selectedLanguageId != null && ids.length >= 2) {
                await Future.delayed(const Duration(milliseconds: 100));
                final currentState = ref.read(compilationEditorProvider);
                if (currentState.selectedProjectIds.length >= 2) {
                  ref
                      .read(compilationConflictResolutionsStateProvider.notifier)
                      .clear();
                  await ref
                      .read(compilationConflictAnalysisProvider.notifier)
                      .analyze(
                        projectIds: currentState.selectedProjectIds.toList(),
                        languageId: currentState.selectedLanguageId!,
                      );
                }
              }
            },
            onDeselectAll: () {
              ref.read(compilationEditorProvider.notifier).deselectAllProjects();
              // Clear analysis when all deselected
              ref.read(compilationConflictAnalysisProvider.notifier).clear();
            },
          ),
        ),
        // Right panel - Conflicting projects (only when applicable)
        if (showConflictPanel) ...[
          const SizedBox(width: 24),
          Expanded(
            flex: 1,
            child: ConflictingProjectsPanel(
              selectedProjectIds: state.selectedProjectIds,
              onToggleProject: (id) {
                ref.read(compilationEditorProvider.notifier).toggleProject(id);
                // Re-run analysis after removing a conflicting project
                Future.delayed(const Duration(milliseconds: 100), () async {
                  final currentState = ref.read(compilationEditorProvider);
                  if (currentState.selectedProjectIds.length >= 2 &&
                      currentState.selectedLanguageId != null) {
                    ref
                        .read(compilationConflictResolutionsStateProvider
                            .notifier)
                        .clear();
                    await ref
                        .read(compilationConflictAnalysisProvider.notifier)
                        .analyze(
                          projectIds: currentState.selectedProjectIds.toList(),
                          languageId: currentState.selectedLanguageId!,
                        );
                  } else {
                    ref.read(compilationConflictAnalysisProvider.notifier).clear();
                  }
                });
              },
            ),
          ),
        ],
      ],
    );

    return configAndProjectsRow;
  }
}
