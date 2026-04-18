import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/list_row.dart';

import '../providers/steam_publish_providers.dart';
import 'steam_publish_action_cell.dart';
import 'steam_publish_list_cells.dart';

/// Header + scrollable list of publishable items rendered with [ListRow].
///
/// Selection state is threaded in from
/// [steamPublishSelectionProvider]; the row's checkbox toggles membership
/// directly on the [StateProvider] so [ListRow] stays dumb (receives
/// `selected: selection.contains(id)` and `onTap` toggle).
class SteamPublishList extends ConsumerWidget {
  final List<PublishableItem> items;

  const SteamPublishList({super.key, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(steamPublishSelectionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SteamPublishListHeader(),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              final selected = selection.contains(item.itemId);
              return ListRow(
                columns: steamPublishColumns,
                selected: selected,
                onTap: () => _toggleSelection(ref, item.itemId),
                children: [
                  SteamSelectionCheckbox(
                    selected: selected,
                    onToggle: () => _toggleSelection(ref, item.itemId),
                  ),
                  SteamCoverCell(item: item),
                  SteamTitleBlock(item: item),
                  SteamStateCell(item: item),
                  SteamLastPublishedCell(item: item),
                  SteamActionCell(item: item),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _toggleSelection(WidgetRef ref, String itemId) {
    final current = ref.read(steamPublishSelectionProvider);
    final next = Set<String>.from(current);
    if (next.contains(itemId)) {
      next.remove(itemId);
    } else {
      next.add(itemId);
    }
    ref.read(steamPublishSelectionProvider.notifier).state = next;
  }
}

/// Mono-caps header row mirroring [steamPublishColumns].
class _SteamPublishListHeader extends StatelessWidget {
  const _SteamPublishListHeader();

  @override
  Widget build(BuildContext context) {
    return ListRowHeader(
      columns: steamPublishColumns,
      labels: const [
        '',
        '',
        'Pack',
        'Status',
        'Last published',
        '',
      ],
    );
  }
}

/// Empty-state widget shown when the publishable items list is empty.
class SteamPublishEmptyState extends StatelessWidget {
  const SteamPublishEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.box_24_regular,
              size: 56,
              color: tokens.textFaint,
            ),
            const SizedBox(height: 16),
            Text(
              'No projects or compilations yet',
              style: tokens.fontDisplay.copyWith(
                fontSize: 18,
                color: tokens.text,
                fontStyle: tokens.fontDisplayStyle,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a project or compilation to see it here.',
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty-state shown when filters trim the list to zero items.
class SteamPublishNoMatchesState extends StatelessWidget {
  const SteamPublishNoMatchesState({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.search_24_regular,
              size: 56,
              color: tokens.textFaint,
            ),
            const SizedBox(height: 12),
            Text(
              'No items match the current filters',
              style: tokens.fontDisplay.copyWith(
                fontSize: 16,
                color: tokens.text,
                fontStyle: tokens.fontDisplayStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
