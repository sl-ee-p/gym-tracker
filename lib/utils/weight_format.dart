/// One place for turning the app's stored weights into display text, and
/// display text back into stored weights.
///
/// Every weight in the database is kilograms, always — `exercise_sets.weight`,
/// `weight_entries.weight` and `user_profiles.currentWeight` alike. The
/// kg/lbs setting is a *display* choice, so conversion belongs at the edges:
/// read a value, convert to the display unit, format; take typed text, parse,
/// convert back to kg, store. Nothing in the storage layer ever sees lbs.
library;

import 'package:flutter/services.dart';

/// Pounds per kilogram. Matches the factor the app has always used, so
/// switching units round-trips to the same stored number.
const double lbsPerKg = 2.20462;

/// Converts a stored kilogram value into [unit] for display.
double kgToUnit(double kg, String unit) => unit == 'lbs' ? kg * lbsPerKg : kg;

/// Converts a value the user typed in [unit] back into kilograms for storage.
double unitToKg(double value, String unit) =>
    unit == 'lbs' ? value / lbsPerKg : value;

/// Formats a number with at most two decimals and no trailing zeros:
/// `92.5 -> "92.5"`, `92.25 -> "92.25"`, `92.0 -> "92"`, `92.256 -> "92.26"`.
///
/// Two decimals because that is what the set-entry field accepts — rounding
/// the display to one decimal (as this app used to) silently hid the
/// difference between a 92.25 kg and a 92.3 kg lift.
String formatDecimal(double value) {
  var text = value.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}

/// A stored kilogram weight as a bare number string in the display unit,
/// with no unit suffix. Use where the unit is already shown elsewhere
/// (a column header, a field's suffix).
String formatWeightValue(double kg, {required String unit}) =>
    formatDecimal(kgToUnit(kg, unit));

/// A stored kilogram weight as display text including the unit, e.g. "92.5 kg".
String formatWeight(double kg, {required String unit}) =>
    '${formatWeightValue(kg, unit: unit)} $unit';

/// Parses text the user typed in [unit] into kilograms, or null if it isn't a
/// number. Accepts both `.` and `,` as the decimal separator — an Italian or
/// French numeric keypad emits a comma, and silently dropping it turned
/// "92,5" into "925".
double? parseWeightToKg(String input, {required String unit}) {
  final normalised = input.trim().replaceAll(',', '.');
  if (normalised.isEmpty) return null;
  final value = double.tryParse(normalised);
  if (value == null) return null;
  return unitToKg(value, unit);
}

/// Accepts a positive decimal with at most two decimal places, normalising a
/// typed comma to a dot as it goes.
///
/// Replaces `FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))`,
/// which quietly deleted anything after the first match — so a comma vanished
/// instead of becoming a decimal point, and a leading "." was impossible,
/// making ".5" untypable.
class DecimalWeightInputFormatter extends TextInputFormatter {
  const DecimalWeightInputFormatter({this.decimalRange = 2});

  final int decimalRange;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(',', '.');
    if (text.isEmpty) return newValue.copyWith(text: text);

    final pattern = RegExp(r'^\d*\.?\d{0,' + decimalRange.toString() + r'}$');
    if (!pattern.hasMatch(text)) return oldValue;

    // Comma->dot is a 1:1 substitution, so the caret stays where it was.
    return TextEditingValue(
      text: text,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}
