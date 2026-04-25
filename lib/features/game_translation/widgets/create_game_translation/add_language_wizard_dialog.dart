import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/wizard/labeled_field.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';

/// Result returned from the add language wizard dialog
class AddLanguageWizardResult {
  final String code;
  final String name;
  final bool setAsDefault;

  const AddLanguageWizardResult({
    required this.code,
    required this.name,
    required this.setAsDefault,
  });
}

/// Dialog for adding a custom language from the game translation wizard.
///
/// Retokenised (Plan 5d · Task 5): token panel/accent/border, [TokenTextField]
/// inputs, [SmallTextButton] footer.
class AddLanguageWizardDialog extends StatefulWidget {
  const AddLanguageWizardDialog({super.key});

  @override
  State<AddLanguageWizardDialog> createState() =>
      _AddLanguageWizardDialogState();
}

class _AddLanguageWizardDialogState extends State<AddLanguageWizardDialog> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _setAsDefault = false;
  String? _codeError;
  String? _nameError;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String? _validateCode(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return t.gameTranslation.addLanguageDialog.fields.codeErrors.required;
    if (trimmed.length < 2) return t.gameTranslation.addLanguageDialog.fields.codeErrors.tooShort;
    if (!RegExp(r'^[a-zA-Z]+$').hasMatch(trimmed)) {
      return t.gameTranslation.addLanguageDialog.fields.codeErrors.lettersOnly;
    }
    return null;
  }

  String? _validateName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return t.gameTranslation.addLanguageDialog.fields.nameErrors.required;
    return null;
  }

  void _save() {
    final codeError = _validateCode(_codeController.text);
    final nameError = _validateName(_nameController.text);
    setState(() {
      _codeError = codeError;
      _nameError = nameError;
    });
    if (codeError != null || nameError != null) return;
    Navigator.pop(
      context,
      AddLanguageWizardResult(
        code: _codeController.text.trim(),
        name: _nameController.text.trim(),
        setAsDefault: _setAsDefault,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return TokenDialog(
      icon: FluentIcons.add_circle_24_regular,
      title: t.gameTranslation.addLanguageDialog.title,
      width: 480,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.gameTranslation.addLanguageDialog.description,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textDim,
            ),
          ),
          const SizedBox(height: 18),
          LabeledField(
            label: t.gameTranslation.addLanguageDialog.fields.codeLabel,
            child: TokenTextField(
              controller: _codeController,
              hint: t.gameTranslation.addLanguageDialog.fields.codeHint,
              enabled: true,
              onChanged: (_) {
                if (_codeError != null) {
                  setState(() => _codeError = null);
                }
              },
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _codeError ?? t.gameTranslation.addLanguageDialog.fields.codeHelper,
            style: tokens.fontBody.copyWith(
              fontSize: 11,
              color: _codeError != null ? tokens.err : tokens.textDim,
            ),
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: t.gameTranslation.addLanguageDialog.fields.nameLabel,
            child: TokenTextField(
              controller: _nameController,
              hint: t.gameTranslation.addLanguageDialog.fields.nameHint,
              enabled: true,
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _nameError ?? t.gameTranslation.addLanguageDialog.fields.nameHelper,
            style: tokens.fontBody.copyWith(
              fontSize: 11,
              color: _nameError != null ? tokens.err : tokens.textDim,
            ),
          ),
          const SizedBox(height: 16),
          _buildDefaultLanguageOption(tokens),
          const SizedBox(height: 10),
          _buildInfoSection(tokens),
        ],
      ),
      actions: [
        SmallTextButton(
          label: t.gameTranslation.wizard.actions.cancel,
          onTap: () => Navigator.pop(context),
        ),
        SmallTextButton(
          label: t.gameTranslation.addLanguageDialog.actions.add,
          icon: FluentIcons.add_24_regular,
          filled: true,
          onTap: _save,
        ),
      ],
    );
  }

  Widget _buildDefaultLanguageOption(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.panel2,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Checkbox(
            value: _setAsDefault,
            activeColor: tokens.accent,
            checkColor: tokens.accentFg,
            onChanged: (value) {
              setState(() => _setAsDefault = value ?? false);
            },
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.gameTranslation.addLanguageDialog.defaultLanguage.label,
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  t.gameTranslation.addLanguageDialog.defaultLanguage.description,
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
    );
  }

  Widget _buildInfoSection(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.accentBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FluentIcons.info_24_regular,
            size: 16,
            color: tokens.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.gameTranslation.addLanguageDialog.info,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
