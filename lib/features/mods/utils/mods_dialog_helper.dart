import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Token-themed helpers for dialogs related to the mods screen.
class ModsDialogHelper {
  /// Shows a warning dialog about importing a local pack file.
  ///
  /// Returns `true` if the user confirms, `false` otherwise.
  static Future<bool> showLocalPackWarning(BuildContext context) {
    return TokenDialog.showConfirm(
      context,
      title: 'Local Pack File',
      message:
          'This pack file is not linked to the Steam Workshop.\n\n'
          'The mod will not be automatically updated when the author releases '
          'a new version. You will need to manually reimport the pack file to '
          'get updates.',
      icon: FluentIcons.warning_24_regular,
      confirmLabel: 'Import Anyway',
      destructive: true,
    );
  }

  /// Shows a dialog to get the project name for a local pack.
  ///
  /// Returns the entered name, or null if cancelled.
  static Future<String?> showLocalPackNameDialog(
    BuildContext context,
    String defaultName,
  ) async {
    final controller = TextEditingController(text: defaultName);

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        return TokenDialog(
          icon: FluentIcons.edit_24_regular,
          title: 'Project Name',
          width: 440,
          body: TextField(
            controller: controller,
            style: tokens.fontBody
                .copyWith(fontSize: 13, color: tokens.text),
            decoration: _decoration(tokens),
            autofocus: true,
            onSubmitted: (value) =>
                Navigator.of(ctx).pop(value.trim()),
          ),
          actions: [
            SmallTextButton(
              label: 'Cancel',
              onTap: () => Navigator.of(ctx).pop(null),
            ),
            SmallTextButton(
              label: 'Create Project',
              icon: FluentIcons.checkmark_24_regular,
              filled: true,
              onTap: () =>
                  Navigator.of(ctx).pop(controller.text.trim()),
            ),
          ],
        );
      },
    );
  }

  static InputDecoration _decoration(TwmtThemeTokens tokens) {
    return InputDecoration(
      labelText: 'Name',
      labelStyle:
          tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
      floatingLabelStyle:
          tokens.fontBody.copyWith(fontSize: 12, color: tokens.accent),
      hintText: 'Enter project name',
      hintStyle:
          tokens.fontBody.copyWith(fontSize: 13, color: tokens.textFaint),
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
    );
  }
}
