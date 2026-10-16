import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/exercise_set.dart';
import 'package:gym_app/models/weight_entry.dart';

void main() {
  test('ExerciseSet volume is calculated from weight and reps', () {
    final set = ExerciseSet(
      workoutSessionId: 1,
      exerciseId: 1,
      setNumber: 1,
      weight: 80,
      reps: 5,
      timestamp: DateTime(2025, 1, 1),
    );

    expect(set.volume, 400);
  });

  test('partial reps are recorded but never counted in volume', () {
    final set = ExerciseSet(
      workoutSessionId: 1,
      exerciseId: 1,
      setNumber: 1,
      weight: 100,
      reps: 8,
      partialReps: 3,
      rpe: 8.5,
      timestamp: DateTime(2025, 1, 1),
    );

    expect(set.volume, 800);

    final restored = ExerciseSet.fromMap(set.toMap());
    expect(restored.partialReps, 3);
    expect(restored.rpe, 8.5);
    expect(restored.volume, 800);
  });

  test('ExerciseSet copyWith can clear partials, RPE and notes', () {
    final set = ExerciseSet(
      workoutSessionId: 1,
      exerciseId: 1,
      setNumber: 1,
      reps: 8,
      partialReps: 3,
      rpe: 9,
      notes: 'grindy',
      timestamp: DateTime(2025, 1, 1),
    );

    final cleared =
        set.copyWith(clearPartialReps: true, clearRpe: true, clearNotes: true);

    expect(cleared.partialReps, isNull);
    expect(cleared.rpe, isNull);
    expect(cleared.notes, isNull);
    expect(cleared.reps, 8);
  });

  test('formatRpe drops the decimal only for whole numbers', () {
    expect(formatRpe(8), '8');
    expect(formatRpe(8.5), '8.5');
  });

  test('ExerciseSet formatted duration returns mm:ss', () {
    final set = ExerciseSet(
      workoutSessionId: 1,
      exerciseId: 2,
      setNumber: 1,
      duration: const Duration(minutes: 2, seconds: 5),
      timestamp: DateTime(2025, 1, 1),
    );

    expect(set.formattedDuration, '2:05');
  });

  // kg/lbs conversion lives in utils/weight_format.dart (see its tests); the
  // entry itself only ever holds kg.
  test('WeightEntry round-trips through its map', () {
    final entry = WeightEntry(
      id: 1,
      weight: 92.25,
      date: DateTime(2025, 1, 1),
      notes: 'morning',
    );

    final restored = WeightEntry.fromMap(entry.toMap());

    expect(restored.id, 1);
    expect(restored.weight, 92.25);
    expect(restored.date, DateTime(2025, 1, 1));
    expect(restored.notes, 'morning');
  });
}
