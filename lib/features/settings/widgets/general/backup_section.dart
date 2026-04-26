import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../../providers/shared/service_providers.dart';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(
          title: t.settings.general.backup.sectionTitle,
          subtitle: t.settings.general.backup.sectionSubtitle,
        ),
        const SizedBox(height: 16),
        _buildBackupCard(context, ref, backupState),
      ],
    );
  }

  Widget _buildBackupCard(
    BuildContext context,
    WidgetRef ref,
    BackupState state,
  ) {
    final tokens = context.tokens;
    final isRunning = state.isOperationInProgress;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.panel,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.folder_zip_24_regular,
                size: 24,
                color: tokens.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t.settings.general.backup.cardTitle,
                  style: tokens.fontBody.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.lastResult != null) ...[
            _buildResultMessage(context, state.lastResult!),
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
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  state.progressMessage ?? t.settings.general.backup.processing,
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.text,
                  ),
                ),
              ],
            ),
          ] else ...[
            _buildActionRow(
              context,
              ref,
              icon: FluentIcons.arrow_export_24_regular,
              title: t.settings.general.backup.exportTitle,
              description: t.settings.general.backup.exportDescription,
              onTap: () => _exportBackup(context, ref),
              isPrimary: true,
            ),
            const SizedBox(height: 12),
            _buildActionRow(
              context,
              ref,
              icon: FluentIcons.arrow_import_24_regular,
              title: t.settings.general.backup.importTitle,
              description: t.settings.general.backup.importDescription,
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
    WidgetRef ref, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isPrimary ? tokens.accentBg : tokens.panel2,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isPrimary ? tokens.accent : tokens.textDim,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tokens.fontBody.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.text,
                      ),
                    ),
                    Text(
                      description,
                      style: tokens.fontBody.copyWith(
                        fontSize: 12,
                        color: tokens.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                FluentIcons.chevron_right_24_regular,
                size: 16,
                color: tokens.textDim,
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
  ) {
    final tokens = context.tokens;
    final isSuccess = result.success;
    final color = isSuccess ? tokens.ok : tokens.err;
    final bgColor = isSuccess ? tokens.okBg : tokens.errBg;
    final icon = isSuccess
        ? FluentIcons.checkmark_circle_24_regular
        : FluentIcons.error_circle_24_regular;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
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
                  style: tokens.fontBody.copyWith(fontSize: 12, color: color),
                ),
                if (result.filePath != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    result.filePath!,
                    style: tokens.fontMono.copyWith(
                      fontSize: 11,
                      color: color.withValues(alpha: 0.8),
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
    final backupService = ref.read(databaseBackupServiceProvider);
    final suggestedName = backupService.generateBackupFilename();

    final result = await FilePicker.platform.saveFile(
      dialogTitle: t.settings.general.backup.saveDialogTitle,
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
      dialogTitle: t.settings.general.backup.openDialogTitle,
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result != null && result.files.isNotEmpty) {
      final filePath = result.files.single.path;
      if (filePath == null) return;

      final fileName = path.basename(filePath);

      if (!context.mounted) return;

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
    if (!context.mounted) return;

    final tokens = context.tokens;

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
                  color: tokens.okBg,
                  borderRadius: BorderRadius.circular(tokens.radiusMd),
                ),
                child: Icon(
                  FluentIcons.checkmark_circle_24_regular,
                  size: 48,
                  color: tokens.ok,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                t.settings.general.backup.restoreDialog.title,
                style: tokens.fontDisplay.copyWith(
                  fontSize: 20,
                  color: tokens.text,
                  fontWeight: FontWeight.w600,
                  fontStyle: tokens.fontDisplayStyle,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.settings.general.backup.restoreDialog.message,
                textAlign: TextAlign.center,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.textDim,
                ),
              ),
              const SizedBox(height: 24),
              SmallTextButton(
                label: t.settings.general.backup.restoreDialog.restartNow,
                filled: true,
                onTap: () => Navigator.of(context).pop(),
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
