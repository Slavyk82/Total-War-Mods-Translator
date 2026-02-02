import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../providers/compilation_conflict_providers.dart';
import 'project_conflicts_detail_dialog.dart';

/// Panel showing projects that have conflicts.
/// Allows users to deselect conflicting projects from compilation.
class ConflictingProjectsPanel extends ConsumerWidget {
  const ConflictingProjectsPanel({
    super.key,
    required this.selectedProjectIds,
    required this.onToggleProject,
  });

  final Set<String> selectedProjectIds;
  final void Function(String projectId) onToggleProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final analysisAsync = ref.watch(compilationConflictAnalysisProvider);
    final conflictingProjects = ref.watch(conflictingProjectsProvider);

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
                  FluentIcons.warning_24_regular,
                  color: conflictingProjects.isEmpty
                      ? Colors.green
                      : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Conflicting Projects',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (conflictingProjects.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${conflictingProjects.length}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Content
          Expanded(
            child: analysisAsync.when(
              data: (analysis) {
                if (analysis == null) {
                  return _buildNoAnalysis(theme);
                }
                if (conflictingProjects.isEmpty) {
                  return _buildNoConflicts(theme);
                }
                return _buildConflictList(
                    context, theme, conflictingProjects);
              },
              loading: () => _buildAnalyzing(theme),
              error: (error, _) => _buildError(theme, error.toString()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoAnalysis(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.scan_24_regular,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'Conflict analysis will run',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              'when you click Generate Pack',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoConflicts(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.checkmark_circle_24_regular,
              size: 48,
              color: Colors.green.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Text(
              'No conflicts detected',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ready to compile',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzing(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Analyzing conflicts...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Analysis failed',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictList(
    BuildContext context,
    ThemeData theme,
    List<ConflictingProjectInfo> projects,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info banner
        Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                FluentIcons.info_24_regular,
                size: 16,
                color: Colors.orange.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Click on a project name to see details. Uncheck to exclude.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Project list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              final isSelected = selectedProjectIds.contains(project.projectId);
              return _ConflictingProjectItem(
                projectId: project.projectId,
                projectName: project.projectName,
                conflictCount: project.conflictCount,
                isSelected: isSelected,
                onToggle: () => onToggleProject(project.projectId),
                onShowDetails: () => _showProjectConflictsDialog(
                  context,
                  project.projectId,
                  project.projectName,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showProjectConflictsDialog(
    BuildContext context,
    String projectId,
    String projectName,
  ) {
    showDialog(
      context: context,
      builder: (context) => ProjectConflictsDetailDialog(
        projectId: projectId,
        projectName: projectName,
      ),
    );
  }
}

class _ConflictingProjectItem extends StatefulWidget {
  const _ConflictingProjectItem({
    required this.projectId,
    required this.projectName,
    required this.conflictCount,
    required this.isSelected,
    required this.onToggle,
    required this.onShowDetails,
  });

  final String projectId;
  final String projectName;
  final int conflictCount;
  final bool isSelected;
  final VoidCallback onToggle;
  final VoidCallback onShowDetails;

  @override
  State<_ConflictingProjectItem> createState() =>
      _ConflictingProjectItemState();
}

class _ConflictingProjectItemState extends State<_ConflictingProjectItem> {
  bool _isHovered = false;
  bool _isNameHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color backgroundColor;
    if (!widget.isSelected) {
      backgroundColor = theme.colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.5);
    } else if (_isHovered) {
      backgroundColor = Colors.orange.withValues(alpha: 0.05);
    } else {
      backgroundColor = Colors.transparent;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
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
            // Checkbox (clickable)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: widget.isSelected ? Colors.orange : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: widget.isSelected
                          ? Colors.orange
                          : theme.colorScheme.outline,
                      width: 2,
                    ),
                  ),
                  child: widget.isSelected
                      ? const Icon(
                          FluentIcons.checkmark_16_regular,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Project name (clickable to show details)
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _isNameHovered = true),
                onExit: (_) => setState(() => _isNameHovered = false),
                child: GestureDetector(
                  onTap: widget.onShowDetails,
                  child: Text(
                    widget.projectName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: widget.isSelected
                          ? (_isNameHovered
                              ? theme.colorScheme.primary
                              : null)
                          : theme.colorScheme.onSurfaceVariant,
                      decoration: widget.isSelected
                          ? (_isNameHovered
                              ? TextDecoration.underline
                              : null)
                          : TextDecoration.lineThrough,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Conflict count badge (clickable to show details)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onShowDetails,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? Colors.orange.withValues(alpha: 0.2)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.conflictCount}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: widget.isSelected
                              ? Colors.orange.shade700
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        FluentIcons.open_16_regular,
                        size: 12,
                        color: widget.isSelected
                            ? Colors.orange.shade700
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
