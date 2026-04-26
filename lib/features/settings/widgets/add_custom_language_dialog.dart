import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/wizard/labeled_field.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';

/// Dialog for adding a custom language.
///
/// Retokenised (Plan 5e · Task 7): token-themed `Dialog` wrapper with
/// two [LabeledField] + [TokenTextField] pairs (code + display name) and
/// [SmallTextButton] actions.
///
/// Returns a record (code, name) if the user confirms, null otherwise.
class AddCustomLanguageDialog extends StatefulWidget {
  const AddCustomLanguageDialog({super.key});

  @override
  State<AddCustomLanguageDialog> createState() =>
      _AddCustomLanguageDialogState();
}

class _AddCustomLanguageDialogState extends State<AddCustomLanguageDialog> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  String? _codeError;
  String? _nameError;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
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
        width: 440,
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
                    FluentIcons.add_circle_24_regular,
                    size: 22,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    t.settings.addCustomLanguage.title,
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
                t.settings.addCustomLanguage.description,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.textDim,
                ),
              ),
              const SizedBox(height: 20),
              // Language code field
              LabeledField(
                label: t.settings.addCustomLanguage.codeLabel,
                child: TokenTextField(
                  controller: _codeController,
                  hint: t.settings.addCustomLanguage.codeHint,
                  enabled: true,
                  onChanged: (_) {
                    if (_codeError != null) {
                      setState(() => _codeError = null);
                    }
                  },
                ),
              ),
              if (_codeError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _codeError!,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.err,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Language name field
              LabeledField(
                label: t.settings.addCustomLanguage.nameLabel,
                child: TokenTextField(
                  controller: _nameController,
                  hint: t.settings.addCustomLanguage.nameHint,
                  enabled: true,
                  onChanged: (_) {
                    if (_nameError != null) {
                      setState(() => _nameError = null);
                    }
                  },
                ),
              ),
              if (_nameError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _nameError!,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.err,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _buildInfoSection(tokens),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SmallTextButton(
                    label: t.settings.addCustomLanguage.cancel,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  SmallTextButton(
                    label: t.settings.addCustomLanguage.add,
                    icon: FluentIcons.add_24_regular,
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

  Widget _buildInfoSection(TwmtThemeTokens tokens) {
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
            size: 16,
            color: tokens.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.settings.addCustomLanguage.info,
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

  void _save() {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();

    String? codeError;
    String? nameError;

    if (code.isEmpty) {
      codeError = t.settings.addCustomLanguage.errors.codeRequired;
    } else if (code.length < 2) {
      codeError = t.settings.addCustomLanguage.errors.codeTooShort;
    } else if (!RegExp(r'^[a-zA-Z]+$').hasMatch(code)) {
      codeError = t.settings.addCustomLanguage.errors.codeLettersOnly;
    } else if (code.length > 5) {
      codeError = t.settings.addCustomLanguage.errors.codeTooLong;
    }

    if (name.isEmpty) {
      nameError = t.settings.addCustomLanguage.errors.nameRequired;
    } else if (name.length > 50) {
      nameError = t.settings.addCustomLanguage.errors.nameTooLong;
    }

    if (codeError != null || nameError != null) {
      setState(() {
        _codeError = codeError;
        _nameError = nameError;
      });
      return;
    }

    Navigator.pop(context, (code: code, name: name));
  }
}
