import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/coach/coach_models.dart';
import 'package:gym_app/coach/load_grid.dart';

void main() {
  group('LoadGrid.learnStep', () {
    final cases = <(String, List<double>, String, double)>[
      ('too few weights: kg default', [20, 22.5], 'kg', 2.5),
      ('too few weights: lb default', [50], 'lbs', 5),
      ('cable stack in 2.5 kg', [22.5, 25, 27.5, 30, 32.5], 'kg', 2.5),
      ('dumbbells in 2 kg', [16, 18, 20], 'kg', 2),
      ('odd add-on weight does not win', [25, 26.5, 27.5, 30, 32.5], 'kg', 2.5),
      ('tie goes to the smaller gap', [15, 16, 17.5], 'kg', 1),
      ('5 kg machine', [40, 45, 50, 55], 'kg', 5),
      ('lb stack in 10s', [70, 80, 90, 100], 'lbs', 10),
      ('kg history seen in lb snaps to 5 lb', [66.14, 71.65, 77.16], 'lbs', 5),
    ];
    for (final (name, ladder, unit, step) in cases) {
      test(name, () => expect(LoadGrid.learnStep(ladder, unit), step));
    }
  });

  group('LoadGrid stack rounding', () {
    LoadGrid grid(List<double> used) => LoadGrid.learn(
      usedWeights: used,
      unit: 'kg',
      equipment: const CoachEquipment.stack(),
    );

    final cases =
        <(String, LoadGrid Function(), double Function(LoadGrid), double)>[
          (
            'up goes to the next used weight',
            () => grid([25, 26.5, 27.5, 30, 32.5]),
            (g) => g.up(25),
            26.5,
          ),
          (
            'up past the ladder adds a step',
            () => grid([25, 27.5, 30]),
            (g) => g.up(30),
            32.5,
          ),
          (
            'two steps ignore the ladder',
            () => grid([25, 27.5, 30]),
            (g) => g.up(25, steps: 2),
            30,
          ),
          (
            'down picks a used weight under the target',
            () => grid([16, 18, 20]),
            (g) => g.down(20, 18.5),
            18,
          ),
          (
            'down without a used weight counts whole steps',
            () => grid([90]),
            (g) => g.down(90, 81),
            80,
          ),
          (
            'down never goes below zero',
            () => grid([2.5]),
            (g) => g.down(2.5, -1),
            0,
          ),
        ];
    for (final (name, make, op, expected) in cases) {
      test(name, () => expect(op(make()), closeTo(expected, 0.001)));
    }
  });

  group('LoadGrid plates', () {
    test('kg: step is two of the smallest plate, rounding down', () {
      final g = LoadGrid.learn(
        usedWeights: const [100],
        unit: 'kg',
        equipment: const CoachEquipment.plates(barWeightKg: 20),
      );
      expect(g.step, 2.5);
      expect(g.up(100), 102.5);
      expect(g.down(100, 91), 90); // 91 isn't loadable; 90 is.
    });

    test('lb: 5 lb step, 20 kg bar converted to lb', () {
      final g = LoadGrid.learn(
        usedWeights: const [],
        unit: 'lbs',
        equipment: const CoachEquipment.plates(barWeightKg: 20),
      );
      expect(g.step, 5);
      // Bar 44.09 lb + pairs of 45s: 224.09 is the loadable weight at 225.
      expect(g.down(230, 225), closeTo(224.09, 0.001));
    });
  });
}
