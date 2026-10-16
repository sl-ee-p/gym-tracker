import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/models/body_measurement.dart';
import 'package:gym_app/utils/length_format.dart';

void main() {
  test('the length unit follows the weight unit', () {
    expect(lengthUnitFor('kg'), 'cm');
    expect(lengthUnitFor('lbs'), 'in');
  });

  test('formats stored cm in the display unit', () {
    expect(formatLength(84.5, lengthUnit: 'cm'), '84.5 cm');
    expect(formatLength(25.4, lengthUnit: 'in'), '10 in');
  });

  test('parses typed text back to cm, accepting a comma', () {
    expect(parseLengthToCm('84,5', lengthUnit: 'cm'), 84.5);
    expect(parseLengthToCm('10', lengthUnit: 'in'), closeTo(25.4, 1e-9));
    expect(parseLengthToCm('', lengthUnit: 'cm'), isNull);
    expect(parseLengthToCm('abc', lengthUnit: 'cm'), isNull);
  });

  test('inches round-trip to the same stored value', () {
    final cm = parseLengthToCm('33.25', lengthUnit: 'in')!;
    expect(cmToUnit(cm, 'in'), closeTo(33.25, 1e-9));
  });

  group('BodyMeasurement', () {
    test('round-trips through its map by stable key', () {
      final entry = BodyMeasurement(
        id: 3,
        type: MeasurementType.leftArm,
        value: 38.5,
        date: DateTime(2026, 2, 1),
        notes: 'flexed',
      );

      final map = entry.toMap();
      expect(map['type'], 'leftArm');

      final restored = BodyMeasurement.fromMap(map)!;
      expect(restored.type, MeasurementType.leftArm);
      expect(restored.value, 38.5);
      expect(restored.notes, 'flexed');
    });

    test('skips a row with an unknown type instead of throwing', () {
      expect(
        BodyMeasurement.fromMap({
          'id': 1,
          'type': 'forearm',
          'value': 30.0,
          'date': DateTime(2026, 2, 1).toIso8601String(),
        }),
        isNull,
      );
    });

    test('only body fat is not a length', () {
      expect(
        MeasurementType.values.where((t) => !t.isLength),
        [MeasurementType.bodyFat],
      );
    });
  });
}
