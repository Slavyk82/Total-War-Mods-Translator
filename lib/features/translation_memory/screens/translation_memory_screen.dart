import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/detail/home_back_toolbar.dart';

import '../providers/tm_providers.dart';
import '../widgets/tm_browser_datagrid.dart';
import '../widgets/tm_cleanup_dialog.dart';
import '../widgets/tm_pagination_bar.dart';
import '../widgets/tm_statistics_panel.dart';
import '../widgets/tmx_export_dialog.dart';
import '../widgets/tmx_import_dialog.dart';

/// Main screen for Translation Memory management.
///
/// Migrated to the §7.1 filterable-list archetype in Plan 5a · Task 6:
///  - Top chrome is a [FilterToolbar] (leading title + count, trailing search
///    + Import/Export/Cleanup actions).
///  - Left sidebar preserves the 280px [TmStatisticsPanel].
///  - Right column stacks the tokenised [TmBrowserDataGrid] over the
///    [TmPaginationBar].
class TranslationMemoryScreen extends ConsumerStatefulWidget {
  const TranslationMemoryScreen({super.key});

  @override
  ConsumerState<TranslationMemoryScreen> createState() =>
      _TranslationMemoryScreenState();
}

class _TranslationMemoryScreenState
    extends ConsumerState<TranslationMemoryScreen> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final filtersState = ref.watch(tmFilterStateProvider);
    final filterNotifier = ref.read(tmFilterStateProvider.notifier);
    final totalAsync = ref.watch(tmEntriesCountProvider(
      targetLang: filtersState.targetLanguage,
    ));
    final total = totalAsync.asData?.value ?? 0;

    return Material(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeBackToolbar(leading: _Leading(total: total)),
          FilterToolbar(
            leading: const SizedBox.shrink(),
            expandLeading: false,
            trailing: [
              Expanded(
                child: ListSearchField(
                  value: filtersState.searchText,
                  hintText: 'Search translation memory...',
                  width: null,
                  onChanged: (value) {
                    filterNotifier.setSearchText(value);
                  },
                  onClear: () => filterNotifier.setSearchText(''),
                ),
              ),
              SmallTextButton(
                label: 'Import TMX',
                icon: FluentIcons.arrow_import_24_regular,
                tooltip: t.tooltips.tm.import,
                onTap: _showImportDialog,
              ),
              SmallTextButton(
                label: 'Export TMX',
                icon: FluentIcons.arrow_export_24_regular,
                tooltip: t.tooltips.tm.export,
                onTap: _showExportDialog,
              ),
              SmallTextButton(
                label: 'Cleanup',
                icon: FluentIcons.broom_24_regular,
                tooltip: t.tooltips.tm.cleanup,
                onTap: _showCleanupDialog,
              ),
            ],
          ),
          Expanded(
            child: Row(
              children: [
                const SizedBox(
                  width: 280,
                  child: TmStatisticsPanel(),
                ),
                VerticalDivider(width: 1, color: tokens.border),
                const Expanded(
                  child: Column(
                    children: [
                      Expanded(child: TmBrowserDataGrid()),
                      TmPaginationBar(),
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

/// Leading row 1 of the [FilterToolbar]: icon + title + entry count.
class _Leading extends StatelessWidget {
  final int total;
  const _Leading({required this.total});

  @override
  Widget build(BuildContext context) {
    final noun = total == 1 ? 'entry' : 'entries';
    return ListToolbarLeading(
      icon: FluentIcons.database_24_regular,
      title: 'Translation Memory',
      countLabel: '$total $noun',
    );
  }
}
