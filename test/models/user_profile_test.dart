import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/user_profile.dart';

void main() {
  UserProfile profile({int? lastProgressExerciseId, int? restTimerSeconds}) =>
      UserProfile(
        name: 'Sam',
        createdDate: DateTime(2025, 3, 1),
        lastProgressExerciseId: lastProgressExerciseId,
        restTimerSeconds: restTimerSeconds,
      );

  group('lastProgressExerciseId', () {
    test('round-trips through toMap/fromMap', () {
      final restored =
          UserProfile.fromMap(profile(lastProgressExerciseId: 42).toMap());

      expect(restored.lastProgressExerciseId, 42);
    });

    test('is null when the column has never been written', () {
      final restored = UserProfile.fromMap(profile().toMap());

      expect(restored.lastProgressExerciseId, isNull);
    });

    test('survives an unrelated copyWith', () {
      final updated =
          profile(lastProgressExerciseId: 42).copyWith(weightUnit: 'lbs');

      expect(updated.lastProgressExerciseId, 42);
    });

    test('needs the clear flag to be nulled', () {
      final original = profile(lastProgressExerciseId: 42);

      // The documented trap: `null ?? this.field` keeps the old value, so
      // passing null cannot clear a nullable field.
      expect(original.copyWith(lastProgressExerciseId: null)
          .lastProgressExerciseId, 42);
      expect(
          original.copyWith(clearLastProgressExercise: true)
              .lastProgressExerciseId,
          isNull);
    });
  });

  group('restTimerSeconds', () {
    test('round-trips through toMap/fromMap', () {
      final restored =
          UserProfile.fromMap(profile(restTimerSeconds: 120).toMap());

      expect(restored.restTimerSeconds, 120);
    });

    test('survives an unrelated copyWith', () {
      final updated = profile(restTimerSeconds: 120).copyWith(themeMode: 'dark');

      expect(updated.restTimerSeconds, 120);
    });
  });

  group('v8 settings', () {
    test('default to off, no goal and the stock reminder times', () {
      final fresh = profile();

      expect(fresh.partialRepsEnabled, isFalse);
      expect(fresh.rpeEnabled, isFalse);
      expect(fresh.targetWeight, isNull);
      expect(fresh.workoutReminderDays, isNull);
      expect(fresh.workoutReminderMinutes, 18 * 60);
      expect(fresh.weighInReminderMinutes, 7 * 60 + 30);
    });

    test('round-trip through toMap/fromMap', () {
      final original = profile().copyWith(
        partialRepsEnabled: true,
        rpeEnabled: true,
        targetWeight: 78.5,
        targetWeightStart: 84,
        workoutReminderDays: '1,3,5',
        workoutReminderMinutes: 17 * 60,
        weighInReminderDays: '1',
        weighInReminderMinutes: 6 * 60,
      );

      final restored = UserProfile.fromMap(original.toMap());

      expect(restored.partialRepsEnabled, isTrue);
      expect(restored.rpeEnabled, isTrue);
      expect(restored.targetWeight, 78.5);
      expect(restored.targetWeightStart, 84);
      expect(restored.workoutReminderDays, '1,3,5');
      expect(restored.workoutReminderMinutes, 17 * 60);
      expect(restored.weighInReminderDays, '1');
      expect(restored.weighInReminderMinutes, 6 * 60);
    });

    test('clearing the target weight clears its starting point too', () {
      final withGoal =
          profile().copyWith(targetWeight: 78.5, targetWeightStart: 84);

      final cleared = withGoal.copyWith(clearTargetWeight: true);

      expect(cleared.targetWeight, isNull);
      expect(cleared.targetWeightStart, isNull);
    });

    test('reminder days need their clear flag to be nulled', () {
      final on = profile().copyWith(workoutReminderDays: '2,4');

      expect(on.copyWith(workoutReminderDays: null).workoutReminderDays, '2,4');
      expect(on.copyWith(clearWorkoutReminder: true).workoutReminderDays,
          isNull);
    });
  });
}
