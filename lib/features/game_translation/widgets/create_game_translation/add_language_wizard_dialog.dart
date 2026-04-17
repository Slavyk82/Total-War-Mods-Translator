import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/theme/twmt_theme_tokens.dart';
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
    if (trimmed.isEmpty) return 'Language code is required';
    if (trimmed.length < 2) return 'Code must be at least 2 characters';
    if (!RegExp(r'^[a-zA-Z]+$').hasMatch(trimmed)) {
      return 'Code must contain only letters';
    }
    return null;
  }

  String? _validateName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Language name is required';
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

    return AlertDialog(
      backgroundColor: tokens.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        side: BorderSide(color: tokens.border),
      ),
      title: Row(
        children: [
          Icon(
            FluentIcons.add_circle_24_regular,
            size: 22,
            color: tokens.accent,
          ),
          const SizedBox(width: 10),
          Text(
            'Add Custom Language',
            style: tokens.fontDisplay.copyWith(
              fontSize: 17,
              color: tokens.text,
              fontStyle: tokens.fontDisplayItalic
                  ? FontStyle.italic
                  : FontStyle.normal,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add a custom language that will be available for translation projects.',
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.textDim,
              ),
            ),
            const SizedBox(height: 18),
            // Language code field
            LabeledField(
              label: 'LANGUAGE CODE',
              child: TokenTextField(
                controller: _codeController,
                hint: 'e.g. pl, ko, ja',
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
              _codeError ?? 'ISO 639-1 code (2-3 characters)',
              style: tokens.fontBody.copyWith(
                fontSize: 11,
                color: _codeError != null ? tokens.err : tokens.textDim,
              ),
            ),
            const SizedBox(height: 14),
            // Language name field
            LabeledField(
              label: 'LANGUAGE NAME',
              child: TokenTextField(
                controller: _nameController,
                hint: 'e.g. Polish, Korean, Japanese',
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
              _nameError ?? 'Display name for this language',
              style: tokens.fontBody.copyWith(
                fontSize: 11,
                color: _nameError != null ? tokens.err : tokens.textDim,
              ),
            ),
            const SizedBox(height: 16),
            // Set as default checkbox
            _buildDefaultLanguageOption(tokens),
            const SizedBox(height: 10),
            _buildInfoSection(tokens),
          ],
        ),
      ),
      actions: [
        SmallTextButton(
          label: 'Cancel',
          onTap: () => Navigator.pop(context),
        ),
        SmallTextButton(
          label: 'Add',
          icon: FluentIcons.add_24_regular,
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
                  'Set as default language',
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'This language will become the default target language for all new mod translation projects.',
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
              'Custom languages can be deleted later from Settings. System languages (English, French, etc.) cannot be modified.',
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
