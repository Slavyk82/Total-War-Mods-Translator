import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../../../services/search/models/search_result.dart';
import '../../../services/file/file_import_export_service.dart';
import '../../../services/toast_notification_service.dart';
import '../models/search_query_model.dart';
import '../providers/search_providers.dart';
import 'search_result_card.dart';
import 'search_pagination_controls.dart';
import 'fluent_buttons.dart';

/// Search results panel widget
///
/// Displays search results with highlighting, pagination, and navigation.
/// Coordinates between:
/// - Header with search summary and export
/// - Pagination controls
/// - Individual result cards
/// - Empty and error states
class SearchResultsPanel extends ConsumerStatefulWidget {
  /// Callback when user wants to navigate to a result
  final void Function(SearchResult result)? onNavigate;

  /// Whether to show as standalone panel or embedded
  final bool standalone;

  const SearchResultsPanel({
    super.key,
    this.onNavigate,
    this.standalone = false,
  });

  @override
  ConsumerState<SearchResultsPanel> createState() =>
      _SearchResultsPanelState();
}

class _SearchResultsPanelState extends ConsumerState<SearchResultsPanel> {
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(searchResultsProvider(page: _currentPage));

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(context, resultsAsync),

          // Results list
          Expanded(
            child: resultsAsync.when(
              data: (results) => _buildResultsList(context, results),
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (error, stack) => _buildError(context, error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AsyncValue<SearchResultsModel> resultsAsync,
  ) {
    final query = ref.watch(searchQueryProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(FluentIcons.search_24_regular, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  query.isValid ? query.summary : 'No search query',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (resultsAsync.hasValue) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${resultsAsync.value!.totalCount} results',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (resultsAsync.hasValue && resultsAsync.value!.totalCount > 0) ...[
            // Export button
            FluentIconButton(
              icon: FluentIcons.arrow_export_24_regular,
              onPressed: () => _exportResults(resultsAsync.value!),
              tooltip: 'Export Results',
            ),
          ],
          if (widget.standalone) ...[
            const SizedBox(width: 8),
            FluentIconButton(
              icon: FluentIcons.dismiss_24_regular,
              onPressed: () {
                // Clear search
                ref.read(searchQueryProvider.notifier).clear();
              },
              tooltip: 'Close',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsList(
    BuildContext context,
    SearchResultsModel results,
  ) {
    if (results.totalCount == 0) {
      return _buildEmptyState(context);
    }

    return Column(
      children: [
        // Pagination header
        SearchPaginationControls(
          results: results,
          isHeader: true,
          onPreviousPage: () {
            setState(() {
              _currentPage--;
            });
          },
          onNextPage: () {
            setState(() {
              _currentPage++;
            });
          },
        ),

        // Results
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: results.results.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final result = results.results[index];
              final globalIndex =
                  (results.currentPage - 1) * results.pageSize + index + 1;
              return SearchResultCard(
                result: result,
                index: globalIndex,
                total: results.totalCount,
                onNavigate: () => widget.onNavigate?.call(result),
              );
            },
          ),
        ),

        // Pagination footer
        SearchPaginationControls(
          results: results,
          isHeader: false,
          onPreviousPage: () {
            setState(() {
              _currentPage--;
            });
          },
          onNextPage: () {
            setState(() {
              _currentPage++;
            });
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.search_24_regular,
            size: 64,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try different search terms or filters',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading results',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _exportResults(SearchResultsModel results) async {
    try {
      // Show file picker dialog
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Search Results',
        fileName: 'search_results_${DateTime.now().millisecondsSinceEpoch}',
        allowedExtensions: ['csv', 'xlsx'],
        type: FileType.custom,
      );

      if (result == null) {
        // User cancelled
        return;
      }

      final filePath = result;
      final fileExtension = path.extension(filePath).toLowerCase();

      // Convert search results to map format
      final data = results.results.map((r) {
        return {
          'key': r.key ?? '',
          'source_text': r.sourceText ?? '',
          'translated_text': r.translatedText ?? '',
          'status': r.status ?? '',
          'project': r.projectName ?? '',
          'file': r.fileName ?? '',
          'matched_field': r.matchedField,
        };
      }).toList();

      final fileService = FileImportExportService();

      // Export based on file extension
      if (fileExtension == '.csv') {
        final exportResult = await fileService.exportToCsv(
          data: data,
          filePath: filePath,
          headers: ['key', 'source_text', 'translated_text', 'status', 'project', 'file', 'matched_field'],
        );

        if (exportResult.isOk) {
          if (mounted) {
            ToastNotificationService.showSuccess(
              context,
              'Exported ${results.results.length} results to CSV',
            );
          }
        } else {
          if (mounted) {
            ToastNotificationService.showError(
              context,
              'Failed to export: ${exportResult.unwrapErr()}',
            );
          }
        }
      } else if (fileExtension == '.xlsx') {
        final exportResult = await fileService.exportToExcel(
          data: data,
          filePath: filePath,
          sheetName: 'Search Results',
          headers: ['key', 'source_text', 'translated_text', 'status', 'project', 'file', 'matched_field'],
        );

        if (exportResult.isOk) {
          if (mounted) {
            ToastNotificationService.showSuccess(
              context,
              'Exported ${results.results.length} results to Excel',
            );
          }
        } else {
          if (mounted) {
            ToastNotificationService.showError(
              context,
              'Failed to export: ${exportResult.unwrapErr()}',
            );
          }
        }
      } else {
        if (mounted) {
          ToastNotificationService.showWarning(
            context,
            'Unsupported file format. Please use .csv or .xlsx',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ToastNotificationService.showError(
          context,
          'Export failed: ${e.toString()}',
        );
      }
    }
  }
}
