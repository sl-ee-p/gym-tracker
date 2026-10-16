import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/weight_goal.dart';

void main() {
  group('losing weight', () {
    test('measures progress from the starting weight', () {
      final progress = WeightGoalProgress.compute(
          targetKg: 80, startKg: 90, currentKg: 85);

      expect(progress.direction, WeightGoalDirection.lose);
      expect(progress.fraction, 0.5);
      expect(progress.remainingKg, 5);
      expect(progress.reached, isFalse);
    });

    test('reads 0, not negative, when moving away from the target', () {
      final progress = WeightGoalProgress.compute(
          targetKg: 80, startKg: 90, currentKg: 92);

      expect(progress.fraction, 0);
      expect(progress.remainingKg, 12);
    });

    test('is reached at or below the target', () {
      final progress = WeightGoalProgress.compute(
          targetKg: 80, startKg: 90, currentKg: 79.5);

      expect(progress.reached, isTrue);
      expect(progress.fraction, 1);
      expect(progress.remainingKg, 0);
    });
  });

  group('gaining weight', () {
    test('measures progress upward', () {
      final progress = WeightGoalProgress.compute(
          targetKg: 75, startKg: 70, currentKg: 72);

      expect(progress.direction, WeightGoalDirection.gain);
      expect(progress.fraction, closeTo(0.4, 1e-9));
      expect(progress.remainingKg, 3);
    });

    test('is reached at or above the target', () {
      final progress = WeightGoalProgress.compute(
          targetKg: 75, startKg: 70, currentKg: 75);

      expect(progress.reached, isTrue);
    });
  });

  test('has no fraction without a starting weight', () {
    final progress = WeightGoalProgress.compute(targetKg: 80, currentKg: 85);

    expect(progress.fraction, isNull);
    expect(progress.remainingKg, 5);
    expect(progress.direction, WeightGoalDirection.lose,
        reason: 'inferred from the current weight');
  });

  test('has no fraction or remainder without a current weight', () {
    final progress = WeightGoalProgress.compute(targetKg: 80, startKg: 90);

    expect(progress.fraction, isNull);
    expect(progress.remainingKg, isNull);
    expect(progress.reached, isFalse);
  });
}
