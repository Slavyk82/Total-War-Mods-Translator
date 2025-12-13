import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../models/domain/llm_custom_rule.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../settings/providers/llm_custom_rules_providers.dart';

/// Dialog for editing a mod-specific translation rule
class ModRuleEditorDialog extends ConsumerStatefulWidget {
  final String projectId;
  final String projectName;

  const ModRuleEditorDialog({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  ConsumerState<ModRuleEditorDialog> createState() => _ModRuleEditorDialogState();
}

class _ModRuleEditorDialogState extends ConsumerState<ModRuleEditorDialog> {
  late TextEditingController _textController;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ruleAsync = ref.watch(projectCustomRuleProvider(widget.projectId));

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            FluentIcons.text_bullet_list_ltr_24_regular,
            size: 24,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Mod Translation Rule'),
                Text(
                  widget.projectName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: ruleAsync.when(
          data: (existingRule) {
            // Initialize controller with existing rule text
            if (_textController.text.isEmpty && existingRule != null) {
              _textController.text = existingRule.ruleText;
            }
            return _buildContent(existingRule);
          },
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SizedBox(
            height: 200,
            child: Center(
              child: Text('Error loading rule: $error'),
            ),
          ),
        ),
      ),
      actions: [
        if (ruleAsync.hasValue && ruleAsync.value != null)
          TextButton.icon(
            onPressed: _isLoading ? null : _deleteRule,
            icon: Icon(
              FluentIcons.delete_24_regular,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            label: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isLoading ? null : _save,
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(FluentIcons.save_24_regular, size: 18),
          label: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildContent(LlmCustomRule? existingRule) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  FluentIcons.info_24_regular,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This rule applies only to this mod and will be appended '
                    'after the global rules in every translation prompt.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.8),
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Rule Text',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _textController,
            maxLines: 8,
            minLines: 4,
            decoration: InputDecoration(
              hintText:
                  'e.g., This mod uses fantasy names that should not be translated...',
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a rule text';
              }
              return null;
            },
            autofocus: existingRule == null,
          ),
          if (existingRule != null) ...[
            const SizedBox(height: 12),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _toggleEnabled,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      existingRule.isEnabled
                          ? FluentIcons.checkbox_checked_24_filled
                          : FluentIcons.checkbox_unchecked_24_regular,
                      size: 18,
                      color: existingRule.isEnabled
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      existingRule.isEnabled ? 'Rule is active' : 'Rule is disabled',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final notifier = ref.read(
      projectCustomRuleProvider(widget.projectId).notifier,
    );
    final (success, error) = await notifier.setRule(_textController.text.trim());

    setState(() => _isLoading = false);

    if (mounted) {
      if (success) {
        FluentToast.success(context, 'Mod rule saved successfully');
        Navigator.pop(context, true);
      } else {
        FluentToast.error(context, error ?? 'Failed to save rule');
      }
    }
  }

  Future<void> _deleteRule() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Mod Rule'),
        content: const Text(
          'Are you sure you want to delete this rule? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    final notifier = ref.read(
      projectCustomRuleProvider(widget.projectId).notifier,
    );
    final (success, error) = await notifier.deleteRule();

    setState(() => _isLoading = false);

    if (mounted) {
      if (success) {
        FluentToast.success(context, 'Mod rule deleted');
        Navigator.pop(context, true);
      } else {
        FluentToast.error(context, error ?? 'Failed to delete rule');
      }
    }
  }

  Future<void> _toggleEnabled() async {
    final notifier = ref.read(
      projectCustomRuleProvider(widget.projectId).notifier,
    );
    final (success, error) = await notifier.toggleEnabled();

    if (mounted && !success) {
      FluentToast.error(context, error ?? 'Failed to toggle rule');
    }
  }
}
