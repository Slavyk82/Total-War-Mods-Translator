import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/translation_version.dart';
import '../providers/editor_providers.dart';

/// Left sidebar with filters and statistics
///
/// Displays status filters, TM source filters, and stats summary
class EditorSidebar extends ConsumerWidget {
  final String projectId;
  final String languageId;

  const EditorSidebar({
    super.key,
    required this.projectId,
    required this.languageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(editorFilterProvider);
    final statsAsync = ref.watch(editorStatsProvider(projectId, languageId));

    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Filters
            _buildSectionHeader(context, 'Status'),
            const SizedBox(height: 8),
            _buildStatusFilter(
              context,
              ref,
              TranslationVersionStatus.pending,
              'Pending',
              FluentIcons.circle_24_regular,
              Colors.grey,
            ),
            _buildStatusFilter(
              context,
              ref,
              TranslationVersionStatus.translating,
              'Translating',
              FluentIcons.arrow_sync_24_regular,
              Colors.blue,
            ),
            _buildStatusFilter(
              context,
              ref,
              TranslationVersionStatus.translated,
              'Translated',
              FluentIcons.checkmark_circle_24_regular,
              Colors.green,
            ),
            _buildStatusFilter(
              context,
              ref,
              TranslationVersionStatus.reviewed,
              'Reviewed',
              FluentIcons.checkmark_circle_24_filled,
              Colors.teal,
            ),
            _buildStatusFilter(
              context,
              ref,
              TranslationVersionStatus.approved,
              'Approved',
              FluentIcons.checkmark_circle_24_filled,
              Colors.green.shade700,
            ),
            _buildStatusFilter(
              context,
              ref,
              TranslationVersionStatus.needsReview,
              'Needs Review',
              FluentIcons.warning_24_regular,
              Colors.orange,
            ),
            const SizedBox(height: 16),

            // TM Source Filters
            _buildSectionHeader(context, 'TM Source'),
            const SizedBox(height: 8),
            _buildTmSourceFilter(
              context,
              ref,
              TmSourceType.exactMatch,
              'Exact Match',
            ),
            _buildTmSourceFilter(
              context,
              ref,
              TmSourceType.fuzzyMatch,
              'Fuzzy Match',
            ),
            _buildTmSourceFilter(
              context,
              ref,
              TmSourceType.llm,
              'LLM',
            ),
            _buildTmSourceFilter(
              context,
              ref,
              TmSourceType.manual,
              'Manual',
            ),
            _buildTmSourceFilter(
              context,
              ref,
              TmSourceType.none,
              'None',
            ),
            const SizedBox(height: 16),

            // Statistics
            _buildSectionHeader(context, 'Statistics'),
            const SizedBox(height: 8),
            statsAsync.when(
              data: (stats) => _buildStatsSection(context, stats),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (_, _) => const Text('Error loading stats'),
            ),

            // Clear Filters Button
            if (filterState.hasActiveFilters) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: _buildClearFiltersButton(context, ref),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildStatusFilter(
    BuildContext context,
    WidgetRef ref,
    TranslationVersionStatus status,
    String label,
    IconData icon,
    Color color,
  ) {
    final filterState = ref.watch(editorFilterProvider);
    final isActive = filterState.statusFilters.contains(status);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final currentFilters = Set<TranslationVersionStatus>.from(
            filterState.statusFilters,
          );
          if (isActive) {
            currentFilters.remove(status);
          } else {
            currentFilters.add(status);
          }
          ref.read(editorFilterProvider.notifier).setStatusFilters(
            currentFilters,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
              ? color.withValues(alpha: 0.1)
              : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                isActive
                  ? FluentIcons.checkbox_checked_24_filled
                  : FluentIcons.checkbox_unchecked_24_regular,
                size: 16,
                color: isActive ? color : Colors.grey,
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive ? color : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTmSourceFilter(
    BuildContext context,
    WidgetRef ref,
    TmSourceType type,
    String label,
  ) {
    final filterState = ref.watch(editorFilterProvider);
    final isActive = filterState.tmSourceFilters.contains(type);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final currentFilters = Set<TmSourceType>.from(
            filterState.tmSourceFilters,
          );
          if (isActive) {
            currentFilters.remove(type);
          } else {
            currentFilters.add(type);
          }
          ref.read(editorFilterProvider.notifier).setTmSourceFilters(
            currentFilters,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                isActive
                  ? FluentIcons.checkbox_checked_24_filled
                  : FluentIcons.checkbox_unchecked_24_regular,
                size: 16,
                color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context, EditorStats stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatRow('Total', stats.totalUnits.toString()),
        _buildStatRow('Pending', stats.pendingCount.toString()),
        _buildStatRow('Translated', stats.translatedCount.toString()),
        _buildStatRow('Reviewed', stats.reviewedCount.toString()),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: stats.completionPercentage / 100,
          backgroundColor: Colors.grey.withValues(alpha: 0.2),
        ),
        const SizedBox(height: 4),
        Text(
          '${stats.completionPercentage.toStringAsFixed(1)}% complete',
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClearFiltersButton(BuildContext context, WidgetRef ref) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          ref.read(editorFilterProvider.notifier).clearFilters();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.grey.withValues(alpha: 0.3),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(FluentIcons.filter_dismiss_24_regular, size: 16),
              SizedBox(width: 6),
              Text(
                'Clear Filters',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
