/// Body-measurement lengths: stored in centimetres, always, and shown in cm
/// or inches. The same edges-only rule as utils/weight_format.dart — convert
/// on display and on input, never in storage.
///
/// There is no separate length setting: someone who logs in kg thinks in cm,
/// and someone who logs in lbs thinks in inches.
library;

import 'weight_format.dart';

const double cmPerInch = 2.54;

/// The length unit that goes with a weight unit: "in" for lbs, else "cm".
String lengthUnitFor(String weightUnit) => weightUnit == 'lbs' ? 'in' : 'cm';

double cmToUnit(double cm, String lengthUnit) =>
    lengthUnit == 'in' ? cm / cmPerInch : cm;

double unitToCm(double value, String lengthUnit) =>
    lengthUnit == 'in' ? value * cmPerInch : value;

/// A stored cm value as display text with its unit, e.g. "84.5 cm".
String formatLength(double cm, {required String lengthUnit}) =>
    '${formatDecimal(cmToUnit(cm, lengthUnit))} $lengthUnit';

/// Text typed in [lengthUnit] as cm, or null if it isn't a number. Accepts a
/// comma as the decimal separator, like [parseWeightToKg].
double? parseLengthToCm(String input, {required String lengthUnit}) {
  final normalised = input.trim().replaceAll(',', '.');
  if (normalised.isEmpty) return null;
  final value = double.tryParse(normalised);
  if (value == null) return null;
  return unitToCm(value, lengthUnit);
}
