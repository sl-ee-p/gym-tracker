import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/utils/weight_format.dart';

void main() {
  group('formatDecimal', () {
    test('keeps a single decimal', () {
      expect(formatDecimal(92.5), '92.5');
    });

    test('keeps two decimals', () {
      expect(formatDecimal(92.25), '92.25');
    });

    test('drops a whole number\'s decimal point entirely', () {
      expect(formatDecimal(92.0), '92');
    });

    test('rounds to two decimals rather than truncating', () {
      expect(formatDecimal(92.256), '92.26');
      expect(formatDecimal(92.254), '92.25');
    });

    test('handles values below one', () {
      expect(formatDecimal(0.5), '0.5');
      expect(formatDecimal(0.05), '0.05');
      expect(formatDecimal(0), '0');
    });

    test('does not lose the 0.25 kg increments the old 1-decimal display hid',
        () {
      // The regression this whole utility exists for: toStringAsFixed(1)
      // rendered both of these as "92.3".
      expect(formatDecimal(92.25), isNot(formatDecimal(92.3)));
    });
  });

  group('unit conversion', () {
    test('kg passes through unchanged', () {
      expect(kgToUnit(80, 'kg'), 80);
      expect(unitToKg(80, 'kg'), 80);
    });

    test('kg to lbs uses the factor the app has always used', () {
      expect(kgToUnit(100, 'lbs'), closeTo(220.462, 0.0001));
    });

    test('round-trips through lbs without drifting', () {
      const original = 82.5;
      final roundTripped = unitToKg(kgToUnit(original, 'lbs'), 'lbs');
      expect(roundTripped, closeTo(original, 1e-9));
    });
  });

  group('formatWeight', () {
    test('appends the display unit', () {
      expect(formatWeight(92.5, unit: 'kg'), '92.5 kg');
    });

    test('converts before formatting rather than just relabelling', () {
      expect(formatWeight(100, unit: 'lbs'), '220.46 lbs');
    });

    test('formatWeightValue omits the unit', () {
      expect(formatWeightValue(92.5, unit: 'kg'), '92.5');
    });
  });

  group('parseWeightToKg', () {
    test('parses a plain decimal in kg', () {
      expect(parseWeightToKg('92.5', unit: 'kg'), 92.5);
    });

    test('accepts a comma as the decimal separator', () {
      // An Italian numeric keypad emits ','. The old formatter deleted it,
      // silently turning 92,5 into 925.
      expect(parseWeightToKg('92,5', unit: 'kg'), 92.5);
    });

    test('converts from the display unit back to kg', () {
      expect(parseWeightToKg('220.462', unit: 'lbs'), closeTo(100, 0.0001));
    });

    test('tolerates surrounding whitespace', () {
      expect(parseWeightToKg('  80 ', unit: 'kg'), 80);
    });

    test('returns null for empty or non-numeric input', () {
      expect(parseWeightToKg('', unit: 'kg'), isNull);
      expect(parseWeightToKg('   ', unit: 'kg'), isNull);
      expect(parseWeightToKg('abc', unit: 'kg'), isNull);
    });
  });

  group('DecimalWeightInputFormatter', () {
    const formatter = DecimalWeightInputFormatter();

    TextEditingValue value(String text) => TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );

    String apply(String oldText, String newText) =>
        formatter.formatEditUpdate(value(oldText), value(newText)).text;

    test('allows digits and up to two decimals', () {
      expect(apply('', '9'), '9');
      expect(apply('9', '92'), '92');
      expect(apply('92', '92.'), '92.');
      expect(apply('92.', '92.5'), '92.5');
      expect(apply('92.5', '92.55'), '92.55');
    });

    test('rejects a third decimal, keeping the old value', () {
      expect(apply('92.55', '92.555'), '92.55');
    });

    test('normalises a typed comma to a dot', () {
      expect(apply('92', '92,'), '92.');
      expect(apply('92,', '92,5'), '92.5');
    });

    test('allows a leading decimal point', () {
      // '.5' was untypable before: the old regex required \d+ first.
      expect(apply('', '.'), '.');
      expect(apply('.', '.5'), '.5');
    });

    test('rejects letters and a second decimal point', () {
      expect(apply('92', '92a'), '92');
      expect(apply('92.5', '92.5.'), '92.5');
    });

    test('allows clearing the field', () {
      expect(apply('92.5', ''), '');
    });
  });
}
