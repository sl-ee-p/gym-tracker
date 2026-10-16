/// Progress towards a body-weight goal, which can point either way: losing
/// down to a target or gaining up to one. Pure maths, so both the Body
/// Weight tab and the Home block show the same numbers.
enum WeightGoalDirection { lose, gain }

class WeightGoalProgress {
  const WeightGoalProgress._({
    required this.targetKg,
    required this.direction,
    required this.fraction,
    required this.remainingKg,
    required this.reached,
  });

  final double targetKg;
  final WeightGoalDirection direction;

  /// 0–1 from the starting weight to the target, or null when there is no
  /// starting or current weight to measure between. Moving away from the
  /// target reads as 0, never negative.
  final double? fraction;

  /// How far the current weight still is from the target, in kg; 0 once
  /// reached. Null without a current weight.
  final double? remainingKg;

  /// True once the current weight is at or past the target, in the goal's
  /// direction.
  final bool reached;

  /// [startKg] is the weight when the goal was set. Without it the direction
  /// is inferred from where [currentKg] sits relative to [targetKg].
  factory WeightGoalProgress.compute({
    required double targetKg,
    double? startKg,
    double? currentKg,
  }) {
    final reference = startKg ?? currentKg;
    final direction = reference != null && reference < targetKg
        ? WeightGoalDirection.gain
        : WeightGoalDirection.lose;

    bool isReached(double current) => direction == WeightGoalDirection.lose
        ? current <= targetKg
        : current >= targetKg;

    final reached = currentKg != null && isReached(currentKg);
    final remaining =
        currentKg == null ? null : (reached ? 0.0 : (currentKg - targetKg).abs());

    double? fraction;
    if (startKg != null && currentKg != null) {
      final total = (startKg - targetKg).abs();
      if (reached) {
        fraction = 1;
      } else if (total == 0) {
        fraction = 0;
      } else {
        final done = direction == WeightGoalDirection.lose
            ? startKg - currentKg
            : currentKg - startKg;
        fraction = (done / total).clamp(0.0, 1.0);
      }
    }

    return WeightGoalProgress._(
      targetKg: targetKg,
      direction: direction,
      fraction: fraction,
      remainingKg: remaining,
      reached: reached,
    );
  }
}
