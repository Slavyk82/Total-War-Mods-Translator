import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../providers/statistics_providers.dart';
import '../widgets/stats_overview_cards.dart';
import '../widgets/charts/progress_chart.dart';
import '../widgets/charts/tm_effectiveness_chart.dart';
import '../widgets/project_stats_table.dart';

/// Statistics screen showing project analytics and metrics
class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  final int _progressDays = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final overviewAsync = ref.watch(statisticsOverviewProvider);
    final progressAsync = ref.watch(dailyProgressDataProvider(_progressDays));
    final tmAsync = ref.watch(tmEffectivenessDataProvider);
    final projectsAsync = ref.watch(projectStatsDataProvider);

    return FluentScaffold(
      backgroundColor: theme.colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: theme.colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            title: Row(
              children: [
                Icon(
                  FluentIcons.data_bar_vertical_24_regular,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Statistics',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: [
              _RefreshButton(onPressed: () => _refreshData()),
              const SizedBox(width: 8),
              _ExportButton(onPressed: () => _exportStatistics()),
              const SizedBox(width: 16),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                overviewAsync.when(
                  data: (overview) => StatsOverviewCards(overview: overview),
                  loading: () => const _LoadingCard(height: 140),
                  error: (error, stack) => _ErrorCard(error: error.toString()),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: progressAsync.when(
                        data: (data) => ProgressChart(data: data),
                        loading: () => const _LoadingCard(height: 360),
                        error: (error, stack) =>
                            _ErrorCard(error: error.toString()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: tmAsync.when(
                        data: (data) => TmEffectivenessChart(data: data),
                        loading: () => const _LoadingCard(height: 360),
                        error: (error, stack) =>
                            _ErrorCard(error: error.toString()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                projectsAsync.when(
                  data: (projects) => ProjectStatsTable(projects: projects),
                  loading: () => const _LoadingCard(height: 400),
                  error: (error, stack) => _ErrorCard(error: error.toString()),
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _refreshData() {
    ref.invalidate(statisticsOverviewProvider);
    ref.invalidate(dailyProgressDataProvider);
    ref.invalidate(monthlyUsageDataProvider);
    ref.invalidate(tmEffectivenessDataProvider);
    ref.invalidate(projectStatsDataProvider);

    FluentToast.success(context, 'Statistics refreshed');
  }

  void _exportStatistics() {
    FluentToast.info(context, 'Export feature coming soon');
  }
}

/// Refresh button with Fluent Design styling
class _RefreshButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _RefreshButton({required this.onPressed});

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? theme.colorScheme.primary
                  : theme.dividerColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.arrow_clockwise_24_regular,
                size: 18,
                color: _isHovered
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Text(
                'Refresh',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _isHovered
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Export button with Fluent Design styling
class _ExportButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _ExportButton({required this.onPressed});

  @override
  State<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<_ExportButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered
                ? theme.colorScheme.primary
                : theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.primary,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.arrow_download_24_regular,
                size: 18,
                color: _isHovered
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                'Export',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _isHovered
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading card placeholder
class _LoadingCard extends StatelessWidget {
  final double height;

  const _LoadingCard({required this.height});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

/// Error card display
class _ErrorCard extends StatelessWidget {
  final String error;

  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.error),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Error loading data: $error',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
