import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Dialog for confirming database restore from backup.
///
/// Shows a critical warning that all current data will be replaced,
/// providing Cancel and Restore actions following Fluent Design principles.
class BackupRestoreConfirmationDialog extends StatefulWidget {
  final String backupFileName;

  const BackupRestoreConfirmationDialog({
    super.key,
    required this.backupFileName,
  });

  @override
  State<BackupRestoreConfirmationDialog> createState() =>
      _BackupRestoreConfirmationDialogState();
}

class _BackupRestoreConfirmationDialogState
    extends State<BackupRestoreConfirmationDialog> {
  bool _isHoveringCancel = false;
  bool _isHoveringRestore = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            _buildContent(context),
            const SizedBox(height: 24),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(
            FluentIcons.warning_24_regular,
            size: 24,
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Restore Database Backup?',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'You are about to restore the database from:',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                FluentIcons.folder_zip_24_regular,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.backupFileName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.red.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                FluentIcons.error_circle_24_regular,
                size: 20,
                color: Colors.red,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Warning: This will replace ALL your current data!',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'All projects, translations, glossaries, and settings will be overwritten. This action cannot be undone.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildCancelButton(context),
        const SizedBox(width: 12),
        _buildRestoreButton(context),
      ],
    );
  }

  Widget _buildCancelButton(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHoveringCancel = true),
      onExit: (_) => setState(() => _isHoveringCancel = false),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: _isHoveringCancel
                ? Colors.grey.withValues(alpha: 0.1)
                : Colors.transparent,
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.3),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRestoreButton(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHoveringRestore = true),
      onExit: (_) => setState(() => _isHoveringRestore = false),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(true),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: _isHoveringRestore ? Colors.orange.shade700 : Colors.orange,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.arrow_import_24_regular,
                size: 16,
                color: Colors.white,
              ),
              SizedBox(width: 8),
              Text(
                'Restore',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
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
