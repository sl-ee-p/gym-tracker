import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/numeric_text_styles.dart';
import '../utils/app_spacing.dart';

/// Rebuilds [builder] as the time since [startTime] advances.
///
/// The elapsed time used to be read from `WorkoutProvider.currentWorkoutDuration`
/// inside a Consumer, which only recomputes when the provider notifies — so it
/// moved when you logged a set and sat frozen in between. This owns a timer, so
/// anything showing elapsed time behaves like a clock.
///
/// It polls every second but only rebuilds when the displayed minute rolls
/// over: 1 Hz polling keeps the rollover punctual, while rebuilding at 1 Hz to
/// move a digit that changes once a minute would be waste.
class ElapsedTime extends StatefulWidget {
  const ElapsedTime({
    super.key,
    required this.startTime,
    required this.builder,
  });

  final DateTime? startTime;
  final Widget Function(BuildContext context, Duration elapsed) builder;

  @override
  State<ElapsedTime> createState() => _ElapsedTimeState();
}

class _ElapsedTimeState extends State<ElapsedTime> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _elapsed = _measure();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _sync());
  }

  @override
  void didUpdateWidget(ElapsedTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startTime != widget.startTime) {
      setState(() => _elapsed = _measure());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _measure() {
    final startTime = widget.startTime;
    if (startTime == null) return Duration.zero;
    final elapsed = DateTime.now().difference(startTime);
    // Guard against a negative value if the device clock moves backwards
    // mid-workout.
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  void _sync() {
    if (!mounted) return;
    final elapsed = _measure();
    if (elapsed.inMinutes == _elapsed.inMinutes) return;
    setState(() => _elapsed = elapsed);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _elapsed);
}

/// The workout screen's elapsed-time pill.
class WorkoutElapsedClock extends StatelessWidget {
  const WorkoutElapsedClock({super.key, required this.startTime});

  final DateTime? startTime;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ElapsedTime(
      startTime: startTime,
      builder: (context, elapsed) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Text(
          formatElapsed(elapsed),
          style: NumericTextStyles.title(color: colorScheme.onPrimaryContainer),
        ),
      ),
    );
  }
}

/// `H:MM` — hours and minutes, e.g. `0:07`, `1:23`, `12:05`.
String formatElapsed(Duration elapsed) {
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes % 60;
  return '$hours:${minutes.toString().padLeft(2, '0')}';
}
