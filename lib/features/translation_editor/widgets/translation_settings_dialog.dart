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
  late bool _isAutoMode;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _isAutoMode = widget.currentUnitsPerBatch == 0;
    _unitsController = TextEditingController(
      text: _isAutoMode ? '100' : widget.currentUnitsPerBatch.toString(),
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
    final parallel = int.tryParse(_parallelController.text);

    // Only validate units if not in auto mode
    if (!_isAutoMode) {
      final units = int.tryParse(_unitsController.text);
      if (units == null || units < 1 || units > 1000) {
        setState(() {
          _errorMessage = 'Units per batch must be between 1 and 1000';
        });
        return false;
      }
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
        // 0 = auto mode
        'unitsPerBatch': _isAutoMode ? 0 : int.parse(_unitsController.text),
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Units per batch',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Auto mode toggle
                Text(
                  'Auto',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _isAutoMode
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 4),
                Switch(
                  value: _isAutoMode,
                  onChanged: (value) {
                    setState(() {
                      _isAutoMode = value;
                      _errorMessage = null;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _unitsController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              enabled: !_isAutoMode,
              decoration: InputDecoration(
                hintText: _isAutoMode ? 'Calculated automatically' : 'Enter number (1-1000)',
                helperText: _isAutoMode
                    ? 'Batch size will be calculated based on token limits'
                    : 'Maximum number of translation units per LLM request',
                helperMaxLines: 2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: _isAutoMode,
                fillColor: _isAutoMode
                    ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                    : null,
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
                      _isAutoMode
                          ? 'Auto mode calculates optimal batch size based on token limits for each request.'
                          : 'Recommended: 3-5 parallel batches for optimal speed. Use Auto mode for best results. If there are a lot of timeouts error, force a lower batch size like 10 units per batch and even 1 but it will consume more tokens.',
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

