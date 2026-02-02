import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../models/domain/game_installation.dart';
import '../../../widgets/common/fluent_spinner.dart' hide FluentProgressBar;
import '../../../widgets/fluent/fluent_progress_indicator.dart';
import '../providers/compilation_conflict_providers.dart';
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
              Expanded(
                child: Text(
                  'Configuration',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
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
              isDisabled: state.isEditing,
            ),
            loading: () => const SizedBox(
              height: 40,
              child: Center(child: FluentSpinner(size: 20, strokeWidth: 2)),
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
              FluentSpinner(
                size: 24,
                strokeWidth: 2.5,
                color: theme.colorScheme.primary,
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
          FluentProgressBar(
            value: state.progress,
            height: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: theme.colorScheme.primary,
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
class CompilationActionSection extends ConsumerWidget {
  const CompilationActionSection({
    super.key,
    required this.state,
    required this.currentGameAsync,
    required this.onSave,
    required this.onGenerate,
    required this.onAnalyze,
    required this.onTogglePackImage,
    this.onCancel,
  });

  final CompilationEditorState state;
  final AsyncValue<GameInstallation?> currentGameAsync;
  final void Function(String gameInstallationId) onSave;
  final void Function(String gameInstallationId, {bool forceWithConflicts}) onGenerate;
  final VoidCallback onAnalyze;
  final VoidCallback onTogglePackImage;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final gameInstallation = currentGameAsync.asData?.value;
    final hasGame = gameInstallation != null;

    // Require at least 2 projects for all actions
    final hasEnoughProjects = state.selectedProjectIds.length >= 2;
    final hasLanguage = state.selectedLanguageId != null;

    final canSave = state.canSave && hasGame && hasEnoughProjects;
    final canAnalyze = hasEnoughProjects && hasLanguage && !state.isCompiling;

    // Check if there are real conflicts
    final hasRealConflicts = ref.watch(hasRealConflictsProvider);
    final isAnalyzing = ref.watch(isAnalyzingConflictsProvider);
    // Allow compilation even with conflicts (user can force)
    final canCompile = state.canCompile && hasGame && hasEnoughProjects && !isAnalyzing;

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

          // Not enough projects warning
          if (!hasEnoughProjects) ...[
            const CompilationMessageBox(
              message: 'Select at least 2 projects to create a compilation',
              isError: true,
            ),
            const SizedBox(height: 12),
          ],

          // Conflict warning (informative, not blocking)
          if (hasRealConflicts && !state.isCompiling) ...[
            const CompilationMessageBox(
              message: 'Conflicts detected. You can uncheck conflicting projects or force generation.',
              isError: false,
              isWarning: true,
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

          // Pack image generation option
          _PackImageCheckbox(
            value: state.generatePackImage,
            onChanged: state.isCompiling ? null : onTogglePackImage,
          ),
          const SizedBox(height: 16),

          // Analyze button (full width)
          SizedBox(
            width: double.infinity,
            child: CompilationActionButton(
              label: isAnalyzing ? 'Analyzing...' : 'Analyze Conflicts',
              icon: FluentIcons.scan_24_regular,
              onTap: canAnalyze && !isAnalyzing ? onAnalyze : null,
              isLoading: isAnalyzing,
            ),
          ),
          const SizedBox(height: 12),

          // Save and Generate buttons
          Row(
            children: [
              Expanded(
                child: CompilationActionButton(
                  label: 'Save',
                  icon: FluentIcons.save_24_regular,
                  onTap: canSave ? () => onSave(gameInstallation.id) : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CompilationActionButton(
                  label: state.isCompiling ? 'Generating...' : 'Generate Pack',
                  icon: FluentIcons.box_multiple_24_regular,
                  onTap: canCompile
                      ? () => _handleGenerate(context, gameInstallation.id, hasRealConflicts)
                      : null,
                  isPrimary: true,
                  isLoading: state.isCompiling,
                  hasWarning: hasRealConflicts,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleGenerate(
    BuildContext context,
    String gameInstallationId,
    bool hasConflicts,
  ) async {
    if (hasConflicts) {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _ConflictWarningDialog(),
      );

      if (confirmed == true) {
        onGenerate(gameInstallationId, forceWithConflicts: true);
      }
    } else {
      onGenerate(gameInstallationId, forceWithConflicts: false);
    }
  }
}

/// Dialog warning about generating with conflicts.
class _ConflictWarningDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(
        FluentIcons.warning_24_filled,
        color: Colors.orange,
        size: 48,
      ),
      title: const Text('Generate with Conflicts?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conflicts have been detected between your selected projects.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    FluentIcons.info_24_regular,
                    color: Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This may cause unexpected behavior in-game, such as missing or incorrect translations.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Do you want to continue anyway?',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange,
          ),
          child: const Text('Generate Anyway'),
        ),
      ],
    );
  }
}

/// Checkbox for pack image generation option
class _PackImageCheckbox extends StatelessWidget {
  const _PackImageCheckbox({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = onChanged != null;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onChanged,
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: value
                    ? (isEnabled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.primary.withValues(alpha: 0.5))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: value
                      ? (isEnabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.primary.withValues(alpha: 0.5))
                      : (isEnabled
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                          : theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                  width: 1.5,
                ),
              ),
              child: value
                  ? Icon(
                      FluentIcons.checkmark_12_filled,
                      size: 14,
                      color: isEnabled
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onPrimary.withValues(alpha: 0.7),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Generate pack image with language flag',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isEnabled
                      ? theme.textTheme.bodyMedium?.color
                      : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
                ),
              ),
            ),
            Icon(
              FluentIcons.image_24_regular,
              size: 18,
              color: isEnabled
                  ? theme.colorScheme.primary.withValues(alpha: 0.7)
                  : theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
