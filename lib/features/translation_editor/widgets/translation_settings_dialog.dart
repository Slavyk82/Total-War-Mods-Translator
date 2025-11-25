import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Dialog for configuring translation batch settings
class TranslationSettingsDialog extends StatefulWidget {
  const TranslationSettingsDialog({
    super.key,
    required this.currentUnitsPerBatch,
    required this.currentParallelBatches,
  });

  final int currentUnitsPerBatch;
  final int currentParallelBatches;

  @override
  State<TranslationSettingsDialog> createState() => _TranslationSettingsDialogState();
}

class _TranslationSettingsDialogState extends State<TranslationSettingsDialog> {
  late TextEditingController _unitsController;
  late TextEditingController _parallelController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _unitsController = TextEditingController(
      text: widget.currentUnitsPerBatch.toString(),
    );
    _parallelController = TextEditingController(
      text: widget.currentParallelBatches.toString(),
    );
  }

  @override
  void dispose() {
    _unitsController.dispose();
    _parallelController.dispose();
    super.dispose();
  }

  bool _validate() {
    final units = int.tryParse(_unitsController.text);
    final parallel = int.tryParse(_parallelController.text);

    if (units == null || units < 10 || units > 500) {
      setState(() {
        _errorMessage = 'Units per batch must be between 10 and 500';
      });
      return false;
    }

    if (parallel == null || parallel < 1 || parallel > 20) {
      setState(() {
        _errorMessage = 'Parallel batches must be between 1 and 20';
      });
      return false;
    }

    setState(() {
      _errorMessage = null;
    });
    return true;
  }

  void _save() {
    if (_validate()) {
      Navigator.of(context).pop({
        'unitsPerBatch': int.parse(_unitsController.text),
        'parallelBatches': int.parse(_parallelController.text),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  FluentIcons.settings_24_regular,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Translation Settings',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Units per batch
            Text(
              'Units per batch',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _unitsController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: 'Enter number (10-500)',
                helperText: 'Number of translation units to send in each LLM request',
                helperMaxLines: 2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (_) => _validate(),
            ),
            const SizedBox(height: 20),

            // Parallel batches
            Text(
              'Parallel batches',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _parallelController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: 'Enter number (1-20)',
                helperText: 'Number of simultaneous LLM requests (higher = faster but more API load)',
                helperMaxLines: 2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (_) => _validate(),
            ),

            // Error message
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.warning_24_regular,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Info box
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    FluentIcons.info_24_regular,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recommended: 50-100 units per batch, 3-5 parallel batches for optimal speed.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}

/// Show the translation settings dialog
Future<Map<String, int>?> showTranslationSettingsDialog(
  BuildContext context, {
  required int currentUnitsPerBatch,
  required int currentParallelBatches,
}) {
  return showDialog<Map<String, int>>(
    context: context,
    builder: (context) => TranslationSettingsDialog(
      currentUnitsPerBatch: currentUnitsPerBatch,
      currentParallelBatches: currentParallelBatches,
    ),
  );
}

