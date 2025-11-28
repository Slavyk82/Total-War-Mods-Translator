import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../providers/pack_compilation_providers.dart';

/// Widget displaying the list of existing compilations.
class CompilationList extends ConsumerWidget {
  const CompilationList({
    super.key,
    required this.onCreateNew,
    required this.onEdit,
  });

  final VoidCallback onCreateNew;
  final void Function(CompilationWithDetails) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final compilationsAsync = ref.watch(compilationsWithDetailsProvider);

    return compilationsAsync.when(
      data: (compilations) {
        if (compilations.isEmpty) {
          return _buildEmptyState(theme);
        }
        return _buildList(context, ref, theme, compilations);
      },
      loading: () => _buildLoading(theme),
      error: (error, _) => _buildError(theme, error),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.box_multiple_24_regular,
            size: 80,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'No compilations yet',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a compilation to group multiple translated projects\ninto a single .pack file',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _CreateFirstButton(onTap: onCreateNew),
        ],
      ),
    );
  }

  Widget _buildLoading(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading compilations...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 64,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load compilations',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    List<CompilationWithDetails> compilations,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: compilations.length,
      itemBuilder: (context, index) {
        final compilation = compilations[index];
        return _CompilationCard(
          compilation: compilation,
          onEdit: () => onEdit(compilation),
          onDelete: () => _confirmDelete(context, ref, compilation),
          onGenerate: () => _generatePack(context, ref, compilation),
        );
      },
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CompilationWithDetails compilation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Compilation'),
        content: Text(
          'Are you sure you want to delete "${compilation.compilation.name}"?\n'
          'This will not delete the projects or any generated pack files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await deleteCompilation(compilation.compilation.id);
      ref.invalidate(compilationsWithDetailsProvider);
    }
  }

  void _generatePack(
    BuildContext context,
    WidgetRef ref,
    CompilationWithDetails compilation,
  ) async {
    // Load the compilation into the editor and generate
    ref.read(compilationEditorProvider.notifier).loadCompilation(compilation);
    final success = await ref
        .read(compilationEditorProvider.notifier)
        .generatePack(compilation.compilation.gameInstallationId);

    if (context.mounted) {
      final theme = Theme.of(context);
      final state = ref.read(compilationEditorProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? state.successMessage ?? 'Pack generated successfully'
                : state.errorMessage ?? 'Failed to generate pack',
          ),
          backgroundColor:
              success ? Colors.green : theme.colorScheme.error,
        ),
      );
    }

    ref.invalidate(compilationsWithDetailsProvider);
  }
}

class _CompilationCard extends StatefulWidget {
  const _CompilationCard({
    required this.compilation,
    required this.onEdit,
    required this.onDelete,
    required this.onGenerate,
  });

  final CompilationWithDetails compilation;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onGenerate;

  @override
  State<_CompilationCard> createState() => _CompilationCardState();
}

class _CompilationCardState extends State<_CompilationCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compilation = widget.compilation.compilation;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onEdit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isHovered
                ? theme.colorScheme.surface
                : theme.colorScheme.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : theme.dividerColor,
            ),
          ),
          child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                FluentIcons.box_multiple_24_filled,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    compilation.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        FluentIcons.folder_24_regular,
                        size: 14,
                        color: theme.textTheme.bodySmall?.color
                            ?.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.compilation.projectCount} projects',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        FluentIcons.games_24_regular,
                        size: 14,
                        color: theme.textTheme.bodySmall?.color
                            ?.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.compilation.gameInstallation?.gameName ?? 'Unknown',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    compilation.fullPackFileName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            // Actions
            if (_isHovered) ...[
              _ActionButton(
                icon: FluentIcons.arrow_sync_24_regular,
                tooltip: 'Generate Pack',
                onTap: widget.onGenerate,
                isPrimary: true,
              ),
              const SizedBox(width: 8),
              _ActionButton(
                icon: FluentIcons.edit_24_regular,
                tooltip: 'Edit',
                onTap: widget.onEdit,
              ),
              const SizedBox(width: 8),
              _ActionButton(
                icon: FluentIcons.delete_24_regular,
                tooltip: 'Delete',
                onTap: widget.onDelete,
                isDestructive: true,
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isPrimary = false,
    this.isDestructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool isDestructive;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color iconColor;
    Color backgroundColor;

    if (widget.isDestructive) {
      iconColor = theme.colorScheme.error;
      backgroundColor = _isHovered
          ? theme.colorScheme.error.withValues(alpha: 0.1)
          : Colors.transparent;
    } else if (widget.isPrimary) {
      iconColor =
          _isHovered ? theme.colorScheme.onPrimary : theme.colorScheme.primary;
      backgroundColor = _isHovered
          ? theme.colorScheme.primary
          : theme.colorScheme.primary.withValues(alpha: 0.1);
    } else {
      iconColor = theme.colorScheme.onSurface;
      backgroundColor = _isHovered
          ? theme.colorScheme.surfaceContainerHighest
          : Colors.transparent;
    }

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 20, color: iconColor),
          ),
        ),
      ),
    );
  }
}

class _CreateFirstButton extends StatefulWidget {
  const _CreateFirstButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CreateFirstButton> createState() => _CreateFirstButtonState();
}

class _CreateFirstButtonState extends State<_CreateFirstButton> {
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: _isHovered
                ? theme.colorScheme.primary.withValues(alpha: 0.9)
                : theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.add_24_regular,
                size: 20,
                color: theme.colorScheme.onPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                'Create First Compilation',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
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
