import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/analytics.dart';
import '../providers/progress_provider.dart';
import '../providers/user_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_date.dart';
import '../utils/app_spacing.dart';
import '../utils/weight_format.dart';
import '../widgets/chart_axis.dart';

/// The Progress screen's fourth tab: figures that need more than one exercise
/// to be meaningful — week-over-week, volume by muscle group, and the full
/// personal-record history.
class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  final _service = AnalyticsService();
  late final ProgressProvider _progressProvider;
  late final UserProvider _userProvider;
  Future<AnalyticsSnapshot>? _snapshot;

  /// The range the current snapshot was built for. The app-bar date filter
  /// lives on ProgressProvider, and this tab has no other way to notice it
  /// moved, so an explicit listener compares against these.
  DateTime? _loadedStart;
  DateTime? _loadedEnd;

  /// The weekly goal the current snapshot's consistency card was built
  /// against. The user can edit this in Settings while this tab is open, so
  /// it needs the same explicit-listener treatment as the date range.
  int? _loadedGoal;

  @override
  void initState() {
    super.initState();
    _progressProvider = context.read<ProgressProvider>();
    _userProvider = context.read<UserProvider>();
    _progressProvider.addListener(_onProgressChanged);
    _userProvider.addListener(_onUserChanged);
    _loadedStart = _progressProvider.startDate;
    _loadedEnd = _progressProvider.endDate;
    _loadedGoal = _userProvider.weeklyWorkoutGoal;
    _snapshot = _load();
  }

  @override
  void dispose() {
    _progressProvider.removeListener(_onProgressChanged);
    _userProvider.removeListener(_onUserChanged);
    super.dispose();
  }

  /// ProgressProvider notifies for every domain it owns, so reload only when
  /// the date range this tab actually depends on has changed.
  void _onProgressChanged() {
    if (!mounted) return;
    if (_progressProvider.startDate == _loadedStart &&
        _progressProvider.endDate == _loadedEnd) {
      return;
    }
    _loadedStart = _progressProvider.startDate;
    _loadedEnd = _progressProvider.endDate;
    setState(() => _snapshot = _load());
  }

  /// UserProvider notifies for every profile field, so reload only when the
  /// weekly goal the consistency card depends on has actually changed.
  void _onUserChanged() {
    if (!mounted) return;
    if (_userProvider.weeklyWorkoutGoal == _loadedGoal) return;
    _loadedGoal = _userProvider.weeklyWorkoutGoal;
    setState(() => _snapshot = _load());
  }

  Future<AnalyticsSnapshot> _load() => AnalyticsSnapshot.load(
        _service,
        startDate: _loadedStart,
        endDate: _loadedEnd,
        weeklyGoal: _loadedGoal!,
      );

  void _reload() => setState(() => _snapshot = _load());

  @override
  Widget build(BuildContext context) {
    final weightUnit = context.watch<UserProvider>().weightUnit;

    return FutureBuilder<AnalyticsSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _AnalyticsError(onRetry: _reload);
        }
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _WeekOverWeekCard(
                comparison: data.weekComparison,
                weightUnit: weightUnit,
              ),
              const SizedBox(height: AppSpacing.lg),
              _TrainingTrendCard(
                totals: data.workoutTotals,
                weightUnit: weightUnit,
              ),
              const SizedBox(height: AppSpacing.lg),
              _ConsistencyCard(weeks: data.weeklyAdherence),
              const SizedBox(height: AppSpacing.lg),
              _MuscleGroupVolumeCard(
                weeks: data.muscleGroupWeeks,
                weightUnit: weightUnit,
              ),
              const SizedBox(height: AppSpacing.lg),
              _MuscleGroupBalanceCard(balances: data.muscleGroupBalance),
              const SizedBox(height: AppSpacing.lg),
              _RepRangeBreakdownCard(
                breakdown: data.repRangeBreakdown,
              ),
              const SizedBox(height: AppSpacing.lg),
              _CategoryBreakdownCard(
                volumeByCategory: data.categoryVolume,
                weightUnit: weightUnit,
              ),
              const SizedBox(height: AppSpacing.lg),
              _PersonalRecordsCard(
                records: data.personalRecords,
                weightUnit: weightUnit,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnalyticsError extends StatelessWidget {
  const _AnalyticsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: AppSpacing.lg),
            const Text('Could not load your analytics.',
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared card shell, so every section on this tab has the same header
/// treatment and padding.
class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            child,
          ],
        ),
      ),
    );
  }
}

/// This week against last, as four deltas.
class _WeekOverWeekCard extends StatelessWidget {
  const _WeekOverWeekCard({required this.comparison, required this.weightUnit});

  final WeekComparison comparison;
  final String weightUnit;

  @override
  Widget build(BuildContext context) {
    final current = comparison.current;

    return _AnalyticsCard(
      title: 'This week vs last',
      subtitle: 'Monday to Sunday',
      child: Column(
        children: [
          Row(
            children: [
              _DeltaTile(
                label: 'Workouts',
                value: '${current.workouts}',
                percent: comparison.percentChange((s) => s.workouts),
              ),
              _DeltaTile(
                label: 'Sets',
                value: '${current.sets}',
                percent: comparison.percentChange((s) => s.sets),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _DeltaTile(
                label: 'Volume',
                value: formatWeight(current.volumeKg, unit: weightUnit),
                percent: comparison.percentChange((s) => s.volumeKg),
              ),
              _DeltaTile(
                label: 'Reps',
                value: '${current.reps}',
                percent: comparison.percentChange((s) => s.reps),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeltaTile extends StatelessWidget {
  const _DeltaTile({
    required this.label,
    required this.value,
    required this.percent,
  });

  final String label;
  final String value;

  /// Null when last week was zero — see [WeekComparison.percentChange].
  final double? percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = context.semanticColors.success;
    final rounded = percent?.round() ?? 0;

    // A change under 1% rounds to zero and reads as flat; colouring it
    // green or red would be noise.
    final (color, icon) = percent == null || rounded == 0
        ? (theme.colorScheme.onSurfaceVariant, Icons.remove)
        : rounded > 0
            ? (success, Icons.arrow_upward)
            : (theme.colorScheme.error, Icons.arrow_downward);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 2),
              Text(
                percent == null
                    ? 'no data last week'
                    : '${rounded.abs()}% vs last week',
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Horizontal bounds for an index-based line chart with [pointCount] points.
///
/// A private copy of progress_screen.dart's identical helper: Dart's `_`
/// privacy is per-file, so that one isn't reachable from here, and the logic
/// is a two-liner not worth promoting to a shared file for.
({double minX, double maxX}) _trendXBounds(int pointCount) {
  if (pointCount <= 1) return (minX: -0.5, maxX: 0.5);
  return (minX: 0, maxX: (pointCount - 1).toDouble());
}

/// What the long-term trend chart plots.
enum _TrendMetric {
  workouts('Workouts'),
  sets('Sets'),
  volume('Volume');

  const _TrendMetric(this.label);
  final String label;
}

/// Multi-week/month line chart of volume, workouts or sets — the long-term
/// counterpart to [_WeekOverWeekCard]'s single this-week-vs-last comparison.
///
/// Regrouping on a granularity toggle is cheap and pure ([groupWorkoutTotals]
/// does no I/O), so this holds its own local UI state rather than triggering
/// a reload for every toggle.
class _TrainingTrendCard extends StatefulWidget {
  const _TrainingTrendCard({required this.totals, required this.weightUnit});

  final List<WorkoutTotal> totals;
  final String weightUnit;

  @override
  State<_TrainingTrendCard> createState() => _TrainingTrendCardState();
}

class _TrainingTrendCardState extends State<_TrainingTrendCard> {
  TrendGranularity _granularity = TrendGranularity.week;
  _TrendMetric _metric = _TrendMetric.volume;

  @override
  Widget build(BuildContext context) {
    if (widget.totals.isEmpty) {
      return const _AnalyticsCard(
        title: 'Training trend',
        child: _EmptySection(
          message: 'Log a few workouts and a trend will appear here.',
        ),
      );
    }

    final theme = Theme.of(context);
    final points = groupWorkoutTotals(widget.totals, _granularity);
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), _metricValue(points[i])),
    ];
    final axis = computeNiceAxis(spots.map((s) => s.y).toList(),
        startAtZero: true);
    final xBounds = _trendXBounds(points.length);
    final xLabelStep = points.length <= 6 ? 1 : (points.length / 6).ceil();
    final primary = theme.colorScheme.primary;

    return _AnalyticsCard(
      title: 'Training trend',
      subtitle: _granularity == TrendGranularity.week
          ? 'By week'
          : 'By calendar month',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<_TrendMetric>(
                  value: _metric,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Metric',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final option in _TrendMetric.values)
                      DropdownMenuItem(
                          value: option, child: Text(option.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _metric = value);
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SegmentedButton<TrendGranularity>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: TrendGranularity.week, label: Text('Week')),
                  ButtonSegment(
                      value: TrendGranularity.month, label: Text('Month')),
                ],
                selected: {_granularity},
                onSelectionChanged: (selection) =>
                    setState(() => _granularity = selection.first),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minX: xBounds.minX,
                maxX: xBounds.maxX,
                minY: axis.minY,
                maxY: axis.maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: axis.interval,
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) =>
                        theme.colorScheme.inverseSurface,
                    getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                      final index =
                          spot.x.round().clamp(0, points.length - 1);
                      final point = points[index];
                      return LineTooltipItem(
                        '${_bucketLabel(point.periodStart)}\n'
                        '${_formatMetricValue(point)}',
                        TextStyle(
                          color: theme.colorScheme.onInverseSurface,
                          fontSize: 12,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: axis.interval,
                      getTitlesWidget: (value, meta) => Text(
                        value >= 1000
                            ? '${(value / 1000).toStringAsFixed(1)}k'
                            : value.toStringAsFixed(0),
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: xLabelStep.toDouble(),
                      getTitlesWidget: (value, meta) {
                        final index = value.round();
                        if (index < 0 || index >= points.length) {
                          return const SizedBox.shrink();
                        }
                        final isBoundary = index == points.length - 1;
                        if (!isBoundary && index % xLabelStep != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _bucketLabel(points[index].periodStart),
                            style: theme.textTheme.labelSmall,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    // Straight segments, not a spline — see the identical
                    // note on the per-exercise chart in progress_screen.dart.
                    isCurved: false,
                    color: primary,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                        radius: spots.length <= 20 ? 4 : 2.5,
                        color: primary,
                        strokeWidth: 1.5,
                        strokeColor: theme.colorScheme.surface,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: primary.withValues(alpha: 0.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _metricValue(TrendPoint point) => switch (_metric) {
        _TrendMetric.workouts => point.workouts.toDouble(),
        _TrendMetric.sets => point.sets.toDouble(),
        _TrendMetric.volume => kgToUnit(point.volumeKg, widget.weightUnit),
      };

  String _formatMetricValue(TrendPoint point) => switch (_metric) {
        _TrendMetric.workouts =>
          '${point.workouts} workout${point.workouts == 1 ? '' : 's'}',
        _TrendMetric.sets => '${point.sets} sets',
        _TrendMetric.volume => formatWeight(point.volumeKg,
            unit: widget.weightUnit),
      };

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _bucketLabel(DateTime periodStart) {
    if (_granularity == TrendGranularity.week) {
      return '${periodStart.day}/${periodStart.month}';
    }
    return '${_months[periodStart.month - 1]} '
        "'${(periodStart.year % 100).toString().padLeft(2, '0')}";
  }
}

/// Adherence to the weekly workout goal: a bar per week, coloured by whether
/// it met the goal, against a dashed reference line at the goal itself.
class _ConsistencyCard extends StatelessWidget {
  const _ConsistencyCard({required this.weeks});

  final List<WeeklyAdherence> weeks;

  @override
  Widget build(BuildContext context) {
    if (weeks.isEmpty) {
      return const _AnalyticsCard(
        title: 'Consistency vs. goal',
        child: _EmptySection(
          message: 'Finish a full week of training to see your adherence '
              'here.',
        ),
      );
    }

    final theme = Theme.of(context);
    final success = context.semanticColors.success;
    final goal = weeks.first.goal;
    final rate = weeks.adherenceRate;
    final streak = weeks.currentStreak;

    final axis = computeNiceAxis(
      [
        for (final week in weeks) week.workouts.toDouble(),
        goal.toDouble(),
      ],
      startAtZero: true,
    );
    final xLabelStep = weeks.length <= 8 ? 1 : (weeks.length / 8).ceil();

    return _AnalyticsCard(
      title: 'Consistency vs. goal',
      subtitle: 'Completed workouts per week against a goal of $goal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  rate == null
                      ? 'No data yet'
                      : '${weeks.metCount} of ${weeks.length} weeks · '
                          '${(rate * 100).round()}%',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              // Never a "0-week" or broken-streak message — matching this
              // app's existing achievement philosophy (see Achievement):
              // this is additive good news only, silent otherwise.
              if (streak >= 1) _StreakChip(streak: streak),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                minY: 0,
                maxY: axis.maxY,
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: goal.toDouble(),
                      color: theme.colorScheme.onSurfaceVariant,
                      strokeWidth: 1.5,
                      dashArray: const [6, 4],
                    ),
                  ],
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) =>
                        theme.colorScheme.inverseSurface,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final week = weeks[group.x.toInt()];
                      return BarTooltipItem(
                        '${_weekLabel(week.weekStart)}\n'
                        '${week.workouts} of ${week.goal}',
                        TextStyle(
                          color: theme.colorScheme.onInverseSurface,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: axis.interval,
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: axis.interval,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(0),
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: xLabelStep.toDouble(),
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= weeks.length) {
                          return const SizedBox.shrink();
                        }
                        final isBoundary = index == weeks.length - 1;
                        if (!isBoundary && index % xLabelStep != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _weekLabel(weeks[index].weekStart),
                            style: theme.textTheme.labelSmall,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < weeks.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: weeks[i].workouts.toDouble(),
                          width: weeks.length > 20 ? 6 : 14,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                          // A missed week is drawn neutrally, not in the
                          // error colour — the same anti-punitive stance
                          // WorkoutHeatmapCard takes: nothing here reads as
                          // broken.
                          color: weeks[i].metGoal
                              ? success
                              : theme.colorScheme.surfaceContainerHighest,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _weekLabel(DateTime weekStart) =>
      '${weekStart.day}/${weekStart.month}';
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    return Chip(
      avatar:
          Icon(Icons.local_fire_department, size: 16, color: colors.success),
      label: Text('$streak week${streak == 1 ? '' : 's'} on target'),
      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onSuccessContainer,
          ),
      backgroundColor: colors.successContainer,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

/// Stacked weekly bars, one segment per muscle group.
class _MuscleGroupVolumeCard extends StatelessWidget {
  const _MuscleGroupVolumeCard({
    required this.weeks,
    required this.weightUnit,
  });

  final List<MuscleGroupWeek> weeks;
  final String weightUnit;

  @override
  Widget build(BuildContext context) {
    if (weeks.isEmpty) {
      return const _AnalyticsCard(
        title: 'Volume by muscle group',
        child: _EmptySection(
          message: 'Log some weighted sets and this fills in.',
        ),
      );
    }

    // Rank groups by total volume so the legend and the stack order agree, and
    // so the colour a group gets is stable across the whole card.
    final totals = <String, double>{};
    for (final week in weeks) {
      week.volumeByGroup.forEach((group, volume) {
        totals[group] = (totals[group] ?? 0) + volume;
      });
    }
    final groups = totals.keys.toList()
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    final palette = _groupPalette(context, groups.length);

    // A shared nice axis rather than fl_chart's automatic ticks, which packed
    // the side of the chart with numbers.
    final weekTotals = [
      for (final week in weeks)
        kgToUnit(week.volumeByGroup.values.fold(0.0, (a, b) => a + b),
            weightUnit),
    ];
    final axis = computeNiceAxis(weekTotals, startAtZero: true);

    return _AnalyticsCard(
      title: 'Volume by muscle group',
      subtitle: 'A set counts toward every muscle it trains, so the segments '
          'add up to more than the session total.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                minY: 0,
                maxY: axis.maxY,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) =>
                        Theme.of(context).colorScheme.inverseSurface,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final week = weeks[group.x.toInt()];
                      final total =
                          week.volumeByGroup.values.fold(0.0, (a, b) => a + b);
                      return BarTooltipItem(
                        '${_weekLabel(week.weekStart)}\n'
                        '${formatWeight(total, unit: weightUnit)}',
                        TextStyle(
                          color:
                              Theme.of(context).colorScheme.onInverseSurface,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: axis.interval,
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: axis.interval,
                      getTitlesWidget: (value, meta) => Text(
                        value >= 1000
                            ? '${(value / 1000).toStringAsFixed(1)}k'
                            : value.toStringAsFixed(0),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= weeks.length) {
                          return const SizedBox.shrink();
                        }
                        // Every other label, so they don't collide at 12 weeks.
                        if (weeks.length > 6 && index.isOdd) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _weekLabel(weeks[index].weekStart),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < weeks.length; i++)
                    _stackedBar(i, weeks[i], groups, palette),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < groups.length; i++)
                _LegendChip(label: groups[i], color: palette[i]),
            ],
          ),
        ],
      ),
    );
  }

  BarChartGroupData _stackedBar(
    int index,
    MuscleGroupWeek week,
    List<String> groups,
    List<Color> palette,
  ) {
    // fl_chart stacks by cumulative from/to ranges rather than by segment
    // height, so this walks a running total.
    final items = <BarChartRodStackItem>[];
    var running = 0.0;
    for (var i = 0; i < groups.length; i++) {
      final volume = week.volumeByGroup[groups[i]];
      if (volume == null || volume <= 0) continue;
      final from = kgToUnit(running, weightUnit);
      running += volume;
      items.add(BarChartRodStackItem(
          from, kgToUnit(running, weightUnit), palette[i]));
    }

    return BarChartGroupData(
      x: index,
      barRods: [
        BarChartRodData(
          toY: kgToUnit(running, weightUnit),
          width: 14,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          rodStackItems: items,
          color: Colors.transparent,
        ),
      ],
    );
  }

  /// Evenly spaced hues at a fixed saturation and lightness, tuned per
  /// brightness. Generated rather than a fixed list so an unusual set of
  /// muscle-group tags still gets distinguishable colours.
  List<Color> _groupPalette(BuildContext context, int count) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      for (var i = 0; i < count; i++)
        HSLColor.fromAHSL(
          1,
          (200 + i * (360 / (count == 0 ? 1 : count))) % 360,
          isDark ? 0.45 : 0.55,
          isDark ? 0.62 : 0.48,
        ).toColor(),
    ];
  }

  String _weekLabel(DateTime weekStart) =>
      '${weekStart.day}/${weekStart.month}';
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

/// Which muscle groups are getting disproportionately little (or much) work
/// relative to the rest, as a ranked list rather than a chart — this is a
/// status judgement per group, not a data series.
class _MuscleGroupBalanceCard extends StatelessWidget {
  const _MuscleGroupBalanceCard({required this.balances});

  final List<MuscleGroupBalance> balances;

  @override
  Widget build(BuildContext context) {
    if (balances.isEmpty) {
      return const _AnalyticsCard(
        title: 'Muscle group balance',
        child: _EmptySection(
          message: 'Tag exercises with muscle groups to see this.',
        ),
      );
    }

    final theme = Theme.of(context);
    final underTrained = [
      for (final b in balances)
        if (b.status == BalanceStatus.underTrained) b,
    ];
    final summary = underTrained.isEmpty
        ? 'Looks balanced across your trained muscle groups.'
        : 'Under-trained: ${underTrained.map((b) => b.muscleGroup).join(', ')}';

    return _AnalyticsCard(
      title: 'Muscle group balance',
      subtitle: 'Sets per group against the average, over the selected range',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: underTrained.isEmpty
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.error,
              fontWeight: underTrained.isEmpty ? null : FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final balance in balances)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _MuscleGroupBalanceRow(balance: balance),
            ),
        ],
      ),
    );
  }
}

class _MuscleGroupBalanceRow extends StatelessWidget {
  const _MuscleGroupBalanceRow({required this.balance});

  final MuscleGroupBalance balance;

  /// The meter's full-width value. Ratios beyond this still show as a full
  /// bar rather than being clipped out of view.
  static const _maxRatio = 2.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnder = balance.status == BalanceStatus.underTrained;
    // No "warning" tone exists in this theme (only error/success), so an
    // over-trained group gets the same neutral treatment as a balanced one —
    // only under-trained is flagged.
    final color =
        isUnder ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant;
    final fraction = (balance.ratioToAverage / _maxRatio).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(balance.muscleGroup, style: theme.textTheme.bodyMedium),
            ),
            Text(
              '${balance.sets} set${balance.sets == 1 ? '' : 's'}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: [
              Container(
                height: 6,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(height: 6, color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sets and volume grouped into strength/hypertrophy/endurance rep ranges.
class _RepRangeBreakdownCard extends StatelessWidget {
  const _RepRangeBreakdownCard({required this.breakdown});

  final List<RepRangeSummary> breakdown;

  @override
  Widget build(BuildContext context) {
    // Every band is present in the data even when empty (see
    // AnalyticsService.repRangeBreakdown); only the populated ones belong on
    // the chart and legend.
    final entries = [
      for (final summary in breakdown)
        if (summary.sets > 0) summary,
    ];

    if (entries.isEmpty) {
      return const _AnalyticsCard(
        title: 'Training focus',
        child: _EmptySection(message: 'Log some sets and this fills in.'),
      );
    }

    final totalSets = entries.fold(0, (a, b) => a + b.sets);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = [
      for (var i = 0; i < entries.length; i++)
        HSLColor.fromAHSL(
          1,
          (20 + i * (360 / entries.length)) % 360,
          isDark ? 0.42 : 0.52,
          isDark ? 0.60 : 0.50,
        ).toColor(),
    ];

    return _AnalyticsCard(
      title: 'Training focus',
      subtitle: 'Sets by rep range, over the selected range',
      child: Row(
        children: [
          SizedBox(
            width: 130,
            height: 130,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 34,
                sections: [
                  for (var i = 0; i < entries.length; i++)
                    PieChartSectionData(
                      value: entries[i].sets.toDouble(),
                      color: colors[i],
                      radius: 26,
                      title: entries[i].sets / totalSets >= 0.08
                          ? '${(entries[i].sets / totalSets * 100).round()}%'
                          : '',
                      titleStyle: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < entries.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: colors[i], shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${entries[i].band.label} · '
                            '${entries[i].band.rangeLabel}',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                        Text(
                          '${entries[i].sets} set${entries[i].sets == 1 ? '' : 's'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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

/// Where the training went, as a share of total volume per category.
class _CategoryBreakdownCard extends StatelessWidget {
  const _CategoryBreakdownCard({
    required this.volumeByCategory,
    required this.weightUnit,
  });

  final Map<String, double> volumeByCategory;
  final String weightUnit;

  @override
  Widget build(BuildContext context) {
    if (volumeByCategory.isEmpty) {
      return const _AnalyticsCard(
        title: 'Where your volume goes',
        child: _EmptySection(message: 'No weighted sets in this range yet.'),
      );
    }

    final total = volumeByCategory.values.fold(0.0, (a, b) => a + b);
    final entries = volumeByCategory.entries.toList();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = [
      for (var i = 0; i < entries.length; i++)
        HSLColor.fromAHSL(
          1,
          (150 + i * (360 / entries.length)) % 360,
          isDark ? 0.42 : 0.52,
          isDark ? 0.60 : 0.50,
        ).toColor(),
    ];

    return _AnalyticsCard(
      title: 'Where your volume goes',
      subtitle: 'By exercise category, over the selected range',
      child: Row(
        children: [
          SizedBox(
            width: 130,
            height: 130,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 34,
                sections: [
                  for (var i = 0; i < entries.length; i++)
                    PieChartSectionData(
                      value: entries[i].value,
                      color: colors[i],
                      radius: 26,
                      // Percentages only, and only when the slice is big
                      // enough to hold the text — the legend carries the rest.
                      title: entries[i].value / total >= 0.08
                          ? '${(entries[i].value / total * 100).round()}%'
                          : '',
                      titleStyle: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < entries.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: colors[i], shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entries[i].key,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                        Text(
                          formatWeight(entries[i].value, unit: weightUnit),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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

/// Every personal record, newest first, grouped under its exercise.
class _PersonalRecordsCard extends StatefulWidget {
  const _PersonalRecordsCard({
    required this.records,
    required this.weightUnit,
  });

  final List<PersonalRecordEntry> records;
  final String weightUnit;

  @override
  State<_PersonalRecordsCard> createState() => _PersonalRecordsCardState();
}

class _PersonalRecordsCardState extends State<_PersonalRecordsCard> {
  /// Collapsed by default: with a long history this list is the tallest thing
  /// on the tab, and it's a reference rather than something to scroll past.
  bool _expanded = false;

  static const _collapsedCount = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final records = widget.records;

    if (records.isEmpty) {
      return const _AnalyticsCard(
        title: 'Personal records',
        child: _EmptySection(
          message: 'Beat a previous best and it will be listed here.',
        ),
      );
    }

    final visible =
        _expanded ? records : records.take(_collapsedCount).toList();
    final hidden = records.length - visible.length;

    return _AnalyticsCard(
      title: 'Personal records',
      subtitle: '${records.length} logged',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final record in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(Icons.trending_up,
                      size: 14, color: context.semanticColors.success),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      record.exerciseName,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    record.reps == null
                        ? formatWeight(record.weightKg, unit: widget.weightUnit)
                        : '${formatWeight(record.weightKg, unit: widget.weightUnit)}'
                            ' × ${record.reps}',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 62,
                    child: Text(
                      _shortDate(record.date),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (hidden > 0 || _expanded)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Show less' : 'Show $hidden more'),
              ),
            ),
        ],
      ),
    );
  }

  String _shortDate(DateTime date) {
    final days = daysBetween(date, DateTime.now());
    if (days == 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '${days}d ago';
    return '${date.day}/${date.month}/${date.year % 100}';
  }
}
