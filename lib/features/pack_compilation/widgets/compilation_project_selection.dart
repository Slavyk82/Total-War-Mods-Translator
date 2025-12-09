import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/domain/game_installation.dart';
import '../providers/pack_compilation_providers.dart';
import 'compilation_editor_form_widgets.dart';

/// Section for selecting projects to include in compilation.
class CompilationProjectSelectionSection extends ConsumerWidget {
  const CompilationProjectSelectionSection({
    super.key,
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
                      CompilationSmallButton(
                        label: 'Select All',
                        onTap: () =>
                            onSelectAll(projects.map((p) => p.id).toList()),
                      ),
                      const SizedBox(width: 8),
                      CompilationSmallButton(
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
                            return CompilationProjectItem(
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

/// Individual project item in the selection list.
class CompilationProjectItem extends StatefulWidget {
  const CompilationProjectItem({
    super.key,
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
  State<CompilationProjectItem> createState() => _CompilationProjectItemState();
}

class _CompilationProjectItemState extends State<CompilationProjectItem> {
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
              CompilationModImage(imageUrl: widget.imageUrl),
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

/// Mod image widget for the project list (75x75).
class CompilationModImage extends StatelessWidget {
  final String? imageUrl;

  const CompilationModImage({super.key, this.imageUrl});

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
