import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../../providers/statistics_providers.dart';

/// Line chart showing translations per day over time
class ProgressChart extends StatelessWidget {
  final List<DailyProgress> data;

  const ProgressChart({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            'Translation Progress',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Daily translations over the last ${data.length} days',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 300,
            child: data.isEmpty
                ? Center(
                    child: Text(
                      'No data available',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : SfCartesianChart(
                    primaryXAxis: DateTimeAxis(
                      dateFormat: DateFormat('MM/dd'),
                      majorGridLines: MajorGridLines(
                        color: theme.dividerColor.withValues(alpha: 0.3),
                      ),
                      axisLine: AxisLine(
                        color: theme.dividerColor,
                      ),
                      labelStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    primaryYAxis: NumericAxis(
                      title: AxisTitle(
                        text: 'Translations',
                        textStyle: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      majorGridLines: MajorGridLines(
                        color: theme.dividerColor.withValues(alpha: 0.3),
                      ),
                      axisLine: AxisLine(
                        color: theme.dividerColor,
                      ),
                      labelStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    tooltipBehavior: TooltipBehavior(
                      enable: true,
                      format: 'point.x: point.y translations',
                      color: theme.colorScheme.inverseSurface,
                      textStyle: TextStyle(
                        color: theme.colorScheme.onInverseSurface,
                      ),
                    ),
                    series: <CartesianSeries<DailyProgress, DateTime>>[
                      LineSeries<DailyProgress, DateTime>(
                        dataSource: data,
                        xValueMapper: (DailyProgress progress, _) =>
                            progress.date,
                        yValueMapper: (DailyProgress progress, _) =>
                            progress.translationsCount,
                        color: theme.colorScheme.primary,
                        width: 3,
                        markerSettings: MarkerSettings(
                          isVisible: true,
                          color: theme.colorScheme.primary,
                          borderColor: theme.colorScheme.surface,
                          borderWidth: 2,
                          height: 8,
                          width: 8,
                        ),
                        dataLabelSettings: const DataLabelSettings(
                          isVisible: false,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
