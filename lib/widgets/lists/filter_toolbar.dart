import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';

/// Double-row toolbar for §7.1 filterable lists.
/// Row 1: leading (crumb/title/count) + trailing (search, sort, actions).
/// Row 2: horizontally scrollable list of [FilterPillGroup]s (hidden if empty).
class FilterToolbar extends StatelessWidget {
  final Widget leading;
  final List<Widget> trailing;
  final List<FilterPillGroup> pillGroups;

  /// When true (default), [leading] is wrapped in an [Expanded] so it fills
  /// the remaining space and pushes [trailing] to the right. Set to false
  /// when one of the [trailing] widgets is itself wrapped in [Expanded]
  /// (or [Flexible]) and should consume the free space instead — e.g. a
  /// search field that must stretch across the toolbar.
  final bool expandLeading;

  const FilterToolbar({
    super.key,
    required this.leading,
    this.trailing = const [],
    this.pillGroups = const [],
    this.expandLeading = true,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: tokens.panel,
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          child: Row(
            children: [
              if (expandLeading) Expanded(child: leading) else leading,
              for (final w in trailing) ...[const SizedBox(width: 12), w],
            ],
          ),
        ),
        if (pillGroups.isNotEmpty)
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: tokens.panel,
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < pillGroups.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    pillGroups[i],
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
