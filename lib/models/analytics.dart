import '../utils/app_date.dart';

/// Aggregated figures for one time window.
class PeriodSummary {
  const PeriodSummary({
    required this.workouts,
    required this.sets,
    required this.volumeKg,
    required this.reps,
  });

  static const empty =
      PeriodSummary(workouts: 0, sets: 0, volumeKg: 0, reps: 0);

  final int workouts;
  final int sets;

  /// Warm-up sets are excluded, matching every other volume figure in the app.
  final double volumeKg;

  final int reps;
}

/// This week measured against last week, for the week-over-week comparison.
class WeekComparison {
  const WeekComparison({required this.current, required this.previous});

  final PeriodSummary current;
  final PeriodSummary previous;

  /// Signed percentage change, or null when the previous week was zero —
  /// "up from nothing" is not a percentage, and rendering it as +100% or
  /// +infinity would be worse than saying nothing.
  double? percentChange(num Function(PeriodSummary) metric) {
    final before = metric(previous).toDouble();
    final now = metric(current).toDouble();
    if (before == 0) return null;
    return (now - before) / before * 100;
  }
}

/// Training volume for one week, split by muscle group.
class MuscleGroupWeek {
  const MuscleGroupWeek({required this.weekStart, required this.volumeByGroup});

  final DateTime weekStart;

  /// Muscle group name -> volume in kg.
  ///
  /// A set counts toward every muscle group its exercise lists, so these
  /// deliberately sum to more than the workout's total volume — the question
  /// this answers is "how much work did each muscle get", not "how does the
  /// total split up".
  final Map<String, double> volumeByGroup;
}

/// One entry in the personal-record history.
class PersonalRecordEntry {
  const PersonalRecordEntry({
    required this.exerciseName,
    required this.weightKg,
    required this.reps,
    required this.date,
  });

  final String exerciseName;
  final double weightKg;
  final int? reps;
  final DateTime date;
}

/// A single point on an exercise's progress chart, in whichever metric the
/// chart is currently showing.
class ExerciseMetricPoint {
  const ExerciseMetricPoint({required this.date, required this.value});

  final DateTime date;
  final double value;
}

/// What the exercise progress chart plots (item 19's metric selector).
enum ExerciseMetric {
  maxWeight('Top set', 'Heaviest weight lifted that session'),
  estimatedOneRepMax('Est. 1RM', 'Epley estimate from the best set'),
  volume('Volume', 'Weight x reps, warm-ups excluded'),
  totalReps('Reps', 'Total working reps that session');

  const ExerciseMetric(this.label, this.description);

  final String label;
  final String description;

  /// Whether values in this metric are weights, and so need unit conversion
  /// and a unit suffix. Reps are a plain count.
  bool get isWeight => this != ExerciseMetric.totalReps;
}

/// How to draw a series (item 19's chart-type switcher).
enum ChartStyle {
  line('Line'),
  bar('Bars');

  const ChartStyle(this.label);

  final String label;
}

/// Epley one-rep-max estimate: `w x (1 + reps/30)`.
///
/// Returns null above [maxMeaningfulReps]. Every 1RM formula is fitted to low
/// rep ranges and drifts badly beyond about ten — a 20-rep set would estimate
/// a number the lifter has no chance of hitting, which is worse than showing
/// no estimate at all.
double? estimateOneRepMax(double weightKg, int reps,
    {int maxMeaningfulReps = 12}) {
  if (reps < 1 || reps > maxMeaningfulReps) return null;
  return weightKg * (1 + reps / 30);
}

/// One completed workout's totals, unbucketed.
///
/// The shared raw feed behind both the long-term trend chart and the
/// weekly-goal adherence calc: [AnalyticsService.workoutTotals] runs the one
/// query, and each feature buckets this same list for itself rather than
/// duplicating the fetch.
class WorkoutTotal {
  const WorkoutTotal({
    required this.date,
    required this.sets,
    required this.volumeKg,
    required this.reps,
  });

  final DateTime date;

  /// Warm-up sets are excluded, matching every other set count in the app.
  final int sets;

  /// Warm-up sets are excluded, matching every other volume figure in the app.
  final double volumeKg;

  /// Warm-up sets are excluded, matching every other rep total in the app.
  final int reps;
}

/// How [groupWorkoutTotals] buckets the raw per-workout feed.
enum TrendGranularity { week, month }

/// One bucket of [groupWorkoutTotals]'s output: everything that happened in
/// one week or month.
class TrendPoint {
  const TrendPoint({
    required this.periodStart,
    required this.workouts,
    required this.sets,
    required this.volumeKg,
    required this.reps,
  });

  final DateTime periodStart;
  final int workouts;
  final int sets;
  final double volumeKg;
  final int reps;
}

/// Buckets [totals] (oldest-first, as returned by
/// [AnalyticsService.workoutTotals]) into weeks or months, summing each
/// bucket's sets/volume/reps and counting its workouts, sorted ascending.
///
/// Pure and synchronous by design: toggling granularity in the UI recomputes
/// this from the already-loaded feed rather than reloading from the database.
List<TrendPoint> groupWorkoutTotals(
  List<WorkoutTotal> totals,
  TrendGranularity granularity,
) {
  final buckets = <int,
      ({DateTime start, int workouts, int sets, double volumeKg, int reps})>{};

  for (final total in totals) {
    final DateTime bucketStart;
    final int key;
    if (granularity == TrendGranularity.week) {
      bucketStart = startOfWeek(total.date);
      key = epochDay(bucketStart);
    } else {
      bucketStart = DateTime(total.date.year, total.date.month);
      key = total.date.year * 12 + total.date.month;
    }

    final existing = buckets[key];
    buckets[key] = (
      start: bucketStart,
      workouts: (existing?.workouts ?? 0) + 1,
      sets: (existing?.sets ?? 0) + total.sets,
      volumeKg: (existing?.volumeKg ?? 0) + total.volumeKg,
      reps: (existing?.reps ?? 0) + total.reps,
    );
  }

  final keys = buckets.keys.toList()..sort();
  return [
    for (final key in keys)
      TrendPoint(
        periodStart: buckets[key]!.start,
        workouts: buckets[key]!.workouts,
        sets: buckets[key]!.sets,
        volumeKg: buckets[key]!.volumeKg,
        reps: buckets[key]!.reps,
      ),
  ];
}

/// Where a muscle group's training stands relative to the average across all
/// trained groups over the period.
enum BalanceStatus { underTrained, balanced, overTrained }

/// One muscle group's share of training over a period, and how that compares
/// to the average group.
class MuscleGroupBalance {
  const MuscleGroupBalance({
    required this.muscleGroup,
    required this.sets,
    required this.volumeKg,
    required this.ratioToAverage,
    required this.status,
  });

  final String muscleGroup;
  final int sets;
  final double volumeKg;

  /// This group's sets divided by the mean sets across all groups. 1.0 is
  /// exactly average.
  final double ratioToAverage;

  final BalanceStatus status;
}

/// Classifies each muscle group in [byGroup] (group name -> its set count and
/// volume) relative to the mean set count across every group present.
///
/// Untagged/no-muscle-group work has no place here — it isn't a real muscle,
/// and folding it in would distort the average — so [byGroup] is expected to
/// already exclude it (see [AnalyticsService.muscleGroupBalance]).
///
/// Sorted ascending by [MuscleGroupBalance.ratioToAverage], worst-served
/// first.
List<MuscleGroupBalance> classifyMuscleGroupBalance(
  Map<String, ({int sets, double volume})> byGroup, {
  double underTrainedThreshold = 0.5,
  double overTrainedThreshold = 1.5,
}) {
  if (byGroup.isEmpty) return [];

  final totalSets = byGroup.values.fold<int>(0, (a, b) => a + b.sets);
  final meanSets = totalSets / byGroup.length;

  final result = [
    for (final entry in byGroup.entries)
      MuscleGroupBalance(
        muscleGroup: entry.key,
        sets: entry.value.sets,
        volumeKg: entry.value.volume,
        ratioToAverage: meanSets == 0 ? 1.0 : entry.value.sets / meanSets,
        status: meanSets == 0
            ? BalanceStatus.balanced
            : _classifyRatio(
                entry.value.sets / meanSets,
                underTrainedThreshold,
                overTrainedThreshold,
              ),
      ),
  ];

  result.sort((a, b) => a.ratioToAverage.compareTo(b.ratioToAverage));
  return result;
}

BalanceStatus _classifyRatio(
  double ratio,
  double underTrainedThreshold,
  double overTrainedThreshold,
) {
  if (ratio < underTrainedThreshold) return BalanceStatus.underTrained;
  if (ratio > overTrainedThreshold) return BalanceStatus.overTrained;
  return BalanceStatus.balanced;
}

/// One calendar week's training against the weekly workout goal.
class WeeklyAdherence {
  const WeeklyAdherence({
    required this.weekStart,
    required this.workouts,
    required this.goal,
  });

  final DateTime weekStart;
  final int workouts;
  final int goal;

  bool get metGoal => workouts >= goal;
}

/// Enumerates every Monday-based week in the half-open range
/// `[rangeStart, rangeEndExclusive)`, counting how many of [totals] fall in
/// each — including weeks with zero workouts, so a gap in training shows up
/// as a missed week rather than being silently absent.
List<WeeklyAdherence> buildWeeklyAdherence(
  List<WorkoutTotal> totals, {
  required DateTime rangeStart,
  required DateTime rangeEndExclusive,
  required int goal,
}) {
  final start = startOfWeek(rangeStart);
  final endExclusive = startOfWeek(rangeEndExclusive);
  if (!endExclusive.isAfter(start)) return [];

  final counts = <int, int>{};
  for (final total in totals) {
    final key = epochDay(startOfWeek(total.date));
    counts[key] = (counts[key] ?? 0) + 1;
  }

  final result = <WeeklyAdherence>[];
  var week = start;
  while (week.isBefore(endExclusive)) {
    result.add(WeeklyAdherence(
      weekStart: week,
      workouts: counts[epochDay(week)] ?? 0,
      goal: goal,
    ));
    week = addDays(week, 7);
  }
  return result;
}

/// Aggregate adherence stats over a list of weeks, in the order given —
/// [buildWeeklyAdherence] returns them oldest first, so "the end of the list"
/// means the most recent week.
extension WeeklyAdherenceStats on List<WeeklyAdherence> {
  int get metCount => where((w) => w.metGoal).length;

  /// Fraction of weeks that met the goal, or null when there are no weeks to
  /// judge — "no data" is not the same as "0% adherence".
  double? get adherenceRate => isEmpty ? null : metCount / length;

  /// Consecutive goal-meeting weeks counting back from the most recent week,
  /// stopping at the first miss.
  int get currentStreak {
    var streak = 0;
    for (var i = length - 1; i >= 0; i--) {
      if (!this[i].metGoal) break;
      streak++;
    }
    return streak;
  }
}

/// Training-focus bucket by rep count, matching [estimateOneRepMax]'s
/// `maxMeaningfulReps` cutoff of 12 for the hypertrophy/endurance boundary.
enum RepRangeBand {
  strength,
  hypertrophy,
  endurance;

  String get label => switch (this) {
        RepRangeBand.strength => 'Strength',
        RepRangeBand.hypertrophy => 'Hypertrophy',
        RepRangeBand.endurance => 'Endurance',
      };

  String get rangeLabel => switch (this) {
        RepRangeBand.strength => '1–5 reps',
        RepRangeBand.hypertrophy => '6–12 reps',
        RepRangeBand.endurance => '13+ reps',
      };
}

/// Sets and volume logged in one [RepRangeBand] over a period.
class RepRangeSummary {
  const RepRangeSummary({
    required this.band,
    required this.sets,
    required this.volumeKg,
  });

  final RepRangeBand band;
  final int sets;
  final double volumeKg;
}
