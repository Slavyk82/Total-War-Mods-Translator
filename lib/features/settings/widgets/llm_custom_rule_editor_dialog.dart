import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/wizard/labeled_field.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';
import '../../../models/domain/llm_custom_rule.dart';

/// Dialog for adding or editing a custom LLM translation rule.
///
/// Retokenised (Plan 5e · Task 7): token-themed `Dialog` wrapper with
/// [LabeledField] + multiline [TokenTextField] body, [SmallTextButton] actions.
class LlmCustomRuleEditorDialog extends StatefulWidget {
  /// Existing rule to edit, or null for creating a new rule
  final LlmCustomRule? existingRule;

  const LlmCustomRuleEditorDialog({
    super.key,
    this.existingRule,
  });

  @override
  State<LlmCustomRuleEditorDialog> createState() =>
      _LlmCustomRuleEditorDialogState();
}

class _LlmCustomRuleEditorDialogState extends State<LlmCustomRuleEditorDialog> {
  late TextEditingController _textController;
  String? _errorText;

  bool get _isEditing => widget.existingRule != null;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.existingRule?.ruleText ?? '',
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

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
        width: 600,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    _isEditing
                        ? FluentIcons.edit_24_regular
                        : FluentIcons.add_circle_24_regular,
                    size: 22,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isEditing ? t.settings.customRules.editorDialog.editTitle : t.settings.customRules.editorDialog.addTitle,
                    style: tokens.fontDisplay.copyWith(
                      fontSize: 18,
                      color: tokens.text,
                      fontStyle: tokens.fontDisplayStyle,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                t.settings.customRules.editorDialog.description,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.textDim,
                ),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: t.settings.customRules.editorDialog.ruleTextLabel,
                child: TokenTextField(
                  controller: _textController,
                  hint: t.settings.customRules.editorDialog.ruleTextHint,
                  enabled: true,
                  minLines: 10,
                  maxLines: 14,
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() => _errorText = null);
                    }
                  },
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 6),
                Text(
                  _errorText!,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.err,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _buildHelpSection(tokens),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SmallTextButton(
                    label: t.settings.customRules.editorDialog.cancel,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  SmallTextButton(
                    label: _isEditing ? t.settings.customRules.editorDialog.save : t.settings.customRules.editorDialog.add,
                    icon: _isEditing
                        ? FluentIcons.save_24_regular
                        : FluentIcons.add_24_regular,
                    onTap: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpSection(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.accentBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.lightbulb_24_regular,
                size: 16,
                color: tokens.accent,
              ),
              const SizedBox(width: 8),
              Text(
                t.settings.customRules.editorDialog.tipsTitle,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.settings.customRules.editorDialog.tipsText,
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final value = _textController.text.trim();
    if (value.isEmpty) {
      setState(() => _errorText = t.settings.customRules.editorDialog.errors.ruleTextRequired);
      return;
    }
    Navigator.pop(context, value);
  }
}
