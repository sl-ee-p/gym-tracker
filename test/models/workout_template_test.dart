// Covers WorkoutTemplate's exerciseGroupIds encoding and the exerciseGroups
// getter derived from it — the metadata that lets a template carry
// supersets/circuits over into a workout started from it.

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/workout_template.dart';

void main() {
  WorkoutTemplate template({
    List<int> exerciseIds = const [],
    List<int?>? exerciseGroupIds,
  }) =>
      WorkoutTemplate(
        name: 'Push Day',
        exerciseIds: exerciseIds,
        exerciseGroupIds: exerciseGroupIds,
        createdDate: DateTime(2026, 1, 1),
      );

  group('exerciseGroupIds default', () {
    test('is an all-null list the same length as exerciseIds when omitted', () {
      final t = template(exerciseIds: [1, 2, 3]);

      expect(t.exerciseGroupIds, [null, null, null]);
    });

    test('is empty when exerciseIds is empty', () {
      final t = template();

      expect(t.exerciseGroupIds, isEmpty);
    });
  });

  group('toMap/fromMap round trip', () {
    test('preserves exerciseGroupIds, including nulls and shared anchors', () {
      final t = template(
        exerciseIds: [1, 2, 3, 4],
        exerciseGroupIds: [1, 1, null, 4],
      );

      final restored = WorkoutTemplate.fromMap(t.toMap());

      expect(restored.exerciseIds, [1, 2, 3, 4]);
      expect(restored.exerciseGroupIds, [1, 1, null, 4]);
    });

    test('round-trips an all-null exerciseGroupIds list', () {
      final t = template(exerciseIds: [5, 6]);

      final restored = WorkoutTemplate.fromMap(t.toMap());

      expect(restored.exerciseGroupIds, [null, null]);
    });

    test(
        'defaults to an all-null list when the column is absent (a pre-v7 row)',
        () {
      final map = template(exerciseIds: [7, 8]).toMap()
        ..remove('exerciseGroupIds');

      final restored = WorkoutTemplate.fromMap(map);

      expect(restored.exerciseGroupIds, [null, null]);
    });

    test('defaults to an all-null list when the column is null', () {
      final map = template(exerciseIds: [7, 8]).toMap();
      map['exerciseGroupIds'] = null;

      final restored = WorkoutTemplate.fromMap(map);

      expect(restored.exerciseGroupIds, [null, null]);
    });
  });

  group('copyWith', () {
    test('updates exerciseGroupIds when passed', () {
      final t = template(exerciseIds: [1, 2]);

      final updated = t.copyWith(exerciseGroupIds: [1, 1]);

      expect(updated.exerciseGroupIds, [1, 1]);
    });

    test('keeps the existing exerciseGroupIds when omitted', () {
      final t = template(exerciseIds: [1, 2], exerciseGroupIds: [1, 1]);

      final updated = t.copyWith(name: 'New name');

      expect(updated.exerciseGroupIds, [1, 1]);
    });
  });

  group('exerciseGroups', () {
    test('is empty for a template with no groups', () {
      final t = template(exerciseIds: [1, 2, 3]);

      expect(t.exerciseGroups, isEmpty);
    });

    test('is empty when the column is null/absent', () {
      final t = template(exerciseIds: [1, 2, 3]);

      expect(t.exerciseGroups, isEmpty);
    });

    test('groups members sharing an anchor, in template order', () {
      final t = template(
        exerciseIds: [1, 2, 3, 4],
        exerciseGroupIds: [1, null, 1, null],
      );

      expect(t.exerciseGroups, [
        [1, 3],
      ]);
    });

    test('supports more than one group, ordered by first appearance', () {
      final t = template(
        exerciseIds: [1, 2, 3, 4, 5],
        exerciseGroupIds: [null, 2, 4, 2, 4],
      );

      expect(t.exerciseGroups, [
        [2, 4],
        [3, 5],
      ]);
    });

    test('omits a would-be group left with fewer than 2 valid members', () {
      // Anchor 1 has only itself — no other exerciseId points at it.
      final t = template(
        exerciseIds: [1, 2, 3],
        exerciseGroupIds: [1, null, null],
      );

      expect(t.exerciseGroups, isEmpty);
    });

    test('a group of 3+ members stays a single row', () {
      final t = template(
        exerciseIds: [1, 2, 3, 4],
        exerciseGroupIds: [1, 1, 1, null],
      );

      expect(t.exerciseGroups, [
        [1, 2, 3],
      ]);
    });
  });
}
