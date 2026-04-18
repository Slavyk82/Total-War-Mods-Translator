import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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
                    'Add Custom Language',
                    style: tokens.fontDisplay.copyWith(
                      fontSize: 18,
                      color: tokens.text,
                      fontStyle: tokens.fontDisplayItalic
                          ? FontStyle.italic
                          : FontStyle.normal,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Add a custom language that will be available for translation projects.',
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.textDim,
                ),
              ),
              const SizedBox(height: 20),
              // Language code field
              LabeledField(
                label: 'Language code (ISO 639-1, 2-3 letters)',
                child: TokenTextField(
                  controller: _codeController,
                  hint: 'e.g., pl, ko, ja',
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
                label: 'Language name',
                child: TokenTextField(
                  controller: _nameController,
                  hint: 'e.g., Polish, Korean, Japanese',
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
                    label: 'Cancel',
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  SmallTextButton(
                    label: 'Add',
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
              'Custom languages can be deleted later. System languages (English, French, etc.) cannot be modified.',
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
      codeError = 'Language code is required';
    } else if (code.length < 2) {
      codeError = 'Code must be at least 2 characters';
    } else if (!RegExp(r'^[a-zA-Z]+$').hasMatch(code)) {
      codeError = 'Code must contain only letters';
    } else if (code.length > 5) {
      codeError = 'Code must be at most 5 characters';
    }

    if (name.isEmpty) {
      nameError = 'Language name is required';
    } else if (name.length > 50) {
      nameError = 'Name must be at most 50 characters';
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
