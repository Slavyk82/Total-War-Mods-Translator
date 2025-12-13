import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:path/path.dart' as path;

import '../../../../services/backup/database_backup_service.dart';
import '../../providers/backup_providers.dart';
import '../dialogs/backup_restore_confirmation_dialog.dart';
import 'settings_section_header.dart';

/// Database backup section for settings.
///
/// Provides actions to export and import database backups
/// for data preservation and recovery.
class BackupSection extends ConsumerWidget {
  const BackupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backupState = ref.watch(backupStateProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Database Backup',
          subtitle:
              'Create backups to protect your data or restore from previous backups.',
        ),
        const SizedBox(height: 16),
        _buildBackupCard(context, ref, backupState, theme),
      ],
    );
  }

  Widget _buildBackupCard(
    BuildContext context,
    WidgetRef ref,
    BackupState state,
    ThemeData theme,
  ) {
    final isRunning = state.isOperationInProgress;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.folder_zip_24_regular,
                size: 24,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Backup Actions',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.lastResult != null) ...[
            _buildResultMessage(context, state.lastResult!, theme),
            const SizedBox(height: 16),
          ],
          if (isRunning) ...[
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  state.progressMessage ?? 'Processing...',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ] else ...[
            _buildActionRow(
              context,
              ref,
              theme,
              icon: FluentIcons.arrow_export_24_regular,
              title: 'Export Backup',
              description: 'Save your database to a ZIP file',
              onTap: () => _exportBackup(context, ref),
              isPrimary: true,
            ),
            const SizedBox(height: 12),
            _buildActionRow(
              context,
              ref,
              theme,
              icon: FluentIcons.arrow_import_24_regular,
              title: 'Import Backup',
              description: 'Restore database from a backup file',
              onTap: () => _importBackup(context, ref),
              isPrimary: false,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionRow(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isPrimary
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isPrimary
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : theme.dividerColor,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isPrimary
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                FluentIcons.chevron_right_24_regular,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultMessage(
    BuildContext context,
    BackupResult result,
    ThemeData theme,
  ) {
    final isSuccess = result.success;
    final color = isSuccess ? Colors.green : theme.colorScheme.error;
    final icon = isSuccess
        ? FluentIcons.checkmark_circle_24_regular
        : FluentIcons.error_circle_24_regular;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.message,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
                if (result.filePath != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    result.filePath!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color.withValues(alpha: 0.8),
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final backupService = DatabaseBackupService();
    final suggestedName = backupService.generateBackupFilename();

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Database Backup',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result != null) {
      // Ensure .zip extension
      final destinationPath =
          result.endsWith('.zip') ? result : '$result.zip';

      ref.read(backupStateProvider.notifier).exportBackup(
            destinationPath,
          );
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Backup File',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result != null && result.files.isNotEmpty) {
      final filePath = result.files.single.path;
      if (filePath == null) return;

      final fileName = path.basename(filePath);

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => BackupRestoreConfirmationDialog(
          backupFileName: fileName,
        ),
      );

      if (confirmed == true) {
        final success =
            await ref.read(backupStateProvider.notifier).importBackup(filePath);

        if (success && context.mounted) {
          await _showRestartDialog(context);
          _restartApplication();
        }
      }
    }
  }

  Future<void> _showRestartDialog(BuildContext context) async {
    final theme = Theme.of(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  FluentIcons.checkmark_circle_24_regular,
                  size: 48,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Restore Complete',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The database has been restored successfully. '
                'The application will now restart to apply the changes.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Restart Now',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _restartApplication() {
    // Get the executable path and restart
    final executable = Platform.resolvedExecutable;
    Process.start(executable, [], mode: ProcessStartMode.detached);
    exit(0);
  }
}
