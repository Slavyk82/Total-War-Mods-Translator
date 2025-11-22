import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../providers/tm_providers.dart';

/// Search bar for Translation Memory entries
class TmSearchBar extends ConsumerStatefulWidget {
  const TmSearchBar({super.key});

  @override
  ConsumerState<TmSearchBar> createState() => _TmSearchBarState();
}

class _TmSearchBarState extends ConsumerState<TmSearchBar> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search translation memory...',
        prefixIcon: const Icon(FluentIcons.search_24_regular),
        suffixIcon: _searchController.text.isNotEmpty
            ? MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    ref
                        .read(tmFilterStateProvider.notifier)
                        .setSearchText('');
                  },
                  child: const Icon(FluentIcons.dismiss_24_regular),
                ),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      onChanged: (value) {
        ref.read(tmFilterStateProvider.notifier).setSearchText(value);
        setState(() {}); // Update to show/hide clear button
      },
    );
  }
}
