import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../models/import_conflict.dart';
import '../../../providers/import_export/import_provider.dart';
import '../../../widgets/fluent/fluent_widgets.dart';

/// Dialog for resolving import conflicts
class ImportConflictDialog extends ConsumerStatefulWidget {
  final List<ImportConflict> conflicts;
  final int initialIndex;

  const ImportConflictDialog({
    super.key,
    required this.conflicts,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<ImportConflictDialog> createState() =>
      _ImportConflictDialogState();
}

class _ImportConflictDialogState extends ConsumerState<ImportConflictDialog> {
  late int _currentIndex;
  ConflictResolution? _selectedResolution;
  bool _applyToAll = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  ImportConflict get _currentConflict => widget.conflicts[_currentIndex];

  void _applyResolution() {
    if (_selectedResolution == null) return;

    if (_applyToAll) {
      // Apply to all remaining conflicts
      ref.read(conflictResolutionsDataProvider.notifier)
          .setDefaultResolution(_selectedResolution!);

      for (int i = _currentIndex; i < widget.conflicts.length; i++) {
        final conflict = widget.conflicts[i];
        ref.read(conflictResolutionsDataProvider.notifier)
            .setResolution(conflict.key, _selectedResolution!);
      }

      Navigator.of(context).pop(true);
    } else {
      // Apply to current conflict only
      ref.read(conflictResolutionsDataProvider.notifier)
          .setResolution(_currentConflict.key, _selectedResolution!);

      // Move to next conflict or close if last
      if (_currentIndex < widget.conflicts.length - 1) {
        setState(() {
          _currentIndex++;
          _selectedResolution = null;
          _applyToAll = false;
        });
      } else {
        Navigator.of(context).pop(true);
      }
    }
  }

  void _previous() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _selectedResolution = null;
        _applyToAll = false;
      });
    }
  }

  void _next() {
    if (_currentIndex < widget.conflicts.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedResolution = null;
        _applyToAll = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(FluentIcons.arrow_sync_24_regular),
          const SizedBox(width: 12),
          const Text('Translation Conflict'),
          const Spacer(),
          Text(
            'Conflict ${_currentIndex + 1} of ${widget.conflicts.length}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      content: SizedBox(
        width: 800,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Key display
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.document_24_regular,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentConflict.key,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontFamily: 'monospace',
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Warning if source text differs
            if (_currentConflict.sourceTextDiffers) ...[
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Row(
                  children: [
                    const Icon(FluentIcons.warning_24_regular, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Warning: Source text differs between existing and imported versions',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Side-by-side comparison
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Existing translation
                  Expanded(
                    child: _buildTranslationPanel(
                      'Existing Translation',
                      _currentConflict.existingData,
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Imported translation
                  Expanded(
                    child: _buildTranslationPanel(
                      'Imported Translation',
                      _currentConflict.importedData,
                      Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Resolution options
            _buildResolutionOptions(),
          ],
        ),
      ),
      actions: [
        if (_currentIndex > 0)
          FluentTextButton(
            onPressed: _previous,
            icon: const Icon(FluentIcons.arrow_left_24_regular),
            child: const Text('Previous'),
          ),
        if (_currentIndex < widget.conflicts.length - 1)
          FluentTextButton(
            onPressed: _next,
            icon: const Icon(FluentIcons.arrow_right_24_regular),
            child: const Text('Next'),
          ),
        FluentTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel Import'),
        ),
        FluentButton(
          onPressed: _selectedResolution != null ? _applyResolution : null,
          icon: const Icon(FluentIcons.checkmark_24_regular),
          child: Text(_applyToAll ? 'Apply to All' : 'Apply'),
        ),
      ],
    );
  }

  Widget _buildTranslationPanel(
    String title,
    ConflictTranslation data,
    Color accentColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        border: Border.all(color: accentColor, width: 2),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data.sourceText != null) ...[
                    Text(
                      'Source Text:',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Text(
                        data.sourceText!,
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (data.translatedText != null) ...[
                    Text(
                      'Translated Text:',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Text(
                        data.translatedText!,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (data.status != null) ...[
                    _buildInfoRow('Status:', data.status!),
                    const SizedBox(height: 8),
                  ],
                  if (data.updatedAt != null) ...[
                    _buildInfoRow(
                      'Last Updated:',
                      DateTime.fromMillisecondsSinceEpoch(data.updatedAt! * 1000)
                          .toString()
                          .split('.')[0],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (data.changedBy != null) ...[
                    _buildInfoRow('Changed By:', data.changedBy!),
                    const SizedBox(height: 8),
                  ],
                  if (data.notes != null && data.notes!.isNotEmpty) ...[
                    Text(
                      'Notes:',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Text(data.notes!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _buildResolutionOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose Action:',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildResolutionButton(
                ConflictResolution.keepExisting,
                'Keep Existing',
                FluentIcons.checkmark_24_regular,
                Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildResolutionButton(
                ConflictResolution.useImported,
                'Use Imported',
                FluentIcons.arrow_import_24_regular,
                Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildResolutionButton(
                ConflictResolution.merge,
                'Merge',
                FluentIcons.arrow_sync_24_regular,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          title: const Text('Apply to all remaining conflicts'),
          value: _applyToAll,
          onChanged: (value) {
            setState(() {
              _applyToAll = value ?? false;
            });
          },
        ),
      ],
    );
  }

  Widget _buildResolutionButton(
    ConflictResolution resolution,
    String label,
    IconData icon,
    Color color,
  ) {
    final isSelected = _selectedResolution == resolution;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedResolution = resolution;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
            border: Border.all(
              color: isSelected ? color : Theme.of(context).colorScheme.outline,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? color : null,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? color : null,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
