import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/wizard/labeled_field.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';
import '../../../providers/batch/batch_operations_provider.dart';

/// Token-themed popup for editing a translation flagged by validation.
class ValidationEditDialog extends StatefulWidget {
  final ValidationIssue issue;

  const ValidationEditDialog({super.key, required this.issue});

  @override
  State<ValidationEditDialog> createState() => _ValidationEditDialogState();
}

class _ValidationEditDialogState extends State<ValidationEditDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.issue.translatedText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return TokenDialog(
      icon: FluentIcons.edit_24_regular,
      title: t.translationEditor.dialogs.editTranslation.title,
      subtitle: widget.issue.unitKey,
      width: 800,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildIssueBanner(tokens),
          const SizedBox(height: 16),
          _buildSourceTextSection(tokens),
          const SizedBox(height: 16),
          LabeledField(
            label: t.translationEditor.dialogs.editTranslation.translationLabel,
            child: TokenTextField(
              controller: _controller,
              hint: t.translationEditor.dialogs.editTranslation.hint,
              enabled: true,
              minLines: 4,
              maxLines: 8,
              autofocus: true,
            ),
          ),
        ],
      ),
      actions: [
        SmallTextButton(
          label: t.common.actions.cancel,
          onTap: () => Navigator.of(context).pop(),
        ),
        SmallTextButton(
          label: t.common.actions.save,
          icon: FluentIcons.checkmark_24_regular,
          filled: true,
          onTap: () {
            final text = _controller.text.trim();
            if (text.isNotEmpty) {
              Navigator.of(context).pop(text);
            }
          },
        ),
      ],
    );
  }

  Widget _buildIssueBanner(TwmtThemeTokens tokens) {
    final isError = widget.issue.severity == ValidationSeverity.error;
    final color = isError ? tokens.err : tokens.warn;
    final bgColor = isError ? tokens.errBg : tokens.warnBg;
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
          Icon(
            isError
                ? FluentIcons.error_circle_24_regular
                : FluentIcons.warning_24_regular,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${widget.issue.issueType}: ${widget.issue.description}',
              style: tokens.fontBody.copyWith(
                fontSize: 12.5,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTextSection(TwmtThemeTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.translationEditor.dialogs.sourceText,
          style: tokens.fontBody.copyWith(
            fontSize: 12,
            color: tokens.textDim,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 150),
          decoration: BoxDecoration(
            color: tokens.panel2,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                widget.issue.sourceText,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
