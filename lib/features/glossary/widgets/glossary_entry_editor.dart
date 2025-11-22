import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import '../providers/glossary_providers.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Dialog for adding or editing a glossary entry
class GlossaryEntryEditorDialog extends ConsumerStatefulWidget {
  final String glossaryId;
  final GlossaryEntry? entry;

  const GlossaryEntryEditorDialog({
    super.key,
    required this.glossaryId,
    this.entry,
  });

  @override
  ConsumerState<GlossaryEntryEditorDialog> createState() =>
      _GlossaryEntryEditorDialogState();
}

class _GlossaryEntryEditorDialogState
    extends ConsumerState<GlossaryEntryEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _sourceTermController;
  late TextEditingController _targetTermController;
  late TextEditingController _notesController;
  String? _selectedCategory;
  bool _caseSensitive = false;
  bool _isSaving = false;

  // Predefined categories
  static const List<String> _categories = [
    'UI',
    'Units',
    'Factions',
    'Locations',
    'Items',
    'Abilities',
    'Buildings',
    'Technologies',
    'Characters',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _sourceTermController = TextEditingController(text: widget.entry?.sourceTerm ?? '');
    _targetTermController = TextEditingController(text: widget.entry?.targetTerm ?? '');
    _notesController = TextEditingController(text: widget.entry?.notes ?? '');
    _selectedCategory = widget.entry?.category;
    _caseSensitive = widget.entry?.caseSensitive ?? false;
  }

  @override
  void dispose() {
    _sourceTermController.dispose();
    _targetTermController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.entry != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Entry' : 'Add Entry'),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source Term
                TextFormField(
                  controller: _sourceTermController,
                  decoration: const InputDecoration(
                    labelText: 'Source Term *',
                    hintText: 'Enter the source term',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 200,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Source term is required';
                    }
                    if (value.trim().length > 200) {
                      return 'Source term must be 200 characters or less';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Target Term
                TextFormField(
                  controller: _targetTermController,
                  decoration: const InputDecoration(
                    labelText: 'Target Term *',
                    hintText: 'Enter the target term',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 200,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Target term is required';
                    }
                    if (value.trim().length > 200) {
                      return 'Target term must be 200 characters or less';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Category
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories.map((category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Notes
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Optional notes or usage guidelines',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 4,
                  maxLength: 500,
                ),
                const SizedBox(height: 16),

                // Case Sensitive checkbox
                CheckboxListTile(
                  title: const Text('Case Sensitive'),
                  subtitle: const Text(
                    'Match this term with exact case (e.g., "Emperor" vs "emperor")',
                  ),
                  value: _caseSensitive,
                  onChanged: (value) {
                    setState(() {
                      _caseSensitive = value ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        FluentTextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FluentTextButton(
          onPressed: _isSaving ? null : _saveEntry,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _saveEntry() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Get target language code from the entry or use default
      final targetLanguageCode = widget.entry?.targetLanguageCode ?? 'fr';

      await ref.read(glossaryEntryEditorProvider.notifier).save(
            glossaryId: widget.glossaryId,
            targetLanguageCode: targetLanguageCode,
            sourceTerm: _sourceTermController.text.trim(),
            targetTerm: _targetTermController.text.trim(),
            category: _selectedCategory,
            caseSensitive: _caseSensitive,
            notes: _notesController.text.trim().isNotEmpty
                ? _notesController.text.trim()
                : null,
          );

      if (mounted) {
        Navigator.of(context).pop();
        FluentToast.success(
          context,
          widget.entry != null
              ? 'Entry updated successfully'
              : 'Entry added successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Error saving entry: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}
