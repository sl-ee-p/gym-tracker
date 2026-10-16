import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/analytics.dart';

void main() {
  group('estimateOneRepMax (Epley)', () {
    test('a single rep is the weight itself, near enough', () {
      // Epley gives w * (1 + 1/30), i.e. a ~3% overshoot at 1 rep. That's the
      // formula's known behaviour, not a bug — asserted so a future change to
      // a different formula is a deliberate one.
      expect(estimateOneRepMax(100, 1), closeTo(103.33, 0.01));
    });

    test('scales with reps', () {
      expect(estimateOneRepMax(100, 5), closeTo(116.67, 0.01));
      expect(estimateOneRepMax(100, 10), closeTo(133.33, 0.01));
    });

    test('returns null beyond the meaningful rep range', () {
      // Every 1RM formula is fitted to low reps; past ~12 it estimates a
      // number the lifter has no chance of hitting.
      expect(estimateOneRepMax(60, 13), isNull);
      expect(estimateOneRepMax(60, 20), isNull);
    });

    test('respects a custom cap', () {
      expect(estimateOneRepMax(60, 13, maxMeaningfulReps: 15), isNotNull);
      expect(estimateOneRepMax(60, 16, maxMeaningfulReps: 15), isNull);
    });

    test('returns null for a non-positive rep count', () {
      expect(estimateOneRepMax(100, 0), isNull);
      expect(estimateOneRepMax(100, -1), isNull);
    });

    test('a heavier set at the same reps estimates higher', () {
      final lighter = estimateOneRepMax(80, 5)!;
      final heavier = estimateOneRepMax(90, 5)!;
      expect(heavier, greaterThan(lighter));
    });
  });

  group('WeekComparison.percentChange', () {
    WeekComparison build(int current, int previous) => WeekComparison(
          current: PeriodSummary(
              workouts: current, sets: 0, volumeKg: 0, reps: 0),
          previous: PeriodSummary(
              workouts: previous, sets: 0, volumeKg: 0, reps: 0),
        );

    test('reports a rise', () {
      expect(build(6, 4).percentChange((s) => s.workouts), closeTo(50, 0.001));
    });

    test('reports a fall as negative', () {
      expect(build(3, 6).percentChange((s) => s.workouts), closeTo(-50, 0.001));
    });

    test('reports no change as zero', () {
      expect(build(4, 4).percentChange((s) => s.workouts), 0);
    });

    test('is null when the previous week was zero', () {
      // "Up from nothing" isn't a percentage; +100% or infinity would both
      // be lies, so the UI says "no data last week" instead.
      expect(build(4, 0).percentChange((s) => s.workouts), isNull);
    });

    test('is null even when both weeks are zero', () {
      expect(build(0, 0).percentChange((s) => s.workouts), isNull);
    });

    test('works over a non-integer metric', () {
      const comparison = WeekComparison(
        current: PeriodSummary(workouts: 0, sets: 0, volumeKg: 1200, reps: 0),
        previous: PeriodSummary(workouts: 0, sets: 0, volumeKg: 1000, reps: 0),
      );
      expect(comparison.percentChange((s) => s.volumeKg), closeTo(20, 0.001));
    });
  });

  group('ExerciseMetric', () {
    test('reps is the only non-weight metric', () {
      // Drives unit conversion and the unit suffix; getting it wrong would
      // convert a rep count from kg to lbs.
      for (final metric in ExerciseMetric.values) {
        expect(metric.isWeight, metric != ExerciseMetric.totalReps,
            reason: metric.name);
      }
    });

    test('every metric has a label and a description', () {
      for (final metric in ExerciseMetric.values) {
        expect(metric.label, isNotEmpty);
        expect(metric.description, isNotEmpty);
      }
    });
  });

  group('groupWorkoutTotals', () {
    WorkoutTotal total(DateTime date, {int sets = 1, double volume = 10, int reps = 5}) =>
        WorkoutTotal(date: date, sets: sets, volumeKg: volume, reps: reps);

    test('returns nothing for an empty feed', () {
      expect(groupWorkoutTotals(const [], TrendGranularity.week), isEmpty);
    });

    test('sums two workouts in the same Monday-based week', () {
      // A Monday and the following Sunday are the same week.
      final points = groupWorkoutTotals([
        total(DateTime(2026, 1, 5), sets: 3, volume: 100, reps: 15), // Monday
        total(DateTime(2026, 1, 11), sets: 2, volume: 50, reps: 10), // Sunday
      ], TrendGranularity.week);

      expect(points, hasLength(1));
      expect(points.single.periodStart, DateTime(2026, 1, 5));
      expect(points.single.workouts, 2);
      expect(points.single.sets, 5);
      expect(points.single.volumeKg, 150);
      expect(points.single.reps, 25);
    });

    test('a Monday is grouped separately from the previous Sunday', () {
      final points = groupWorkoutTotals([
        total(DateTime(2026, 1, 4)), // Sunday, end of the prior week
        total(DateTime(2026, 1, 5)), // Monday, start of the next week
      ], TrendGranularity.week);

      expect(points, hasLength(2));
      expect(points[0].periodStart, DateTime(2025, 12, 29));
      expect(points[1].periodStart, DateTime(2026, 1, 5));
    });

    test('groups by calendar month', () {
      final points = groupWorkoutTotals([
        total(DateTime(2026, 1, 31), sets: 1),
        total(DateTime(2026, 2, 1), sets: 2),
      ], TrendGranularity.month);

      expect(points, hasLength(2));
      expect(points[0].periodStart, DateTime(2026, 1));
      expect(points[0].sets, 1);
      expect(points[1].periodStart, DateTime(2026, 2));
      expect(points[1].sets, 2);
    });

    test('is sorted ascending regardless of input order', () {
      final points = groupWorkoutTotals([
        total(DateTime(2026, 3, 1)),
        total(DateTime(2026, 1, 1)),
        total(DateTime(2026, 2, 1)),
      ], TrendGranularity.month);

      expect(points.map((p) => p.periodStart), [
        DateTime(2026, 1),
        DateTime(2026, 2),
        DateTime(2026, 3),
      ]);
    });
  });

  group('classifyMuscleGroupBalance', () {
    test('returns nothing for an empty map', () {
      expect(classifyMuscleGroupBalance(const {}), isEmpty);
    });

    test('a single group is always exactly average and balanced', () {
      final result = classifyMuscleGroupBalance({
        'Chest': (sets: 12, volume: 500.0),
      });

      expect(result, hasLength(1));
      expect(result.single.ratioToAverage, 1.0);
      expect(result.single.status, BalanceStatus.balanced);
    });

    test('exactly at the under-trained threshold is not under-trained', () {
      // Mean is 10; 5 / 10 == 0.5, the threshold itself — the boundary is
      // strictly "<", so exactly 0.5 must land as balanced.
      final result = classifyMuscleGroupBalance({
        'A': (sets: 5, volume: 0.0),
        'B': (sets: 15, volume: 0.0),
      });

      final a = result.firstWhere((b) => b.muscleGroup == 'A');
      expect(a.ratioToAverage, 0.5);
      expect(a.status, BalanceStatus.balanced);
    });

    test('just under the under-trained threshold is flagged', () {
      final result = classifyMuscleGroupBalance({
        'A': (sets: 4, volume: 0.0),
        'B': (sets: 16, volume: 0.0),
      });

      final a = result.firstWhere((b) => b.muscleGroup == 'A');
      expect(a.ratioToAverage, 0.4);
      expect(a.status, BalanceStatus.underTrained);
    });

    test('exactly at the over-trained threshold is not over-trained', () {
      // Mean is 10; 15 / 10 == 1.5, the threshold itself — "<" is strict on
      // the low side and ">" is strict on the high side, so 1.5 is balanced.
      final result = classifyMuscleGroupBalance({
        'A': (sets: 5, volume: 0.0),
        'B': (sets: 15, volume: 0.0),
      });

      final b = result.firstWhere((x) => x.muscleGroup == 'B');
      expect(b.ratioToAverage, 1.5);
      expect(b.status, BalanceStatus.balanced);
    });

    test('just over the over-trained threshold is flagged', () {
      final result = classifyMuscleGroupBalance({
        'A': (sets: 4, volume: 0.0),
        'B': (sets: 16, volume: 0.0),
      });

      final b = result.firstWhere((x) => x.muscleGroup == 'B');
      expect(b.ratioToAverage, 1.6);
      expect(b.status, BalanceStatus.overTrained);
    });

    test('is sorted ascending by ratio, worst-served first', () {
      final result = classifyMuscleGroupBalance({
        'Overworked': (sets: 20, volume: 0.0),
        'Neglected': (sets: 2, volume: 0.0),
        'Average': (sets: 8, volume: 0.0),
      });

      expect(result.map((b) => b.muscleGroup),
          ['Neglected', 'Average', 'Overworked']);
    });

    test('zero sets everywhere is balanced, not a division by zero', () {
      final result = classifyMuscleGroupBalance({
        'A': (sets: 0, volume: 0.0),
        'B': (sets: 0, volume: 0.0),
      });

      for (final balance in result) {
        expect(balance.status, BalanceStatus.balanced);
        expect(balance.ratioToAverage, isNot(isNaN));
      }
    });
  });

  group('buildWeeklyAdherence / WeeklyAdherenceStats', () {
    WorkoutTotal workoutOn(DateTime date) =>
        WorkoutTotal(date: date, sets: 1, volumeKg: 1, reps: 1);

    test('a week with no logged workouts still appears, as a miss', () {
      final weeks = buildWeeklyAdherence(
        [workoutOn(DateTime(2026, 1, 5))], // week 1 only
        rangeStart: DateTime(2026, 1, 5),
        rangeEndExclusive: DateTime(2026, 1, 19), // covers weeks 1 and 2
        goal: 3,
      );

      expect(weeks, hasLength(2));
      expect(weeks[0].workouts, 1);
      expect(weeks[1].workouts, 0);
      expect(weeks[1].metGoal, isFalse);
    });

    test('empty range produces no weeks', () {
      final weeks = buildWeeklyAdherence(
        const [],
        rangeStart: DateTime(2026, 1, 5),
        rangeEndExclusive: DateTime(2026, 1, 5),
        goal: 3,
      );
      expect(weeks, isEmpty);
    });

    test('adherenceRate is null for an empty list, not zero', () {
      expect(const <WeeklyAdherence>[].adherenceRate, isNull);
    });

    test('adherenceRate and metCount over a mixed history', () {
      final weeks = [
        WeeklyAdherence(weekStart: DateTime(2026, 1, 5), workouts: 3, goal: 3),
        WeeklyAdherence(weekStart: DateTime(2026, 1, 12), workouts: 1, goal: 3),
        WeeklyAdherence(weekStart: DateTime(2026, 1, 19), workouts: 4, goal: 3),
      ];

      expect(weeks.metCount, 2);
      expect(weeks.adherenceRate, closeTo(2 / 3, 0.0001));
    });

    test('currentStreak counts back from the end and stops at the first miss', () {
      final weeks = [
        WeeklyAdherence(weekStart: DateTime(2026, 1, 5), workouts: 3, goal: 3),
        WeeklyAdherence(weekStart: DateTime(2026, 1, 12), workouts: 0, goal: 3),
        WeeklyAdherence(weekStart: DateTime(2026, 1, 19), workouts: 3, goal: 3),
        WeeklyAdherence(weekStart: DateTime(2026, 1, 26), workouts: 4, goal: 3),
      ];

      // The two most recent weeks met the goal; the miss two weeks back
      // stops the count from reaching further back.
      expect(weeks.currentStreak, 2);
    });

    test('currentStreak is zero when the most recent week missed', () {
      final weeks = [
        WeeklyAdherence(weekStart: DateTime(2026, 1, 5), workouts: 3, goal: 3),
        WeeklyAdherence(weekStart: DateTime(2026, 1, 12), workouts: 0, goal: 3),
      ];
      expect(weeks.currentStreak, 0);
    });

    test('currentStreak on an empty list is zero', () {
      expect(const <WeeklyAdherence>[].currentStreak, 0);
    });
  });

  group('RepRangeBand', () {
    test('every band has a non-empty label and range label', () {
      for (final band in RepRangeBand.values) {
        expect(band.label, isNotEmpty);
        expect(band.rangeLabel, isNotEmpty);
      }
    });

    test('labels are distinct across bands', () {
      final labels = RepRangeBand.values.map((b) => b.label).toSet();
      expect(labels, hasLength(RepRangeBand.values.length));
    });
  });
}
