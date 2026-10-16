import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_date.dart';

/// The dashboard's grid metrics. The home-screen widget renders the same
/// painter at a smaller [WorkoutHeatmap.cellSize] to fit a 4x2 launcher cell.
const double _defaultCellSize = 12, _defaultCellGap = 3;

/// A GitHub-style contribution heatmap: [weeksToShow] columns (Monday→Sunday
/// weeks) x 7 weekday rows, drawn in one [CustomPaint] pass rather than as
/// individual widgets — this is a purely informational surface with no
/// per-cell interaction (the only requested tap target is the card that
/// hosts this, not individual cells).
///
/// Deliberately binary (worked out / didn't) rather than intensity-shaded:
/// the data only reports which days had a workout, and for realistic
/// single-person cadence (usually 0 or 1 session/day) a multi-level
/// gradient would be visual complexity with no added signal.
class WorkoutHeatmap extends StatelessWidget {
  final Set<DateTime> workoutDays; // each: DateTime(y, m, d), local
  final int weeksToShow;
  final DateTime? endDate;

  /// Cell edge and the gap between cells, in logical pixels. Overridden only
  /// by the home-screen widget, whose bitmap is a fixed size — see
  /// [HomeWidgetHeatmapCanvas].
  final double cellSize;
  final double cellGap;

  const WorkoutHeatmap({
    super.key,
    required this.workoutDays,
    this.weeksToShow = 12,
    this.endDate,
    this.cellSize = _defaultCellSize,
    this.cellGap = _defaultCellGap,
  });

  /// The exact painted size for [weeksToShow] columns at these metrics.
  /// Callers laying this out inside a fixed-size bitmap need it up front,
  /// rather than discovering an overflow at paint time.
  static Size sizeFor({
    required int weeksToShow,
    double cellSize = _defaultCellSize,
    double cellGap = _defaultCellGap,
  }) =>
      Size(
        weeksToShow * (cellSize + cellGap) - cellGap,
        7 * (cellSize + cellGap) - cellGap,
      );

  @override
  Widget build(BuildContext context) {
    // The whole grid is addressed by integer day numbers rather than
    // DateTimes. `gridStart.add(Duration(days: n))` adds 24 real hours, which
    // across a DST boundary lands at 23:00 or 01:00 instead of midnight — and
    // those never compared equal to the exact-midnight keys in [workoutDays],
    // so cells silently stopped colouring in for part of the year.
    final today = endDate ?? DateTime.now();
    final todayNumber = epochDay(today);
    final endOfCurrentWeek = addDays(today, 7 - today.weekday);
    final gridStartNumber = epochDay(endOfCurrentWeek) - (weeksToShow * 7 - 1);

    return CustomPaint(
      size: sizeFor(
        weeksToShow: weeksToShow,
        cellSize: cellSize,
        cellGap: cellGap,
      ),
      painter: _HeatmapPainter(
        gridStartNumber: gridStartNumber,
        weeksToShow: weeksToShow,
        todayNumber: todayNumber,
        workoutDayNumbers: workoutDays.map(epochDay).toSet(),
        workoutColor: context.semanticColors.success,
        emptyColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        cellSize: cellSize,
        cellGap: cellGap,
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  /// All three are epoch day numbers — see [epochDay]. Integers, so stepping
  /// through the grid is plain addition with no calendar arithmetic to get
  /// wrong.
  final int gridStartNumber;
  final int weeksToShow;
  final int todayNumber;
  final Set<int> workoutDayNumbers;
  final Color workoutColor;
  final Color emptyColor;
  final double cellSize;
  final double cellGap;

  _HeatmapPainter({
    required this.gridStartNumber,
    required this.weeksToShow,
    required this.todayNumber,
    required this.workoutDayNumbers,
    required this.workoutColor,
    required this.emptyColor,
    required this.cellSize,
    required this.cellGap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    // Scaled with the cell so the widget's smaller grid keeps the same
    // corner-to-edge proportion as the dashboard's.
    final radius = Radius.circular(cellSize / 4);
    for (var week = 0; week < weeksToShow; week++) {
      for (var weekday = 0; weekday < 7; weekday++) {
        final dayNumber = gridStartNumber + week * 7 + weekday;
        if (dayNumber > todayNumber) continue; // future days stay blank

        paint.color =
            workoutDayNumbers.contains(dayNumber) ? workoutColor : emptyColor;
        final rect = Rect.fromLTWH(
          week * (cellSize + cellGap),
          weekday * (cellSize + cellGap),
          cellSize,
          cellSize,
        );
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) {
    return oldDelegate.gridStartNumber != gridStartNumber ||
        oldDelegate.weeksToShow != weeksToShow ||
        oldDelegate.todayNumber != todayNumber ||
        oldDelegate.workoutColor != workoutColor ||
        oldDelegate.emptyColor != emptyColor ||
        oldDelegate.cellSize != cellSize ||
        oldDelegate.cellGap != cellGap ||
        !setEquals(oldDelegate.workoutDayNumbers, workoutDayNumbers);
  }
}
