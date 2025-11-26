import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import '../providers/tm_providers.dart';

/// Statistics panel showing TM metrics and insights
class TmStatisticsPanel extends ConsumerWidget {
  const TmStatisticsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtersState = ref.watch(tmFilterStateProvider);
    final statsAsync = ref.watch(tmStatisticsProvider(
      targetLang: filtersState.targetLanguage,
    ));

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(
                  FluentIcons.data_bar_vertical_24_regular,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Statistics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      ref.invalidate(tmStatisticsProvider);
                    },
                    child: Icon(
                      FluentIcons.arrow_clockwise_24_regular,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Expanded(
            child: statsAsync.when(
              data: (stats) => _buildStatsContent(context, stats),
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (error, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        FluentIcons.error_circle_24_regular,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Failed to load statistics',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsContent(BuildContext context, TmStatistics stats) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total Entries
          _buildBigStat(
            context,
            label: 'Total Entries',
            value: stats.totalEntries.toString(),
            icon: FluentIcons.database_24_regular,
            color: Theme.of(context).colorScheme.primary,
          ),

          const SizedBox(height: 24),

          // Language Pairs
          _buildSectionHeader(context, 'Language Pairs'),
          const SizedBox(height: 8),
          ...stats.entriesByLanguagePair.entries.map(
            (entry) => _buildLanguagePairStat(
              context,
              languagePair: entry.key,
              count: entry.value,
            ),
          ),

          const SizedBox(height: 24),

          // Performance Stats
          _buildSectionHeader(context, 'Performance'),
          const SizedBox(height: 8),
          _buildSmallStat(
            context,
            label: 'Total Reuse',
            value: stats.totalReuseCount.toString(),
          ),
          const SizedBox(height: 4),
          _buildSmallStat(
            context,
            label: 'Tokens Saved',
            value: _formatNumber(stats.tokensSaved),
          ),
          const SizedBox(height: 4),
          _buildSmallStat(
            context,
            label: 'Reuse Rate',
            value: '${(stats.reuseRate * 100).toStringAsFixed(1)}%',
          ),
        ],
      ),
    );
  }

  Widget _buildBigStat(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _buildLanguagePairStat(
    BuildContext context, {
    required String languagePair,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: [
          Icon(
            FluentIcons.translate_24_regular,
            size: 16,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              languagePair,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            count.toString(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallStat(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
        ),
      ],
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }
}
