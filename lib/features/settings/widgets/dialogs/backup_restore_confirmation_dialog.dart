import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Dialog for confirming database restore from backup.
///
/// Shows a critical warning that all current data will be replaced,
/// providing Cancel and Restore actions.
///
/// Retokenised (Plan 5e · Task 7): token-themed `Dialog` wrapper, warn/err
/// tokens for the warning banners, [SmallTextButton] actions.
class BackupRestoreConfirmationDialog extends StatelessWidget {
  final String backupFileName;

  const BackupRestoreConfirmationDialog({
    super.key,
    required this.backupFileName,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Dialog(
      backgroundColor: tokens.panel,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        side: BorderSide(color: tokens.border),
      ),
      child: SizedBox(
        width: 500,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(tokens),
              const SizedBox(height: 16),
              _buildContent(tokens),
              const SizedBox(height: 24),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(TwmtThemeTokens tokens) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: tokens.warnBg,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Icon(
            FluentIcons.warning_24_regular,
            size: 22,
            color: tokens.warn,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Restore Database Backup?',
            style: tokens.fontDisplay.copyWith(
              fontSize: 18,
              color: tokens.text,
              fontStyle: tokens.fontDisplayItalic
                  ? FontStyle.italic
                  : FontStyle.normal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(TwmtThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'You are about to restore the database from:',
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.text,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.panel2,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: [
              Icon(
                FluentIcons.folder_zip_24_regular,
                size: 18,
                color: tokens.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  backupFileName,
                  style: tokens.fontMono.copyWith(
                    fontSize: 12.5,
                    color: tokens.text,
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
            color: tokens.errBg,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(
              color: tokens.err.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                FluentIcons.error_circle_24_regular,
                size: 18,
                color: tokens.err,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Warning: This will replace ALL your current data!',
                      style: tokens.fontBody.copyWith(
                        fontSize: 13,
                        color: tokens.err,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'All projects, translations, glossaries, and settings will be overwritten. This action cannot be undone.',
                      style: tokens.fontBody.copyWith(
                        fontSize: 12,
                        color: tokens.err,
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
        SmallTextButton(
          label: 'Cancel',
          onTap: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(width: 8),
        SmallTextButton(
          label: 'Restore',
          icon: FluentIcons.arrow_import_24_regular,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
