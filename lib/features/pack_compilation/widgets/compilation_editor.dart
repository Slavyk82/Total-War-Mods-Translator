import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/domain/game_installation.dart';
import '../../translation_editor/screens/progress/progress_widgets.dart';
import '../providers/pack_compilation_providers.dart';

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
                _CompilationProgressSection(
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
            child: _ProjectSelectionSection(
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
                _ConfigSection(
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
                const _BBCodeSection(),
                const SizedBox(height: 24),
                _ActionSection(
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
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        // Right panel - Project selection
        Expanded(
          flex: 2,
          child: _ProjectSelectionSection(
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

class _ConfigSection extends StatelessWidget {
  const _ConfigSection({
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
          _FieldLabel(label: 'Compilation Name'),
          const SizedBox(height: 4),
          _FluentTextField(
            value: state.name,
            onChanged: onNameChanged,
            hint: 'My French Translations...',
          ),
          const SizedBox(height: 16),

          // Language selection
          _FieldLabel(label: 'Language'),
          const SizedBox(height: 4),
          languagesAsync.when(
            data: (languages) => _LanguageDropdown(
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
          _FieldLabel(label: 'Prefix'),
          const SizedBox(height: 4),
          _FluentTextField(
            value: state.prefix,
            onChanged: onPrefixChanged,
            hint: '!!!!!!!!!!_FR_Compilation_',
          ),
          const SizedBox(height: 16),

          // Pack name
          _FieldLabel(label: 'Pack Name'),
          const SizedBox(height: 4),
          _FluentTextField(
            value: state.packName,
            onChanged: onPackNameChanged,
            hint: 'my_translations',
          ),
          const SizedBox(height: 16),

          // Preview
          const Divider(),
          const SizedBox(height: 12),
          _FieldLabel(label: 'Output Filename'),
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
class _CompilationProgressSection extends StatelessWidget {
  const _CompilationProgressSection({
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
          _SelectionSummary(count: state.selectedProjectIds.length),
          const SizedBox(height: 20),

          // Stop button
          SizedBox(
            width: double.infinity,
            child: _StopButton(
              onTap: state.isCancelled ? null : onStop,
              isCancelling: state.isCancelled,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stop button for cancelling compilation.
class _StopButton extends StatefulWidget {
  const _StopButton({
    required this.onTap,
    required this.isCancelling,
  });

  final VoidCallback? onTap;
  final bool isCancelling;

  @override
  State<_StopButton> createState() => _StopButtonState();
}

class _StopButtonState extends State<_StopButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onTap != null && !widget.isCancelling;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isEnabled
                ? (_isHovered
                    ? theme.colorScheme.error.withValues(alpha: 0.9)
                    : theme.colorScheme.error)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isCancelling) ...[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onError,
                  ),
                ),
              ] else ...[
                Icon(
                  FluentIcons.stop_24_regular,
                  size: 18,
                  color: isEnabled
                      ? theme.colorScheme.onError
                      : theme.textTheme.bodyMedium!.color!.withValues(alpha: 0.5),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                widget.isCancelling ? 'Cancelling...' : 'Stop Generation',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isEnabled
                      ? theme.colorScheme.onError
                      : theme.textTheme.bodyMedium!.color!.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({
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
            _MessageBox(
              message: 'Select a game in the sidebar to continue',
              isError: true,
            ),
            const SizedBox(height: 12),
          ],

          // Error/success messages
          if (state.errorMessage != null) ...[
            _MessageBox(
              message: state.errorMessage!,
              isError: true,
            ),
            const SizedBox(height: 12),
          ],
          if (state.successMessage != null) ...[
            _MessageBox(
              message: state.successMessage!,
              isError: false,
            ),
            const SizedBox(height: 12),
          ],

          // Progress
          if (state.isCompiling) ...[
            _ProgressIndicator(
              progress: state.progress,
              currentStep: state.currentStep,
            ),
            const SizedBox(height: 16),
          ],

          // Selection summary
          _SelectionSummary(count: state.selectedProjectIds.length),
          const SizedBox(height: 16),

          // Buttons
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Save',
                  icon: FluentIcons.save_24_regular,
                  onTap: canSave ? () => onSave(gameInstallation!.id) : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
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

class _ProjectSelectionSection extends ConsumerWidget {
  const _ProjectSelectionSection({
    required this.state,
    required this.currentGameAsync,
    required this.onToggle,
    required this.onSelectAll,
    required this.onDeselectAll,
  });

  final CompilationEditorState state;
  final AsyncValue<GameInstallation?> currentGameAsync;
  final void Function(String) onToggle;
  final void Function(List<String>) onSelectAll;
  final VoidCallback onDeselectAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gameInstallation = currentGameAsync.asData?.value;

    final projectsAsync = ref.watch(
      projectsWithTranslationProvider(ProjectFilterParams(
        gameInstallationId: gameInstallation?.id,
        languageId: state.selectedLanguageId,
      )),
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  FluentIcons.folder_24_regular,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Select Projects',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${state.selectedProjectIds.length} selected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                projectsAsync.whenData((projects) {
                  return Row(
                    children: [
                      _SmallButton(
                        label: 'Select All',
                        onTap: () =>
                            onSelectAll(projects.map((p) => p.id).toList()),
                      ),
                      const SizedBox(width: 8),
                      _SmallButton(
                        label: 'Deselect All',
                        onTap: onDeselectAll,
                      ),
                    ],
                  );
                }).value ?? const SizedBox.shrink(),
              ],
            ),
          ),
          const Divider(height: 1),
          // Project list
          Expanded(
            child: gameInstallation == null
                ? _buildSelectGameMessage(theme)
                : state.selectedLanguageId == null
                    ? _buildSelectLanguageMessage(theme)
                    : projectsAsync.when(
                        data: (projects) {
                        if (projects.isEmpty) {
                          return _buildNoProjectsMessage(theme);
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: projects.length,
                          itemBuilder: (context, index) {
                            final projectInfo = projects[index];
                            final isSelected =
                                state.selectedProjectIds.contains(projectInfo.id);
                            return _ProjectItem(
                              name: projectInfo.displayName,
                              imageUrl: projectInfo.imageUrl,
                              isSelected: isSelected,
                              onToggle: () => onToggle(projectInfo.id),
                              progressPercent: projectInfo.progressPercent,
                            );
                          },
                        );
                      },
                        loading: () => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        error: (error, _) => Center(
                          child: Text(
                            'Failed to load projects',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectGameMessage(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.games_24_regular,
            size: 48,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'Select a game in the sidebar first',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectLanguageMessage(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.translate_24_regular,
            size: 48,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'Select a language first',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoProjectsMessage(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.folder_24_regular,
            size: 48,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'No projects with translations in this language',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// Helper widgets

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
      ),
    );
  }
}

class _FluentTextField extends StatefulWidget {
  const _FluentTextField({
    required this.value,
    required this.onChanged,
    required this.hint,
  });

  final String value;
  final void Function(String) onChanged;
  final String hint;

  @override
  State<_FluentTextField> createState() => _FluentTextFieldState();
}

class _FluentTextFieldState extends State<_FluentTextField> {
  late TextEditingController _controller;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_FluentTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Focus(
      onFocusChange: (hasFocus) => setState(() => _isFocused = hasFocus),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _isFocused
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.5),
            width: _isFocused ? 2 : 1,
          ),
        ),
        child: TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({
    required this.languages,
    required this.selectedId,
    required this.onChanged,
  });

  final List languages;
  final String? selectedId;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedId,
          isExpanded: true,
          hint: Text(
            'Select a language...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
            ),
          ),
          items: languages.map<DropdownMenuItem<String>>((lang) {
            return DropdownMenuItem(
              value: lang.id,
              child: Text(lang.displayName),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError ? theme.colorScheme.error : Colors.green;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isError
                ? FluentIcons.error_circle_24_regular
                : FluentIcons.checkmark_circle_24_regular,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressIndicator extends StatelessWidget {
  const _ProgressIndicator({
    required this.progress,
    this.currentStep,
  });

  final double progress;
  final String? currentStep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor:
                      AlwaysStoppedAnimation(theme.colorScheme.primary),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${(progress * 100).toInt()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        if (currentStep != null) ...[
          const SizedBox(height: 8),
          Text(
            currentStep!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }
}

class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = count == 0
        ? 'No projects selected'
        : count == 1
            ? '1 project selected'
            : '$count projects selected';

    return Row(
      children: [
        Icon(
          count > 0
              ? FluentIcons.checkbox_checked_24_regular
              : FluentIcons.checkbox_unchecked_24_regular,
          size: 20,
          color: count > 0
              ? theme.colorScheme.primary
              : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: count > 0
                ? theme.textTheme.bodyMedium?.color
                : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.isPrimary = false,
    this.isLoading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isPrimary;
  final bool isLoading;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onTap != null && !widget.isLoading;

    Color backgroundColor;
    Color contentColor;

    if (widget.isPrimary) {
      backgroundColor = isEnabled
          ? (_isHovered
              ? theme.colorScheme.primary.withValues(alpha: 0.9)
              : theme.colorScheme.primary)
          : theme.colorScheme.surfaceContainerHighest;
      contentColor = isEnabled
          ? theme.colorScheme.onPrimary
          : theme.textTheme.bodyMedium!.color!.withValues(alpha: 0.5);
    } else {
      backgroundColor = _isHovered
          ? theme.colorScheme.surfaceContainerHighest
          : Colors.transparent;
      contentColor = isEnabled
          ? theme.colorScheme.onSurface
          : theme.textTheme.bodyMedium!.color!.withValues(alpha: 0.5);
    }

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6),
            border: widget.isPrimary
                ? null
                : Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isLoading) ...[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: contentColor,
                  ),
                ),
              ] else ...[
                Icon(widget.icon, size: 18, color: contentColor),
              ],
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: contentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatefulWidget {
  const _SmallButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<_SmallButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _isHovered
                ? theme.colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            widget.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectItem extends StatefulWidget {
  const _ProjectItem({
    required this.name,
    required this.isSelected,
    required this.onToggle,
    this.imageUrl,
    this.progressPercent = 0.0,
  });

  final String name;
  final String? imageUrl;
  final bool isSelected;
  final VoidCallback onToggle;
  final double progressPercent;

  @override
  State<_ProjectItem> createState() => _ProjectItemState();
}

class _ProjectItemState extends State<_ProjectItem> {
  bool _isHovered = false;

  Color _getProgressColor(ThemeData theme, double progress) {
    if (progress >= 100) {
      return Colors.green;
    } else if (progress >= 50) {
      return theme.colorScheme.primary;
    } else if (progress > 0) {
      return Colors.orange;
    } else {
      return theme.colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressPercent = widget.progressPercent.clamp(0.0, 100.0);

    Color backgroundColor;
    if (widget.isSelected) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.1);
    } else if (_isHovered) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.05);
    } else {
      backgroundColor = Colors.transparent;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              // Checkbox
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: widget.isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    width: 2,
                  ),
                ),
                child: widget.isSelected
                    ? Icon(
                        FluentIcons.checkmark_16_regular,
                        size: 14,
                        color: theme.colorScheme.onPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              // Mod image
              _ModImage(imageUrl: widget.imageUrl),
              const SizedBox(width: 12),
              // Project name and progress
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Progress bar
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: SizedBox(
                              height: 4,
                              child: LinearProgressIndicator(
                                value: progressPercent / 100,
                                backgroundColor: theme
                                    .colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _getProgressColor(theme, progressPercent),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${progressPercent.toInt()}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: _getProgressColor(theme, progressPercent),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mod image widget for the project list (75x75)
class _ModImage extends StatelessWidget {
  final String? imageUrl;

  const _ModImage({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return Container(
        width: 75,
        height: 75,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          FluentIcons.image_off_24_regular,
          size: 24,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    // Check if it's a local file path or a URL
    final isLocalFile =
        !imageUrl!.startsWith('http://') && !imageUrl!.startsWith('https://');

    if (isLocalFile) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(imageUrl!),
          width: 75,
          height: 75,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 75,
            height: 75,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              FluentIcons.image_alt_text_24_regular,
              size: 24,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        width: 75,
        height: 75,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: 75,
          height: 75,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: 75,
          height: 75,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            FluentIcons.image_alt_text_24_regular,
            size: 24,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Section displaying BBCode links for Steam Workshop publication.
class _BBCodeSection extends ConsumerStatefulWidget {
  const _BBCodeSection();

  @override
  ConsumerState<_BBCodeSection> createState() => _BBCodeSectionState();
}

class _BBCodeSectionState extends ConsumerState<_BBCodeSection> {
  bool _copied = false;

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bbCodeAsync = ref.watch(compilationBBCodeProvider);
    final state = ref.watch(compilationEditorProvider);

    // Don't show if no projects selected
    if (state.selectedProjectIds.isEmpty) {
      return const SizedBox.shrink();
    }

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
                FluentIcons.link_24_regular,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Steam Workshop BBCode',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              bbCodeAsync.when(
                data: (bbCode) {
                  if (bbCode.isEmpty) return const SizedBox.shrink();
                  return _CopyButton(
                    onTap: () => _copyToClipboard(bbCode),
                    isCopied: _copied,
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Copy this BBCode to use in your Steam Workshop description:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          bbCodeAsync.when(
            data: (bbCode) {
              if (bbCode.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Text(
                    'No mods with Steam Workshop IDs selected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color
                          ?.withValues(alpha: 0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                );
              }
              return Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    bbCode,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              );
            },
            loading: () => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: theme.dividerColor),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (error, _) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
                border:
                    Border.all(color: theme.colorScheme.error.withValues(alpha: 0.5)),
              ),
              child: Text(
                'Error generating BBCode',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Copy button with hover state and feedback.
class _CopyButton extends StatefulWidget {
  const _CopyButton({
    required this.onTap,
    required this.isCopied,
  });

  final VoidCallback onTap;
  final bool isCopied;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isCopied
                ? Colors.green.withValues(alpha: 0.1)
                : _isHovered
                    ? theme.colorScheme.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: widget.isCopied
                  ? Colors.green.withValues(alpha: 0.5)
                  : theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isCopied
                    ? FluentIcons.checkmark_16_regular
                    : FluentIcons.copy_16_regular,
                size: 16,
                color: widget.isCopied ? Colors.green : theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                widget.isCopied ? 'Copied!' : 'Copy',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      widget.isCopied ? Colors.green : theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
