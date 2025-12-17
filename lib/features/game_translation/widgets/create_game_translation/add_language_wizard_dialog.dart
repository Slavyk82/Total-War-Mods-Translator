import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Result returned from the add language wizard dialog
class AddLanguageWizardResult {
  final String code;
  final String name;
  final bool setAsDefault;

  const AddLanguageWizardResult({
    required this.code,
    required this.name,
    required this.setAsDefault,
  });
}

/// Dialog for adding a custom language from the game translation wizard.
///
/// Similar to [AddCustomLanguageDialog] but includes an option to set
/// the new language as the default for mod translations.
class AddLanguageWizardDialog extends StatefulWidget {
  const AddLanguageWizardDialog({super.key});

  @override
  State<AddLanguageWizardDialog> createState() =>
      _AddLanguageWizardDialogState();
}

class _AddLanguageWizardDialogState extends State<AddLanguageWizardDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _setAsDefault = false;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            FluentIcons.add_circle_24_regular,
            size: 24,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Text('Add Custom Language'),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add a custom language that will be available for translation projects.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
                  fillColor: theme.colorScheme.surface,
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
                  fillColor: theme.colorScheme.surface,
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
              const SizedBox(height: 16),
              // Set as default checkbox
              _buildDefaultLanguageOption(theme),
              const SizedBox(height: 12),
              _buildInfoSection(theme),
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

  Widget _buildDefaultLanguageOption(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: _setAsDefault,
            onChanged: (value) {
              setState(() => _setAsDefault = value ?? false);
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set as default language',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This language will become the default target language for all new mod translation projects.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
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
              'Custom languages can be deleted later from Settings. System languages (English, French, etc.) cannot be modified.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(
        context,
        AddLanguageWizardResult(
          code: _codeController.text.trim(),
          name: _nameController.text.trim(),
          setAsDefault: _setAsDefault,
        ),
      );
    }
  }
}
