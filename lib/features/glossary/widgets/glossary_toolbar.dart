import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Toolbar for the Glossary list view.
///
/// Row 1 hosts the crumb + title + count, plus trailing actions
/// (search field and New glossary button). No pill groups — the current
/// glossary list has no filter chips to preserve (refresh-strict).
class GlossaryToolbar extends StatelessWidget {
  final int totalCount;
  final int filteredCount;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onNewGlossary;

  const GlossaryToolbar({
    super.key,
    required this.totalCount,
    required this.filteredCount,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onNewGlossary,
  });

  @override
  Widget build(BuildContext context) {
    return FilterToolbar(
      leading: _Leading(
        totalCount: totalCount,
        filteredCount: filteredCount,
        searchActive: searchQuery.isNotEmpty,
      ),
      trailing: [
        ListSearchField(
          value: searchQuery,
          hintText: t.glossary.hints.searchEntries,
          onChanged: onSearchChanged,
          onClear: () => onSearchChanged(''),
        ),
        SmallTextButton(
          label: t.glossary.empty.createNewGlossary,
          icon: FluentIcons.add_24_regular,
          tooltip: t.tooltips.glossary.kNew,
          onTap: onNewGlossary,
        ),
      ],
    );
  }
}

class _Leading extends StatelessWidget {
  final int totalCount;
  final int filteredCount;
  final bool searchActive;

  const _Leading({
    required this.totalCount,
    required this.filteredCount,
    required this.searchActive,
  });

  @override
  Widget build(BuildContext context) {
    final noun = totalCount == 1 ? 'glossary' : 'glossaries';
    final countLabel = searchActive
        ? '$filteredCount / $totalCount $noun'
        : '$totalCount $noun';
    return ListToolbarLeading(
      icon: FluentIcons.book_24_regular,
      title: 'Glossaries',
      countLabel: countLabel,
    );
  }
}
