import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/utils/warmup_generator.dart';

void main() {
  test('a plate-loaded lift opens with the empty bar, then ramps', () {
    final sets = generateWarmups(
        workingWeight: 100, barWeight: 20, unit: 'kg', usesPlates: true);

    expect(sets, [
      (weight: 20.0, reps: 10),
      (weight: 40.0, reps: 5),
      (weight: 60.0, reps: 3),
      (weight: 80.0, reps: 2),
    ]);
  });

  test('plate-loaded steps round down to a loadable weight', () {
    // 40% of 105 is 42 — the plates only make 40 (20 + 2×10) on a 20 kg bar.
    final sets = generateWarmups(
        workingWeight: 105, barWeight: 20, unit: 'kg', usesPlates: true);

    expect(sets[1].weight, 40);
    for (final set in sets) {
      expect(((set.weight - 20) / 2) % 1.25, closeTo(0, 1e-9),
          reason: '${set.weight} must be the bar plus a pair of plates');
    }
  });

  test('without plates, steps round down to the rack increment', () {
    final kg = generateWarmups(
        workingWeight: 33, barWeight: 20, unit: 'kg', usesPlates: false);
    expect(kg.map((s) => s.weight), [12.5, 17.5, 25]);

    final lbs = generateWarmups(
        workingWeight: 70, barWeight: 45, unit: 'lbs', usesPlates: false);
    expect(lbs.map((s) => s.weight), [25, 40, 55]);
  });

  test('a light working weight drops steps instead of repeating them', () {
    // 40/60% of 30 kg round to the bar and are dropped; 80% makes 22.5.
    final sets = generateWarmups(
        workingWeight: 30, barWeight: 20, unit: 'kg', usesPlates: true);

    expect(sets, [(weight: 20.0, reps: 10), (weight: 22.5, reps: 2)]);
  });

  test('nothing to warm up at or under the bar weight', () {
    expect(
        generateWarmups(
            workingWeight: 20, barWeight: 20, unit: 'kg', usesPlates: true),
        isEmpty);
  });
}
