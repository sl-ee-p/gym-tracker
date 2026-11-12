// CoachService against real SQLite (sqflite_common_ffi), like the other
// repository tests: only completed workouts and working sets reach the
// engine, and the exercise's settings pick the rounding.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/coach/coach_models.dart';
import 'package:gym_app/models/exercise.dart';
import 'package:gym_app/models/exercise_set.dart';
import 'package:gym_app/models/workout_session.dart';
import 'package:gym_app/services/coach_service.dart';
import 'package:gym_app/services/database_helper.dart';
import 'package:gym_app/services/workout_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Database db;
  final repo = WorkoutRepository();
  final day0 = DateTime(2026, 9, 1, 18);

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('gym_app_coach_test');
    db = await DatabaseHelper().openDatabaseAt(
      p.join(tempDir.path, 'gym_tracker.db'),
    );
    DatabaseHelper.setDatabaseForTesting(db);
  });

  tearDown(() async {
    DatabaseHelper.setDatabaseForTesting(null);
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  /// One workout [day] days after day 0 with [sets] for exercise 1.
  Future<void> log(
    int day,
    List<(double, int, bool)> sets, {
    bool completed = true,
  }) async {
    final date = day0.add(Duration(days: day));
    final workoutId = await repo.insertWorkout(
      WorkoutSession(date: date, name: 'Push', isCompleted: completed),
    );
    var n = 1;
    for (final (w, r, warmup) in sets) {
      await repo.insertSet(
        ExerciseSet(
          workoutSessionId: workoutId,
          exerciseId: 1,
          setNumber: n,
          weight: w,
          reps: r,
          isWarmup: warmup,
          timestamp: date.add(Duration(minutes: n++)),
        ),
      );
    }
  }

  Exercise machine() => Exercise(id: 1, name: 'Chest Press', categoryId: 1);

  test('three completed workouts give a learned suggestion', () async {
    await log(0, [(40, 10, true), (85, 8, false), (85, 7, false)]);
    await log(7, [(40, 10, true), (87.5, 8, false), (87.5, 7, false)]);
    await log(14, [(40, 10, true), (90, 8, false), (90, 7, false)]);

    final report = await CoachService().reportFor(
      machine(),
      unit: 'kg',
      defaultBarWeightKg: 20,
      now: day0.add(const Duration(days: 17)),
    );

    expect(report.status, CoachStatus.progressing);
    expect(report.exposures, 3);
    expect(report.range.toString(), '6-8');
    expect(report.suggestion!.action, CoachAction.addWeight);
    expect(report.suggestion!.weight, 92.5);
  });

  test('the workout in progress and warm-ups are ignored', () async {
    await log(0, [(85, 8, false), (85, 7, false)]);
    await log(7, [(100, 3, false)], completed: false);
    await log(8, [(20, 12, true)]);

    final report = await CoachService().reportFor(
      machine(),
      unit: 'kg',
      defaultBarWeightKg: 20,
      now: day0.add(const Duration(days: 9)),
    );

    expect(report.status, CoachStatus.baseline);
    expect(report.exposures, 1);
    expect(report.suggestion!.weight, 85);
  });

  test('lb display converts the suggestion', () async {
    for (var i = 0; i < 3; i++) {
      await log(i * 7, [(100 / coachLbsPerKg, 8, false)]);
    }
    final report = await CoachService().reportFor(
      machine(),
      unit: 'lbs',
      defaultBarWeightKg: 20,
      now: day0.add(const Duration(days: 17)),
    );
    expect(report.suggestion!.weight, 105);
  });

  test('timed and unweighted exercises are unsupported', () async {
    final service = CoachService();
    for (final e in [
      Exercise(id: 1, name: 'Plank', categoryId: 1, isTimeBased: true),
      Exercise(id: 1, name: 'Push-up', categoryId: 1, isWeightBased: false),
    ]) {
      final r = await service.reportFor(e, unit: 'kg', defaultBarWeightKg: 20);
      expect(r.status, CoachStatus.unsupported, reason: e.name);
    }
  });

  test('exposuresFromRows groups by workout and drops warm-ups', () {
    final rows = [
      {
        'workoutId': 1,
        'workoutDate': '2026-09-01T18:00:00.000',
        'weight': 20.0,
        'reps': 10,
        'isWarmup': 1,
      },
      {
        'workoutId': 1,
        'workoutDate': '2026-09-01T18:00:00.000',
        'weight': 80.0,
        'reps': 8,
        'isWarmup': 0,
      },
      {
        'workoutId': 2,
        'workoutDate': '2026-09-05T18:00:00.000',
        'weight': 82.5,
        'reps': 7,
        'isWarmup': 0,
      },
    ];
    final exposures = CoachService.exposuresFromRows(rows);
    expect(exposures, hasLength(2));
    expect(exposures.first.sets.single.weightKg, 80);
    expect(exposures.last.date, DateTime(2026, 9, 5, 18));
  });
}
