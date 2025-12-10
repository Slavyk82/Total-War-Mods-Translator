import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Dialog for adding a custom language
///
/// Returns a record (code, name) if the user confirms, null otherwise.
class AddCustomLanguageDialog extends StatefulWidget {
  const AddCustomLanguageDialog({super.key});

  @override
  State<AddCustomLanguageDialog> createState() =>
      _AddCustomLanguageDialogState();
}

class _AddCustomLanguageDialogState extends State<AddCustomLanguageDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            FluentIcons.add_circle_24_regular,
            size: 24,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Text('Add Custom Language'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add a custom language that will be available for translation projects.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                    ),
              ),
              const SizedBox(height: 20),
              // Language code field
              TextFormField(
                controller: _codeController,
                decoration: InputDecoration(
                  labelText: 'Language Code',
                  hintText: 'e.g., pl, ko, ja',
                  helperText: 'ISO 639-1 code (2-3 characters)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  prefixIcon: const Icon(FluentIcons.code_24_regular),
                ),
                textCapitalization: TextCapitalization.none,
                maxLength: 5,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Language code is required';
                  }
                  if (value.trim().length < 2) {
                    return 'Code must be at least 2 characters';
                  }
                  if (!RegExp(r'^[a-zA-Z]+$').hasMatch(value.trim())) {
                    return 'Code must contain only letters';
                  }
                  return null;
                },
                autofocus: true,
              ),
              const SizedBox(height: 16),
              // Language name field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Language Name',
                  hintText: 'e.g., Polish, Korean, Japanese',
                  helperText: 'Display name for this language',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  prefixIcon: const Icon(FluentIcons.local_language_24_regular),
                ),
                textCapitalization: TextCapitalization.words,
                maxLength: 50,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Language name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildInfoSection(),
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
          icon: const Icon(FluentIcons.add_24_regular, size: 18),
          label: const Text('Add'),
        ),
      ],
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FluentIcons.info_24_regular,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Custom languages can be deleted later. System languages (English, French, etc.) cannot be modified.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, (
        code: _codeController.text.trim(),
        name: _nameController.text.trim(),
      ));
    }
  }
}
