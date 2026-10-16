import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/analytics.dart';
import '../models/progress_date_range.dart';
import '../providers/progress_provider.dart';
import '../providers/exercise_provider.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import '../theme/numeric_text_styles.dart';
import '../utils/app_spacing.dart';
import '../utils/personal_records.dart';
import '../utils/weight_format.dart';
import '../widgets/chart_axis.dart';
import '../widgets/app_overflow_menu.dart';
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/weight_goal_card.dart';
import 'analytics_tab.dart';
import 'workout_detail_screen.dart';
import 'workout_history_screen.dart';

/// Shown when a progress query throws, instead of the friendly "no data yet"
/// empty state — those look identical to the user but mean opposite things,
/// and only one of them is worth retrying.
class _ChartLoadError extends StatelessWidget {
  const _ChartLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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

/// Horizontal bounds for an index-based chart with [pointCount] points.
///
/// A single point would otherwise give `minX == maxX == 0`, a zero-width axis:
/// fl_chart doesn't crash on it, but the lone dot is pinned to the very left
/// edge with no line and no fill, so a chart with exactly one session looked
/// empty. Padding to ±0.5 centres it instead.
({double minX, double maxX}) _computeXBounds(int pointCount) {
  if (pointCount <= 1) return (minX: -0.5, maxX: 0.5);
  return (minX: 0, maxX: (pointCount - 1).toDouble());
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
          FlLine(color: primary.withValues(alpha: 0.4), strokeWidth: 2),
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
      getTooltipColor: (_) => Theme.of(context).colorScheme.inverseSurface,
      tooltipBorderRadius: BorderRadius.circular(8),
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

/// Shows the most recent [initialCount] entries from an ascending
/// (oldest-first) data list — the sort order required by the progress
/// charts — reversed for newest-first display, with a "Show more" control
/// that reveals [batchSize] additional (older) entries at a time from the
/// same already-loaded list. Purely a client-side reveal: no re-fetching,
/// no re-sorting of the caller's list.
///
/// Give this widget a `key` derived from [ascendingData]'s identity (e.g.
/// `ObjectKey(ascendingData)`) so the visible count resets whenever the
/// caller loads a new list (switching exercises, changing the date-range
/// filter, etc) — the provider always reassigns a fresh List instance on
/// reload, so ObjectKey changes exactly when the data actually changes,
/// and Flutter remounts fresh state automatically. No manual bookkeeping.
class _RecentEntriesList extends StatefulWidget {
  final List<Map<String, dynamic>> ascendingData;
  final Widget Function(BuildContext context, Map<String, dynamic> entry) itemBuilder;

  /// Both call sites want the same pagination, so these are constants rather
  /// than constructor parameters no one ever passes.
  static const int initialCount = 5;
  static const int batchSize = 10;

  const _RecentEntriesList({
    super.key,
    required this.ascendingData,
    required this.itemBuilder,
  });

  @override
  State<_RecentEntriesList> createState() => _RecentEntriesListState();
}

class _RecentEntriesListState extends State<_RecentEntriesList> {
  late int _visibleCount = _RecentEntriesList.initialCount;

  @override
  Widget build(BuildContext context) {
    // Newest-first for display only; the caller's ascending list (required
    // for the charts) is never mutated or reassigned.
    final descending = widget.ascendingData.reversed.toList();
    final visibleCount = _visibleCount.clamp(0, descending.length);
    final visible = descending.take(visibleCount).toList();
    final remaining = descending.length - visibleCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in visible) widget.itemBuilder(context, entry),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _visibleCount = visibleCount + _RecentEntriesList.batchSize;
                  });
                },
                child: Text('Show ${math.min(_RecentEntriesList.batchSize, remaining)} more'),
              ),
            ),
          ),
      ],
    );
  }
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, this.initialExerciseId});

  /// Preselects the Exercise tab's dropdown, e.g. when arriving here from a
  /// workout's "See stats" action. Ignored once the user picks a different
  /// exercise — that pick becomes the new remembered default as usual.
  final int? initialExerciseId;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  /// Read from the profile rather than held here. This screen is rebuilt from
  /// scratch every time you switch nav tabs (the shell uses an
  /// AnimatedSwitcher), so a local field reset to the default on every visit
  /// while the provider kept the range you'd actually picked — the chip and
  /// the data disagreed. Persisting it also carries the choice across
  /// restarts.
  ProgressDateRange get _selectedRange =>
      ProgressDateRange.fromName(context.watch<UserProvider>().progressDateRange);

  /// Tracked separately from `_tabController.index` so `canPop` below is
  /// recomputed when it changes. A TabBar rebuilds itself on a swipe, but this
  /// State does not, so reading the controller directly in build would leave
  /// the back-button behaviour stuck at whatever tab was active last build.
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.index == _tabIndex) return;
    setState(() => _tabIndex = _tabController.index);
  }

  Future<void> _applyDateRange(ProgressDateRange range) async {
    final progressProvider = context.read<ProgressProvider>();
    await context.read<UserProvider>().updateProgressDateRange(range.name);
    if (!mounted) return;
    range.applyTo(progressProvider);

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
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// Back steps to the first tab before leaving the screen, mirroring how the
  /// bottom nav behaves in HomeScreen — a tab switch isn't a route, so without
  /// this the gesture skips straight past three tabs of context.
  void _handleSystemBack(bool didPop, Object? result) {
    if (didPop) return;
    _tabController.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tabIndex == 0,
      onPopInvokedWithResult: _handleSystemBack,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Progress'),
              const SizedBox(width: AppSpacing.sm),
              // The active range has to be visible on the screen itself: a
              // filter you can't see is indistinguishable from missing data.
              Chip(
                label: Text(_selectedRange.shortLabel),
                labelStyle: Theme.of(context).textTheme.labelSmall,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          bottom: TabBar(
            controller: _tabController,
            // Scrollable now that there are four: fixed tabs squeeze the
            // labels to the point of truncation on a narrow phone.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Exercise'),
              Tab(text: 'Analytics'),
              Tab(text: 'Body Weight'),
              Tab(text: 'History'),
            ],
          ),
          actions: [
            AppOverflowMenu(
              icon: Icons.date_range,
              tooltip: 'Date range',
              items: [
                for (final range in ProgressDateRange.values)
                  AppMenuItem(
                    label: range.label,
                    icon: range.icon,
                    isSelected: range == _selectedRange,
                    onSelected: () => _applyDateRange(range),
                  ),
              ],
            ),
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _ExerciseProgressTab(initialExerciseId: widget.initialExerciseId),
            const AnalyticsTab(),
            const _WeightProgressTab(),
            const _WorkoutHistoryTab(),
          ],
        ),
      ),
    );
  }
}

/// Best weight at each rep count — the numbers the rep-PR rule compares
/// against, so "New best" on a 100 kg × 8 is explained by the 8-rep row.
class _RepMaxCard extends StatelessWidget {
  const _RepMaxCard({required this.repMaxes, required this.weightUnit});

  final List<RepMax> repMaxes;
  final String weightUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rep maxes', style: theme.textTheme.titleMedium),
            Text('Heaviest weight for at least that many reps, all-time',
                style: muted),
            const SizedBox(height: 8),
            for (final repMax in repMaxes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        '${repMax.reps} rep${repMax.reps == 1 ? '' : 's'}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        formatWeight(repMax.weightKg, unit: weightUnit),
                        style: NumericTextStyles.body(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '${repMax.date.day}/${repMax.date.month}/${repMax.date.year}',
                      style: muted,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseProgressTab extends StatefulWidget {
  const _ExerciseProgressTab({this.initialExerciseId});

  final int? initialExerciseId;

  @override
  State<_ExerciseProgressTab> createState() => _ExerciseProgressTabState();
}

class _ExerciseProgressTabState extends State<_ExerciseProgressTab> {

  /// The display unit for every weight this screen renders. Stored weights
  /// are always kg; formatWeight converts before formatting.
  String get weightUnit => context.watch<UserProvider>().weightUnit;

  int? _selectedExerciseId;
  Map<String, dynamic>? _personalRecords;
  List<RepMax> _repMaxes = const [];

  /// What the chart plots and how it draws it. Local rather than persisted:
  /// this is a "how do I want to look at it right now" choice, not a setting.
  ExerciseMetric _metric = ExerciseMetric.maxWeight;
  ChartStyle _chartStyle = ChartStyle.line;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _selectInitialExercise());
  }

  /// Opens on the exercise passed in via [ProgressScreen.initialExerciseId]
  /// (e.g. a workout's "See stats" action), then the one the user last chose,
  /// then the one they most recently trained, then the first in the library.
  ///
  /// The saved choice comes before "most recently trained" because this
  /// screen is rebuilt from scratch on every nav-tab switch (the shell uses an
  /// AnimatedSwitcher), so without it the tab silently snapped back to "most
  /// recently trained" every visit — the same complaint the persisted date
  /// range fixed.
  ///
  /// Every step is guarded against the id belonging to a since-deleted
  /// exercise: deletion is a hard delete with no cascade, so both a saved id
  /// and an old set can outlive their exercise.
  Future<void> _selectInitialExercise() async {
    if (!mounted) return;
    final exerciseProvider = context.read<ExerciseProvider>();
    final progressProvider = context.read<ProgressProvider>();
    final userProvider = context.read<UserProvider>();

    bool exists(int? id) =>
        id != null && exerciseProvider.exercises.any((e) => e.id == id);

    final requestedId = widget.initialExerciseId;
    final savedId = userProvider.lastProgressExerciseId;
    int? id;

    if (exists(requestedId)) {
      id = requestedId;
      // Treated like an explicit pick, so it also becomes the default the
      // next time this tab opens without a requested exercise.
      await userProvider.updateLastProgressExercise(id);
      if (!mounted) return;
    } else if (exists(savedId)) {
      id = savedId;
    } else {
      // Forget an id that no longer resolves — but only once the library has
      // actually loaded, so a mount that races ExerciseProvider doesn't wipe a
      // still-valid choice.
      if (savedId != null && exerciseProvider.exercises.isNotEmpty) {
        await userProvider.updateLastProgressExercise(null);
        if (!mounted) return;
      }
      final trainedId = await progressProvider.getMostRecentlyTrainedExerciseId();
      if (!mounted) return;
      id = exists(trainedId)
          ? trainedId
          : (exerciseProvider.exercises.isEmpty
              ? null
              : exerciseProvider.exercises.first.id);
    }
    if (id == null) return;

    setState(() => _selectedExerciseId = id);
    await progressProvider.loadExerciseProgress(id);
    await _loadPersonalRecords(id);
  }

  Future<void> _loadPersonalRecords(int exerciseId) async {
    final progressProvider = context.read<ProgressProvider>();
    final records = await progressProvider.getPersonalRecords(exerciseId);
    final repMaxes = await progressProvider.getRepMaxes(exerciseId);
    if (!mounted) return;
    setState(() {
      _personalRecords = records;
      _repMaxes = repMaxes;
    });
  }

  Future<void> _pickExercise() async {
    final selected = await showExercisePickerSheet(context, title: 'Select Exercise');
    if (selected?.id == null || !mounted) return;

    final id = selected!.id!;
    final userProvider = context.read<UserProvider>();
    final progressProvider = context.read<ProgressProvider>();
    setState(() {
      _selectedExerciseId = id;
    });
    // Only an explicit pick is remembered. The "most recently trained"
    // default keeps working until the user actually chooses something.
    await userProvider.updateLastProgressExercise(id);
    if (!mounted) return;
    await progressProvider.loadExerciseProgress(id);
    await _loadPersonalRecords(id);
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
              final selectedExercise = _selectedExerciseId != null
                  ? exerciseProvider.getExerciseById(_selectedExerciseId!)
                  : null;

              // Recovery path for the startup race: ExerciseProvider may still
              // have been loading when initState ran. Goes through
              // _selectInitialExercise so it picks the same exercise and also
              // refreshes the all-time PR caption — the old inline version
              // loaded progress only, leaving that caption stale.
              if (selectedExercise == null && exerciseProvider.exercises.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final selectionIsValid = exerciseProvider.exercises
                      .any((exercise) => exercise.id == _selectedExerciseId);
                  if (selectionIsValid) return;
                  _selectInitialExercise();
                });
              }

              return InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: exerciseProvider.exercises.isEmpty ? null : _pickExercise,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Select Exercise',
                    prefixIcon: Icon(Icons.fitness_center),
                    suffixIcon: Icon(Icons.arrow_drop_down),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    selectedExercise?.name ??
                        (exerciseProvider.exercises.isEmpty
                            ? 'No exercises yet'
                            : 'Tap to choose an exercise'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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

              if (progressProvider.exerciseError != null) {
                return _ChartLoadError(
                  message: progressProvider.exerciseError!,
                  onRetry: () => progressProvider
                      .loadExerciseProgress(_selectedExerciseId!),
                );
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
                              child: Builder(builder: (context) {
                                final visibleMaxWeight = progressData
                                    .map((d) => d['maxWeight'] as double)
                                    .reduce((a, b) => a > b ? a : b);
                                final allTimeMaxWeight =
                                    (_personalRecords?['maxWeight'] as num?)?.toDouble();
                                final showAllTimeCaption = allTimeMaxWeight != null &&
                                    allTimeMaxWeight > visibleMaxWeight;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.trending_up,
                                          size: 18,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'MAX WEIGHT',
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                letterSpacing: 0.5,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatWeight(visibleMaxWeight, unit: weightUnit),
                                      style: NumericTextStyles.title(
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    if (showAllTimeCaption) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'All-time: ${formatWeight(allTimeMaxWeight, unit: weightUnit)}',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ],
                                );
                              }),
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
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.stacked_bar_chart,
                                        size: 18,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'TOTAL VOLUME',
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                              letterSpacing: 0.5,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    formatWeight(
                                      progressData.fold(0.0,
                                          (sum, d) => sum + (d['totalVolume'] as double)),
                                      unit: weightUnit,
                                    ),
                                    style: NumericTextStyles.title(
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // All-time, like the "All-time" caption above — records
                    // don't reset because the date range is narrower.
                    if (_repMaxes.isNotEmpty) ...[
                      _RepMaxCard(repMaxes: _repMaxes, weightUnit: weightUnit),
                      const SizedBox(height: 16),
                    ],

                    // Progress Chart
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _metric.label,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              _metric.description,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            _ChartControls(
                              metric: _metric,
                              style: _chartStyle,
                              onMetricChanged: (metric) =>
                                  setState(() => _metric = metric),
                              onStyleChanged: (style) =>
                                  setState(() => _chartStyle = style),
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
                            _RecentEntriesList(
                              key: ObjectKey(progressData),
                              ascendingData: progressData,
                              itemBuilder: (context, session) {
                                final date = session['date'] as DateTime;
                                final maxWeight = session['maxWeight'] as double;
                                final totalSets = session['totalSets'] as int;

                                final workoutId =
                                    session['workoutId'] as int?;
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(_formatDate(date)),
                                  subtitle: Text('$totalSets sets'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(formatWeight(maxWeight,
                                          unit: weightUnit)),
                                      if (workoutId != null)
                                        const Icon(Icons.chevron_right,
                                            size: 18),
                                    ],
                                  ),
                                  onTap: workoutId == null
                                      ? null
                                      : () => _openWorkout(workoutId),
                                );
                              },
                            ),
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

  /// The bar rendering of the same series.
  ///
  /// Bars suit volume and rep counts, where each session is a discrete
  /// quantity and the zero baseline is meaningful; the line suits top set and
  /// 1RM, where the trend between sessions is the point. Offering both is
  /// cheaper than guessing which the user wants.
  Widget _buildExerciseBarChart(
    BuildContext context, {
    required List<({int index, double value})> points,
    required List<Map<String, dynamic>> progressData,
    required List<FlSpot> spots,
    required ChartAxis axis,
    required int xLabelStep,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final theme = Theme.of(context);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        // Bars are read against zero, so unlike the line chart this axis
        // always starts there — a padded minY would exaggerate differences.
        minY: 0,
        maxY: axis.maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: axis.interval,
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final point = points[group.x.clamp(0, points.length - 1)];
              final session = progressData[point.index];
              return BarTooltipItem(
                '${_formatDate(session['date'] as DateTime)}\n'
                '${_formatMetric(point.value)}',
                TextStyle(
                  color: theme.colorScheme.onInverseSurface,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
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
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                final isBoundary = index == points.length - 1;
                if (!isBoundary && index % xLabelStep != 0) {
                  return const SizedBox.shrink();
                }
                final date =
                    progressData[points[index].index]['date'] as DateTime;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${date.day}/${date.month}',
                    style: theme.textTheme.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < spots.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: spots[i].y,
                  color: primary,
                  width: spots.length > 20 ? 6 : 12,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// The selected metric's value for one session, or null when that session
  /// has nothing to contribute to it. Weights stay in kg here; conversion to
  /// the display unit happens at the plotting site.
  double? _metricValue(Map<String, dynamic> session) {
    switch (_metric) {
      case ExerciseMetric.maxWeight:
        final value = (session['maxWeight'] as num?)?.toDouble();
        return (value == null || value <= 0) ? null : value;
      case ExerciseMetric.estimatedOneRepMax:
        return (session['estimated1RM'] as num?)?.toDouble();
      case ExerciseMetric.volume:
        final value = (session['totalVolume'] as num?)?.toDouble();
        return (value == null || value <= 0) ? null : value;
      case ExerciseMetric.totalReps:
        final value = (session['totalReps'] as num?)?.toDouble();
        return (value == null || value <= 0) ? null : value;
    }
  }

  /// Formats a metric value for a tooltip, with a unit only where one applies.
  String _formatMetric(double value) => _metric.isWeight
      ? formatWeight(value, unit: weightUnit)
      : '${value.round()} reps';

  /// Opens the workout behind a Recent Sessions row.
  ///
  /// The chart aggregates by day and holds no WorkoutSession, so the row
  /// carries only an id and the session is fetched on tap — cheaper than
  /// hydrating every workout in the list up front for the one you might open.
  Future<void> _openWorkout(int workoutId) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final workout =
        await context.read<ProgressProvider>().getWorkoutById(workoutId);
    if (!mounted) return;

    if (workout == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That workout is no longer available.')),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute(builder: (_) => WorkoutDetailScreen(workout: workout)),
    );
  }

  /// The note to show alongside a session's value, or null.
  ///
  /// The stored note belongs to that session's *heaviest* set. That is the set
  /// "Top set" plots, so the note describes exactly what you're looking at.
  /// Every other metric is derived from a different set or from all of them —
  /// the best estimated 1RM often comes from a lighter, higher-rep set — so
  /// attaching that note would caption the chart with a remark about a set the
  /// number has nothing to do with.
  String? _noteFor(Map<String, dynamic> session) =>
      _metric == ExerciseMetric.maxWeight ? session['note'] as String? : null;

  Widget _buildExerciseChart(
    BuildContext context,
    List<Map<String, dynamic>> progressData,
  ) {
    // Only the sessions where the selected metric actually has a value. A day
    // with no qualifying set (no 1RM estimable from a 20-rep set, say) is
    // skipped rather than plotted as 0, which would draw a dip to the axis
    // that reads as a real drop in performance.
    final points = <({int index, double value})>[];
    for (var i = 0; i < progressData.length; i++) {
      final value = _metricValue(progressData[i]);
      if (value != null) points.add((index: i, value: value));
    }

    if (points.isEmpty) {
      return Center(
        child: Text(
          'No ${_metric.label.toLowerCase()} data for this exercise yet.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    // Plot in the display unit, not the stored kg — otherwise a lbs user
    // reads kg numbers off an axis labelled in nothing at all. Rep counts are
    // not weights and pass through unconverted.
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(
          i.toDouble(),
          _metric.isWeight
              ? kgToUnit(points[i].value, weightUnit)
              : points[i].value,
        ),
    ];

    final axis = computeNiceAxis(spots.map((s) => s.y).toList());
    final xBounds = _computeXBounds(spots.length);
    final xLabelStep = points.length <= 5 ? 1 : (points.length / 5).ceil();
    final primary = Theme.of(context).colorScheme.primary;

    if (_chartStyle == ChartStyle.bar) {
      return _buildExerciseBarChart(
        context,
        points: points,
        progressData: progressData,
        spots: spots,
        // Bars are read against zero, so the axis is recomputed from zero
        // rather than reusing the line chart's padded one. Keeping that axis
        // and merely forcing minY: 0 left the interval sized for a narrow
        // band — an 80-100 kg range gave a 5 kg step, which over a 0-105 axis
        // is twenty-one labels down the side.
        axis: computeNiceAxis(
          spots.map((s) => s.y).toList(),
          startAtZero: true,
        ),
        xLabelStep: xLabelStep,
      );
    }

    return LineChart(
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
        lineTouchData: _buildLineTouchData(
          context,
          // The x axis indexes `points`, not `progressData` — sessions with no
          // value for this metric were filtered out — so the tooltip hops back
          // through the point to find its session.
          tooltipBuilder: (index) {
            final point = points[index.clamp(0, points.length - 1)];
            final session = progressData[point.index];
            return _TooltipContent(
              header: _formatDate(session['date'] as DateTime),
              value: _formatMetric(point.value),
              note: _noteFor(session),
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
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }

                final isBoundary = index == points.length - 1;
                if (!isBoundary && index % xLabelStep != 0) {
                  return const SizedBox.shrink();
                }

                final date =
                    progressData[points[index].index]['date'] as DateTime;
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
            // Straight segments, not a spline. A cubic Bezier through sparse
            // session points overshoots between them, drawing peaks above the
            // heaviest weight actually lifted — the chart inventing a lift
            // that never happened.
            isCurved: false,
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
              color: primary.withValues(alpha: 0.2),
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

  /// The display unit for every weight this screen renders. Stored weights
  /// are always kg; formatWeight converts before formatting.
  String get weightUnit => context.watch<UserProvider>().weightUnit;

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

        if (progressProvider.weightError != null) {
          return _ChartLoadError(
            message: progressProvider.weightError!,
            onRetry: progressProvider.loadWeightProgress,
          );
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
              const WeightGoalCard(),
              const SizedBox(height: 16),

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
                                  ? Theme.of(context).colorScheme.tertiary
                                  : trend['trend'] == 'decreasing'
                                      ? context.semanticColors.success
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${formatWeight((trend['change'] as double).abs(), unit: weightUnit)} ${trend['trend']}',
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
                      _RecentEntriesList(
                        key: ObjectKey(weightData),
                        ascendingData: weightData,
                        itemBuilder: (context, entry) {
                          final date = entry['date'] as DateTime;
                          final weight = entry['weight'] as double;
                          final notes = entry['notes'] as String?;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_formatDate(date)),
                            subtitle: notes != null && notes.isNotEmpty ? Text(notes) : null,
                            trailing:
                                Text(formatWeight(weight, unit: weightUnit)),
                          );
                        },
                      ),
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
    // Body-weight entries are stored in kg like everything else; plot in the
    // display unit so this chart and WeightTrackingScreen agree.
    final spots = <FlSpot>[];
    for (var i = 0; i < weightData.length; i++) {
      final kg = (weightData[i]['weight'] as num?)?.toDouble() ?? 0;
      spots.add(FlSpot(i.toDouble(), kgToUnit(kg, weightUnit)));
    }

    // The goal joins the axis range, so its line is on the chart even while
    // the target is still well below (or above) every logged weight.
    final targetKg = context.watch<UserProvider>().targetWeight;
    final target = targetKg == null ? null : kgToUnit(targetKg, weightUnit);
    final axis = computeNiceAxis([
      ...spots.map((s) => s.y),
      ?target,
    ]);
    final xBounds = _computeXBounds(spots.length);
    final xLabelStep = weightData.length <= 5 ? 1 : (weightData.length / 5).ceil();
    final secondary = Theme.of(context).colorScheme.secondary;

    return LineChart(
      LineChartData(
        minX: xBounds.minX,
        maxX: xBounds.maxX,
        minY: axis.minY,
        maxY: axis.maxY,
        // Same dashed style as the weekly-goal line on the Analytics tab.
        extraLinesData: target == null
            ? null
            : ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: target,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    strokeWidth: 1.5,
                    dashArray: const [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: Theme.of(context).textTheme.labelSmall,
                      labelResolver: (_) => 'Goal',
                    ),
                  ),
                ],
              ),
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
              value: formatWeight(weight, unit: weightUnit),
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
            // See the note on the exercise chart: a spline through sparse
            // points invents maxima and minima the data doesn't contain.
            isCurved: false,
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
              color: secondary.withValues(alpha: 0.2),
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

/// The exercise chart's metric and chart-type pickers (item 19).
///
/// A dropdown for the metric and a segmented button for the style: four
/// metrics is too many for segments on a phone, while two styles are too few
/// to be worth a dropdown.
class _ChartControls extends StatelessWidget {
  const _ChartControls({
    required this.metric,
    required this.style,
    required this.onMetricChanged,
    required this.onStyleChanged,
  });

  final ExerciseMetric metric;
  final ChartStyle style;
  final ValueChanged<ExerciseMetric> onMetricChanged;
  final ValueChanged<ChartStyle> onStyleChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<ExerciseMetric>(
            value: metric,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Metric',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final option in ExerciseMetric.values)
                DropdownMenuItem(value: option, child: Text(option.label)),
            ],
            onChanged: (value) {
              if (value != null) onMetricChanged(value);
            },
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        SegmentedButton<ChartStyle>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: ChartStyle.line,
              icon: Icon(Icons.show_chart, size: 18),
              tooltip: 'Line',
            ),
            ButtonSegment(
              value: ChartStyle.bar,
              icon: Icon(Icons.bar_chart, size: 18),
              tooltip: 'Bars',
            ),
          ],
          selected: {style},
          onSelectionChanged: (selection) => onStyleChanged(selection.first),
        ),
      ],
    );
  }
}
