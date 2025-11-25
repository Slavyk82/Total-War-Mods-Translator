import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../providers/glossary_providers.dart';

/// Panel displaying glossary statistics
class GlossaryStatisticsPanel extends ConsumerWidget {
  final String glossaryId;

  const GlossaryStatisticsPanel({
    super.key,
    required this.glossaryId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(glossaryStatisticsProvider(glossaryId));

    return Container(
      width: 250,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
      child: statsAsync.when(
        data: (stats) => _buildStatistics(context, stats),
        loading: () => _buildLoadingState(context),
        error: (error, stack) => _buildErrorState(context, error),
      ),
    );
  }

  Widget _buildStatistics(BuildContext context, GlossaryStatistics stats) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                FluentIcons.data_pie_24_regular,
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Statistics',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Total Entries
          _buildStatCard(
            context,
            icon: FluentIcons.book_24_regular,
            label: 'Total Entries',
            value: stats.totalEntries.toString(),
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),

          // By Language
          Text(
            'By Language',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          if (stats.entriesByLanguagePair.isEmpty)
            Text(
              'No languages',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
            )
          else
            ...stats.entriesByLanguagePair.entries
                .map((entry) => _buildLanguageItem(context, entry.key, entry.value)),
          const SizedBox(height: 16),

          // Usage Stats
          Text(
            'Usage',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          _buildStatRow(
            context,
            'Used in translations',
            stats.usedInTranslations.toString(),
          ),
          _buildStatRow(
            context,
            'Unused',
            stats.unusedEntries.toString(),
          ),
          _buildStatRow(
            context,
            'Usage rate',
            '${(stats.usageRate * 100).toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 16),

          // Quality Metrics
          Text(
            'Quality',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          _buildStatRow(
            context,
            'Consistency score',
            '${(stats.consistencyScore * 100).toStringAsFixed(1)}%',
          ),
          _buildStatRow(
            context,
            'Duplicates',
            stats.duplicatesDetected.toString(),
            isWarning: stats.duplicatesDetected > 0,
          ),
          _buildStatRow(
            context,
            'Missing translations',
            stats.missingTranslations.toString(),
            isWarning: stats.missingTranslations > 0,
          ),
          const SizedBox(height: 16),

          // Other Stats
          Text(
            'Other',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          _buildStatRow(
            context,
            'Case sensitive',
            stats.caseSensitiveTerms.toString(),
          ),
          const SizedBox(height: 24),

          // Refresh button
          SizedBox(
            width: double.infinity,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  // Force refresh statistics
                  final container = ProviderScope.containerOf(context);
                  container.invalidate(glossaryStatisticsProvider(glossaryId));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        FluentIcons.arrow_sync_24_regular,
                        size: 20,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Refresh Stats',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
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

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.0),
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
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageItem(BuildContext context, String language, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(
            FluentIcons.globe_24_regular,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              language.toUpperCase(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            count.toString(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(
    BuildContext context,
    String label,
    String value, {
    bool isWarning = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isWarning
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24.0),
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading statistics',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
