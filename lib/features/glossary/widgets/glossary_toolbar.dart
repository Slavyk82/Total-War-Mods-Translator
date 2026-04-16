import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/config/tooltip_strings.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
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
          hintText: 'Search glossaries...',
          onChanged: onSearchChanged,
          onClear: () => onSearchChanged(''),
        ),
        SmallTextButton(
          label: 'New glossary',
          icon: FluentIcons.add_24_regular,
          tooltip: TooltipStrings.glossaryNew,
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
    final tokens = context.tokens;
    final noun = totalCount == 1 ? 'glossary' : 'glossaries';
    final countLabel = searchActive
        ? '$filteredCount / $totalCount $noun'
        : '$totalCount $noun';
    return Row(
      children: [
        Icon(
          FluentIcons.book_24_regular,
          size: 20,
          color: tokens.textMid,
        ),
        const SizedBox(width: 10),
        Text(
          'Glossaries',
          style: tokens.fontDisplay.copyWith(
            fontSize: 20,
            color: tokens.text,
            fontStyle:
                tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          countLabel,
          style: tokens.fontMono.copyWith(
            fontSize: 12,
            color: tokens.textDim,
          ),
        ),
      ],
    );
  }
}
