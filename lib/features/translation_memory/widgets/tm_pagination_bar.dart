import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../providers/tm_providers.dart';

/// Pagination bar for the Translation Memory browser.
///
/// Retokenised in Plan 5a · Task 6 — preserved wholesale as a feature of the
/// TM screen but switched off [Theme.of(context)] onto [TwmtThemeTokens] so
/// it composes with the [FilterToolbar] + tokenised [SfDataGrid] above it.
class TmPaginationBar extends ConsumerWidget {
  const TmPaginationBar({super.key});

  static const _itemsPerPage = 1000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final pageState = ref.watch(tmPageStateProvider);
    final filterState = ref.watch(tmFilterStateProvider);
    final countAsync = ref.watch(tmEntriesCountProvider(
      targetLang: filterState.targetLanguage,
    ));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Items per page info
          countAsync.when(
            data: (totalCount) =>
                _buildItemsInfo(tokens, pageState, totalCount),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),

          // Page navigation
          countAsync.when(
            data: (totalCount) => _buildPageNavigation(
              tokens,
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

  Widget _buildItemsInfo(
      TwmtThemeTokens tokens, int currentPage, int totalCount) {
    if (totalCount == 0) {
      return Text(
        '0 entries',
        style: tokens.fontMono.copyWith(fontSize: 12, color: tokens.textDim),
      );
    }
    final startItem = (currentPage - 1) * _itemsPerPage + 1;
    final endItem = (currentPage * _itemsPerPage).clamp(0, totalCount);
    return Text(
      'Showing $startItem–$endItem of $totalCount',
      style: tokens.fontMono.copyWith(fontSize: 12, color: tokens.textDim),
    );
  }

  Widget _buildPageNavigation(
    TwmtThemeTokens tokens,
    WidgetRef ref,
    int currentPage,
    int totalCount,
  ) {
    final totalPages = (totalCount / _itemsPerPage).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();

    final pageNumbers = _computeVisiblePages(currentPage, totalPages);

    return Row(
      children: [
        _NavIcon(
          icon: FluentIcons.chevron_double_left_20_regular,
          tooltip: 'First page',
          tokens: tokens,
          onTap: currentPage > 1
              ? () => ref.read(tmPageStateProvider.notifier).setPage(1)
              : null,
        ),
        const SizedBox(width: 4),
        _NavIcon(
          icon: FluentIcons.chevron_left_24_regular,
          tooltip: 'Previous page',
          tokens: tokens,
          onTap: currentPage > 1
              ? () => ref.read(tmPageStateProvider.notifier).previousPage()
              : null,
        ),
        ...pageNumbers.map((pageNum) {
          if (pageNum == -1) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(
                '…',
                style: tokens.fontMono
                    .copyWith(fontSize: 12, color: tokens.textDim),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: _PageButton(
              pageNumber: pageNum,
              isActive: pageNum == currentPage,
              tokens: tokens,
              onPressed: () =>
                  ref.read(tmPageStateProvider.notifier).setPage(pageNum),
            ),
          );
        }),
        const SizedBox(width: 4),
        _NavIcon(
          icon: FluentIcons.chevron_right_24_regular,
          tooltip: 'Next page',
          tokens: tokens,
          onTap: currentPage < totalPages
              ? () => ref.read(tmPageStateProvider.notifier).nextPage()
              : null,
        ),
        const SizedBox(width: 4),
        _NavIcon(
          icon: FluentIcons.chevron_double_right_20_regular,
          tooltip: 'Last page',
          tokens: tokens,
          onTap: currentPage < totalPages
              ? () =>
                  ref.read(tmPageStateProvider.notifier).setPage(totalPages)
              : null,
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

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final TwmtThemeTokens tokens;
  final VoidCallback? onTap;

  const _NavIcon({
    required this.icon,
    required this.tooltip,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final core = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.panel2,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Icon(
            icon,
            size: 14,
            color: enabled ? tokens.textMid : tokens.textFaint,
          ),
        ),
      ),
    );
    if (!enabled) return core;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: core,
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.pageNumber,
    required this.isActive,
    required this.tokens,
    required this.onPressed,
  });

  final int pageNumber;
  final bool isActive;
  final TwmtThemeTokens tokens;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minWidth: 28),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? tokens.accent : tokens.panel2,
            border: Border.all(
              color: isActive ? tokens.accent : tokens.border,
            ),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Text(
            pageNumber.toString(),
            style: tokens.fontMono.copyWith(
              fontSize: 12,
              color: isActive ? tokens.accentFg : tokens.textMid,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
