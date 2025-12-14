import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../models/domain/ignored_source_text.dart';

/// Dialog for adding or editing an ignored source text
class IgnoredSourceTextEditorDialog extends StatefulWidget {
  /// Existing text to edit, or null for creating a new one
  final IgnoredSourceText? existingText;

  const IgnoredSourceTextEditorDialog({
    super.key,
    this.existingText,
  });

  @override
  State<IgnoredSourceTextEditorDialog> createState() =>
      _IgnoredSourceTextEditorDialogState();
}

class _IgnoredSourceTextEditorDialogState
    extends State<IgnoredSourceTextEditorDialog> {
  late TextEditingController _textController;
  final _formKey = GlobalKey<FormState>();

  bool get _isEditing => widget.existingText != null;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.existingText?.sourceText ?? '',
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isEditing
                ? FluentIcons.edit_24_regular
                : FluentIcons.add_circle_24_regular,
            size: 24,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(_isEditing ? 'Edit Ignored Text' : 'Add Ignored Text'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter a source text that should be skipped during translation. '
                'Matching is case-insensitive.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _textController,
                maxLines: 1,
                decoration: InputDecoration(
                  hintText: 'e.g., placeholder, [hidden], etc.',
                  hintStyle: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a source text';
                  }
                  return null;
                },
                autofocus: true,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              _buildHelpSection(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: Icon(
            _isEditing
                ? FluentIcons.save_24_regular
                : FluentIcons.add_24_regular,
            size: 18,
          ),
          label: Text(_isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Widget _buildHelpSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.lightbulb_24_regular,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Info',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• Units matching these texts are excluded from translation\n'
            '• Bracketed texts like [unit_name] are automatically skipped\n'
            '• Use this for custom placeholders specific to your mods\n'
            '• Changes take effect immediately for new translations',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                ),
          ),
        ],
      ),
    );
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _textController.text.trim());
    }
  }
}
