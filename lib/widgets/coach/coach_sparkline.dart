import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../coach/coach_models.dart';
import '../chart_axis.dart';

/// Session values as faint dots plus the moving average as the line, so a
/// single good or bad day doesn't read as a trend.
///
/// [compact] drops the axis labels for the card; the explanation sheet
/// shows the labelled version. Values are converted to the display unit.
class CoachSparkline extends StatelessWidget {
  const CoachSparkline({
    super.key,
    required this.points,
    required this.unit,
    this.compact = true,
    this.showValues = true,
  });

  final List<CoachTrendPoint> points;
  final String unit;
  final bool compact;

  /// False for the high-rep strength index: its numbers look like kg but
  /// aren't, so only the shape is shown.
  final bool showValues;

  double _u(double kg) => unit == 'lbs' ? kg * coachLbsPerKg : kg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (points.length < 2) return const SizedBox.shrink();

    final values = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), _u(points[i].valueKg)),
    ];
    final averages = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), _u(points[i].averageKg)),
    ];
    final ys = [...values.map((s) => s.y), ...averages.map((s) => s.y)];
    final axis = computeNiceAxis(ys, startAtZero: false);

    return Semantics(
      // The card states the numbers in text; the chart is decoration for
      // screen readers.
      excludeSemantics: true,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: axis.minY,
          maxY: axis.maxY,
          lineTouchData: const LineTouchData(enabled: false),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: !compact,
            drawVerticalLine: false,
            horizontalInterval: axis.interval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            show: !compact,
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            // Reserved but empty: keeps the lowest axis label clear of whatever
            // sits under the chart.
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: !compact,
                reservedSize: 12,
                getTitlesWidget: (_, _) => const SizedBox.shrink(),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: showValues,
                reservedSize: 40,
                interval: axis.interval,
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(0),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: values,
              barWidth: 0,
              color: Colors.transparent,
              dotData: FlDotData(
                getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                  radius: compact ? 2 : 3,
                  color: scheme.primary.withValues(alpha: 0.35),
                  strokeWidth: 0,
                ),
              ),
            ),
            LineChartBarData(
              spots: averages,
              barWidth: compact ? 2.5 : 3,
              isStrokeCapRound: true,
              color: scheme.primary,
              dotData: FlDotData(
                checkToShowDot: (spot, _) => spot.x == averages.last.x,
                getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                  radius: compact ? 3.5 : 4.5,
                  color: scheme.primary,
                  strokeWidth: 2,
                  strokeColor: scheme.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.primary.withValues(alpha: 0.18),
                    scheme.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
