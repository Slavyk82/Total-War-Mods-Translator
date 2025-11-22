import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Collection of confirmation dialogs for destructive batch operations
///
/// Provides standardized confirmation dialogs with:
/// - Clear warning messages
/// - Optional checkboxes for additional options
/// - Destructive action styling (red buttons)
/// - Cancel option

/// Show confirmation dialog for clearing translations
///
/// Returns true if user confirms, false if cancelled
/// Also returns whether to keep validated translations
Future<ClearTranslationsResult?> showClearTranslationsConfirmation({
  required BuildContext context,
  required int count,
}) async {
  bool keepValidated = true;

  return showDialog<ClearTranslationsResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        icon: Icon(
          FluentIcons.warning_24_regular,
          size: 48,
          color: Colors.orange[700],
        ),
        title: Text('Clear $count Translations?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will clear the translated text for $count unit${count == 1 ? '' : 's'}. '
              'The source text and metadata will be preserved.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: keepValidated,
                  onChanged: (value) => setState(() => keepValidated = value!),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Keep validated translations',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          FluentButton(
            onPressed: () => Navigator.of(context).pop(
              ClearTranslationsResult(keepValidated: keepValidated),
            ),
            backgroundColor: Colors.orange[700],
            icon: const Icon(FluentIcons.eraser_24_regular),
            child: const Text('Clear'),
          ),
        ],
      ),
    ),
  );
}

/// Result of clear translations confirmation
class ClearTranslationsResult {
  final bool keepValidated;

  const ClearTranslationsResult({required this.keepValidated});
}

/// Show confirmation dialog for deleting units
///
/// Returns true if user confirms, false if cancelled
Future<bool> showDeleteUnitsConfirmation({
  required BuildContext context,
  required int count,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        FluentIcons.error_circle_24_regular,
        size: 48,
        color: Colors.red[700],
      ),
      title: Text('Delete $count Unit${count == 1 ? '' : 's'}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This will permanently delete $count translation unit${count == 1 ? '' : 's'} '
            'and all associated data.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[300]!),
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.warning_24_regular,
                  size: 20,
                  color: Colors.red[700],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This action cannot be undone',
                    style: TextStyle(
                      color: Colors.red[900],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        FluentTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FluentButton(
          onPressed: () => Navigator.of(context).pop(true),
          backgroundColor: Colors.red[700],
          icon: const Icon(FluentIcons.delete_24_regular),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  return result ?? false;
}

/// Show confirmation dialog for overwriting translations
///
/// Returns the selected action or null if cancelled
Future<OverwriteAction?> showOverwriteConfirmation({
  required BuildContext context,
  required int count,
  required String operation,
}) async {
  return showDialog<OverwriteAction>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        FluentIcons.warning_24_regular,
        size: 48,
        color: Colors.orange[700],
      ),
      title: Text('Overwrite Existing Translations?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count unit${count == 1 ? '' : 's'} already ${count == 1 ? 'has' : 'have'} '
            '${count == 1 ? 'a' : ''} translation${count == 1 ? '' : 's'}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'What would you like to do?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        FluentTextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FluentTextButton(
          onPressed: () => Navigator.of(context).pop(OverwriteAction.skipExisting),
          child: const Text('Skip Existing'),
        ),
        FluentButton(
          onPressed: () => Navigator.of(context).pop(OverwriteAction.overwrite),
          backgroundColor: Colors.orange[700],
          icon: const Icon(FluentIcons.arrow_sync_24_regular),
          child: const Text('Overwrite'),
        ),
      ],
    ),
  );
}

/// Action to take when encountering existing translations
enum OverwriteAction {
  overwrite,
  skipExisting,
}

/// Show confirmation dialog for batch translation
///
/// Confirms that user wants to start translating the selected units
Future<bool> showBatchTranslateConfirmation({
  required BuildContext context,
  required int count,
  required String provider,
  required String model,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        FluentIcons.translate_24_regular,
        size: 48,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('Start Batch Translation?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This will translate $count unit${count == 1 ? '' : 's'} using:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _buildInfoRow(context, 'Provider', _capitalizeFirst(provider)),
          _buildInfoRow(context, 'Model', model),
          _buildInfoRow(context, 'Units', '$count'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.info_24_regular,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This may take several minutes depending on the number of units.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        FluentTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FluentButton(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(FluentIcons.translate_24_regular),
          child: const Text('Start Translation'),
        ),
      ],
    ),
  );

  return result ?? false;
}

/// Show confirmation dialog for marking units as validated
Future<bool> showMarkValidatedConfirmation({
  required BuildContext context,
  required int count,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        FluentIcons.checkmark_circle_24_regular,
        size: 48,
        color: Colors.green[700],
      ),
      title: Text('Mark $count Unit${count == 1 ? '' : 's'} as Validated?'),
      content: Text(
        'This will change the status of $count unit${count == 1 ? '' : 's'} to "Validated". '
        'Validated translations are considered final and ready for export.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      actions: [
        FluentTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FluentButton(
          onPressed: () => Navigator.of(context).pop(true),
          backgroundColor: Colors.green[700],
          icon: const Icon(FluentIcons.checkmark_24_regular),
          child: const Text('Mark as Validated'),
        ),
      ],
    ),
  );

  return result ?? false;
}

/// Show progress dialog for long-running operations
///
/// This is a non-dismissible dialog that shows progress
Future<T?> showProgressDialog<T>({
  required BuildContext context,
  required String title,
  required Future<T> Function() operation,
}) async {
  // Show the dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(title),
          ],
        ),
      ),
    ),
  );

  try {
    // Perform the operation
    final result = await operation();

    // Close the dialog
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    return result;
  } catch (e) {
    // Close the dialog
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    // Show error
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            FluentIcons.error_circle_24_regular,
            size: 48,
            color: Colors.red[700],
          ),
          title: const Text('Operation Failed'),
          content: Text('An error occurred: ${e.toString()}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    return null;
  }
}

// Helper function to build info rows
Widget _buildInfoRow(BuildContext context, String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

String _capitalizeFirst(String text) {
  if (text.isEmpty) return text;
  return text[0].toUpperCase() + text.substring(1);
}
