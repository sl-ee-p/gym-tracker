import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/utils/plate_calculator.dart';

// MapEntry has no value equality, so list-equality on List<MapEntry> always
// fails between distinct instances even with identical key/value pairs.
// Compare a stable string projection instead.
List<String> _entries(List<MapEntry<double, int>> list) =>
    list.map((e) => '${e.key}x${e.value}').toList();

void main() {
  group('PlateCalculator.calculate (kg)', () {
    test('exact match: 100kg on a 20kg bar is 25+15 per side', () {
      final breakdown = PlateCalculator.calculate(
        targetWeight: 100,
        barWeight: PlateDefaults.barWeightKg,
        availablePlates: PlateDefaults.platesKg,
      );

      expect(breakdown.isExact, isTrue);
      expect(breakdown.achievedWeight, 100);
      expect(breakdown.remainder, 0);
      expect(_entries(breakdown.platesPerSide), ['25.0x1', '15.0x1']);
    });

    test('unreachable target reports a correct positive remainder, never overshooting', () {
      final breakdown = PlateCalculator.calculate(
        targetWeight: 101,
        barWeight: PlateDefaults.barWeightKg,
        availablePlates: PlateDefaults.platesKg,
      );

      expect(breakdown.isExact, isFalse);
      expect(breakdown.achievedWeight, lessThanOrEqualTo(101));
      expect(breakdown.remainder, closeTo(1.0, 0.001));
      expect(breakdown.remainder, greaterThan(0));
    });

    test('target below bar weight returns an empty breakdown and negative remainder', () {
      final breakdown = PlateCalculator.calculate(
        targetWeight: 15,
        barWeight: PlateDefaults.barWeightKg,
        availablePlates: PlateDefaults.platesKg,
      );

      expect(breakdown.platesPerSide, isEmpty);
      expect(breakdown.achievedWeight, PlateDefaults.barWeightKg);
      expect(breakdown.remainder, closeTo(-5.0, 0.001));
    });

    test('target exactly equal to bar weight is exact with no plates', () {
      final breakdown = PlateCalculator.calculate(
        targetWeight: PlateDefaults.barWeightKg,
        barWeight: PlateDefaults.barWeightKg,
        availablePlates: PlateDefaults.platesKg,
      );

      expect(breakdown.isExact, isTrue);
      expect(breakdown.platesPerSide, isEmpty);
    });

    test('classic float-trap value (42.5kg with 1.25kg plates) resolves exact', () {
      // Naive floating-point subtraction (11.25 - 10 == 1.25) is prone to
      // binary round-off; the integer-hundredths scaling must still resolve
      // this exactly.
      final breakdown = PlateCalculator.calculate(
        targetWeight: 42.5,
        barWeight: PlateDefaults.barWeightKg,
        availablePlates: PlateDefaults.platesKg,
      );

      expect(breakdown.isExact, isTrue);
      expect(_entries(breakdown.platesPerSide), ['10.0x1', '1.25x1']);
    });

    test('empty plate list can only reach the bar weight', () {
      final breakdown = PlateCalculator.calculate(
        targetWeight: 100,
        barWeight: PlateDefaults.barWeightKg,
        availablePlates: const [],
      );

      expect(breakdown.platesPerSide, isEmpty);
      expect(breakdown.achievedWeight, PlateDefaults.barWeightKg);
    });

    test('duplicate plate values are not double-counted', () {
      final breakdown = PlateCalculator.calculate(
        targetWeight: 60,
        barWeight: PlateDefaults.barWeightKg,
        availablePlates: const [20, 20, 10],
      );

      expect(breakdown.isExact, isTrue);
      expect(_entries(breakdown.platesPerSide), ['20.0x1']);
    });
  });

  group('PlateCalculator.calculate (lbs)', () {
    test('a classic one-plate-per-side lbs load is exact', () {
      final breakdown = PlateCalculator.calculate(
        targetWeight: 135,
        barWeight: PlateDefaults.barWeightLbs,
        availablePlates: PlateDefaults.platesLbs,
      );

      expect(breakdown.isExact, isTrue);
      expect(_entries(breakdown.platesPerSide), ['45.0x1']);
    });
  });

  // Bar weight became per-exercise in Part 6e (Exercise.barWeightKg, falling
  // back to the profile default), so it is no longer safe to assume 20 kg.
  group('PlateCalculator.calculate (non-standard bars)', () {
    test('an EZ bar leaves an odd remainder a 20kg bar would not', () {
      final breakdown = PlateCalculator.calculate(
        targetWeight: 32.5,
        barWeight: 7.5,
        availablePlates: PlateDefaults.platesKg,
      );
      // (32.5 - 7.5) / 2 = 12.5 per side.
      expect(breakdown.isExact, isTrue);
      expect(_entries(breakdown.platesPerSide), ['10.0x1', '2.5x1']);
    });

    test('a trap bar shifts the whole breakdown', () {
      final breakdown = PlateCalculator.calculate(
        targetWeight: 105,
        barWeight: 25,
        availablePlates: PlateDefaults.platesKg,
      );
      // (105 - 25) / 2 = 40 per side.
      expect(breakdown.isExact, isTrue);
      expect(_entries(breakdown.platesPerSide), ['25.0x1', '15.0x1']);
    });

    test('a fractional bar weight stays exact (integer-hundredths math)', () {
      final breakdown = PlateCalculator.calculate(
        targetWeight: 20.75,
        barWeight: 8.25,
        availablePlates: PlateDefaults.platesKg,
      );
      // (20.75 - 8.25) / 2 = 6.25 per side = 5 + 1.25.
      expect(breakdown.isExact, isTrue);
      expect(_entries(breakdown.platesPerSide), ['5.0x1', '1.25x1']);
    });

    test('the same target on different bars needs different plates', () {
      List<String> forBar(double barWeight) => _entries(
            PlateCalculator.calculate(
              targetWeight: 60,
              barWeight: barWeight,
              availablePlates: PlateDefaults.platesKg,
            ).platesPerSide,
          );
      expect(forBar(20), ['20.0x1']);
      expect(forBar(10), ['25.0x1']);
      expect(forBar(20), isNot(forBar(10)));
    });

    test('a zero bar weight loads the full target', () {
      final breakdown = PlateCalculator.calculate(
        targetWeight: 50,
        barWeight: 0,
        availablePlates: PlateDefaults.platesKg,
      );
      expect(breakdown.isExact, isTrue);
      expect(_entries(breakdown.platesPerSide), ['25.0x1']);
    });
  });
}
