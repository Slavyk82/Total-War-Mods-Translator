import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../providers/tm_providers.dart';
import '../widgets/tm_browser_datagrid.dart';
import '../widgets/tm_statistics_panel.dart';
import '../widgets/tmx_import_dialog.dart';
import '../widgets/tmx_export_dialog.dart';
import '../widgets/tm_filter_panel.dart';
import '../widgets/tm_search_bar.dart';
import '../widgets/tm_cleanup_dialog.dart';
import '../widgets/tm_pagination_bar.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Main screen for Translation Memory management
class TranslationMemoryScreen extends ConsumerStatefulWidget {
  const TranslationMemoryScreen({super.key});

  @override
  ConsumerState<TranslationMemoryScreen> createState() =>
      _TranslationMemoryScreenState();
}

class _TranslationMemoryScreenState
    extends ConsumerState<TranslationMemoryScreen> {
  bool _showFilters = true;

  @override
  Widget build(BuildContext context) {
    return FluentScaffold(
      body: Column(
        children: [
          // Header
          _buildHeader(context),

          const Divider(height: 1),

          // Main content
          Expanded(
            child: Row(
              children: [
                // Statistics panel (left sidebar) with fixed width
                const SizedBox(
                  width: 280,
                  child: TmStatisticsPanel(),
                ),

                const VerticalDivider(width: 1),

                // Main content area
                Expanded(
                  child: Column(
                    children: [
                      // Toolbar
                      _buildToolbar(context),

                      const Divider(height: 1),

                      // Filters (collapsible)
                      if (_showFilters) ...[
                        const TmFilterPanel(),
                        const Divider(height: 1),
                      ],

                      // DataGrid
                      const Expanded(
                        child: TmBrowserDataGrid(),
                      ),

                      const Divider(height: 1),

                      // Pagination
                      const TmPaginationBar(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          Icon(
            FluentIcons.database_24_regular,
            size: 32,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            'Translation Memory',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const Spacer(),
          // Action buttons
          _buildActionButton(
            context,
            icon: FluentIcons.arrow_import_24_regular,
            label: 'Import',
            onPressed: () => _showImportDialog(),
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            context,
            icon: FluentIcons.arrow_export_24_regular,
            label: 'Export',
            onPressed: () => _showExportDialog(),
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            context,
            icon: FluentIcons.broom_24_regular,
            label: 'Cleanup',
            onPressed: () => _showCleanupDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          // Search bar
          const Expanded(
            flex: 2,
            child: TmSearchBar(),
          ),

          const SizedBox(width: 16),

          // Toggle filters button
          _buildToolbarButton(
            context,
            icon: _showFilters
                ? FluentIcons.chevron_up_24_regular
                : FluentIcons.chevron_down_24_regular,
            label: 'Filters',
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
          ),

          const SizedBox(width: 8),

          // Refresh button
          _buildToolbarButton(
            context,
            icon: FluentIcons.arrow_clockwise_24_regular,
            label: 'Refresh',
            onPressed: () {
              ref.invalidate(tmEntriesProvider);
              ref.invalidate(tmStatisticsProvider);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FluentButton(
      onPressed: onPressed,
      icon: Icon(icon),
      child: Text(label),
    );
  }

  Widget _buildToolbarButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FluentTextButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      child: Text(label),
    );
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (context) => const TmxImportDialog(),
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) => const TmxExportDialog(),
    );
  }

  void _showCleanupDialog() {
    showDialog(
      context: context,
      builder: (context) => const TmCleanupDialog(),
    );
  }
}
