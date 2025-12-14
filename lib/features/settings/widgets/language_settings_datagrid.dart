import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../../../models/domain/language.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../providers/language_settings_providers.dart';
import 'language_settings_data_source.dart';

/// DataGrid widget for displaying and managing languages in settings
class LanguageSettingsDataGrid extends ConsumerStatefulWidget {
  const LanguageSettingsDataGrid({super.key});

  @override
  ConsumerState<LanguageSettingsDataGrid> createState() =>
      _LanguageSettingsDataGridState();
}

class _LanguageSettingsDataGridState
    extends ConsumerState<LanguageSettingsDataGrid> {
  late LanguageSettingsDataSource _dataSource;
  final DataGridController _controller = DataGridController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(languageSettingsProvider);

    return settingsAsync.when(
      data: (state) {
        _dataSource = LanguageSettingsDataSource(
          languages: state.languages,
          defaultLanguageCode: state.defaultLanguageCode,
          context: context,
          onSetDefault: _setDefaultLanguage,
          onDelete: _deleteLanguage,
        );
        return _buildDataGrid(state.languages);
      },
      loading: () => const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => _buildErrorState(error.toString()),
    );
  }

  Widget _buildDataGrid(List<Language> languages) {
    if (languages.isEmpty) {
      return _buildEmptyState();
    }

    return SizedBox(
      height: _calculateGridHeight(languages.length),
      child: SfDataGrid(
        source: _dataSource,
        controller: _controller,
        allowSorting: false,
        columnWidthMode: ColumnWidthMode.fill,
        gridLinesVisibility: GridLinesVisibility.both,
        headerGridLinesVisibility: GridLinesVisibility.both,
        selectionMode: SelectionMode.single,
        rowHeight: 48,
        headerRowHeight: 40,
        columns: [
          GridColumn(
            columnName: 'default',
            width: 80,
            label: Container(
              padding: const EdgeInsets.all(8.0),
              alignment: Alignment.center,
              child: Text(
                'Default',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          GridColumn(
            columnName: 'code',
            width: 100,
            label: Container(
              padding: const EdgeInsets.all(8.0),
              alignment: Alignment.centerLeft,
              child: Text(
                'Code',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          GridColumn(
            columnName: 'name',
            label: Container(
              padding: const EdgeInsets.all(8.0),
              alignment: Alignment.centerLeft,
              child: Text(
                'Language',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          GridColumn(
            columnName: 'actions',
            width: 60,
            label: Container(
              padding: const EdgeInsets.all(8.0),
              alignment: Alignment.center,
              child: Text(
                '',
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
    const headerHeight = 40.0;
    const rowHeight = 48.0;
    const maxRows = 8;
    const padding = 2.0;

    final displayRows = rowCount > maxRows ? maxRows : rowCount;
    return headerHeight + (rowHeight * displayRows) + padding;
  }

  Widget _buildEmptyState() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.local_language_24_regular,
              size: 32,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'No languages available',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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
              'Error loading languages',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setDefaultLanguage(Language language) async {
    final (success, error) =
        await ref.read(languageSettingsProvider.notifier).setDefaultLanguage(
              language.code,
            );

    if (mounted) {
      if (success) {
        FluentToast.success(
          context,
          '${language.name} set as default language',
        );
      } else {
        FluentToast.error(context, error ?? 'Failed to set default language');
      }
    }
  }

  Future<void> _deleteLanguage(Language language) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Language'),
        content: Text(
          'Are you sure you want to delete "${language.name}"? This action cannot be undone.',
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
          await ref.read(languageSettingsProvider.notifier).deleteLanguage(
                language.id,
              );

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Language deleted successfully');
        } else {
          FluentToast.error(context, error ?? 'Failed to delete language');
        }
      }
    }
  }
}
