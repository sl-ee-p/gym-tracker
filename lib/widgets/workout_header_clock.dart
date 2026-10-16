import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/rest_timer_controller.dart';
import '../theme/app_theme.dart';
import '../theme/numeric_text_styles.dart';
import '../utils/app_spacing.dart';
import '../utils/rest_duration_format.dart' show formatRestDuration;
import 'workout_elapsed_clock.dart';

/// The workout screen's headline number.
///
/// One pill, three states: the workout's elapsed time normally, the rest
/// countdown while a timer runs, and a "Rest done!" flag until the user
/// acknowledges it. Replacing the elapsed time is deliberate — mid-rest, the
/// seconds left are the number you actually want, and the workout clock is
/// still there the moment the rest ends.
///
/// **Watch the controller here, not in the workout screen's build.** That
/// screen's body is one large Consumer wrapping a ListView of exercise cards;
/// watching the timer up there would rebuild the whole list once a second for
/// the length of every rest.
class WorkoutHeaderClock extends StatelessWidget {
  const WorkoutHeaderClock({
    super.key,
    required this.workoutStartTime,
    required this.onOpenTimer,
  });

  final DateTime? workoutStartTime;

  /// Reopens the rest timer sheet. Closing it doesn't stop the timer, so
  /// there has to be a way back in.
  final VoidCallback onOpenTimer;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RestTimerController>();

    switch (controller.phase) {
      case RestTimerPhase.idle:
        // Reused verbatim, so the elapsed path keeps its own once-a-minute
        // ticker and stays byte-identical to what it always was.
        return WorkoutElapsedClock(startTime: workoutStartTime);
      case RestTimerPhase.running:
      case RestTimerPhase.paused:
        return _RestCountdownPill(
          controller: controller,
          onOpenTimer: onOpenTimer,
        );
      case RestTimerPhase.completed:
        return _RestDonePill(onAcknowledge: controller.acknowledgeCompletion);
    }
  }
}

/// Shared pill chrome, so all three states are the same shape and only the
/// colour and contents change.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.background,
    required this.child,
    this.onTap,
    this.trailing,
    this.semanticLabel,
  });

  final Color background;
  final Widget child;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Only the label opens the sheet; the trailing control sits outside
        // this InkWell so the two tap targets can't fight.
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: child,
          ),
        ),
        ?trailing,
      ],
    );

    return Semantics(
      liveRegion: semanticLabel != null,
      label: semanticLabel,
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Material(color: Colors.transparent, child: content),
      ),
    );
  }
}

class _RestCountdownPill extends StatelessWidget {
  const _RestCountdownPill({
    required this.controller,
    required this.onOpenTimer,
  });

  final RestTimerController controller;
  final VoidCallback onOpenTimer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final paused = controller.isPaused;

    return _Pill(
      background: colorScheme.secondaryContainer,
      onTap: onOpenTimer,
      trailing: IconButton(
        onPressed: controller.stop,
        icon: const Icon(Icons.stop_rounded, size: 20),
        tooltip: 'Stop rest',
        visualDensity: VisualDensity.compact,
        color: colorScheme.onSecondaryContainer,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            paused ? Icons.pause_circle_outline : Icons.timer,
            size: 20,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            // roundUp so a freshly started 90 s timer reads 01:30, not 01:29.
            formatRestDuration(controller.remaining, roundUp: true),
            style: NumericTextStyles.title(
                color: colorScheme.onSecondaryContainer),
          ),
        ],
      ),
    );
  }
}

/// The "the rest you couldn't see has finished" signal.
///
/// Needed because the timer now outlives the sheet: when it ends with the
/// sheet closed, the chime is the only thing that fires, and a chime is easy
/// to miss in a gym. This holds the state visually until it's acknowledged.
class _RestDonePill extends StatefulWidget {
  const _RestDonePill({required this.onAcknowledge});

  final VoidCallback onAcknowledge;

  @override
  State<_RestDonePill> createState() => _RestDonePillState();
}

class _RestDonePillState extends State<_RestDonePill>
    with SingleTickerProviderStateMixin {
  /// The motion stops after this; the highlighted state does not. "Persists
  /// until acknowledged" is about the state, not the animation — an
  /// indefinite repeat would keep the app requesting frames forever if the
  /// user never taps it.
  static const _pulseWindow = Duration(seconds: 30);

  late final AnimationController _pulse;
  Timer? _pulseTimeout;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);
    _pulseTimeout = Timer(_pulseWindow, () {
      if (!mounted) return;
      _pulse.stop();
      _pulse.value = 0;
    });
  }

  @override
  void dispose() {
    _pulseTimeout?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Transform.scale(
        scale: 1.0 + 0.05 * _pulse.value,
        child: child,
      ),
      child: _Pill(
        background: semantic.successContainer,
        onTap: widget.onAcknowledge,
        semanticLabel: 'Rest finished',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle,
                size: 20, color: semantic.onSuccessContainer),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Rest done!',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: semantic.onSuccessContainer,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
