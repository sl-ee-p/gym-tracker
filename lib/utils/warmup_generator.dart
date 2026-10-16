/// Warm-up ramps for a working weight: a few lighter sets with falling reps,
/// each rounded to a weight you can actually load.
library;

import 'plate_calculator.dart';

/// One warm-up set, in the display unit.
typedef WarmupSet = ({double weight, int reps});

/// The ramp, as fractions of the working weight and their reps. Reps fall
/// as the weight climbs, so the warm-up primes the lift without tiring it.
const List<(double, int)> _ramp = [(0.4, 5), (0.6, 3), (0.8, 2)];

/// Warm-ups for [workingWeight], all in [unit] (the display unit).
///
/// With [usesPlates], every step rounds *down* to what the plate calculator
/// can load on [barWeight], and the ramp opens with the empty bar × 10.
/// Without, steps round down to the nearest 2.5 kg / 5 lb — a machine or
/// dumbbell rack's usual increment.
///
/// Steps that round to nothing, to the bar alone (after the bar set), to the
/// same weight as the step before, or to the working weight itself are
/// dropped, so a light working weight gives a short ramp rather than
/// repeats.
List<WarmupSet> generateWarmups({
  required double workingWeight,
  required double barWeight,
  required String unit,
  required bool usesPlates,
}) {
  final sets = <WarmupSet>[];
  if (usesPlates) {
    if (workingWeight <= barWeight) return sets;
    sets.add((weight: barWeight, reps: 10));
  }

  final increment = unit == 'lbs' ? 5.0 : 2.5;
  for (final (fraction, reps) in _ramp) {
    final target = workingWeight * fraction;
    final weight = usesPlates
        ? PlateCalculator.calculate(
            targetWeight: target,
            barWeight: barWeight,
            availablePlates: PlateDefaults.platesFor(unit),
          ).achievedWeight
        : (target / increment).floorToDouble() * increment;

    if (weight <= 0 || weight >= workingWeight) continue;
    if (usesPlates && weight <= barWeight) continue;
    if (sets.isNotEmpty && weight <= sets.last.weight) continue;
    sets.add((weight: weight, reps: reps));
  }
  return sets;
}
