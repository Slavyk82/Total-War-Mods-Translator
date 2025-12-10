import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../../../models/domain/llm_custom_rule.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../providers/llm_custom_rules_providers.dart';
import 'llm_custom_rules_data_source.dart';
import 'llm_custom_rule_editor_dialog.dart';

/// DataGrid widget for displaying and managing LLM custom rules
class LlmCustomRulesDataGrid extends ConsumerStatefulWidget {
  const LlmCustomRulesDataGrid({super.key});

  @override
  ConsumerState<LlmCustomRulesDataGrid> createState() =>
      _LlmCustomRulesDataGridState();
}

class _LlmCustomRulesDataGridState extends ConsumerState<LlmCustomRulesDataGrid> {
  late LlmCustomRulesDataSource _dataSource;
  final DataGridController _controller = DataGridController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rulesAsync = ref.watch(llmCustomRulesProvider);

    return rulesAsync.when(
      data: (rules) {
        _dataSource = LlmCustomRulesDataSource(
          rules: rules,
          context: context,
          onEdit: _editRule,
          onDelete: _deleteRule,
          onToggleEnabled: _toggleEnabled,
        );
        return _buildDataGrid(rules);
      },
      loading: () => const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => _buildErrorState(error.toString()),
    );
  }

  Widget _buildDataGrid(List<LlmCustomRule> rules) {
    if (rules.isEmpty) {
      return _buildEmptyState();
    }

    return SizedBox(
      height: _calculateGridHeight(rules.length),
      child: SfDataGrid(
        source: _dataSource,
        controller: _controller,
        allowSorting: false,
        columnWidthMode: ColumnWidthMode.fill,
        gridLinesVisibility: GridLinesVisibility.both,
        headerGridLinesVisibility: GridLinesVisibility.both,
        selectionMode: SelectionMode.single,
        rowHeight: 52,
        headerRowHeight: 40,
        columns: [
          GridColumn(
            columnName: 'enabled',
            width: 80,
            label: Container(
              padding: const EdgeInsets.all(8.0),
              alignment: Alignment.center,
              child: Text(
                'Active',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          GridColumn(
            columnName: 'ruleText',
            label: Container(
              padding: const EdgeInsets.all(8.0),
              alignment: Alignment.centerLeft,
              child: Text(
                'Rule Text',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          GridColumn(
            columnName: 'actions',
            width: 100,
            label: Container(
              padding: const EdgeInsets.all(8.0),
              alignment: Alignment.center,
              child: Text(
                'Actions',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateGridHeight(int rowCount) {
    // Header height + (row height * row count) + some padding
    const headerHeight = 40.0;
    const rowHeight = 52.0;
    const maxRows = 5;
    const padding = 2.0;

    final displayRows = rowCount > maxRows ? maxRows : rowCount;
    return headerHeight + (rowHeight * displayRows) + padding;
  }

  Widget _buildEmptyState() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.document_text_24_regular,
              size: 32,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'No custom rules defined',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add global rules to customize all translation prompts',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.error),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 32,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              'Error loading rules',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editRule(LlmCustomRule rule) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => LlmCustomRuleEditorDialog(existingRule: rule),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final (success, error) =
          await ref.read(llmCustomRulesProvider.notifier).updateRule(
                rule.id,
                result,
              );

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Rule updated successfully');
        } else {
          FluentToast.error(context, error ?? 'Failed to update rule');
        }
      }
    }
  }

  Future<void> _deleteRule(LlmCustomRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rule'),
        content: const Text(
          'Are you sure you want to delete this custom rule? This action cannot be undone.',
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

    if (confirmed == true && mounted) {
      final (success, error) =
          await ref.read(llmCustomRulesProvider.notifier).deleteRule(rule.id);

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Rule deleted successfully');
        } else {
          FluentToast.error(context, error ?? 'Failed to delete rule');
        }
      }
    }
  }

  Future<void> _toggleEnabled(LlmCustomRule rule) async {
    final (success, error) =
        await ref.read(llmCustomRulesProvider.notifier).toggleEnabled(rule.id);

    if (mounted && !success) {
      FluentToast.error(context, error ?? 'Failed to toggle rule');
    }
  }
}
