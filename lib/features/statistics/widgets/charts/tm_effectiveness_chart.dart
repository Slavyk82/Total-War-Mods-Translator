import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../providers/statistics_providers.dart';

/// Pie chart showing translation source breakdown
class TmEffectivenessChart extends StatelessWidget {
  final TmEffectiveness data;

  const TmEffectivenessChart({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final List<_ChartData> chartData = [
      if (data.exactMatches > 0)
        _ChartData(
          'Exact Match',
          data.exactMatches,
          Colors.green,
        ),
      if (data.fuzzyHigh > 0)
        _ChartData(
          'Fuzzy High (95%+)',
          data.fuzzyHigh,
          Colors.lightGreen,
        ),
      if (data.fuzzyMedium > 0)
        _ChartData(
          'Fuzzy Medium (85-95%)',
          data.fuzzyMedium,
          Colors.yellow.shade700,
        ),
      if (data.llmTranslations > 0)
        _ChartData(
          'LLM Translation',
          data.llmTranslations,
          Colors.blue,
        ),
      if (data.manualEdits > 0)
        _ChartData(
          'Manual Edit',
          data.manualEdits,
          Colors.orange,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Translation Memory Effectiveness',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Breakdown of translation sources',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 350,
            child: chartData.isEmpty
                ? Center(
                    child: Text(
                      'No data available',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : SfCircularChart(
                    legend: Legend(
                      isVisible: true,
                      position: LegendPosition.right,
                      overflowMode: LegendItemOverflowMode.wrap,
                      textStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    tooltipBehavior: TooltipBehavior(
                      enable: true,
                      format: 'point.x: point.y (point.percentage%)',
                      color: theme.colorScheme.inverseSurface,
                      textStyle: TextStyle(
                        color: theme.colorScheme.onInverseSurface,
                      ),
                    ),
                    series: <CircularSeries>[
                      PieSeries<_ChartData, String>(
                        dataSource: chartData,
                        xValueMapper: (_ChartData data, _) => data.category,
                        yValueMapper: (_ChartData data, _) => data.value,
                        pointColorMapper: (_ChartData data, _) => data.color,
                        dataLabelSettings: DataLabelSettings(
                          isVisible: true,
                          labelPosition: ChartDataLabelPosition.outside,
                          useSeriesColor: false,
                          textStyle: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          connectorLineSettings: ConnectorLineSettings(
                            color: theme.dividerColor,
                            type: ConnectorType.curve,
                          ),
                          labelIntersectAction: LabelIntersectAction.shift,
                        ),
                        dataLabelMapper: (_ChartData data, _) {
                          final percentage =
                              (data.value / this.data.total * 100)
                                  .toStringAsFixed(1);
                          return '$percentage%';
                        },
                        enableTooltip: true,
                        explode: true,
                        explodeIndex: 0,
                        explodeOffset: '10%',
                        radius: '80%',
                      ),
                    ],
                  ),
          ),
          if (chartData.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(color: theme.dividerColor),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _StatItem(
                  label: 'Total',
                  value: data.total.toString(),
                  theme: theme,
                ),
                _StatItem(
                  label: 'TM Matches',
                  value:
                      '${data.exactMatches + data.fuzzyHigh + data.fuzzyMedium}',
                  theme: theme,
                ),
                _StatItem(
                  label: 'LLM Used',
                  value: data.llmTranslations.toString(),
                  theme: theme,
                ),
                _StatItem(
                  label: 'Manual',
                  value: data.manualEdits.toString(),
                  theme: theme,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartData {
  final String category;
  final int value;
  final Color color;

  _ChartData(this.category, this.value, this.color);
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;

  const _StatItem({
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
