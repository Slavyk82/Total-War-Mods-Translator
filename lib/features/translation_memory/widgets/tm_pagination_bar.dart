import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../providers/tm_providers.dart';

/// Pagination bar for Translation Memory entries
class TmPaginationBar extends ConsumerWidget {
  const TmPaginationBar({super.key});

  static const _itemsPerPage = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageState = ref.watch(tmPageStateProvider);
    final filterState = ref.watch(tmFilterStateProvider);
    final countAsync = ref.watch(tmEntriesCountProvider(
      targetLang: filterState.targetLanguage,
      gameContext: filterState.gameContext,
      minQuality: filterState.effectiveMinQuality,
    ));

    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Items per page info
          countAsync.when(
            data: (totalCount) => _buildItemsInfo(context, pageState, totalCount),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),

          // Page navigation
          countAsync.when(
            data: (totalCount) => _buildPageNavigation(
              context,
              ref,
              pageState,
              totalCount,
            ),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),

          const SizedBox(width: 100), // Balance layout
        ],
      ),
    );
  }

  Widget _buildItemsInfo(BuildContext context, int currentPage, int totalCount) {
    final startItem = (currentPage - 1) * _itemsPerPage + 1;
    final endItem = (currentPage * _itemsPerPage).clamp(0, totalCount);
    return Text(
      'Showing $startItem-$endItem of $totalCount',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  Widget _buildPageNavigation(
    BuildContext context,
    WidgetRef ref,
    int currentPage,
    int totalCount,
  ) {
    final totalPages = (totalCount / _itemsPerPage).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();

    return Row(
      children: [
        // Previous button
        FluentIconButton(
          icon: const Icon(FluentIcons.chevron_left_24_regular),
          onPressed: currentPage > 1
              ? () {
                  ref.read(tmPageStateProvider.notifier).previousPage();
                }
              : null,
          tooltip: 'Previous page',
        ),

        // Page numbers
        ...List.generate(
          totalPages.clamp(0, 5),
          (index) {
            final pageNumber = index + 1;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: _PageButton(
                pageNumber: pageNumber,
                isActive: pageNumber == currentPage,
                onPressed: () {
                  ref.read(tmPageStateProvider.notifier).setPage(pageNumber);
                },
              ),
            );
          },
        ),

        // Next button
        FluentIconButton(
          icon: const Icon(FluentIcons.chevron_right_24_regular),
          onPressed: currentPage < totalPages
              ? () {
                  ref.read(tmPageStateProvider.notifier).nextPage();
                }
              : null,
          tooltip: 'Next page',
        ),
      ],
    );
  }
}

/// Page button for pagination
class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.pageNumber,
    required this.isActive,
    required this.onPressed,
  });

  final int pageNumber;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            pageNumber.toString(),
            style: TextStyle(
              color: isActive
                  ? Colors.white
                  : Theme.of(context).textTheme.bodyMedium?.color,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
