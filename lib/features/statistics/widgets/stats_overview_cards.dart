import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../providers/statistics_providers.dart';

/// Stats overview cards displaying key metrics
class StatsOverviewCards extends StatelessWidget {
  final StatisticsOverview overview;

  const StatsOverviewCards({
    super.key,
    required this.overview,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1200;
        final cardsPerRow = isWide ? 4 : 2;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _StatCard(
              icon: FluentIcons.folder_24_regular,
              label: 'Total Projects',
              value: overview.totalProjects.toString(),
              color: Colors.blue,
            ),
            _StatCard(
              icon: FluentIcons.translate_24_regular,
              label: 'Total Translations',
              value: _formatNumber(overview.totalTranslations),
              color: Colors.green,
            ),
            _StatCard(
              icon: FluentIcons.text_bullet_list_tree_24_regular,
              label: 'TM Reuse Rate',
              value: '${overview.tmReuseRate.toStringAsFixed(1)}%',
              color: Colors.teal,
            ),
            _StatCard(
              icon: FluentIcons.star_24_regular,
              label: 'Average Quality',
              value: '${overview.averageQuality.toStringAsFixed(1)}%',
              color: Colors.amber,
            ),
          ]
              .take(cardsPerRow * ((4 / cardsPerRow).ceil()))
              .map((card) => SizedBox(
                    width: (constraints.maxWidth - (16 * (cardsPerRow - 1))) /
                        cardsPerRow,
                    child: card,
                  ))
              .toList(),
        );
      },
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

/// Individual stat card
class _StatCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _isHovered
              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isHovered
                ? widget.color.withValues(alpha: 0.3)
                : theme.dividerColor,
            width: _isHovered ? 2 : 1,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              widget.value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
