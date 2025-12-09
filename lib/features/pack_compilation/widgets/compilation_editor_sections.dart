import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../models/domain/game_installation.dart';
import '../providers/pack_compilation_providers.dart';
import 'compilation_editor_form_widgets.dart';

/// Configuration section for compilation settings.
class CompilationConfigSection extends StatelessWidget {
  const CompilationConfigSection({
    super.key,
    required this.state,
    required this.languagesAsync,
    required this.onNameChanged,
    required this.onPrefixChanged,
    required this.onPackNameChanged,
    required this.onLanguageChanged,
  });

  final CompilationEditorState state;
  final AsyncValue languagesAsync;
  final void Function(String) onNameChanged;
  final void Function(String) onPrefixChanged;
  final void Function(String) onPackNameChanged;
  final void Function(String?) onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.settings_24_regular,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Configuration',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Name
          const CompilationFieldLabel(label: 'Compilation Name'),
          const SizedBox(height: 4),
          CompilationTextField(
            value: state.name,
            onChanged: onNameChanged,
            hint: 'My French Translations...',
          ),
          const SizedBox(height: 16),

          // Language selection
          const CompilationFieldLabel(label: 'Language'),
          const SizedBox(height: 4),
          languagesAsync.when(
            data: (languages) => CompilationLanguageDropdown(
              languages: languages,
              selectedId: state.selectedLanguageId,
              onChanged: onLanguageChanged,
            ),
            loading: () => const SizedBox(
              height: 40,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (error, stack) => Text(
              'Failed to load languages',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          const SizedBox(height: 16),

          // Prefix
          const CompilationFieldLabel(label: 'Prefix'),
          const SizedBox(height: 4),
          CompilationTextField(
            value: state.prefix,
            onChanged: onPrefixChanged,
            hint: '!!!!!!!!!!_FR_Compilation_',
          ),
          const SizedBox(height: 16),

          // Pack name
          const CompilationFieldLabel(label: 'Pack Name'),
          const SizedBox(height: 4),
          CompilationTextField(
            value: state.packName,
            onChanged: onPackNameChanged,
            hint: 'my_translations',
          ),
          const SizedBox(height: 16),

          // Preview
          const Divider(),
          const SizedBox(height: 12),
          const CompilationFieldLabel(label: 'Output Filename'),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.box_24_filled,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.fullPackName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Section displayed during compilation with progress and stop button.
class CompilationProgressSection extends StatelessWidget {
  const CompilationProgressSection({
    super.key,
    required this.state,
    required this.onStop,
  });

  final CompilationEditorState state;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Generating Pack...',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),
          ),
          const SizedBox(height: 12),

          // Progress info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  state.currentStep ?? 'Processing...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${(state.progress * 100).toInt()}%',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Selection summary
          CompilationSelectionSummary(count: state.selectedProjectIds.length),
          const SizedBox(height: 20),

          // Stop button
          SizedBox(
            width: double.infinity,
            child: CompilationStopButton(
              onTap: state.isCancelled ? null : onStop,
              isCancelling: state.isCancelled,
            ),
          ),
        ],
      ),
    );
  }
}

/// Action section with save and generate buttons.
class CompilationActionSection extends StatelessWidget {
  const CompilationActionSection({
    super.key,
    required this.state,
    required this.currentGameAsync,
    required this.onSave,
    required this.onGenerate,
    this.onCancel,
  });

  final CompilationEditorState state;
  final AsyncValue<GameInstallation?> currentGameAsync;
  final void Function(String gameInstallationId) onSave;
  final void Function(String gameInstallationId) onGenerate;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final gameInstallation = currentGameAsync.asData?.value;
    final hasGame = gameInstallation != null;
    final canSave = state.canSave && hasGame;
    final canCompile = state.canCompile && hasGame;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // No game selected warning
          if (!hasGame) ...[
            const CompilationMessageBox(
              message: 'Select a game in the sidebar to continue',
              isError: true,
            ),
            const SizedBox(height: 12),
          ],

          // Error/success messages
          if (state.errorMessage != null) ...[
            CompilationMessageBox(
              message: state.errorMessage!,
              isError: true,
            ),
            const SizedBox(height: 12),
          ],
          if (state.successMessage != null) ...[
            CompilationMessageBox(
              message: state.successMessage!,
              isError: false,
            ),
            const SizedBox(height: 12),
          ],

          // Progress
          if (state.isCompiling) ...[
            CompilationProgressIndicator(
              progress: state.progress,
              currentStep: state.currentStep,
            ),
            const SizedBox(height: 16),
          ],

          // Selection summary
          CompilationSelectionSummary(count: state.selectedProjectIds.length),
          const SizedBox(height: 16),

          // Buttons
          Row(
            children: [
              Expanded(
                child: CompilationActionButton(
                  label: 'Save',
                  icon: FluentIcons.save_24_regular,
                  onTap: canSave ? () => onSave(gameInstallation!.id) : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CompilationActionButton(
                  label: state.isCompiling ? 'Generating...' : 'Generate Pack',
                  icon: FluentIcons.box_multiple_24_regular,
                  onTap:
                      canCompile ? () => onGenerate(gameInstallation!.id) : null,
                  isPrimary: true,
                  isLoading: state.isCompiling,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
