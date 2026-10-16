class PlateDefaults {
  const PlateDefaults._();
  static const double barWeightKg = 20.0;
  static const List<double> platesKg = [25, 20, 15, 10, 5, 2.5, 1.25];
  static const double barWeightLbs = 45.0;
  static const List<double> platesLbs = [45, 35, 25, 10, 5, 2.5];
  static double barWeightFor(String unit) => unit == 'lbs' ? barWeightLbs : barWeightKg;
  static List<double> platesFor(String unit) => unit == 'lbs' ? platesLbs : platesKg;
}

class PlateBreakdown {
  final double targetWeight, barWeight, achievedWeight, remainder;
  final List<MapEntry<double, int>> platesPerSide; // plate size -> count per side, largest-first
  const PlateBreakdown({required this.targetWeight, required this.barWeight,
      required this.platesPerSide, required this.achievedWeight, required this.remainder});
  bool get isExact => remainder.abs() < 0.001;
}

/// Greedy largest-plate-first breakdown for one side of the bar (loading
/// always assumed symmetric). All arithmetic happens in integer hundredths
/// (weights scaled x100) instead of directly on doubles, specifically to
/// avoid binary floating-point round-off turning an exactly-achievable
/// target into a spurious "unreachable" remainder.
class PlateCalculator {
  const PlateCalculator._();
  static const int _scale = 100;

  static PlateBreakdown calculate({
    required double targetWeight, required double barWeight, required List<double> availablePlates,
  }) {
    final targetScaled = (targetWeight * _scale).round();
    final barScaled = (barWeight * _scale).round();

    if (targetScaled <= barScaled) {
      final achieved = barScaled / _scale;
      return PlateBreakdown(targetWeight: targetWeight, barWeight: barWeight,
          platesPerSide: const [], achievedWeight: achieved, remainder: targetWeight - achieved);
    }

    var perSideRemaining = ((targetScaled - barScaled) / 2).floor();
    final sortedPlates = [...availablePlates]..removeWhere((p) => p <= 0)..sort((a, b) => b.compareTo(a));

    final breakdown = <double, int>{};
    for (final plate in sortedPlates) {
      final plateScaled = (plate * _scale).round();
      if (plateScaled <= 0 || breakdown.containsKey(plate)) continue;
      final count = perSideRemaining ~/ plateScaled;
      if (count > 0) {
        breakdown[plate] = count;
        perSideRemaining -= count * plateScaled;
      }
    }

    final usedScaledPerSide = breakdown.entries.fold<int>(0, (sum, e) => sum + (e.key * _scale).round() * e.value);
    final achieved = (barScaled + usedScaledPerSide * 2) / _scale;
    final orderedEntries = sortedPlates.where((p) => breakdown.containsKey(p)).toSet()
        .map((p) => MapEntry(p, breakdown[p]!)).toList();

    return PlateBreakdown(targetWeight: targetWeight, barWeight: barWeight,
        platesPerSide: orderedEntries, achievedWeight: achieved, remainder: targetWeight - achieved);
  }
}
