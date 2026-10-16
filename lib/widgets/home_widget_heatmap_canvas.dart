import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/app_date.dart';
import 'workout_heatmap.dart';

/// What gets rendered to the PNG behind the home-screen widget: the weekly
/// goal ring the dashboard leads with, beside the 12-week day grid.
///
/// Three constraints make this different from any other widget in the app,
/// and all three are easy to break by accident:
///
/// * It is rendered **outside the widget tree**, so there is no ancestor
///   `Theme` and `context.semanticColors` would throw. The caller supplies a
///   real [ThemeData] built by `AppTheme`, and this wraps it — which is what
///   lets [WorkoutHeatmap] be reused completely unmodified, cells coloured
///   from the same seeded palette the dashboard card uses.
/// * **Never read `theme.textTheme` here.** Every entry in it goes through
///   `GoogleFonts.inter`, which resolves a font over the network. An off-tree
///   render paints once and never repaints, so an uncached font would
///   silently fall back or fail. The styles below are hand-written, and the
///   platform font is the right choice on a home screen anyway.
/// * **Nothing here may need a ticker.** One frame is pumped and captured, so
///   the goal ring is a [CustomPaint] rather than a
///   `CircularProgressIndicator`, which builds an `AnimationController` even
///   in its determinate form.
///
/// The frame around all this — rounded card, background, hairline border — is
/// deliberately *not* painted here. It is drawn natively by
/// `HeatmapWidgetProvider`, tinted with the colours `HomeWidgetService` saves
/// alongside the image, because a bitmap can only ever be letterboxed inside
/// a resizable launcher cell: a card drawn into the PNG would float with
/// wallpaper showing above and below it. This canvas paints on transparency
/// and bakes in its own [_padding], so the native card fills the box exactly
/// and the content sits centred inside it at any widget size.
class HomeWidgetHeatmapCanvas extends StatelessWidget {
  const HomeWidgetHeatmapCanvas({
    super.key,
    required this.theme,
    required this.workoutDays,
    required this.workoutsThisWeek,
    required this.weeklyGoal,
    this.weeksToShow = defaultWeeksToShow,
    this.today,
  });

  /// 12 weeks, matching the dashboard card. Not 52: even at the reduced
  /// [_cellSize] below that is 646 px of grid, unreadable in a 4-cell-wide
  /// widget, and it pushes the bitmap past 2 MB — near the Binder
  /// transaction ceiling.
  static const int defaultWeeksToShow = 12;

  /// The rendered size in logical pixels. Fixed, so the bitmap cost is known:
  /// 340x150 at pixelRatio 3 is ~1.8 MB.
  ///
  /// The 2.27 aspect ratio is chosen to sit close to a 4x2 launcher cell
  /// (~250-330dp x ~110-150dp) so `fitCenter` scales it to very nearly the
  /// full box. Getting this wrong is only cosmetic now that the card behind
  /// it is native, but the closer the match, the less dead space.
  static const Size logicalSize = Size(340, 150);

  /// Matches the dashboard card's `AppSpacing.lg` inset, and is what keeps
  /// the content clear of the native card's rounded corners.
  static const double _padding = 16;

  /// Width reserved for the goal block; the grid takes what is left. This and
  /// [_cellSize] are the two numbers that decide whether the layout fits, so
  /// [debugMetrics] exposes them for a test to assert against.
  static const double _goalWidth = 128;
  static const double _dividerGap = 14;

  /// 10.5/2 rather than the dashboard's 12/3: 12 weeks at the larger metrics
  /// is 177 px wide and 102 px tall, which cannot sit beside the goal block
  /// in a 4x2 cell. The single-column layout this replaced kept the larger
  /// cell and overflowed its own bitmap by roughly 30 px because of it — a
  /// permanent clip on the home screen, not a debug stripe. This is the
  /// largest cell that fits.
  static const double _cellSize = 10.5, _cellGap = 2;

  static const double _ringSize = 54, _ringStroke = 5;

  final ThemeData theme;
  final Set<DateTime> workoutDays;
  final int workoutsThisWeek;
  final int weeklyGoal;
  final int weeksToShow;

  /// Injectable only so tests get a stable grid and "days left" line; null
  /// means now, which is what production always passes.
  final DateTime? today;

  /// The width the grid column gets and the size the grid actually paints at.
  /// The layout is a fixed-size bitmap with no room to reflow, so a test
  /// asserts the grid still fits rather than waiting for a silent clip on
  /// someone's home screen.
  static ({double gridColumn, Size heatmap}) get debugMetrics => (
        gridColumn:
            logicalSize.width - _padding * 2 - _goalWidth - 1 - _dividerGap * 2,
        heatmap: WorkoutHeatmap.sizeFor(
          weeksToShow: defaultWeeksToShow,
          cellSize: _cellSize,
          cellGap: _cellGap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = theme.colorScheme;
    final now = today ?? DateTime.now();

    return Theme(
      data: theme,
      // Pins the text scale: the widget's layout is a fixed-size bitmap, so a
      // large system font setting would overflow it rather than reflow.
      child: MediaQuery(
        data: const MediaQueryData(),
        child: SizedBox(
          width: logicalSize.width,
          height: logicalSize.height,
          child: Padding(
            padding: const EdgeInsets.all(_padding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _goalWidth,
                  child: _WeeklyGoal(
                    completed: workoutsThisWeek,
                    goal: weeklyGoal,
                    now: now,
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(
                    horizontal: _dividerGap,
                    vertical: 2,
                  ),
                  color: colors.outlineVariant,
                ),
                Expanded(
                  child: _GridBlock(
                    workoutDays: workoutDays,
                    weeksToShow: weeksToShow,
                    now: now,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The same three things the dashboard's `WeeklyGoalSummary` leads with —
/// the ring, "N of M workouts", and how long is left — recomposed for a block
/// a quarter the width. Reads as one phrase across the ring: "3 | of 4
/// workouts".
class _WeeklyGoal extends StatelessWidget {
  const _WeeklyGoal({
    required this.completed,
    required this.goal,
    required this.now,
  });

  final int completed;
  final int goal;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final success = context.semanticColors.success;
    // Mirrors WeeklyGoalSummary: a zero or negative stored goal must not
    // divide by zero or read as "3 of 0".
    final safeGoal = goal <= 0 ? 1 : goal;
    final metGoal = completed >= safeGoal;

    // spaceBetween, not centre: it puts the section label on the same line as
    // the grid's and the footer level with the grid's bottom row, so the two
    // halves of the card read as one composition rather than two blocks
    // floating at different heights. [_GridBlock] holds up the other end.
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('THIS WEEK'),
        Row(
          children: [
            _GoalRing(
              progress: (completed / safeGoal).clamp(0.0, 1.0),
              completed: completed,
              metGoal: metGoal,
              trackColor: colors.surfaceContainerHighest,
              progressColor: metGoal ? success : colors.primary,
              labelColor: colors.onSurface,
              checkColor: success,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'of $safeGoal',
                    // Every label in this file is capped at one line and fades
                    // rather than wrapping. The bitmap cannot reflow, so a
                    // font with wider metrics than the one this was measured
                    // against must lose a character, not push the grid out of
                    // the frame.
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    safeGoal == 1 ? 'workout' : 'workouts',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      height: 1.0,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Text(
          metGoal ? 'Goal reached' : _daysLeftLabel(),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            height: 1.1,
            color: metGoal ? success : colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _daysLeftLabel() {
    // Including today: on a Sunday there is still one day left, not zero.
    // Same arithmetic as WeeklyGoalSummary._daysLeftLabel.
    final daysLeft = 7 - daysBetween(startOfWeek(now), now);
    return '$daysLeft day${daysLeft == 1 ? '' : 's'} left';
  }
}

/// The small-caps heading over each half of the card. Shared, because the two
/// are laid out on the same line: a difference of even a pixel in size or
/// weight shows up as a misalignment across the divider.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        height: 1.1,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The progress ring, with the count — or a tick once the goal is met —
/// inside it.
///
/// A [CustomPaint] rather than the dashboard's `CircularProgressIndicator`:
/// that builds an `AnimationController` even when determinate, and this tree
/// is rendered off-tree from a single pumped frame with no ticker provider.
/// Painting it directly also gets round stroke caps, which the Material
/// indicator does not offer.
class _GoalRing extends StatelessWidget {
  const _GoalRing({
    required this.progress,
    required this.completed,
    required this.metGoal,
    required this.trackColor,
    required this.progressColor,
    required this.labelColor,
    required this.checkColor,
  });

  final double progress;
  final int completed;
  final bool metGoal;
  final Color trackColor;
  final Color progressColor;
  final Color labelColor;
  final Color checkColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: HomeWidgetHeatmapCanvas._ringSize,
      height: HomeWidgetHeatmapCanvas._ringSize,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress,
          strokeWidth: HomeWidgetHeatmapCanvas._ringStroke,
          trackColor: trackColor,
          progressColor: progressColor,
        ),
        child: Center(
          child: metGoal
              // MaterialIcons ships as a bundled font asset, unlike the
              // GoogleFonts text styles this file avoids, so an icon is safe
              // in a one-shot render.
              ? Icon(Icons.check_rounded, size: 26, color: checkColor)
              : Text(
                  '$completed',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    color: labelColor,
                  ),
                ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final double strokeWidth;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect =
        Rect.fromLTWH(0, 0, size.width, size.height).deflate(strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;

    canvas.drawArc(rect, 0, math.pi * 2, false, paint);
    if (progress <= 0) return;

    // From 12 o'clock, clockwise, like the Material indicator.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      paint..color = progressColor,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}

/// The day grid, captioned, with how many of the days it shows were sessions.
class _GridBlock extends StatelessWidget {
  const _GridBlock({
    required this.workoutDays,
    required this.weeksToShow,
    required this.now,
  });

  final Set<DateTime> workoutDays;
  final int weeksToShow;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sessions = _sessionsInGrid();

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Only the label flexes, and nothing separates the two: a second
        // Flexible would cap *each* side at half the row and fade a label
        // that actually fits, whereas a fixed-width count leaves the label
        // all the room the count does not need. spaceBetween then pushes the
        // count out to the right edge.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: _SectionLabel('LAST $weeksToShow WEEKS')),
            Text(
              '$sessions session${sessions == 1 ? '' : 's'}',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                height: 1.1,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        WorkoutHeatmap(
          workoutDays: workoutDays,
          weeksToShow: weeksToShow,
          endDate: now,
          cellSize: HomeWidgetHeatmapCanvas._cellSize,
          cellGap: HomeWidgetHeatmapCanvas._cellGap,
        ),
      ],
    );
  }

  /// Only the days the grid actually shows. [workoutDays] carries a full
  /// year, so counting it whole would caption the 12-week grid with a number
  /// that does not match the cells above it.
  int _sessionsInGrid() {
    // Same window arithmetic as WorkoutHeatmap, in epoch-day integers — see
    // [epochDay] for why not DateTime.add.
    final endNumber = epochDay(addDays(now, 7 - now.weekday));
    final startNumber = endNumber - (weeksToShow * 7 - 1);
    return workoutDays
        .map(epochDay)
        .where((day) => day >= startNumber && day <= endNumber)
        .length;
  }
}
