import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../models/domain/llm_custom_rule.dart';

/// Dialog for adding or editing a custom LLM translation rule
class LlmCustomRuleEditorDialog extends StatefulWidget {
  /// Existing rule to edit, or null for creating a new rule
  final LlmCustomRule? existingRule;

  const LlmCustomRuleEditorDialog({
    super.key,
    this.existingRule,
  });

  @override
  State<LlmCustomRuleEditorDialog> createState() =>
      _LlmCustomRuleEditorDialogState();
}

class _LlmCustomRuleEditorDialogState extends State<LlmCustomRuleEditorDialog> {
  late TextEditingController _textController;
  final _formKey = GlobalKey<FormState>();

  bool get _isEditing => widget.existingRule != null;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.existingRule?.ruleText ?? '',
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
          Text(_isEditing ? 'Edit Custom Rule' : 'Add Custom Rule'),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the rule text that will be appended to every translation prompt. '
                'These rules apply globally to all projects.',
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
                maxLines: 8,
                minLines: 4,
                decoration: InputDecoration(
                  hintText:
                      'e.g., Always use formal language and avoid contractions...',
                  hintStyle: TextStyle(
                    color:
                        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  filled: true,
                  fillColor:
                      Theme.of(context).colorScheme.surface,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a rule text';
                  }
                  return null;
                },
                autofocus: true,
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
            _isEditing ? FluentIcons.save_24_regular : FluentIcons.add_24_regular,
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
                'Tips',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• Be specific and clear in your instructions\n'
            '• Use bullet points for multiple rules\n'
            '• Rules are appended in order to the translation prompt\n'
            '• You can disable rules temporarily without deleting them',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
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
