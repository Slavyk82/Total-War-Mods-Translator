import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import '../providers/glossary_providers.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';

/// Dialog for adding or editing a glossary entry
class GlossaryEntryEditorDialog extends ConsumerStatefulWidget {
  final String glossaryId;
  final String? targetLanguageCode;
  final GlossaryEntry? entry;

  const GlossaryEntryEditorDialog({
    super.key,
    required this.glossaryId,
    this.targetLanguageCode,
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
  bool _caseSensitive = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _sourceTermController = TextEditingController(text: widget.entry?.sourceTerm ?? '');
    _targetTermController = TextEditingController(text: widget.entry?.targetTerm ?? '');
    _notesController = TextEditingController(text: widget.entry?.notes ?? '');
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

                // Notes for LLM context
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (LLM context)',
                    hintText: 'e.g., "Bretonnian is not gendered in English but can be Bretonnien/Bretonnienne in French"',
                    border: OutlineInputBorder(),
                    helperText: 'Optional hints for the translator about gender, context, or usage',
                    helperMaxLines: 2,
                  ),
                  maxLines: 3,
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
              ? const FluentSpinner(size: 16, strokeWidth: 2)
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _saveEntry() async {
    print('[GlossaryEntryEditor._saveEntry] Starting save operation');
    
    if (!_formKey.currentState!.validate()) {
      print('[GlossaryEntryEditor._saveEntry] Form validation failed');
      return;
    }

    if (!mounted) {
      print('[GlossaryEntryEditor._saveEntry] Widget not mounted, aborting');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Get target language code from entry, widget prop, or default
      final targetLanguageCode = widget.entry?.targetLanguageCode 
          ?? widget.targetLanguageCode 
          ?? 'fr';

      final notes = _notesController.text.trim().isNotEmpty 
          ? _notesController.text.trim() 
          : null;

      print('[GlossaryEntryEditor._saveEntry] Calling provider.save with:');
      print('  glossaryId: ${widget.glossaryId}');
      print('  targetLanguageCode: $targetLanguageCode');
      print('  sourceTerm: "${_sourceTermController.text.trim()}"');
      print('  targetTerm: "${_targetTermController.text.trim()}"');
      print('  caseSensitive: $_caseSensitive');
      print('  notes: ${notes != null ? "\"$notes\"" : "null"}');
      
      await ref.read(glossaryEntryEditorProvider.notifier).save(
            glossaryId: widget.glossaryId,
            targetLanguageCode: targetLanguageCode,
            sourceTerm: _sourceTermController.text.trim(),
            targetTerm: _targetTermController.text.trim(),
            caseSensitive: _caseSensitive,
            notes: notes,
          );

      print('[GlossaryEntryEditor._saveEntry] Provider.save completed successfully');

      if (!mounted) {
        print('[GlossaryEntryEditor._saveEntry] Widget not mounted after save, returning');
        return;
      }

      // Refresh entries and statistics
      print('[GlossaryEntryEditor._saveEntry] Invalidating providers...');
      ref.invalidate(glossaryEntriesProvider);
      ref.invalidate(glossaryStatisticsProvider);
      print('[GlossaryEntryEditor._saveEntry] Providers invalidated');

      print('[GlossaryEntryEditor._saveEntry] Closing dialog and showing success toast');
      Navigator.of(context).pop();
      FluentToast.success(
        context,
        widget.entry != null
            ? 'Entry updated successfully'
            : 'Entry added successfully',
      );
      print('[GlossaryEntryEditor._saveEntry] Save operation completed successfully');
    } catch (e, stackTrace) {
      print('[GlossaryEntryEditor._saveEntry] ERROR: Exception caught: $e');
      print('[GlossaryEntryEditor._saveEntry] Stack trace: $stackTrace');
      if (!mounted) return;
      FluentToast.error(context, 'Error saving entry: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}
