import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../models/search_query_model.dart';
import 'fluent_buttons.dart';

/// Pagination controls for search results
///
/// Displays pagination navigation with:
/// - Previous/Next page buttons
/// - Current page and range information
/// - Disabled state when no more pages
class SearchPaginationControls extends StatelessWidget {
  final SearchResultsModel results;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final bool isHeader;

  const SearchPaginationControls({
    super.key,
    required this.results,
    this.onPreviousPage,
    this.onNextPage,
    this.isHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isHeader) {
      return _buildHeader(context);
    } else {
      return _buildFooter(context);
    }
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          FluentIconButton(
            icon: FluentIcons.chevron_left_24_regular,
            onPressed: results.hasPreviousPage ? onPreviousPage : null,
            tooltip: 'Previous Page',
          ),
          const SizedBox(width: 12),
          Text(
            results.rangeText,
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(width: 12),
          FluentIconButton(
            icon: FluentIcons.chevron_right_24_regular,
            onPressed: results.hasNextPage ? onNextPage : null,
            tooltip: 'Next Page',
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FluentIconButton(
            icon: FluentIcons.chevron_left_24_regular,
            onPressed: results.hasPreviousPage ? onPreviousPage : null,
            tooltip: 'Previous Page',
          ),
          const SizedBox(width: 12),
          Text(
            'Page ${results.currentPage} of ${results.totalPages}',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(width: 12),
          FluentIconButton(
            icon: FluentIcons.chevron_right_24_regular,
            onPressed: results.hasNextPage ? onNextPage : null,
            tooltip: 'Next Page',
          ),
        ],
      ),
    );
  }
}
