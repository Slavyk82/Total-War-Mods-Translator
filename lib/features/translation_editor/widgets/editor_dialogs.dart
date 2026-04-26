import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Dialog utilities for the translation editor screen.
///
/// Thin wrappers over [TokenDialog] so editor actions share the same
/// token-themed chrome (panel background, border, fontDisplay title,
/// tokens.info/warn/err tints) as the rest of the app.
class EditorDialogs {
  const EditorDialogs._();

  static Future<void> showFeatureNotImplemented(
    BuildContext context,
    String feature,
  ) {
    return TokenDialog.showInfo(
      context,
      title: feature,
      message: 'This feature will be fully implemented in the next phase.\n\n'
          'Current implementation provides the UI structure and event handlers.',
    );
  }

  static Future<void> showNoSelectionDialog(BuildContext context) {
    final d = t.translationEditor.dialogs.noSelection;
    return TokenDialog.showWarning(
      context,
      title: d.title,
      message: d.message,
    );
  }

  static Future<void> showNoUntranslatedDialog(BuildContext context) {
    final d = t.translationEditor.dialogs.noUntranslated;
    return TokenDialog.showInfo(
      context,
      title: d.title,
      message: d.message,
    );
  }

  static Future<void> showAllTranslatedDialog(BuildContext context) {
    final d = t.translationEditor.dialogs.allTranslated;
    return TokenDialog.showInfo(
      context,
      title: d.title,
      message: d.message,
    );
  }

  static Future<void> showErrorDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    return TokenDialog.showError(
      context,
      title: title,
      message: message,
    );
  }

  static Future<bool> showTranslateConfirmationDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return TokenDialog.showConfirm(
      context,
      title: title,
      message: message,
      icon: FluentIcons.translate_24_regular,
      confirmIcon: FluentIcons.translate_24_regular,
      confirmLabel: t.common.actions.translate,
    );
  }

  static Future<void> showInfoDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    return TokenDialog.showInfo(
      context,
      title: title,
      message: message,
    );
  }

  static Future<String?> showExportDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        final d = t.translationEditor.dialogs.export;
        return TokenDialog(
          icon: FluentIcons.arrow_export_24_regular,
          title: d.title,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                d.selectFormat,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.textDim,
                ),
              ),
              const SizedBox(height: 12),
              _ExportOption(
                icon: FluentIcons.document_24_regular,
                title: d.packTitle,
                subtitle: d.packSubtitle,
                onTap: () => Navigator.of(ctx).pop('pack'),
              ),
              _ExportOption(
                icon: FluentIcons.table_24_regular,
                title: d.csvTitle,
                subtitle: d.csvSubtitle,
                onTap: () => Navigator.of(ctx).pop('csv'),
              ),
              _ExportOption(
                icon: FluentIcons.document_table_24_regular,
                title: d.excelTitle,
                subtitle: d.excelSubtitle,
                onTap: () => Navigator.of(ctx).pop('excel'),
              ),
            ],
          ),
          actions: [
            SmallTextButton(
              label: t.common.actions.cancel,
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        );
      },
    );
  }
}

class _ExportOption extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ExportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_ExportOption> createState() => _ExportOptionState();
}

class _ExportOptionState extends State<_ExportOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered ? tokens.accentBg : tokens.panel2,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(
              color: _hovered ? tokens.accent : tokens.border,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: tokens.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: tokens.fontBody.copyWith(
                        fontSize: 13,
                        color: tokens.text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: tokens.fontBody.copyWith(
                        fontSize: 12,
                        color: tokens.textDim,
                      ),
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
