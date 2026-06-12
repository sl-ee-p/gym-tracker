import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/progress_provider.dart';
import '../providers/exercise_provider.dart';
import 'workout_history_screen.dart';

/// Resolved vertical-axis bounds for a chart: a padded, "nice"-rounded range
/// with an interval that yields a small number of evenly spaced gridlines.
class _ChartAxis {
  final double minY;
  final double maxY;
  final double interval;

  const _ChartAxis({
    required this.minY,
    required this.maxY,
    required this.interval,
  });
}

/// Computes clean axis bounds for [values]. When [startAtZero] is false the
/// range hugs the data (so progress is easy to read instead of being squashed
/// against a zero baseline), while still padding the line away from the edges.
_ChartAxis _computeNiceAxis(List<double> values, {bool startAtZero = false}) {
  if (values.isEmpty) {
    return const _ChartAxis(minY: 0, maxY: 10, interval: 2.5);
  }

  var dataMin = values.reduce((a, b) => a < b ? a : b);
  var dataMax = values.reduce((a, b) => a > b ? a : b);
  if (startAtZero) dataMin = 0;

  if (dataMin == dataMax) {
    // Single value (or all equal): build a band around it.
    final v = dataMin;
    final span = v.abs() < 1 ? 1.0 : v.abs() * 0.1;
    dataMin = startAtZero ? 0 : v - span;
    dataMax = v + span;
  }

  var range = dataMax - dataMin;
  if (range <= 0) range = 1;

  final pad = range * 0.15;
  var lo = startAtZero ? 0.0 : dataMin - pad;
  var hi = dataMax + pad;
  // Keep non-negative data on a non-negative axis.
  if (lo < 0 && dataMin >= 0) lo = 0;

  final interval = _niceNumber((hi - lo) / 4, round: true);

  // Snap bounds outward to whole intervals so labels are round numbers.
  lo = (lo / interval).floorToDouble() * interval;
  hi = (hi / interval).ceilToDouble() * interval;
  if (lo < 0 && dataMin >= 0) lo = 0;
  if (hi <= lo) hi = lo + interval;

  return _ChartAxis(minY: lo, maxY: hi, interval: interval);
}

/// Rounds [value] to a "nice" number (1, 2, 5 × 10ⁿ) for axis intervals.
double _niceNumber(double value, {required bool round}) {
  if (value <= 0) return 1;
  final exponent = (math.log(value) / math.ln10).floor();
  final fraction = value / math.pow(10, exponent);
  double niceFraction;
  if (round) {
    if (fraction < 1.5) {
      niceFraction = 1;
    } else if (fraction < 3) {
      niceFraction = 2;
    } else if (fraction < 7) {
      niceFraction = 5;
    } else {
      niceFraction = 10;
    }
  } else {
    if (fraction <= 1) {
      niceFraction = 1;
    } else if (fraction <= 2) {
      niceFraction = 2;
    } else if (fraction <= 5) {
      niceFraction = 5;
    } else {
      niceFraction = 10;
    }
  }
  return niceFraction * math.pow(10, exponent).toDouble();
}

/// The text rendered inside a chart point's tooltip.
class _TooltipContent {
  final String header;
  final String value;
  final String? note;

  const _TooltipContent({
    required this.header,
    required this.value,
    this.note,
  });
}

/// Builds touch behaviour shared by the progress charts: a generous tap
/// threshold so points are easy to hit, a highlighted indicator on the touched
/// point, and a tooltip (date, value and any note) for the touched spot.
LineTouchData _buildLineTouchData(
  BuildContext context, {
  required _TooltipContent Function(int index) tooltipBuilder,
}) {
  final primary = Theme.of(context).colorScheme.primary;
  return LineTouchData(
    enabled: true,
    handleBuiltInTouches: true,
    // Larger threshold => the tooltip appears when tapping anywhere near a
    // point, not only directly on the thin line.
    touchSpotThreshold: 28,
    getTouchedSpotIndicator: (barData, spotIndexes) {
      return spotIndexes.map((index) {
        return TouchedSpotIndicatorData(
          FlLine(color: primary.withOpacity(0.4), strokeWidth: 2),
          FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, i) => FlDotCirclePainter(
              radius: 6,
              color: primary,
              strokeWidth: 2,
              strokeColor: Theme.of(context).colorScheme.surface,
            ),
          ),
        );
      }).toList();
    },
    touchTooltipData: LineTouchTooltipData(
      tooltipBgColor: Theme.of(context).colorScheme.inverseSurface,
      tooltipRoundedRadius: 8,
      maxContentWidth: 220,
      fitInsideHorizontally: true,
      fitInsideVertically: true,
      getTooltipItems: (touchedSpots) {
        return touchedSpots.map((spot) {
          final content = tooltipBuilder(spot.x.round());
          final onInverse = Theme.of(context).colorScheme.onInverseSurface;
          final buffer = StringBuffer()
            ..writeln(content.header)
            ..write(content.value);
          if (content.note != null && content.note!.trim().isNotEmpty) {
            buffer.write('\n📝 ${content.note!.trim()}');
          }
          return LineTooltipItem(
            buffer.toString(),
            TextStyle(
              color: onInverse,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          );
        }).toList();
      },
    ),
  );
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Exercise Progress'),
            Tab(text: 'Body Weight'),
            Tab(text: 'Workout History'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              final progressProvider = context.read<ProgressProvider>();
              switch (value) {
                case 'last30':
                  progressProvider.setLast30Days();
                  break;
                case 'last90':
                  progressProvider.setLast90Days();
                  break;
                case 'last6months':
                  progressProvider.setLast6Months();
                  break;
                case 'lastyear':
                  progressProvider.setLastYear();
                  break;
                case 'all':
                  progressProvider.clearDateRange();
                  break;
              }

              final futures = <Future<void>>[
                progressProvider.loadWeightProgress(),
                progressProvider.loadWorkoutStatistics(),
                progressProvider.loadWeightStatistics(),
              ];
              if (progressProvider.selectedExerciseId != null) {
                futures.insert(
                  0,
                  progressProvider
                      .loadExerciseProgress(progressProvider.selectedExerciseId!),
                );
              }
              await Future.wait(futures);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'last30', child: Text('Last 30 Days')),
              const PopupMenuItem(value: 'last90', child: Text('Last 90 Days')),
              const PopupMenuItem(value: 'last6months', child: Text('Last 6 Months')),
              const PopupMenuItem(value: 'lastyear', child: Text('Last Year')),
              const PopupMenuItem(value: 'all', child: Text('All Time')),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ExerciseProgressTab(),
          _WeightProgressTab(),
          _WorkoutHistoryTab(),
        ],
      ),
    );
  }
}

class _ExerciseProgressTab extends StatefulWidget {
  const _ExerciseProgressTab();

  @override
  State<_ExerciseProgressTab> createState() => _ExerciseProgressTabState();
}

class _ExerciseProgressTabState extends State<_ExerciseProgressTab> {
  int? _selectedExerciseId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Load progress for first exercise if available
      final exerciseProvider = context.read<ExerciseProvider>();
      if (exerciseProvider.exercises.isNotEmpty) {
        _selectedExerciseId = exerciseProvider.exercises.first.id!;
        context.read<ProgressProvider>().loadExerciseProgress(_selectedExerciseId!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Exercise Selector
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Consumer<ExerciseProvider>(
            builder: (context, exerciseProvider, child) {
              final selectedValue = exerciseProvider.exercises
                      .any((exercise) => exercise.id == _selectedExerciseId)
                  ? _selectedExerciseId
                  : null;

              if (selectedValue == null && exerciseProvider.exercises.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final selectionIsValid = exerciseProvider.exercises
                      .any((exercise) => exercise.id == _selectedExerciseId);
                  if (selectionIsValid) return;

                  final firstExerciseId = exerciseProvider.exercises.first.id;
                  if (firstExerciseId == null) return;

                  setState(() {
                    _selectedExerciseId = firstExerciseId;
                  });
                  context.read<ProgressProvider>().loadExerciseProgress(firstExerciseId);
                });
              }

              return DropdownButtonFormField<int>(
                value: selectedValue,
                decoration: const InputDecoration(
                  labelText: 'Select Exercise',
                  prefixIcon: Icon(Icons.fitness_center),
                  border: OutlineInputBorder(),
                ),
                items: exerciseProvider.exercises.map((exercise) {
                  return DropdownMenuItem<int>(
                    value: exercise.id,
                    child: Text(exercise.name),
                  );
                }).toList(),
                onChanged: (exerciseId) async {
                  setState(() {
                    _selectedExerciseId = exerciseId;
                  });
                  
                  if (exerciseId != null && mounted) {
                    await context.read<ProgressProvider>().loadExerciseProgress(exerciseId);
                  }
                },
              );
            },
          ),
        ),
        
        // Progress Content
        Expanded(
          child: Consumer<ProgressProvider>(
            builder: (context, progressProvider, child) {
              if (_selectedExerciseId == null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.trending_up,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Select an Exercise',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose an exercise from the dropdown above to view your progress',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (progressProvider.isExerciseLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final progressData = progressProvider.exerciseProgressData;
              
              if (progressData.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bar_chart_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Progress Data',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Complete some workouts with this exercise to see your progress',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Statistics Cards
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Max Weight',
                                    style: Theme.of(context).textTheme.labelMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${progressData.map((d) => d['maxWeight'] as double).reduce((a, b) => a > b ? a : b).toStringAsFixed(1)} kg',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Volume',
                                    style: Theme.of(context).textTheme.labelMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${progressData.fold(0.0, (sum, d) => sum + (d['totalVolume'] as double)).toStringAsFixed(0)} kg',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Progress Chart
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Weight Progress',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 220,
                              child: _buildExerciseChart(context, progressData),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Recent Sessions
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recent Sessions',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            ...progressData.take(5).map((session) {
                              final date = session['date'] as DateTime;
                              final maxWeight = session['maxWeight'] as double;
                              final totalSets = session['totalSets'] as int;
                              
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(_formatDate(date)),
                                subtitle: Text('$totalSets sets'),
                                trailing: Text('${maxWeight.toStringAsFixed(1)} kg'),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildExerciseChart(
    BuildContext context,
    List<Map<String, dynamic>> progressData,
  ) {
    final spots = <FlSpot>[];
    for (var i = 0; i < progressData.length; i++) {
      final value = (progressData[i]['maxWeight'] as num?)?.toDouble() ?? 0;
      spots.add(FlSpot(i.toDouble(), value));
    }

    final axis = _computeNiceAxis(spots.map((s) => s.y).toList());
    final xLabelStep = progressData.length <= 5
        ? 1
        : (progressData.length / 5).ceil();
    final primary = Theme.of(context).colorScheme.primary;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: axis.minY,
        maxY: axis.maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: axis.interval,
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: _buildLineTouchData(
          context,
          tooltipBuilder: (index) {
            final date = progressData[index]['date'] as DateTime;
            final maxWeight = (progressData[index]['maxWeight'] as num).toDouble();
            final note = progressData[index]['note'] as String?;
            return _TooltipContent(
              header: '${date.day}/${date.month}/${date.year}',
              value: '${maxWeight.toStringAsFixed(1)} kg',
              note: note,
            );
          },
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: axis.interval,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(0),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: xLabelStep.toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= progressData.length) {
                  return const SizedBox.shrink();
                }

                final isBoundary = index == progressData.length - 1;
                if (!isBoundary && index % xLabelStep != 0) {
                  return const SizedBox.shrink();
                }

                final date = progressData[index]['date'] as DateTime;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${date.day}/${date.month}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: primary,
            barWidth: 3,
            // Always show dots so every recorded weight is a visible,
            // tappable target.
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(
                radius: spots.length <= 20 ? 4 : 2.5,
                color: primary,
                strokeWidth: 1.5,
                strokeColor: Theme.of(context).colorScheme.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: primary.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightProgressTab extends StatefulWidget {
  const _WeightProgressTab();

  @override
  State<_WeightProgressTab> createState() => _WeightProgressTabState();
}

class _WeightProgressTabState extends State<_WeightProgressTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProgressProvider>().loadWeightProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProgressProvider>(
      builder: (context, progressProvider, child) {
        if (progressProvider.isWeightLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final weightData = progressProvider.weightProgressData;

        if (weightData.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.monitor_weight,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'No Weight Data',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Start logging your weight to track your progress',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        final trend = progressProvider.calculateWeightTrend();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Weight Trend Card
              if (trend['trend'] != 'insufficient_data')
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weight Trend',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              trend['trend'] == 'increasing' 
                                  ? Icons.trending_up
                                  : trend['trend'] == 'decreasing'
                                      ? Icons.trending_down
                                      : Icons.trending_flat,
                              color: trend['trend'] == 'increasing' 
                                  ? Colors.orange
                                  : trend['trend'] == 'decreasing'
                                      ? Colors.green
                                      : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${trend['change'].abs().toStringAsFixed(1)} kg ${trend['trend']}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              
              const SizedBox(height: 16),
              
              // Weight Chart
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weight History',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 220,
                        child: _buildWeightChart(context, weightData),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Recent Weight Entries
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recent Entries',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ...weightData.take(5).map((entry) {
                        final date = entry['date'] as DateTime;
                        final weight = entry['weight'] as double;
                        final notes = entry['notes'] as String?;
                        
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_formatDate(date)),
                          subtitle: notes != null && notes.isNotEmpty ? Text(notes) : null,
                          trailing: Text('${weight.toStringAsFixed(1)} kg'),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildWeightChart(
    BuildContext context,
    List<Map<String, dynamic>> weightData,
  ) {
    final spots = <FlSpot>[];
    for (var i = 0; i < weightData.length; i++) {
      final value = (weightData[i]['weight'] as num?)?.toDouble() ?? 0;
      spots.add(FlSpot(i.toDouble(), value));
    }

    final axis = _computeNiceAxis(spots.map((s) => s.y).toList());
    final xLabelStep = weightData.length <= 5 ? 1 : (weightData.length / 5).ceil();
    final secondary = Theme.of(context).colorScheme.secondary;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: axis.minY,
        maxY: axis.maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: axis.interval,
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: _buildLineTouchData(
          context,
          tooltipBuilder: (index) {
            final date = weightData[index]['date'] as DateTime;
            final weight = (weightData[index]['weight'] as num).toDouble();
            final note = weightData[index]['notes'] as String?;
            return _TooltipContent(
              header: '${date.day}/${date.month}/${date.year}',
              value: '${weight.toStringAsFixed(1)} kg',
              note: note,
            );
          },
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: axis.interval,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(axis.interval < 1 ? 1 : 0),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: xLabelStep.toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= weightData.length) {
                  return const SizedBox.shrink();
                }

                final isBoundary = index == weightData.length - 1;
                if (!isBoundary && index % xLabelStep != 0) {
                  return const SizedBox.shrink();
                }

                final date = weightData[index]['date'] as DateTime;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${date.day}/${date.month}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: secondary,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(
                radius: spots.length <= 20 ? 4 : 2.5,
                color: secondary,
                strokeWidth: 1.5,
                strokeColor: Theme.of(context).colorScheme.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: secondary.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkoutHistoryTab extends StatelessWidget {
  const _WorkoutHistoryTab();

  @override
  Widget build(BuildContext context) {
    return const WorkoutHistoryScreen();
  }
}
