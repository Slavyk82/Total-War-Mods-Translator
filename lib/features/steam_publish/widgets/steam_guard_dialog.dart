import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Token-themed popup for entering a Steam Guard authentication code.
class SteamGuardDialog extends StatefulWidget {
  const SteamGuardDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SteamGuardDialog(),
    );
  }

  @override
  State<SteamGuardDialog> createState() => _SteamGuardDialogState();
}

class _SteamGuardDialogState extends State<SteamGuardDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_controller.text.trim().toUpperCase());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return TokenDialog(
      icon: FluentIcons.shield_keyhole_24_regular,
      title: 'Steam Guard',
      width: 420,
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter the 5-character code from your Steam Mobile app.\n'
              'Open the Steam app → Steam Guard → use the rotating code shown on screen.',
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.textDim,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Note: approving the push notification is not enough — steamcmd requires the code.',
              style: tokens.fontBody.copyWith(
                fontSize: 11.5,
                color: tokens.textFaint,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _controller,
              style: tokens.fontBody
                  .copyWith(fontSize: 13, color: tokens.text),
              decoration: _decoration(tokens),
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                LengthLimitingTextInputFormatter(5),
              ],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Code is required';
                }
                if (value.trim().length < 5) {
                  return 'Code must be 5 characters';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        SmallTextButton(
          label: 'Cancel',
          onTap: () => Navigator.of(context).pop(null),
        ),
        SmallTextButton(
          label: 'Verify',
          icon: FluentIcons.checkmark_24_regular,
          filled: true,
          onTap: _submit,
        ),
      ],
    );
  }

  InputDecoration _decoration(TwmtThemeTokens tokens) {
    return InputDecoration(
      labelText: 'Steam Guard Code',
      labelStyle:
          tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
      floatingLabelStyle:
          tokens.fontBody.copyWith(fontSize: 12, color: tokens.accent),
      hintText: 'XXXXX',
      hintStyle:
          tokens.fontBody.copyWith(fontSize: 13, color: tokens.textFaint),
      prefixIcon: Icon(
        FluentIcons.key_24_regular,
        color: tokens.textDim,
        size: 18,
      ),
      filled: true,
      fillColor: tokens.panel2,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.err),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.err),
      ),
      errorStyle:
          tokens.fontBody.copyWith(fontSize: 11.5, color: tokens.err),
    );
  }
}
