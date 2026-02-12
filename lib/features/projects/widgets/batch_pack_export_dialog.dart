import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../widgets/fluent/fluent_progress_indicator.dart';
import '../providers/batch_pack_export_notifier.dart';

/// Dialog for batch pack export progress
class BatchPackExportDialog extends ConsumerStatefulWidget {
  final List<ProjectExportInfo> projects;
  final String languageCode;
  final String languageName;

  const BatchPackExportDialog({
    super.key,
    required this.projects,
    required this.languageCode,
    required this.languageName,
  });

  @override
  ConsumerState<BatchPackExportDialog> createState() => _BatchPackExportDialogState();
}

class _BatchPackExportDialogState extends ConsumerState<BatchPackExportDialog> {
  final DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Start export after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(batchPackExportProvider.notifier).exportBatch(
        projects: widget.projects,
        languageCode: widget.languageCode,
      );
    });
  }

  @override
  void dispose() {
    // Reset state when dialog closes
    ref.read(batchPackExportProvider.notifier).reset();
    super.dispose();
  }

  String get _elapsedTime {
    final elapsed = DateTime.now().difference(_startTime);
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(batchPackExportProvider);

    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(theme, state),
            const Divider(height: 1),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Progress section
                    _buildProgressSection(theme, state),
                    const SizedBox(height: 20),
                    // Project list
                    _buildProjectList(theme, state),
                    // Results summary (when complete)
                    if (state.isComplete) ...[
                      const SizedBox(height: 20),
                      _buildResultsSummary(theme, state),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            // Footer
            _buildFooter(theme, state),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, BatchPackExportState state) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(
            FluentIcons.arrow_export_24_regular,
            size: 28,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Batch Pack Export',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.projects.length} projects \u2022 ${widget.languageName}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          // Elapsed time
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.timer_24_regular,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  _elapsedTime,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection(ThemeData theme, BatchPackExportState state) {
    final progressPercent = (state.overallProgress * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                state.isComplete
                    ? 'Export Complete'
                    : state.isCancelled
                        ? 'Cancelled'
                        : 'Exporting...',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$progressPercent%',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: state.isComplete && state.failedCount == 0
                      ? Colors.green.shade700
                      : state.failedCount > 0
                          ? Colors.orange.shade700
                          : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FluentProgressBar(
            value: state.overallProgress,
            height: 8,
            color: state.isComplete && state.failedCount == 0
                ? Colors.green.shade700
                : state.failedCount > 0
                    ? Colors.orange.shade700
                    : theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 8),
          Text(
            '${state.completedProjects} / ${state.totalProjects} projects',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (state.currentProjectName != null && state.isExporting) ...[
            const SizedBox(height: 4),
            Text(
              'Current: ${state.currentProjectName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProjectList(ThemeData theme, BatchPackExportState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Projects',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 250),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: widget.projects.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final project = widget.projects[index];
              final status = state.projectStatuses[project.id] ?? BatchProjectStatus.pending;
              final result = state.results.cast<ProjectExportResult?>().firstWhere(
                (r) => r?.projectId == project.id,
                orElse: () => null,
              );

              return _ProjectStatusItem(
                name: project.name,
                status: status,
                result: result,
                isCurrentProject: state.currentProjectId == project.id,
                currentProgress: state.currentProjectId == project.id
                    ? state.currentProjectProgress
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultsSummary(ThemeData theme, BatchPackExportState state) {
    final hasFailures = state.failedCount > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasFailures
            ? Colors.orange.withValues(alpha: 0.1)
            : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasFailures
              ? Colors.orange.withValues(alpha: 0.3)
              : Colors.green.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasFailures
                ? FluentIcons.warning_24_regular
                : FluentIcons.checkmark_circle_24_regular,
            size: 24,
            color: hasFailures ? Colors.orange.shade700 : Colors.green.shade700,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasFailures
                      ? 'Export completed with errors'
                      : 'All packs exported successfully',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: hasFailures ? Colors.orange.shade700 : Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${state.successCount} succeeded, ${state.failedCount} failed',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: hasFailures ? Colors.orange.shade700 : Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme, BatchPackExportState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (state.isExporting && !state.isCancelled)
            TextButton.icon(
              onPressed: () {
                ref.read(batchPackExportProvider.notifier).cancel();
              },
              icon: const Icon(FluentIcons.dismiss_24_regular, size: 18),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          if (state.isComplete || state.isCancelled) ...[
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(FluentIcons.checkmark_24_regular, size: 18),
              label: const Text('Close'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Individual project status item in the list
class _ProjectStatusItem extends StatelessWidget {
  final String name;
  final BatchProjectStatus status;
  final ProjectExportResult? result;
  final bool isCurrentProject;
  final double? currentProgress;

  const _ProjectStatusItem({
    required this.name,
    required this.status,
    this.result,
    this.isCurrentProject = false,
    this.currentProgress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: isCurrentProject
          ? theme.colorScheme.primary.withValues(alpha: 0.05)
          : null,
      child: Row(
        children: [
          // Status icon
          _buildStatusIcon(theme),
          const SizedBox(width: 10),
          // Project name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isCurrentProject ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (result != null && result!.success) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${result!.entryCount} entries',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
                if (result != null && !result!.success && result!.errorMessage != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    result!.errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // Progress for current project
          if (isCurrentProject && currentProgress != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 60,
              child: FluentProgressBar(
                value: currentProgress!,
                height: 4,
                color: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIcon(ThemeData theme) {
    switch (status) {
      case BatchProjectStatus.pending:
        return Icon(
          FluentIcons.circle_24_regular,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        );
      case BatchProjectStatus.inProgress:
        return SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        );
      case BatchProjectStatus.success:
        return Icon(
          FluentIcons.checkmark_circle_24_filled,
          size: 18,
          color: Colors.green.shade700,
        );
      case BatchProjectStatus.failed:
        return Icon(
          FluentIcons.error_circle_24_filled,
          size: 18,
          color: theme.colorScheme.error,
        );
      case BatchProjectStatus.cancelled:
        return Icon(
          FluentIcons.dismiss_circle_24_regular,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        );
    }
  }
}
