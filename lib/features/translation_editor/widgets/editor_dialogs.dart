import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../widgets/fluent/fluent_widgets.dart';

/// Dialog utilities for translation editor screen
///
/// Provides reusable dialogs for various editor operations:
/// - Feature not implemented notifications
/// - No selection warnings
/// - Provider setup prompts
/// - Translation confirmations
/// - Error messages
class EditorDialogs {
  const EditorDialogs._();

  static void showFeatureNotImplemented(
    BuildContext context,
    String feature,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(FluentIcons.info_24_regular),
            const SizedBox(width: 8),
            Text(feature),
          ],
        ),
        content: const Text(
          'This feature will be fully implemented in the next phase.\n\n'
          'Current implementation provides the UI structure and event handlers.',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void showNoSelectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.warning_24_regular, color: Colors.orange),
            SizedBox(width: 8),
            Text('No Selection'),
          ],
        ),
        content: const Text(
          'Please select one or more translation units to translate.',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void showNoUntranslatedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.info_24_regular, color: Colors.blue),
            SizedBox(width: 8),
            Text('No Untranslated Units'),
          ],
        ),
        content: const Text(
          'All units in this project language are already translated.',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void showAllTranslatedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.info_24_regular, color: Colors.blue),
            SizedBox(width: 8),
            Text('All Selected Units Translated'),
          ],
        ),
        content: const Text(
          'All selected units are already translated.',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void showErrorDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(FluentIcons.error_circle_24_regular, color: Colors.red),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static Future<bool> showTranslateConfirmationDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(FluentIcons.translate_24_regular),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FluentButton(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(FluentIcons.translate_24_regular),
            child: const Text('Translate'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  static void showInfoDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(FluentIcons.info_24_regular, color: Colors.blue),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static Future<String?> showExportDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.arrow_export_24_regular),
            SizedBox(width: 8),
            Text('Export Translations'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select export format:'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(FluentIcons.document_24_regular),
              title: const Text('.pack (Total War Mod)'),
              subtitle: const Text('Game-ready package file'),
              onTap: () => Navigator.of(context).pop('pack'),
            ),
            ListTile(
              leading: const Icon(FluentIcons.table_24_regular),
              title: const Text('CSV'),
              subtitle: const Text('Comma-separated values'),
              onTap: () => Navigator.of(context).pop('csv'),
            ),
            ListTile(
              leading: const Icon(FluentIcons.document_table_24_regular),
              title: const Text('Excel'),
              subtitle: const Text('Microsoft Excel spreadsheet'),
              onTap: () => Navigator.of(context).pop('excel'),
            ),
          ],
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    return result;
  }
}
