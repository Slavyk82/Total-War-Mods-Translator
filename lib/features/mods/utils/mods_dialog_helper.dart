import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Helper class for displaying dialogs related to mods screen
///
/// Extracts dialog workflows from the ModsScreen to maintain
/// single responsibility principle. All dialogs follow Fluent Design.
class ModsDialogHelper {
  /// Shows a warning dialog about importing a local pack file
  ///
  /// Returns true if the user confirms they want to proceed,
  /// false otherwise.
  static Future<bool> showLocalPackWarning(BuildContext context) async {
    final theme = Theme.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  FluentIcons.warning_24_regular,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 12),
                const Text('Local Pack File'),
              ],
            ),
            content: const SizedBox(
              width: 450,
              child: Text(
                'This pack file is not linked to the Steam Workshop.\n\n'
                'The mod will not be automatically updated when the author releases a new version. '
                'You will need to manually reimport the pack file to get updates.',
              ),
            ),
            actions: [
              FluentTextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FluentButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Import Anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Shows a dialog to get the project name for a local pack
  ///
  /// [defaultName] is pre-filled in the text field (usually the pack filename).
  /// Returns the entered name, or null if cancelled.
  static Future<String?> showLocalPackNameDialog(
    BuildContext context,
    String defaultName,
  ) async {
    final controller = TextEditingController(text: defaultName);
    final theme = Theme.of(context);

    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              FluentIcons.edit_24_regular,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            const Text('Project Name'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Enter project name',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          FluentButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create Project'),
          ),
        ],
      ),
    );
  }
}
