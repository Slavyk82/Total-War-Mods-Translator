import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../providers/glossary_providers.dart';
import '../../../providers/shared/logging_providers.dart';

/// Token-themed popup for adding or editing a glossary entry.
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
    _sourceTermController =
        TextEditingController(text: widget.entry?.sourceTerm ?? '');
    _targetTermController =
        TextEditingController(text: widget.entry?.targetTerm ?? '');
    _notesController =
        TextEditingController(text: widget.entry?.notes ?? '');
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
    final tokens = context.tokens;
    final isEditing = widget.entry != null;

    return TokenDialog(
      icon: isEditing
          ? FluentIcons.edit_24_regular
          : FluentIcons.add_24_regular,
      title: isEditing ? 'Edit Entry' : 'Add Entry',
      width: 620,
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _sourceTermController,
                style: tokens.fontBody
                    .copyWith(fontSize: 13, color: tokens.text),
                decoration: _decoration(
                  tokens,
                  label: 'Source Term *',
                  hint: 'Enter the source term',
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _targetTermController,
                style: tokens.fontBody
                    .copyWith(fontSize: 13, color: tokens.text),
                decoration: _decoration(
                  tokens,
                  label: 'Target Term *',
                  hint: 'Enter the target term',
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                style: tokens.fontBody
                    .copyWith(fontSize: 13, color: tokens.text),
                decoration: _decoration(
                  tokens,
                  label: 'Notes (LLM context)',
                  hint:
                      'e.g., "Bretonnian is not gendered in English but can be Bretonnien/Bretonnienne in French"',
                  helper:
                      'Optional hints for the translator about gender, context, or usage',
                ),
                maxLines: 3,
                maxLength: 500,
              ),
              const SizedBox(height: 12),
              _CaseSensitiveToggle(
                value: _caseSensitive,
                onChanged: (v) => setState(() => _caseSensitive = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        SmallTextButton(
          label: 'Cancel',
          onTap: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        SmallTextButton(
          label: _isSaving ? 'Saving...' : 'Save',
          icon: FluentIcons.save_24_regular,
          filled: true,
          onTap: _isSaving ? null : _saveEntry,
        ),
      ],
    );
  }

  InputDecoration _decoration(
    TwmtThemeTokens tokens, {
    required String label,
    String? hint,
    String? helper,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: tokens.fontBody.copyWith(
        fontSize: 12,
        color: tokens.textDim,
      ),
      floatingLabelStyle: tokens.fontBody.copyWith(
        fontSize: 12,
        color: tokens.accent,
      ),
      hintText: hint,
      hintStyle: tokens.fontBody.copyWith(
        fontSize: 13,
        color: tokens.textFaint,
      ),
      helperText: helper,
      helperMaxLines: 2,
      helperStyle: tokens.fontBody.copyWith(
        fontSize: 11.5,
        color: tokens.textDim,
      ),
      filled: true,
      fillColor: tokens.panel2,
      isDense: true,
      counterStyle: tokens.fontBody.copyWith(
        fontSize: 11,
        color: tokens.textFaint,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.err),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        borderSide: BorderSide(color: tokens.err),
      ),
      errorStyle: tokens.fontBody.copyWith(
        fontSize: 11.5,
        color: tokens.err,
      ),
    );
  }

  Future<void> _saveEntry() async {
    final logging = ref.read(loggingServiceProvider);
    logging.debug('[GlossaryEntryEditor._saveEntry] Starting save operation');

    if (!_formKey.currentState!.validate()) {
      logging.debug('[GlossaryEntryEditor._saveEntry] Form validation failed');
      return;
    }

    if (!mounted) return;

    setState(() => _isSaving = true);

    try {
      final targetLanguageCode = widget.entry?.targetLanguageCode ??
          widget.targetLanguageCode ??
          'fr';

      final notes = _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null;

      await ref.read(glossaryEntryEditorProvider.notifier).save(
            glossaryId: widget.glossaryId,
            targetLanguageCode: targetLanguageCode,
            sourceTerm: _sourceTermController.text.trim(),
            targetTerm: _targetTermController.text.trim(),
            caseSensitive: _caseSensitive,
            notes: notes,
            existingEntry: widget.entry,
          );

      if (!mounted) return;

      ref.invalidate(glossaryEntriesProvider);
      ref.invalidate(glossaryStatisticsProvider);

      Navigator.of(context).pop();
      FluentToast.success(
        context,
        widget.entry != null
            ? 'Entry updated successfully'
            : 'Entry added successfully',
      );
    } catch (e, stackTrace) {
      logging.error(
          '[GlossaryEntryEditor._saveEntry] Exception caught', e, stackTrace);
      if (!mounted) return;
      FluentToast.error(context, 'Error saving entry: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

class _CaseSensitiveToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CaseSensitiveToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                value
                    ? FluentIcons.checkbox_checked_24_filled
                    : FluentIcons.checkbox_unchecked_24_regular,
                size: 18,
                color: value ? tokens.accent : tokens.textFaint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Case Sensitive',
                      style: tokens.fontBody.copyWith(
                        fontSize: 13,
                        color: tokens.text,
                      ),
                    ),
                    Text(
                      'Match this term with exact case '
                      '(e.g., "Emperor" vs "emperor")',
                      style: tokens.fontBody.copyWith(
                        fontSize: 11.5,
                        color: tokens.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
