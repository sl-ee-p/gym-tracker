// Guards the "exercises reorder alphabetically after closing the app" bug.
//
// WorkoutRepository.getSetsByWorkout orders by "exerciseId, setNumber" for
// query-plan reasons unrelated to display — that is ascending exercise
// library id, not the order exercises were added to this workout.
// loadActiveWorkout used to rebuild its exercise list straight from that
// query's row order, so every restart silently reshuffled the current
// workout. Runs against real SQLite through sqflite_common_ffi, the same way
// the repository and migration tests do.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/workout_template.dart';
import 'package:gym_app/providers/workout_provider.dart';
import 'package:gym_app/services/database_helper.dart';
import 'package:gym_app/services/workout_template_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('gym_app_provider_test');
    db = await DatabaseHelper()
        .openDatabaseAt(p.join(tempDir.path, 'gym_tracker.db'));
    DatabaseHelper.setDatabaseForTesting(db);
  });

  tearDown(() async {
    DatabaseHelper.setDatabaseForTesting(null);
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  test(
      'loadActiveWorkout keeps exercises in first-logged order, not '
      'ascending exercise id', () async {
    final provider = WorkoutProvider();
    await provider.startWorkout(workoutName: 'Push Day');

    // Deliberately out of ascending-id order: exercise 30 is logged first,
    // then 10, then 20 — ascending-id order would read 10, 20, 30.
    await provider.addSet(exerciseId: 30, weight: 100, reps: 5);
    await provider.addSet(exerciseId: 10, weight: 50, reps: 8);
    await provider.addSet(exerciseId: 20, weight: 20, reps: 12);

    expect(provider.getCurrentWorkoutExercises(), [30, 10, 20]);

    // Simulate an app restart: a fresh provider, rehydrated from the DB.
    final reloaded = WorkoutProvider();
    await reloaded.loadActiveWorkout();

    expect(reloaded.getCurrentWorkoutExercises(), [30, 10, 20]);
  });

  group('personal records', () {
    test('addSet flags more reps at the same weight as a new best', () async {
      final provider = WorkoutProvider();
      await provider.startWorkout(workoutName: 'Push Day');

      final first = await provider.addSet(exerciseId: 1, weight: 100, reps: 5);
      final moreReps =
          await provider.addSet(exerciseId: 1, weight: 100, reps: 8);
      final repeat = await provider.addSet(exerciseId: 1, weight: 100, reps: 8);

      expect(first.isPersonalRecord, isFalse);
      expect(moreReps.isPersonalRecord, isTrue);
      expect(repeat.isPersonalRecord, isFalse);
    });

    test('partial reps are stored but never make a set a record', () async {
      final provider = WorkoutProvider();
      await provider.startWorkout(workoutName: 'Push Day');

      await provider.addSet(exerciseId: 1, weight: 100, reps: 8);
      final withPartials = await provider.addSet(
          exerciseId: 1, weight: 100, reps: 8, partialReps: 4);

      expect(withPartials.partialReps, 4);
      expect(withPartials.isPersonalRecord, isFalse);
      expect(withPartials.volume, 800);
    });

    test('updateSet re-resolves the edited set and the ones after it',
        () async {
      final provider = WorkoutProvider();
      await provider.startWorkout(workoutName: 'Push Day');

      final first = await provider.addSet(exerciseId: 1, weight: 100, reps: 5);
      final second = await provider.addSet(exerciseId: 1, weight: 105, reps: 5);
      expect(second.isPersonalRecord, isTrue);

      // Raising the first set to 110 means the 105 no longer beats anything.
      final edited = await provider.updateSet(first.copyWith(weight: 110));

      expect(edited.isPersonalRecord, isFalse,
          reason: 'still the first set, so still nothing to beat');
      final sets = provider.getSetsForExercise(1);
      expect(sets.map((s) => s.weight), [110, 105]);
      expect(sets.map((s) => s.isPersonalRecord), [false, false]);

      // And it was persisted, not just patched in memory.
      final reloaded = WorkoutProvider();
      await reloaded.loadActiveWorkout();
      expect(reloaded.getSetsForExercise(1).map((s) => s.weight), [110, 105]);
    });
  });

  group('exercise groups (supersets/circuits)', () {
    test(
        'a grouped exercise with zero logged sets survives loadActiveWorkout',
        () async {
      final provider = WorkoutProvider();
      await provider.startWorkout(workoutName: 'Push Day');

      // Group two exercises, but only ever log a set for one of them — the
      // other has no footprint in exercise_sets at all.
      await provider.groupExercises([100, 200]);
      await provider.addSet(exerciseId: 100, weight: 50, reps: 8);

      expect(provider.getCurrentWorkoutExercises(), containsAll([100, 200]));

      // Simulate an app restart: a fresh provider, rehydrated from the DB.
      final reloaded = WorkoutProvider();
      await reloaded.loadActiveWorkout();

      final ids = reloaded.getCurrentWorkoutExercises();
      expect(ids, containsAll([100, 200]),
          reason: 'the zero-set member must not vanish on reload');
      final indexOf100 = ids.indexOf(100);
      final indexOf200 = ids.indexOf(200);
      expect((indexOf100 - indexOf200).abs(), 1,
          reason: 'the group must stay contiguous after reload');

      expect(reloaded.isLastInGroup(100), isFalse);
      expect(reloaded.isLastInGroup(200), isTrue);
      expect(reloaded.groupMembersFor(100), [100, 200]);
    });

    test('ungroupExercise dissolves a two-member group entirely', () async {
      final provider = WorkoutProvider();
      await provider.startWorkout(workoutName: 'Push Day');
      await provider.groupExercises([1, 2]);

      expect(provider.isLastInGroup(1), isFalse);
      expect(provider.groupMembersFor(2), [1, 2]);

      await provider.ungroupExercise(1);

      expect(provider.groupMembersFor(1), isNull);
      expect(provider.groupMembersFor(2), isNull,
          reason: 'a superset of one member left behind is not meaningful');
      expect(provider.isLastInGroup(1), isTrue);
      expect(provider.isLastInGroup(2), isTrue);
    });

    test(
        'startWorkoutFromTemplate carries over template grouping, dropping a '
        'group to standalone when a member no longer exists', () async {
      // A default category already exists (seeded on first open) — reuse it
      // rather than inserting a duplicate 'Push' name, which the table's
      // UNIQUE constraint on name would reject.
      final categoryId = (await db.query('exercise_categories', limit: 1))
          .single['id'] as int;
      Future<int> insertExercise(String name) => db.insert('exercises', {
            'name': name,
            'categoryId': categoryId,
            'isWeightBased': 1,
            'isTimeBased': 0,
            'isRepsBased': 1,
          });

      final benchId = await insertExercise('Bench Press');
      final flyId = await insertExercise('Chest Fly');
      final curlId = await insertExercise('Bicep Curl');
      final rowId = await insertExercise('Cable Row');

      final template = WorkoutTemplate(
        name: 'Push/Pull',
        exerciseIds: [benchId, flyId, curlId, rowId],
        // bench+fly form one group; curl+row form another.
        exerciseGroupIds: [benchId, benchId, curlId, curlId],
        createdDate: DateTime(2026, 1, 1),
      );
      final templateId =
          await WorkoutTemplateRepository().insertTemplate(template);

      // curlId no longer exists in the exercise library — the same
      // dangling-id situation duplicateWorkout already defends against.
      await db.delete('exercises', where: 'id = ?', whereArgs: [curlId]);

      final provider = WorkoutProvider();
      await provider.startWorkoutFromTemplate(templateId);

      final ids = provider.getCurrentWorkoutExercises();
      expect(ids, containsAll([benchId, flyId, rowId]));
      expect(ids, isNot(contains(curlId)));

      // bench+fly survive as a group...
      expect(provider.groupMembersFor(benchId), containsAll([benchId, flyId]));
      expect(provider.isLastInGroup(flyId), isTrue);

      // ...but curl+row's group is down to a single valid member (rowId),
      // so it goes standalone rather than a "superset of one".
      expect(provider.groupMembersFor(rowId), isNull);
      expect(provider.isLastInGroup(rowId), isTrue);
    });
  });
}
