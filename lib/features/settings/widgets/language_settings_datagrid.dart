import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_confirm_dialog.dart';
import 'package:twmt/widgets/lists/token_data_grid_theme.dart';
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
  LanguageSettingsDataSource? _dataSource;
  final DataGridController _controller = DataGridController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(languageSettingsProvider);
    final tokens = context.tokens;

    return settingsAsync.when(
      data: (state) {
        // Settings datagrids have small N (<100 rows), and the data source needs
        // `tokens` baked in at construction time. Re-creating on every build is
        // cheap and naturally picks up theme switches without manual invalidation.
        // For larger grids, see `tm_browser_datagrid.dart`'s updateEntries pattern.
        _dataSource = LanguageSettingsDataSource(
          languages: state.languages,
          defaultLanguageCode: state.defaultLanguageCode,
          tokens: tokens,
          onSetDefault: _setDefaultLanguage,
          onDelete: _deleteLanguage,
        );
        return _buildDataGrid(state.languages, tokens);
      },
      loading: () => const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => _buildErrorState(error.toString(), tokens),
    );
  }

  Widget _buildDataGrid(List<Language> languages, TwmtThemeTokens tokens) {
    if (languages.isEmpty) {
      return _buildEmptyState(tokens);
    }

    return SizedBox(
      height: _calculateGridHeight(languages.length),
      child: SfDataGridTheme(
        data: buildTokenDataGridTheme(tokens),
        child: SfDataGrid(
          source: _dataSource!,
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
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: tokens.text,
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
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: tokens.text,
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
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: tokens.text,
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
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: tokens.text,
                  ),
                ),
              ),
            ),
          ],
        ),
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

  Widget _buildEmptyState(TwmtThemeTokens tokens) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.local_language_24_regular,
              size: 32,
              color: tokens.textFaint,
            ),
            const SizedBox(height: 8),
            Text(
              'No languages available',
              style: tokens.fontBody.copyWith(
                fontSize: 14,
                color: tokens.textMid,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error, TwmtThemeTokens tokens) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        border: Border.all(color: tokens.err),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 32,
              color: tokens.err,
            ),
            const SizedBox(height: 8),
            Text(
              'Error loading languages',
              style: tokens.fontBody.copyWith(
                fontSize: 14,
                color: tokens.err,
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
      builder: (_) => TokenConfirmDialog(
        title: 'Delete Language',
        message: 'Are you sure you want to delete "${language.name}"?',
        warningMessage: 'This action cannot be undone.',
        confirmLabel: 'Delete',
        confirmIcon: FluentIcons.delete_24_regular,
        destructive: true,
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
