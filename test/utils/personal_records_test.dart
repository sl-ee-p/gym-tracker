import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/utils/personal_records.dart';

void main() {
  group('findRepRecords', () {
    Set<int> records(List<(double, int)> sets) => findRepRecords([
          for (var i = 0; i < sets.length; i++)
            (id: i, weight: sets[i].$1, reps: sets[i].$2),
        ]);

    test('the first set is never a record', () {
      expect(records([(100, 5)]), isEmpty);
    });

    test('a heavier set is a record', () {
      expect(records([(100, 5), (105, 5)]), {1});
    });

    test('more reps at the same weight is a record', () {
      expect(records([(100, 5), (100, 10)]), {1});
    });

    test('an exact repeat is not a record', () {
      expect(records([(100, 5), (100, 5)]), isEmpty);
    });

    test('a set matched on both counts by any earlier set is not a record', () {
      // 90×8 is matched by the 100×10 two sets earlier, even though it beats
      // the set right before it.
      expect(records([(100, 10), (80, 5), (90, 8)]), isEmpty);
    });

    test('lighter but longer counts when nothing reached those reps', () {
      expect(records([(100, 5), (60, 15)]), {1});
    });

    test('remembers bests that were later superseded on one axis', () {
      // 120×1 then 100×10: neither matches the other. 110×2 is matched by
      // neither (120×1 has too few reps, 100×10 too little weight).
      expect(records([(120, 1), (100, 10), (110, 2)]), {1, 2});
    });
  });

  group('computeRepMaxes', () {
    final day1 = DateTime(2026, 1, 1);
    final day2 = DateTime(2026, 1, 8);

    test('uses "at least N reps", so a longer set fills shorter targets', () {
      final maxes = computeRepMaxes([
        (weight: 100, reps: 6, date: day1),
      ], targets: [1, 5, 8]);

      expect(maxes.map((m) => m.reps), [1, 5]);
      expect(maxes.every((m) => m.weightKg == 100), isTrue);
    });

    test('takes the heaviest qualifying set for each target', () {
      final maxes = computeRepMaxes([
        (weight: 140, reps: 1, date: day1),
        (weight: 100, reps: 5, date: day1),
        (weight: 80, reps: 10, date: day2),
      ], targets: [1, 5, 10]);

      expect([for (final m in maxes) (m.reps, m.weightKg)],
          [(1, 140.0), (5, 100.0), (10, 80.0)]);
    });

    test('keeps the date the max was first reached', () {
      final maxes = computeRepMaxes([
        (weight: 100, reps: 5, date: day2),
        (weight: 100, reps: 5, date: day1),
      ], targets: [5]);

      expect(maxes.single.date, day1);
    });

    test('is empty with no sets', () {
      expect(computeRepMaxes(const []), isEmpty);
    });
  });
}
