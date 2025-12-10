import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../providers/tm_providers.dart';

/// Pagination bar for Translation Memory entries
class TmPaginationBar extends ConsumerWidget {
  const TmPaginationBar({super.key});

  static const _itemsPerPage = 1000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageState = ref.watch(tmPageStateProvider);
    final filterState = ref.watch(tmFilterStateProvider);
    final countAsync = ref.watch(tmEntriesCountProvider(
      targetLang: filterState.targetLanguage,
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

    final pageNumbers = _computeVisiblePages(currentPage, totalPages);

    return Row(
      children: [
        // First page button
        FluentIconButton(
          icon: const Icon(FluentIcons.chevron_double_left_20_regular),
          onPressed: currentPage > 1
              ? () {
                  ref.read(tmPageStateProvider.notifier).setPage(1);
                }
              : null,
          tooltip: 'First page',
        ),

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

        // Page numbers with ellipses
        ...pageNumbers.map((pageNum) {
          if (pageNum == -1) {
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0),
              child: Text('...'),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: _PageButton(
              pageNumber: pageNum,
              isActive: pageNum == currentPage,
              onPressed: () {
                ref.read(tmPageStateProvider.notifier).setPage(pageNum);
              },
            ),
          );
        }),

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

        // Last page button
        FluentIconButton(
          icon: const Icon(FluentIcons.chevron_double_right_20_regular),
          onPressed: currentPage < totalPages
              ? () {
                  ref.read(tmPageStateProvider.notifier).setPage(totalPages);
                }
              : null,
          tooltip: 'Last page',
        ),
      ],
    );
  }

  /// Computes visible page numbers with ellipses (-1 represents ellipsis)
  List<int> _computeVisiblePages(int currentPage, int totalPages) {
    const maxVisible = 7;

    if (totalPages <= maxVisible) {
      return List.generate(totalPages, (i) => i + 1);
    }

    final pages = <int>[];

    // Always show first page
    pages.add(1);

    // Calculate range around current page
    int start = currentPage - 2;
    int end = currentPage + 2;

    // Adjust range if near edges
    if (start <= 2) {
      start = 2;
      end = 5;
    } else if (end >= totalPages - 1) {
      end = totalPages - 1;
      start = totalPages - 4;
    }

    // Add ellipsis before range if needed
    if (start > 2) {
      pages.add(-1);
    }

    // Add pages in range
    for (int i = start; i <= end; i++) {
      if (i > 1 && i < totalPages) {
        pages.add(i);
      }
    }

    // Add ellipsis after range if needed
    if (end < totalPages - 1) {
      pages.add(-1);
    }

    // Always show last page
    pages.add(totalPages);

    return pages;
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
