import '../models/analytics.dart';
import '../utils/app_date.dart';
import 'database_helper.dart';

/// Read-only aggregation for the Progress screen's Analytics tab.
///
/// Deliberately a service returning plain data rather than provider state:
/// nothing here is mutated, every figure is derived from what's already in the
/// database, and the tab reloads it when its inputs change. Keeping it out of
/// ProgressProvider also keeps that class from growing a fifth loading flag.
class AnalyticsService {
  AnalyticsService();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// Totals for completed workouts in the half-open range [start, end).
  Future<PeriodSummary> periodSummary(DateTime start, DateTime end) async {
    final rows = await _dbHelper.rawQuery('''
      SELECT
        COUNT(DISTINCT ws.id) as workouts,
        COUNT(es.id) as sets,
        COALESCE(SUM(COALESCE(es.weight, 0) * COALESCE(es.reps, 0)), 0) as volume,
        COALESCE(SUM(COALESCE(es.reps, 0)), 0) as reps
      FROM workout_sessions ws
      LEFT JOIN exercise_sets es
        ON es.workoutSessionId = ws.id AND es.isWarmup = 0
      WHERE ws.isCompleted = 1 AND ws.date >= ? AND ws.date < ?
    ''', [start.toIso8601String(), end.toIso8601String()]);

    if (rows.isEmpty) return PeriodSummary.empty;
    final row = rows.first;
    return PeriodSummary(
      workouts: (row['workouts'] as num?)?.toInt() ?? 0,
      sets: (row['sets'] as num?)?.toInt() ?? 0,
      volumeKg: (row['volume'] as num?)?.toDouble() ?? 0,
      reps: (row['reps'] as num?)?.toInt() ?? 0,
    );
  }

  /// This calendar week against the previous one, both Monday-based.
  Future<WeekComparison> weekOverWeek({DateTime? now}) async {
    final thisWeekStart = startOfWeek(now ?? DateTime.now());
    final lastWeekStart = addDays(thisWeekStart, -7);
    final results = await Future.wait([
      periodSummary(thisWeekStart, addDays(thisWeekStart, 7)),
      periodSummary(lastWeekStart, thisWeekStart),
    ]);
    return WeekComparison(current: results[0], previous: results[1]);
  }

  /// Weekly training volume per muscle group, oldest week first.
  ///
  /// The split happens in Dart, not SQL: `exercises.muscleGroups` is a
  /// comma-joined TEXT column (the same precedent as WorkoutTemplate's
  /// exerciseIds), which SQLite has no way to expand into rows.
  Future<List<MuscleGroupWeek>> muscleGroupVolume({
    DateTime? startDate,
    DateTime? endDate,
    int maxWeeks = 12,
  }) async {
    final clauses = <String>[
      'ws.isCompleted = 1',
      'es.isWarmup = 0',
      'es.weight IS NOT NULL',
      'es.reps IS NOT NULL',
    ];
    final args = <dynamic>[];
    if (startDate != null) {
      clauses.add('ws.date >= ?');
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      clauses.add('ws.date <= ?');
      args.add(endDate.toIso8601String());
    }

    final rows = await _dbHelper.rawQuery('''
      SELECT ws.date, e.muscleGroups, es.weight, es.reps
      FROM exercise_sets es
      INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id
      INNER JOIN exercises e ON es.exerciseId = e.id
      WHERE ${clauses.join(' AND ')}
      ORDER BY ws.date ASC
    ''', args);

    final byWeek = <int, Map<String, double>>{};
    final weekStarts = <int, DateTime>{};
    for (final row in rows) {
      final date = DateTime.parse(row['date'] as String);
      final weekStart = startOfWeek(date);
      final key = epochDay(weekStart);
      weekStarts[key] = weekStart;

      final volume = ((row['weight'] as num).toDouble()) *
          ((row['reps'] as num).toDouble());
      final groups = (row['muscleGroups'] as String?)
              ?.split(',')
              .map((g) => g.trim())
              .where((g) => g.isNotEmpty)
              .toList() ??
          const <String>[];
      // An exercise with no muscle groups tagged still represents work done,
      // so it is bucketed rather than dropped.
      final buckets = groups.isEmpty ? const ['Untagged'] : groups;

      final week = byWeek.putIfAbsent(key, () => <String, double>{});
      for (final group in buckets) {
        week[group] = (week[group] ?? 0) + volume;
      }
    }

    final keys = byWeek.keys.toList()..sort();
    final trimmed = keys.length > maxWeeks
        ? keys.sublist(keys.length - maxWeeks)
        : keys;
    return [
      for (final key in trimmed)
        MuscleGroupWeek(
          weekStart: weekStarts[key]!,
          volumeByGroup: byWeek[key]!,
        ),
    ];
  }

  /// Personal records, newest first, read from the persisted flag.
  Future<List<PersonalRecordEntry>> personalRecordHistory({
    int limit = 50,
    int? exerciseId,
  }) async {
    final clauses = <String>['es.isPersonalRecord = 1', 'ws.isCompleted = 1'];
    final args = <dynamic>[];
    if (exerciseId != null) {
      clauses.add('es.exerciseId = ?');
      args.add(exerciseId);
    }
    args.add(limit);

    // LEFT JOIN so a record set logged against a since-deleted exercise still
    // appears, matching the CSV export's treatment of the same case.
    final rows = await _dbHelper.rawQuery('''
      SELECT e.name as exerciseName, es.weight, es.reps, es.timestamp
      FROM exercise_sets es
      INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id
      LEFT JOIN exercises e ON es.exerciseId = e.id
      WHERE ${clauses.join(' AND ')}
      ORDER BY es.timestamp DESC
      LIMIT ?
    ''', args);

    return [
      for (final row in rows)
        PersonalRecordEntry(
          exerciseName:
              (row['exerciseName'] as String?) ?? '(deleted exercise)',
          weightKg: (row['weight'] as num?)?.toDouble() ?? 0,
          reps: (row['reps'] as num?)?.toInt(),
          date: DateTime.parse(row['timestamp'] as String),
        ),
    ];
  }

  /// Volume per exercise category over the range, for the breakdown chart.
  Future<Map<String, double>> categoryVolume({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final clauses = <String>[
      'ws.isCompleted = 1',
      'es.isWarmup = 0',
      'es.weight IS NOT NULL',
      'es.reps IS NOT NULL',
    ];
    final args = <dynamic>[];
    if (startDate != null) {
      clauses.add('ws.date >= ?');
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      clauses.add('ws.date <= ?');
      args.add(endDate.toIso8601String());
    }

    final rows = await _dbHelper.rawQuery('''
      SELECT COALESCE(c.name, 'Uncategorised') as categoryName,
             SUM(es.weight * es.reps) as volume
      FROM exercise_sets es
      INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id
      INNER JOIN exercises e ON es.exerciseId = e.id
      LEFT JOIN exercise_categories c ON e.categoryId = c.id
      WHERE ${clauses.join(' AND ')}
      GROUP BY categoryName
      ORDER BY volume DESC
    ''', args);

    return {
      for (final row in rows)
        row['categoryName'] as String: (row['volume'] as num?)?.toDouble() ?? 0,
    };
  }

  /// One row per completed workout in the (inclusive) range, oldest first —
  /// no bucketing, no grouping. The raw feed [groupWorkoutTotals] (trend
  /// chart) and [weeklyGoalAdherence] (consistency card) each bucket for
  /// themselves, so the query lives here exactly once.
  Future<List<WorkoutTotal>> workoutTotals({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final clauses = <String>['ws.isCompleted = 1'];
    final args = <dynamic>[];
    if (startDate != null) {
      clauses.add('ws.date >= ?');
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      clauses.add('ws.date <= ?');
      args.add(endDate.toIso8601String());
    }

    final rows = await _dbHelper.rawQuery('''
      SELECT
        ws.date as date,
        COUNT(CASE WHEN es.isWarmup = 0 THEN es.id END) as sets,
        COALESCE(SUM(CASE WHEN es.isWarmup = 0
          THEN COALESCE(es.weight, 0) * COALESCE(es.reps, 0) ELSE 0 END), 0) as volume,
        COALESCE(SUM(CASE WHEN es.isWarmup = 0
          THEN COALESCE(es.reps, 0) ELSE 0 END), 0) as reps
      FROM workout_sessions ws
      LEFT JOIN exercise_sets es ON es.workoutSessionId = ws.id
      WHERE ${clauses.join(' AND ')}
      GROUP BY ws.id
      ORDER BY ws.date ASC
    ''', args);

    return [
      for (final row in rows)
        WorkoutTotal(
          date: DateTime.parse(row['date'] as String),
          sets: (row['sets'] as num?)?.toInt() ?? 0,
          volumeKg: (row['volume'] as num?)?.toDouble() ?? 0,
          reps: (row['reps'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  /// How training over the range splits across muscle groups, relative to
  /// each other — flags groups that are getting disproportionately little or
  /// much work.
  ///
  /// Untagged exercises are dropped entirely rather than bucketed under some
  /// placeholder: unlike [muscleGroupVolume] (which is asking "how much work
  /// happened, broken down by tag"), this is asking "is any real muscle
  /// under-served", and an "Untagged" bucket isn't a muscle — folding it in
  /// would only distort the average every other group is judged against.
  Future<List<MuscleGroupBalance>> muscleGroupBalance({
    DateTime? startDate,
    DateTime? endDate,
    double underTrainedThreshold = 0.5,
    double overTrainedThreshold = 1.5,
  }) async {
    final clauses = <String>['ws.isCompleted = 1', 'es.isWarmup = 0'];
    final args = <dynamic>[];
    if (startDate != null) {
      clauses.add('ws.date >= ?');
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      clauses.add('ws.date <= ?');
      args.add(endDate.toIso8601String());
    }

    final rows = await _dbHelper.rawQuery('''
      SELECT e.muscleGroups, es.weight, es.reps
      FROM exercise_sets es
      INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id
      INNER JOIN exercises e ON es.exerciseId = e.id
      WHERE ${clauses.join(' AND ')}
    ''', args);

    final byGroup = <String, ({int sets, double volume})>{};
    for (final row in rows) {
      final groups = (row['muscleGroups'] as String?)
              ?.split(',')
              .map((g) => g.trim())
              .where((g) => g.isNotEmpty)
              .toList() ??
          const <String>[];
      if (groups.isEmpty) continue;

      final weight = (row['weight'] as num?)?.toDouble();
      final reps = (row['reps'] as num?)?.toDouble();
      // A bodyweight or timed-hold set (no weight logged) still counts as a
      // set of work toward the group; it just adds nothing to the volume.
      final volume = (weight != null && reps != null) ? weight * reps : 0.0;

      for (final group in groups) {
        final existing = byGroup[group];
        byGroup[group] = (
          sets: (existing?.sets ?? 0) + 1,
          volume: (existing?.volume ?? 0) + volume,
        );
      }
    }

    return classifyMuscleGroupBalance(
      byGroup,
      underTrainedThreshold: underTrainedThreshold,
      overTrainedThreshold: overTrainedThreshold,
    );
  }

  /// Adherence to the weekly workout goal, one entry per week, oldest first.
  ///
  /// The range defaults to everything since the earliest completed workout
  /// and always excludes the current, still-in-progress week — the
  /// dashboard's [WeeklyGoalSummary] already shows that week live, and a
  /// streak/adherence figure has no business judging a week that hasn't
  /// finished. Trimmed to the most recent [maxWeeks] so a long history
  /// doesn't make this card (or its chart) unbounded.
  Future<List<WeeklyAdherence>> weeklyGoalAdherence({
    required int goal,
    DateTime? startDate,
    DateTime? endDate,
    int maxWeeks = 26,
    DateTime? now,
  }) async {
    final totals = await workoutTotals(startDate: startDate, endDate: endDate);
    if (totals.isEmpty) return [];

    final currentWeekStart = startOfWeek(now ?? DateTime.now());
    final rangeStart = startOfWeek(startDate ?? totals.first.date);
    var rangeEndExclusive =
        endDate == null ? currentWeekStart : startOfWeek(endDate);
    if (rangeEndExclusive.isAfter(currentWeekStart)) {
      rangeEndExclusive = currentWeekStart;
    }

    if (!rangeEndExclusive.isAfter(rangeStart)) return [];

    var weeks = buildWeeklyAdherence(
      totals,
      rangeStart: rangeStart,
      rangeEndExclusive: rangeEndExclusive,
      goal: goal,
    );

    if (weeks.length > maxWeeks) {
      weeks = weeks.sublist(weeks.length - maxWeeks);
    }
    return weeks;
  }

  /// Sets and volume grouped by rep-range training focus (strength /
  /// hypertrophy / endurance), every band present even when empty.
  ///
  /// The 5/12 cutoffs match [estimateOneRepMax]'s `maxMeaningfulReps` of 12,
  /// so "hypertrophy" here is exactly the rep range that formula still trusts.
  Future<List<RepRangeSummary>> repRangeBreakdown({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final clauses = <String>[
      'ws.isCompleted = 1',
      'es.isWarmup = 0',
      'es.reps IS NOT NULL',
      'es.reps > 0',
    ];
    final args = <dynamic>[];
    if (startDate != null) {
      clauses.add('ws.date >= ?');
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      clauses.add('ws.date <= ?');
      args.add(endDate.toIso8601String());
    }

    final rows = await _dbHelper.rawQuery('''
      SELECT
        CASE
          WHEN es.reps <= 5 THEN 'strength'
          WHEN es.reps <= 12 THEN 'hypertrophy'
          ELSE 'endurance'
        END as band,
        COUNT(es.id) as sets,
        COALESCE(SUM(COALESCE(es.weight, 0) * es.reps), 0) as volume
      FROM exercise_sets es
      INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id
      WHERE ${clauses.join(' AND ')}
      GROUP BY band
    ''', args);

    final byBand = <String, ({int sets, double volume})>{
      for (final row in rows)
        row['band'] as String: (
          sets: (row['sets'] as num).toInt(),
          volume: (row['volume'] as num?)?.toDouble() ?? 0,
        ),
    };

    const bandKeys = {
      RepRangeBand.strength: 'strength',
      RepRangeBand.hypertrophy: 'hypertrophy',
      RepRangeBand.endurance: 'endurance',
    };

    return [
      for (final band in RepRangeBand.values)
        RepRangeSummary(
          band: band,
          sets: byBand[bandKeys[band]]?.sets ?? 0,
          volumeKg: byBand[bandKeys[band]]?.volume ?? 0,
        ),
    ];
  }
}

/// Everything the Analytics tab needs, loaded together so the tab makes one
/// round trip rather than five that each repaint independently.
class AnalyticsSnapshot {
  const AnalyticsSnapshot({
    required this.weekComparison,
    required this.muscleGroupWeeks,
    required this.personalRecords,
    required this.categoryVolume,
    required this.workoutTotals,
    required this.muscleGroupBalance,
    required this.weeklyAdherence,
    required this.repRangeBreakdown,
  });

  final WeekComparison weekComparison;
  final List<MuscleGroupWeek> muscleGroupWeeks;
  final List<PersonalRecordEntry> personalRecords;
  final Map<String, double> categoryVolume;

  /// The raw per-workout feed behind the long-term trend chart.
  final List<WorkoutTotal> workoutTotals;
  final List<MuscleGroupBalance> muscleGroupBalance;
  final List<WeeklyAdherence> weeklyAdherence;
  final List<RepRangeSummary> repRangeBreakdown;

  static Future<AnalyticsSnapshot> load(
    AnalyticsService service, {
    DateTime? startDate,
    DateTime? endDate,
    required int weeklyGoal,
  }) async {
    final results = await Future.wait([
      service.weekOverWeek(),
      service.muscleGroupVolume(startDate: startDate, endDate: endDate),
      service.personalRecordHistory(),
      service.categoryVolume(startDate: startDate, endDate: endDate),
      service.workoutTotals(startDate: startDate, endDate: endDate),
      service.muscleGroupBalance(startDate: startDate, endDate: endDate),
      // Deliberately not scoped to the tab's startDate/endDate filter: like
      // weekOverWeek and personalRecordHistory above, adherence is inherently
      // a rolling "how am I doing lately" figure (capped at maxWeeks weeks,
      // always excluding the still-open current week), not a snapshot of an
      // arbitrary picked range.
      service.weeklyGoalAdherence(goal: weeklyGoal),
      service.repRangeBreakdown(startDate: startDate, endDate: endDate),
    ]);
    return AnalyticsSnapshot(
      weekComparison: results[0] as WeekComparison,
      muscleGroupWeeks: results[1] as List<MuscleGroupWeek>,
      personalRecords: results[2] as List<PersonalRecordEntry>,
      categoryVolume: results[3] as Map<String, double>,
      workoutTotals: results[4] as List<WorkoutTotal>,
      muscleGroupBalance: results[5] as List<MuscleGroupBalance>,
      weeklyAdherence: results[6] as List<WeeklyAdherence>,
      repRangeBreakdown: results[7] as List<RepRangeSummary>,
    );
  }
}
