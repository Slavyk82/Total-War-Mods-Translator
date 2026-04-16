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

  const FilterToolbar({
    super.key,
    required this.leading,
    this.trailing = const [],
    this.pillGroups = const [],
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
              Expanded(child: leading),
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
