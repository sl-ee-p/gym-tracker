import '../utils/plate_calculator.dart';
import 'coach_models.dart';

/// Turns "add a step" or "take off 10%" into a weight the lifter can load.
///
/// Every weight here is in the display unit. Machines, cables and dumbbells
/// rarely follow one clean grid (a 16/18/20 dumbbell rack, a stack with a
/// 26.5 kg add-on), so stack equipment prefers the weights the lifter has
/// actually used (the *ladder*) and falls back to the learned step. Plate-
/// loaded lifts round down to what the bar and standard plates can make.
class LoadGrid {
  LoadGrid._({
    required this.unit,
    required this.step,
    required this.ladder,
    required this.equipment,
  });

  /// [usedWeights] are the display-unit weights of recent working sets.
  factory LoadGrid.learn({
    required Iterable<double> usedWeights,
    required String unit,
    required CoachEquipment equipment,
  }) {
    final ladder = usedWeights.map(_round2).toSet().toList()..sort();
    final double step;
    if (equipment.plateLoaded) {
      final plates = PlateDefaults.platesFor(unit);
      step = 2 * plates.reduce((a, b) => a < b ? a : b);
    } else {
      step = learnStep(ladder, unit);
    }
    return LoadGrid._(
      unit: unit,
      step: step,
      ladder: ladder,
      equipment: equipment,
    );
  }

  final String unit;
  final double step;
  final List<double> ladder;
  final CoachEquipment equipment;

  static const List<double> _kgSteps = [1, 1.25, 2, 2.5, 5];
  static const List<double> _lbsSteps = [2.5, 5, 10];

  static double defaultStep(String unit) => unit == 'lbs' ? 5 : 2.5;

  /// Most common gap between adjacent distinct weights (ties go to the
  /// smaller gap), snapped to a standard increment. Needs three distinct
  /// weights; otherwise the default step.
  static double learnStep(List<double> sortedLadder, String unit) {
    if (sortedLadder.length < 3) return defaultStep(unit);
    final counts = <double, int>{};
    for (var i = 1; i < sortedLadder.length; i++) {
      final gap = _round2(sortedLadder[i] - sortedLadder[i - 1]);
      if (gap > 0) counts[gap] = (counts[gap] ?? 0) + 1;
    }
    if (counts.isEmpty) return defaultStep(unit);
    final mode = counts.entries.reduce((a, b) {
      if (a.value != b.value) return a.value > b.value ? a : b;
      return a.key < b.key ? a : b;
    }).key;
    final allowed = unit == 'lbs' ? _lbsSteps : _kgSteps;
    return allowed.reduce(
      (a, b) => (a - mode).abs() <= (b - mode).abs() ? a : b,
    );
  }

  /// [steps] increments above [from].
  double up(double from, {int steps = 1}) {
    final target = from + steps * step;
    if (equipment.plateLoaded) return _plateFloor(target + 0.001);
    if (steps == 1) {
      for (final w in ladder) {
        if (w > from + 0.001 && w <= target + 0.001) return w;
      }
    }
    return _round2(target);
  }

  /// The heaviest loadable weight at or below [target], measured from the
  /// working weight [from]. Never returns more than [target].
  double down(double from, double target) {
    if (equipment.plateLoaded) return _plateFloor(target + 0.001);
    double? best;
    for (final w in ladder) {
      if (w <= target + 0.001 && w >= target - step - 0.001) best = w;
    }
    if (best != null) return best;
    final stepsDown = ((from - target) / step - 1e-9).ceil();
    final v = from - stepsDown * step;
    return _round2(v < 0 ? 0 : v);
  }

  double _plateFloor(double target) {
    final bar = unit == 'lbs'
        ? equipment.barWeightKg * coachLbsPerKg
        : equipment.barWeightKg;
    return _round2(
      PlateCalculator.calculate(
        targetWeight: target,
        barWeight: _round2(bar),
        availablePlates: PlateDefaults.platesFor(unit),
      ).achievedWeight,
    );
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;
}
