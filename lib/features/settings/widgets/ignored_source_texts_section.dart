import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_confirm_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/settings/settings_accordion_section.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../providers/ignored_source_texts_providers.dart';
import 'ignored_source_texts_datagrid.dart';
import 'ignored_source_text_editor_dialog.dart';

/// Expandable section for managing ignored source texts.
class IgnoredSourceTextsSection extends ConsumerWidget {
  const IgnoredSourceTextsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledCount =
        ref.watch(enabledIgnoredTextsCountProvider).value ?? 0;

    return SettingsAccordionSection(
      icon: FluentIcons.text_bullet_list_square_24_regular,
      title: 'Ignored Source Texts',
      subtitle: 'Skip specific source texts during translation',
      activeCount: enabledCount,
      child: _IgnoredSourceTextsBody(
        onAdd: () => _addText(context, ref),
        onReset: () => _resetToDefaults(context, ref),
      ),
    );
  }

  Future<void> _addText(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const IgnoredSourceTextEditorDialog(),
    );

    if (result == null || result.isEmpty) return;
    if (!context.mounted) return;

    final (success, error) =
        await ref.read(ignoredSourceTextsProvider.notifier).addText(result);

    if (!context.mounted) return;
    if (success) {
      FluentToast.success(context, 'Text added successfully');
    } else {
      FluentToast.error(context, error ?? 'Failed to add text');
    }
  }

  Future<void> _resetToDefaults(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _ResetConfirmDialog(),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    final (success, error) =
        await ref.read(ignoredSourceTextsProvider.notifier).resetToDefaults();

    if (!context.mounted) return;
    if (success) {
      FluentToast.success(context, 'Reset to defaults successfully');
    } else {
      FluentToast.error(context, error ?? 'Failed to reset to defaults');
    }
  }
}

class _IgnoredSourceTextsBody extends StatelessWidget {
  const _IgnoredSourceTextsBody({
    required this.onAdd,
    required this.onReset,
  });

  final VoidCallback onAdd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.panel2,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                FluentIcons.info_24_regular,
                size: 18,
                color: tokens.textDim,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Source texts matching these values will be excluded from translation. '
                  'Note: Fully bracketed texts like [PLACEHOLDER] are automatically skipped. '
                  'Use this list for custom patterns specific to your mods.',
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.textMid,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SmallTextButton(
              label: 'Reset to Defaults',
              icon: FluentIcons.arrow_reset_24_regular,
              tooltip: t.tooltips.settings.resetIgnoredDefaults,
              onTap: onReset,
            ),
            const SizedBox(width: 8),
            SmallTextButton(
              label: 'Add Text',
              icon: FluentIcons.add_24_regular,
              tooltip: t.tooltips.settings.addIgnoredText,
              onTap: onAdd,
            ),
          ],
        ),
        const SizedBox(height: 12),

        const IgnoredSourceTextsDataGrid(),
      ],
    );
  }
}

class _ResetConfirmDialog extends StatelessWidget {
  const _ResetConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return const TokenConfirmDialog(
      icon: FluentIcons.arrow_reset_24_regular,
      title: 'Reset to Defaults',
      message:
          'This will delete all current ignored texts and restore the default '
          'values:\n\n'
          '• placeholder\n'
          '• dummy\n\n'
          'Note: Texts fully enclosed in brackets like [placeholder] are always '
          'filtered automatically.\n\n'
          'Are you sure you want to continue?',
      confirmLabel: 'Reset',
      confirmIcon: FluentIcons.arrow_reset_24_regular,
    );
  }
}
