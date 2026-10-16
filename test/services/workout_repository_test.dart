// Guards the "All time max weight is wrong" family of bugs.
//
// Three separate defects fed the same symptom: deleteWorkout leaked its sets
// (the schema's ON DELETE CASCADE never fires, because PRAGMA foreign_keys is
// deliberately never switched on), the all-time query counted the workout
// still in progress, and it required `reps IS NOT NULL` where the chart does
// not — which could make all-time read *lower* than the visible max.
//
// Runs against real SQLite through sqflite_common_ffi, the same way the
// migration tests do.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/services/database_helper.dart';
import 'package:gym_app/services/workout_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Database db;
  late WorkoutRepository repository;

  /// Monotonic, so `ORDER BY timestamp` is deterministic across inserts.
  var clock = DateTime(2026, 1, 1, 9, 0, 0);

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('gym_app_repo_test');
    db = await DatabaseHelper()
        .openDatabaseAt(p.join(tempDir.path, 'gym_tracker.db'));
    DatabaseHelper.setDatabaseForTesting(db);
    repository = WorkoutRepository();
    clock = DateTime(2026, 1, 1, 9, 0, 0);
  });

  tearDown(() async {
    DatabaseHelper.setDatabaseForTesting(null);
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<int> insertWorkout({required bool completed}) {
    clock = clock.add(const Duration(minutes: 1));
    return db.insert('workout_sessions', {
      'date': clock.toIso8601String(),
      'name': 'Session',
      'isCompleted': completed ? 1 : 0,
    });
  }

  Future<int> insertSet({
    required int workoutId,
    required int exerciseId,
    double? weight,
    int? reps,
    bool warmup = false,
    int setNumber = 1,
  }) {
    clock = clock.add(const Duration(seconds: 30));
    return db.insert('exercise_sets', {
      'workoutSessionId': workoutId,
      'exerciseId': exerciseId,
      'setNumber': setNumber,
      'weight': weight,
      'reps': reps,
      'isWarmup': warmup ? 1 : 0,
      'isPersonalRecord': 0,
      'timestamp': clock.toIso8601String(),
    });
  }

  Future<double?> allTimeMax(int exerciseId) async {
    final records = await repository.getExercisePersonalRecords(exerciseId);
    return (records?['maxWeight'] as num?)?.toDouble();
  }

  Future<int> setCount() async =>
      (await db.rawQuery('SELECT COUNT(*) AS c FROM exercise_sets'))
          .first['c'] as int;

  group('deleteWorkout', () {
    test('removes the workout and its sets', () async {
      final workoutId = await insertWorkout(completed: true);
      await insertSet(workoutId: workoutId, exerciseId: 1, weight: 100, reps: 5);
      await insertSet(
          workoutId: workoutId, exerciseId: 1, weight: 105, reps: 3, setNumber: 2);

      await repository.deleteWorkout(workoutId);

      expect(await setCount(), 0,
          reason: 'the cascade this used to rely on never fires');
    });

    test('leaves other workouts and their sets alone', () async {
      final kept = await insertWorkout(completed: true);
      await insertSet(workoutId: kept, exerciseId: 1, weight: 80, reps: 5);
      final removed = await insertWorkout(completed: true);
      await insertSet(workoutId: removed, exerciseId: 1, weight: 200, reps: 1);

      await repository.deleteWorkout(removed);

      expect(await setCount(), 1);
      expect(await allTimeMax(1), 80);
    });

    test('a cancelled workout cannot inflate the all-time max', () async {
      final history = await insertWorkout(completed: true);
      await insertSet(workoutId: history, exerciseId: 1, weight: 90, reps: 5);

      // The reported bug, end to end: log something heavy, then cancel.
      final cancelled = await insertWorkout(completed: false);
      await insertSet(workoutId: cancelled, exerciseId: 1, weight: 250, reps: 1);
      await repository.deleteWorkout(cancelled);

      expect(await allTimeMax(1), 90);
    });

    test('also removes its workout_exercise_groups rows', () async {
      final workoutId = await insertWorkout(completed: false);
      await repository.upsertWorkoutExerciseGroup(
          workoutSessionId: workoutId, exerciseId: 1, groupId: 1, groupOrder: 0);
      await repository.upsertWorkoutExerciseGroup(
          workoutSessionId: workoutId, exerciseId: 2, groupId: 1, groupOrder: 1);

      await repository.deleteWorkout(workoutId);

      final remaining = await db.query('workout_exercise_groups');
      expect(remaining, isEmpty,
          reason: 'no cascade ever fires in this app — same reasoning as '
              'exercise_sets above');
    });
  });

  group('workout exercise groups', () {
    test('upsertWorkoutExerciseGroup then getWorkoutExerciseGroups round-trips',
        () async {
      final workoutId = await insertWorkout(completed: false);
      await repository.upsertWorkoutExerciseGroup(
          workoutSessionId: workoutId, exerciseId: 10, groupId: 10, groupOrder: 0);
      await repository.upsertWorkoutExerciseGroup(
          workoutSessionId: workoutId, exerciseId: 20, groupId: 10, groupOrder: 1);

      final groups = await repository.getWorkoutExerciseGroups(workoutId);

      expect(groups, hasLength(2));
      expect(groups.map((g) => g.exerciseId), [10, 20]);
      expect(groups.every((g) => g.groupId == 10), isTrue);
      expect(groups.map((g) => g.groupOrder), [0, 1]);
    });

    test(
        're-upserting an exercise already in a different group moves it '
        '(the unique index means it can only be in one)', () async {
      final workoutId = await insertWorkout(completed: false);
      await repository.upsertWorkoutExerciseGroup(
          workoutSessionId: workoutId, exerciseId: 10, groupId: 10, groupOrder: 0);
      await repository.upsertWorkoutExerciseGroup(
          workoutSessionId: workoutId, exerciseId: 20, groupId: 10, groupOrder: 1);

      // Move exercise 10 into a brand-new group with exercise 30.
      await repository.upsertWorkoutExerciseGroup(
          workoutSessionId: workoutId, exerciseId: 30, groupId: 30, groupOrder: 0);
      await repository.upsertWorkoutExerciseGroup(
          workoutSessionId: workoutId, exerciseId: 10, groupId: 30, groupOrder: 1);

      final groups = await repository.getWorkoutExerciseGroups(workoutId);
      final byExercise = {for (final g in groups) g.exerciseId: g};

      expect(byExercise[10]!.groupId, 30, reason: 'moved out of its old group');
      expect(byExercise[20]!.groupId, 10,
          reason: 'left behind, still in the original group');
      expect(byExercise[30]!.groupId, 30);
      expect(groups.where((g) => g.exerciseId == 10), hasLength(1),
          reason: 'exactly one row for exercise 10, not two');
    });

    test("deleteWorkoutExerciseGroup removes just that exercise's membership",
        () async {
      final workoutId = await insertWorkout(completed: false);
      await repository.upsertWorkoutExerciseGroup(
          workoutSessionId: workoutId, exerciseId: 10, groupId: 10, groupOrder: 0);
      await repository.upsertWorkoutExerciseGroup(
          workoutSessionId: workoutId, exerciseId: 20, groupId: 10, groupOrder: 1);

      await repository.deleteWorkoutExerciseGroup(workoutId, 10);

      final groups = await repository.getWorkoutExerciseGroups(workoutId);
      expect(groups.map((g) => g.exerciseId), [20]);
    });
  });

  group('getExercisePersonalRecords', () {
    test('ignores the workout still in progress', () async {
      final done = await insertWorkout(completed: true);
      await insertSet(workoutId: done, exerciseId: 1, weight: 100, reps: 5);
      final inProgress = await insertWorkout(completed: false);
      await insertSet(workoutId: inProgress, exerciseId: 1, weight: 140, reps: 1);

      expect(await allTimeMax(1), 100,
          reason: 'the chart beside it excludes the active workout too');
    });

    test('ignores warm-up sets', () async {
      final workoutId = await insertWorkout(completed: true);
      await insertSet(workoutId: workoutId, exerciseId: 1, weight: 60, reps: 10);
      await insertSet(
          workoutId: workoutId,
          exerciseId: 1,
          weight: 300,
          reps: 1,
          warmup: true,
          setNumber: 2);

      expect(await allTimeMax(1), 60);
    });

    test('counts a weighted set that has no reps', () async {
      // A loaded carry or timed hold. The chart's per-day max counts it, so
      // all-time must too — otherwise all-time reads lower than the visible
      // max, which is impossible, and the caption silently disappears.
      final workoutId = await insertWorkout(completed: true);
      await insertSet(workoutId: workoutId, exerciseId: 1, weight: 70, reps: 5);
      await insertSet(
          workoutId: workoutId, exerciseId: 1, weight: 120, setNumber: 2);

      expect(await allTimeMax(1), 120);
    });

    test('never reports less than the chart shows for the same data',
        () async {
      final workoutId = await insertWorkout(completed: true);
      await insertSet(workoutId: workoutId, exerciseId: 1, weight: 70, reps: 5);
      await insertSet(
          workoutId: workoutId, exerciseId: 1, weight: 130, setNumber: 2);

      final rows = await repository.getExerciseProgressData(1);
      final chartMax = rows
          .where((row) => row['isWarmup'] == 0 && row['weight'] != null)
          .map((row) => (row['weight'] as num).toDouble())
          .reduce((a, b) => a > b ? a : b);

      expect(await allTimeMax(1), greaterThanOrEqualTo(chartMax));
    });

    test('returns a null max for an exercise with no qualifying sets',
        () async {
      expect(await allTimeMax(99), isNull);
    });
  });

  group('isRepPersonalRecord', () {
    test('does see the workout in progress', () async {
      // The opposite of the display query, and deliberately so: the second
      // heavy set of a session must beat the first, not just history.
      final inProgress = await insertWorkout(completed: false);
      await insertSet(workoutId: inProgress, exerciseId: 1, weight: 110, reps: 3);

      expect(
          await repository.isRepPersonalRecord(1, weight: 110, reps: 3), isFalse,
          reason: 'matched exactly by the set logged minutes earlier');
      expect(
          await repository.isRepPersonalRecord(1, weight: 110, reps: 4), isTrue);
    });

    test('credits more reps at the same weight, not fewer', () async {
      final workoutId = await insertWorkout(completed: true);
      await insertSet(workoutId: workoutId, exerciseId: 1, weight: 100, reps: 5);

      expect(await repository.isRepPersonalRecord(1, weight: 100, reps: 10),
          isTrue);
      expect(await repository.isRepPersonalRecord(1, weight: 90, reps: 5),
          isFalse);
      expect(await repository.isRepPersonalRecord(1, weight: 60, reps: 15),
          isTrue, reason: 'nothing earlier reached 15 reps');
    });

    test('ignores warm-ups and sets without reps', () async {
      final workoutId = await insertWorkout(completed: true);
      await insertSet(workoutId: workoutId, exerciseId: 1, weight: 100, reps: 5);
      await insertSet(
          workoutId: workoutId,
          exerciseId: 1,
          weight: 300,
          reps: 1,
          warmup: true,
          setNumber: 2);
      await insertSet(
          workoutId: workoutId, exerciseId: 1, weight: 250, setNumber: 3);

      expect(await repository.isRepPersonalRecord(1, weight: 120, reps: 1),
          isTrue, reason: 'the heavier warm-up and rep-less set do not count');
    });

    test('is never a record with no history', () async {
      expect(await repository.isRepPersonalRecord(1, weight: 100, reps: 5),
          isFalse);
    });
  });

  group('getRepMaxSets', () {
    test('returns completed working sets only', () async {
      final done = await insertWorkout(completed: true);
      final inProgress = await insertWorkout(completed: false);
      await insertSet(workoutId: done, exerciseId: 1, weight: 100, reps: 5);
      await insertSet(
          workoutId: done, exerciseId: 1, weight: 200, reps: 1, warmup: true);
      await insertSet(workoutId: inProgress, exerciseId: 1, weight: 150, reps: 1);

      final sets = await repository.getRepMaxSets(1);

      expect(sets, hasLength(1));
      expect(sets.single.weight, 100);
      expect(sets.single.reps, 5);
    });
  });

  group('recalculatePersonalRecords', () {
    test('ignores sets whose workout no longer exists', () async {
      final workoutId = await insertWorkout(completed: true);
      final first =
          await insertSet(workoutId: workoutId, exerciseId: 1, weight: 80, reps: 5);
      // Inserted directly against a workout id that was never created — the
      // shape every cancelled workout used to leave behind.
      await insertSet(workoutId: 9999, exerciseId: 1, weight: 500, reps: 1);
      final later = await insertSet(
          workoutId: workoutId, exerciseId: 1, weight: 90, reps: 5, setNumber: 2);

      final records = await repository.recalculatePersonalRecords(1);

      expect(records, contains(later),
          reason: '90 beats 80; the phantom 500 must not mask it');
      expect(records, isNot(contains(first)),
          reason: 'the first set of an exercise has no prior max to beat');
    });

    test('applies the rep rule and persists the flags', () async {
      final workoutId = await insertWorkout(completed: true);
      await insertSet(workoutId: workoutId, exerciseId: 1, weight: 100, reps: 5);
      final moreReps = await insertSet(
          workoutId: workoutId, exerciseId: 1, weight: 100, reps: 8, setNumber: 2);
      final matched = await insertSet(
          workoutId: workoutId, exerciseId: 1, weight: 95, reps: 8, setNumber: 3);

      final records = await repository.recalculatePersonalRecords(1);

      expect(records, {moreReps});
      final flagged = await db.query('exercise_sets',
          where: 'isPersonalRecord = 1', columns: ['id']);
      expect(flagged.map((row) => row['id']), [moreReps]);
      expect(records, isNot(contains(matched)));
    });
  });
}
