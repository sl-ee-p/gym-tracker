import 'dart:math' as math;

/// Vertical-axis maths shared by every chart in the app.
///
/// Lives outside progress_screen.dart because the Analytics tab's charts need
/// exactly the same "give me round numbers and few of them" behaviour — and a
/// second, slightly different copy is how axes drift apart.

/// Resolved vertical-axis bounds for a chart: a padded, "nice"-rounded range
/// with an interval that yields a small number of evenly spaced gridlines.
class ChartAxis {
  final double minY;
  final double maxY;
  final double interval;

  const ChartAxis({
    required this.minY,
    required this.maxY,
    required this.interval,
  });
}

/// Computes clean axis bounds for [values]. When [startAtZero] is false the
/// range hugs the data (so progress is easy to read instead of being squashed
/// against a zero baseline), while still padding the line away from the edges.
ChartAxis computeNiceAxis(List<double> values, {bool startAtZero = false}) {
  if (values.isEmpty) {
    return const ChartAxis(minY: 0, maxY: 10, interval: 2.5);
  }

  var dataMin = values.reduce((a, b) => a < b ? a : b);
  var dataMax = values.reduce((a, b) => a > b ? a : b);
  if (startAtZero) dataMin = 0;

  if (dataMin == dataMax) {
    // Single value (or all equal): build a band around it.
    final v = dataMin;
    final span = v.abs() < 1 ? 1.0 : v.abs() * 0.1;
    dataMin = startAtZero ? 0 : v - span;
    dataMax = v + span;
  }

  var range = dataMax - dataMin;
  if (range <= 0) range = 1;

  final pad = range * 0.15;
  var lo = startAtZero ? 0.0 : dataMin - pad;
  var hi = dataMax + pad;
  // Keep non-negative data on a non-negative axis.
  if (lo < 0 && dataMin >= 0) lo = 0;

  final interval = _niceNumber((hi - lo) / 4, round: true);

  // Snap bounds outward to whole intervals so labels are round numbers.
  lo = (lo / interval).floorToDouble() * interval;
  hi = (hi / interval).ceilToDouble() * interval;
  if (lo < 0 && dataMin >= 0) lo = 0;
  if (hi <= lo) hi = lo + interval;

  return ChartAxis(minY: lo, maxY: hi, interval: interval);
}

/// Rounds [value] to a "nice" number (1, 2, 5 × 10ⁿ) for axis intervals.
double _niceNumber(double value, {required bool round}) {
  if (value <= 0) return 1;
  final exponent = (math.log(value) / math.ln10).floor();
  final fraction = value / math.pow(10, exponent);
  double niceFraction;
  if (round) {
    if (fraction < 1.5) {
      niceFraction = 1;
    } else if (fraction < 3) {
      niceFraction = 2;
    } else if (fraction < 7) {
      niceFraction = 5;
    } else {
      niceFraction = 10;
    }
  } else {
    if (fraction <= 1) {
      niceFraction = 1;
    } else if (fraction <= 2) {
      niceFraction = 2;
    } else if (fraction <= 5) {
      niceFraction = 5;
    } else {
      niceFraction = 10;
    }
  }
  return niceFraction * math.pow(10, exponent).toDouble();
}
