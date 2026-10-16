// Covers the four analytics additions' queries: the raw per-workout feed,
// muscle-group balance, weekly-goal adherence, and the rep-range breakdown.
//
// Runs against real SQLite through sqflite_common_ffi, the same scaffold as
// workout_repository_test.dart — this project has no mocking library, and a
// hand-rolled fake would risk drifting from SQLite's actual behaviour (e.g.
// NULL handling in aggregates), which is exactly what these queries lean on.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/analytics.dart';
import 'package:gym_app/services/analytics_service.dart';
import 'package:gym_app/services/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Database db;
  late AnalyticsService service;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('gym_app_analytics_test');
    db = await DatabaseHelper()
        .openDatabaseAt(p.join(tempDir.path, 'gym_tracker.db'));
    DatabaseHelper.setDatabaseForTesting(db);
    service = AnalyticsService();
  });

  tearDown(() async {
    DatabaseHelper.setDatabaseForTesting(null);
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<int> insertWorkout({
    required DateTime date,
    bool completed = true,
  }) {
    return db.insert('workout_sessions', {
      'date': date.toIso8601String(),
      'name': 'Session',
      'isCompleted': completed ? 1 : 0,
    });
  }

  Future<int> insertExercise({
    String name = 'Exercise',
    String? muscleGroups,
  }) {
    return db.insert('exercises', {
      'name': name,
      'categoryId': 1,
      'muscleGroups': muscleGroups,
    });
  }

  Future<int> insertSet({
    required int workoutId,
    required int exerciseId,
    double? weight,
    int? reps,
    bool warmup = false,
    int setNumber = 1,
    DateTime? timestamp,
  }) {
    return db.insert('exercise_sets', {
      'workoutSessionId': workoutId,
      'exerciseId': exerciseId,
      'setNumber': setNumber,
      'weight': weight,
      'reps': reps,
      'isWarmup': warmup ? 1 : 0,
      'isPersonalRecord': 0,
      'timestamp': (timestamp ?? DateTime(2026, 1, 1)).toIso8601String(),
    });
  }

  group('workoutTotals', () {
    test('excludes warm-ups from sets/volume, but a zero-set workout still '
        'appears', () async {
      final exerciseId = await insertExercise();

      // Only a warm-up: no qualifying sets at all.
      final warmupOnly = await insertWorkout(date: DateTime(2026, 1, 5));
      await insertSet(
        workoutId: warmupOnly,
        exerciseId: exerciseId,
        weight: 300,
        reps: 1,
        warmup: true,
      );

      // A warm-up plus a working set.
      final mixed = await insertWorkout(date: DateTime(2026, 1, 6));
      await insertSet(
        workoutId: mixed,
        exerciseId: exerciseId,
        weight: 300,
        reps: 1,
        warmup: true,
      );
      await insertSet(
        workoutId: mixed,
        exerciseId: exerciseId,
        weight: 100,
        reps: 5,
        setNumber: 2,
      );

      final totals = await service.workoutTotals();

      expect(totals, hasLength(2),
          reason: 'the warm-up-only workout must still appear');
      expect(totals[0].date, DateTime(2026, 1, 5));
      expect(totals[0].sets, 0);
      expect(totals[0].volumeKg, 0);
      expect(totals[0].reps, 0);

      expect(totals[1].date, DateTime(2026, 1, 6));
      expect(totals[1].sets, 1, reason: 'the warm-up does not count');
      expect(totals[1].volumeKg, 500);
      expect(totals[1].reps, 5);
    });

    test('ignores a workout still in progress', () async {
      final exerciseId = await insertExercise();
      final inProgress =
          await insertWorkout(date: DateTime(2026, 1, 5), completed: false);
      await insertSet(workoutId: inProgress, exerciseId: exerciseId,
          weight: 100, reps: 5);

      expect(await service.workoutTotals(), isEmpty);
    });

    test('filters by date range', () async {
      final exerciseId = await insertExercise();
      final inRange = await insertWorkout(date: DateTime(2026, 1, 10));
      await insertSet(
          workoutId: inRange, exerciseId: exerciseId, weight: 50, reps: 5);
      final outOfRange = await insertWorkout(date: DateTime(2026, 2, 1));
      await insertSet(
          workoutId: outOfRange, exerciseId: exerciseId, weight: 50, reps: 5);

      final totals = await service.workoutTotals(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 31),
      );

      expect(totals, hasLength(1));
      expect(totals.single.date, DateTime(2026, 1, 10));
    });
  });

  group('muscleGroupBalance', () {
    test('a multi-muscle-group exercise counts a set toward each group',
        () async {
      final bench =
          await insertExercise(name: 'Bench', muscleGroups: 'Chest,Triceps');
      final curl =
          await insertExercise(name: 'Curl', muscleGroups: 'Biceps');

      final workoutId = await insertWorkout(date: DateTime(2026, 1, 5));
      await insertSet(
          workoutId: workoutId, exerciseId: bench, weight: 80, reps: 5);
      await insertSet(workoutId: workoutId, exerciseId: bench, weight: 80,
          reps: 5, setNumber: 2);
      await insertSet(
          workoutId: workoutId, exerciseId: curl, weight: 15, reps: 10,
          setNumber: 3);

      final balances = await service.muscleGroupBalance();
      final byGroup = {for (final b in balances) b.muscleGroup: b};

      expect(byGroup['Chest']!.sets, 2);
      expect(byGroup['Triceps']!.sets, 2);
      expect(byGroup['Biceps']!.sets, 1);
    });

    test('a no-muscle-group exercise is excluded entirely, not bucketed',
        () async {
      final tagged =
          await insertExercise(name: 'Bench', muscleGroups: 'Chest');
      final untagged = await insertExercise(name: 'Mystery machine');

      final workoutId = await insertWorkout(date: DateTime(2026, 1, 5));
      await insertSet(
          workoutId: workoutId, exerciseId: tagged, weight: 80, reps: 5);
      await insertSet(workoutId: workoutId, exerciseId: untagged, weight: 40,
          reps: 8, setNumber: 2);

      final balances = await service.muscleGroupBalance();

      expect(balances.map((b) => b.muscleGroup), ['Chest']);
      expect(balances.any((b) => b.muscleGroup == 'Untagged'), isFalse);
    });

    test('a bodyweight set still counts toward sets with zero volume',
        () async {
      final exerciseId =
          await insertExercise(name: 'Pull-up', muscleGroups: 'Back');
      final workoutId = await insertWorkout(date: DateTime(2026, 1, 5));
      await insertSet(
          workoutId: workoutId, exerciseId: exerciseId, weight: null, reps: 8);

      final balances = await service.muscleGroupBalance();

      expect(balances.single.muscleGroup, 'Back');
      expect(balances.single.sets, 1);
      expect(balances.single.volumeKg, 0);
    });
  });

  group('weeklyGoalAdherence', () {
    test('a week with no logged workouts appears as missed', () async {
      final exerciseId = await insertExercise();
      // Monday-based weeks: 5 Jan and 19 Jan 2026 are both Mondays, with the
      // week of 12 Jan left empty in between.
      final week1 = await insertWorkout(date: DateTime(2026, 1, 5));
      await insertSet(
          workoutId: week1, exerciseId: exerciseId, weight: 50, reps: 5);
      final week3 = await insertWorkout(date: DateTime(2026, 1, 19));
      await insertSet(
          workoutId: week3, exerciseId: exerciseId, weight: 50, reps: 5);

      final weeks = await service.weeklyGoalAdherence(
        goal: 1,
        now: DateTime(2026, 1, 26), // one week after the last logged week
      );

      expect(weeks, hasLength(3));
      expect(weeks[0].weekStart, DateTime(2026, 1, 5));
      expect(weeks[0].workouts, 1);
      expect(weeks[1].weekStart, DateTime(2026, 1, 12));
      expect(weeks[1].workouts, 0);
      expect(weeks[1].metGoal, isFalse);
      expect(weeks[2].weekStart, DateTime(2026, 1, 19));
      expect(weeks[2].workouts, 1);
    });

    test('the current in-progress week is never included', () async {
      final exerciseId = await insertExercise();
      final now = DateTime(2026, 1, 21); // a Wednesday
      final currentWeekStart = DateTime(2026, 1, 19); // that week's Monday

      final lastWeek = await insertWorkout(date: DateTime(2026, 1, 12));
      await insertSet(
          workoutId: lastWeek, exerciseId: exerciseId, weight: 50, reps: 5);
      final thisWeek = await insertWorkout(date: DateTime(2026, 1, 20));
      await insertSet(
          workoutId: thisWeek, exerciseId: exerciseId, weight: 50, reps: 5);

      final weeks = await service.weeklyGoalAdherence(goal: 1, now: now);

      expect(weeks.any((w) => w.weekStart == currentWeekStart), isFalse,
          reason: 'the still-open current week must never be judged');
      expect(weeks.last.weekStart, DateTime(2026, 1, 12));
    });

    test("falls back to the earliest workout's week when startDate is null",
        () async {
      final exerciseId = await insertExercise();
      final earliest = await insertWorkout(date: DateTime(2026, 1, 7));
      await insertSet(
          workoutId: earliest, exerciseId: exerciseId, weight: 50, reps: 5);

      final weeks = await service.weeklyGoalAdherence(
        goal: 1,
        now: DateTime(2026, 1, 26),
      );

      expect(weeks.first.weekStart, DateTime(2026, 1, 5),
          reason: "the Monday of the earliest workout's week");
    });

    test('returns [] with no data', () async {
      expect(await service.weeklyGoalAdherence(goal: 3), isEmpty);
    });
  });

  group('repRangeBreakdown', () {
    test('rep counts exactly at the 5/12 boundaries land in the correct '
        'band', () async {
      final exerciseId = await insertExercise();
      final workoutId = await insertWorkout(date: DateTime(2026, 1, 5));
      await insertSet(workoutId: workoutId, exerciseId: exerciseId,
          weight: 100, reps: 5, setNumber: 1); // strength (boundary)
      await insertSet(workoutId: workoutId, exerciseId: exerciseId,
          weight: 100, reps: 6, setNumber: 2); // hypertrophy (boundary)
      await insertSet(workoutId: workoutId, exerciseId: exerciseId,
          weight: 100, reps: 12, setNumber: 3); // hypertrophy (boundary)
      await insertSet(workoutId: workoutId, exerciseId: exerciseId,
          weight: 100, reps: 13, setNumber: 4); // endurance (boundary)

      final breakdown = await service.repRangeBreakdown();
      final byBand = {for (final b in breakdown) b.band: b};

      expect(byBand[RepRangeBand.strength]!.sets, 1);
      expect(byBand[RepRangeBand.hypertrophy]!.sets, 2);
      expect(byBand[RepRangeBand.endurance]!.sets, 1);
    });

    test('every band is present even when empty', () async {
      final breakdown = await service.repRangeBreakdown();
      expect(breakdown.map((b) => b.band).toSet(), RepRangeBand.values.toSet());
      for (final summary in breakdown) {
        expect(summary.sets, 0);
        expect(summary.volumeKg, 0);
      }
    });

    test('null-rep sets are excluded', () async {
      final exerciseId = await insertExercise();
      final workoutId = await insertWorkout(date: DateTime(2026, 1, 5));
      await insertSet(
          workoutId: workoutId, exerciseId: exerciseId, weight: 100, reps: null);

      final breakdown = await service.repRangeBreakdown();
      final totalSets =
          breakdown.fold<int>(0, (sum, summary) => sum + summary.sets);
      expect(totalSets, 0);
    });

    test('a bodyweight set contributes to sets but not volumeKg', () async {
      final exerciseId = await insertExercise();
      final workoutId = await insertWorkout(date: DateTime(2026, 1, 5));
      await insertSet(
          workoutId: workoutId, exerciseId: exerciseId, weight: null, reps: 10);

      final breakdown = await service.repRangeBreakdown();
      final hypertrophy =
          breakdown.firstWhere((b) => b.band == RepRangeBand.hypertrophy);

      expect(hypertrophy.sets, 1);
      expect(hypertrophy.volumeKg, 0);
    });
  });
}
