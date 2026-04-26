import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/wizard/labeled_field.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';
import '../../../models/domain/llm_custom_rule.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../settings/providers/llm_custom_rules_providers.dart';

/// Dialog for editing a mod-specific translation rule.
///
/// Token-themed `Dialog` wrapper with [LabeledField] + multiline
/// [TokenTextField] body and [SmallTextButton] actions, mirroring the
/// `LlmCustomRuleEditorDialog` archetype.
class ModRuleEditorDialog extends ConsumerStatefulWidget {
  final String projectId;
  final String projectName;

  const ModRuleEditorDialog({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  ConsumerState<ModRuleEditorDialog> createState() => _ModRuleEditorDialogState();
}

class _ModRuleEditorDialogState extends ConsumerState<ModRuleEditorDialog> {
  late TextEditingController _textController;
  bool _isLoading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final ruleAsync = ref.watch(projectCustomRuleProvider(widget.projectId));

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
          child: ruleAsync.when(
            data: (existingRule) {
              if (_textController.text.isEmpty && existingRule != null) {
                _textController.text = existingRule.ruleText;
              }
              return _buildBody(tokens, existingRule);
            },
            loading: () => SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(color: tokens.accent),
              ),
            ),
            error: (error, _) => SizedBox(
              height: 200,
              child: Center(
                child: Text(
                  'Error loading rule: $error',
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.err,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(TwmtThemeTokens tokens, LlmCustomRule? existingRule) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              FluentIcons.text_bullet_list_ltr_24_regular,
              size: 22,
              color: tokens.accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.translationEditor.dialogs.modRule.title,
                    style: tokens.fontDisplay.copyWith(
                      fontSize: 18,
                      color: tokens.text,
                      fontStyle: tokens.fontDisplayStyle,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.projectName,
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
        const SizedBox(height: 16),
        _buildInfoBanner(tokens),
        const SizedBox(height: 16),
        LabeledField(
          label: t.translationEditor.dialogs.modRule.ruleTextLabel,
          child: TokenTextField(
            controller: _textController,
            hint: t.translationEditor.dialogs.modRule.ruleTextHint,
            enabled: !_isLoading,
            minLines: 10,
            maxLines: 10,
            autofocus: existingRule == null,
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
        if (existingRule != null) ...[
          const SizedBox(height: 12),
          _buildEnabledToggle(tokens, existingRule),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (existingRule != null) ...[
              SmallTextButton(
                label: t.common.actions.delete,
                icon: FluentIcons.delete_24_regular,
                onTap: _isLoading ? null : _deleteRule,
              ),
              const Spacer(),
            ],
            SmallTextButton(
              label: t.common.actions.cancel,
              onTap: _isLoading ? null : () => Navigator.pop(context),
            ),
            const SizedBox(width: 8),
            SmallTextButton(
              label: t.common.actions.save,
              icon: FluentIcons.save_24_regular,
              filled: true,
              onTap: _isLoading ? null : _save,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoBanner(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.accentBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FluentIcons.info_24_regular,
            size: 18,
            color: tokens.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t.translationEditor.dialogs.modRule.infoBanner,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnabledToggle(TwmtThemeTokens tokens, LlmCustomRule rule) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _toggleEnabled,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              rule.isEnabled
                  ? FluentIcons.checkbox_checked_24_filled
                  : FluentIcons.checkbox_unchecked_24_regular,
              size: 18,
              color: rule.isEnabled ? tokens.accent : tokens.textFaint,
            ),
            const SizedBox(width: 8),
            Text(
              rule.isEnabled ? t.translationEditor.dialogs.modRule.ruleActive : t.translationEditor.dialogs.modRule.ruleDisabled,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final value = _textController.text.trim();
    if (value.isEmpty) {
      setState(() => _errorText = t.translationEditor.dialogs.modRule.validationEmpty);
      return;
    }

    setState(() => _isLoading = true);

    final notifier = ref.read(
      projectCustomRuleProvider(widget.projectId).notifier,
    );
    final (success, error) = await notifier.setRule(value);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      FluentToast.success(context, t.translationEditor.dialogs.modRule.savedSuccess);
      Navigator.pop(context, true);
    } else {
      FluentToast.error(context, error ?? t.translationEditor.dialogs.modRule.errorSave);
    }
  }

  Future<void> _deleteRule() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteConfirmationDialog(),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    final notifier = ref.read(
      projectCustomRuleProvider(widget.projectId).notifier,
    );
    final (success, error) = await notifier.deleteRule();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      FluentToast.success(context, t.translationEditor.dialogs.modRule.deletedSuccess);
      Navigator.pop(context, true);
    } else {
      FluentToast.error(context, error ?? t.translationEditor.dialogs.modRule.errorDelete);
    }
  }

  Future<void> _toggleEnabled() async {
    final notifier = ref.read(
      projectCustomRuleProvider(widget.projectId).notifier,
    );
    final (success, error) = await notifier.toggleEnabled();

    if (mounted && !success) {
      FluentToast.error(context, error ?? t.translationEditor.dialogs.modRule.errorToggle);
    }
  }
}

class _DeleteConfirmationDialog extends StatelessWidget {
  const _DeleteConfirmationDialog();

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
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    FluentIcons.delete_24_regular,
                    size: 22,
                    color: tokens.err,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    t.translationEditor.dialogs.modRule.deleteTitle,
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
                t.translationEditor.dialogs.modRule.deleteMessage,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.textDim,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SmallTextButton(
                    label: t.common.actions.cancel,
                    onTap: () => Navigator.pop(context, false),
                  ),
                  const SizedBox(width: 8),
                  SmallTextButton(
                    label: t.common.actions.delete,
                    icon: FluentIcons.delete_24_regular,
                    filled: true,
                    onTap: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
