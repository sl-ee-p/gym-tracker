import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../providers/rest_timer_controller.dart';
import '../theme/app_theme.dart';
import '../theme/numeric_text_styles.dart';
import '../utils/app_spacing.dart';
import '../utils/rest_duration_format.dart';

/// A rest timer that opens on a duration picker (rather than always
/// launching a fixed countdown), with its own gradient-ring countdown and a
/// chime + burst animation on completion.
///
/// This is a *view* over [RestTimerController]: the countdown itself lives
/// there, so it keeps running when this is dismissed or the whole workout
/// screen is unmounted. Closing this widget no longer stops anything — only
/// the Stop control does.
class RestTimerWidget extends StatefulWidget {
  /// Closes the overlay. The timer is deliberately left running.
  final VoidCallback? onDismiss;

  const RestTimerWidget({super.key, this.onDismiss});

  @override
  State<RestTimerWidget> createState() => _RestTimerWidgetState();
}

class _RestTimerWidgetState extends State<RestTimerWidget>
    with TickerProviderStateMixin {
  static const _presets = [
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(seconds: 90),
    Duration(minutes: 2),
    Duration(minutes: 3),
    Duration(minutes: 5),
  ];

  /// The only countdown-ish state left here, and it is genuinely local: the
  /// picker's value *before* a timer exists.
  Duration _selectedDuration = RestTimerController.defaultDuration;
  bool _seededSelection = false;

  /// Drives the ring. A frame ticker, not a Timer.periodic: the ring used to
  /// be repainted from a 200 ms timer, so it advanced in five visible jumps a
  /// second. It reads the controller's wall clock rather than owning any
  /// countdown, and only runs while this widget is mounted and the timer is
  /// running — exactly when a 60 fps repaint is worth paying for.
  Ticker? _frameTicker;

  /// The ring's 0..1 fill, updated every frame. Kept in a ValueNotifier so
  /// only the CustomPaint listening to it repaints.
  final ValueNotifier<double> _ringProgress = ValueNotifier<double>(0);

  /// The burst plays once per completion. It can no longer be fired by the
  /// completion itself — this widget is usually unmounted when a rest ends —
  /// so it is triggered on *observing* the completed phase, including when
  /// the user reopens the modal afterwards.
  bool _burstPlayed = false;

  late final AnimationController _pulseController;
  late final AnimationController _completeController;

  RestTimerController? _controller;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _completeController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<RestTimerController>();
    if (identical(controller, _controller)) return;

    _controller?.removeListener(_onControllerChanged);
    _controller = controller..addListener(_onControllerChanged);

    if (!_seededSelection) {
      _seededSelection = true;
      _selectedDuration =
          RestTimerController.clampDuration(controller.lastUsedDuration);
    }
    _syncToController();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _stopFrameTicker();
    _ringProgress.dispose();
    _pulseController.dispose();
    _completeController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _syncToController();
    setState(() {});
  }

  /// Brings every local animation into line with the controller's phase.
  void _syncToController() {
    final controller = _controller;
    if (controller == null) return;

    if (controller.isRunning) {
      _startFrameTicker();
    } else {
      _stopFrameTicker();
      _ringProgress.value = controller.progress;
    }

    if (controller.isCompleted) {
      if (!_burstPlayed) {
        _burstPlayed = true;
        _completeController.forward(from: 0);
      }
    } else {
      _burstPlayed = false;
    }

    _updateUrgency();
  }

  void _startFrameTicker() {
    if (_frameTicker != null) return;
    _frameTicker = createTicker(_onFrame)..start();
  }

  void _stopFrameTicker() {
    _frameTicker?.dispose();
    _frameTicker = null;
  }

  void _onFrame(Duration _) {
    final controller = _controller;
    if (controller == null) return;
    _ringProgress.value = controller.progressAt(DateTime.now());
  }

  void _updateUrgency() {
    final controller = _controller;
    final urgent = controller != null &&
        controller.isRunning &&
        controller.remaining <= const Duration(seconds: 3);
    if (urgent && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!urgent && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  void _adjustSetupDuration(int seconds) {
    setState(() {
      _selectedDuration = RestTimerController.clampDuration(
        _selectedDuration + Duration(seconds: seconds),
      );
    });
  }

  /// Closes the overlay without touching the countdown.
  void _dismiss() => widget.onDismiss?.call();

  // --- Build ---------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RestTimerController>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: switch (controller.phase) {
          RestTimerPhase.idle => _buildSetup(context, controller),
          RestTimerPhase.running ||
          RestTimerPhase.paused =>
            _buildRunning(context, controller),
          RestTimerPhase.completed => _buildCompleted(context, controller),
        },
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required String title,
    required IconData icon,
    Color? color,
    String closeTooltip = 'Close',
  }) {
    final onColor = color ?? Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Icon(icon, color: onColor),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
          ),
        ),
        IconButton(
          onPressed: _dismiss,
          icon: const Icon(Icons.close, size: 20),
          tooltip: closeTooltip,
        ),
      ],
    );
  }

  Widget _buildSetup(BuildContext context, RestTimerController controller) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, title: 'Rest Timer', icon: Icons.timer_outlined),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepperButton(
              icon: Icons.remove,
              onTap: () => _adjustSetupDuration(-15),
            ),
            const SizedBox(width: AppSpacing.xl),
            SizedBox(
              width: 140,
              child: Text(
                _formatDuration(_selectedDuration),
                textAlign: TextAlign.center,
                style: NumericTextStyles.display(color: colorScheme.onSurface),
              ),
            ),
            const SizedBox(width: AppSpacing.xl),
            _StepperButton(
              icon: Icons.add,
              onTap: () => _adjustSetupDuration(15),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _presets.map((preset) {
            final selected = preset == _selectedDuration;
            return ChoiceChip(
              label: Text(_formatDuration(preset)),
              selected: selected,
              onSelected: (_) => setState(() => _selectedDuration = preset),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: () => controller.start(_selectedDuration),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Timer'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          ),
        ),
      ],
    );
  }

  Widget _buildRunning(BuildContext context, RestTimerController controller) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRunning = controller.isRunning;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(
          context,
          title: 'Rest Timer',
          icon: Icons.timer,
          closeTooltip: 'Close (timer keeps running)',
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Only this subtree rebuilds per frame, and _TimerRingPainter's
              // shouldRepaint compares progress, so a frame costs one arc
              // repaint rather than a full subtree rebuild.
              ValueListenableBuilder<double>(
                valueListenable: _ringProgress,
                builder: (context, progress, _) => CustomPaint(
                  size: const Size(220, 220),
                  painter: _TimerRingPainter(
                    progress: progress,
                    trackColor: colorScheme.outline.withValues(alpha: 0.15),
                    startColor: colorScheme.primary,
                    endColor: colorScheme.secondary,
                    strokeWidth: 12,
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final scale = 1.0 + 0.06 * _pulseController.value;
                  return Transform.scale(scale: scale, child: child);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatDuration(controller.remaining, roundUp: true),
                      style: NumericTextStyles.display(color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isRunning ? 'remaining' : 'paused',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton.outlined(
              onPressed: controller.stop,
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Change time',
            ),
            IconButton.filled(
              onPressed: isRunning ? controller.pause : controller.resume,
              icon: Icon(isRunning ? Icons.pause : Icons.play_arrow),
              tooltip: isRunning ? 'Pause' : 'Resume',
              style: IconButton.styleFrom(
                minimumSize: const Size(64, 64),
              ),
            ),
            // Was "Skip Rest", which shared the ✕'s meaning. Now the two are
            // distinct: ✕ closes the sheet, this ends the rest.
            IconButton.outlined(
              onPressed: () {
                controller.stop();
                _dismiss();
              },
              icon: const Icon(Icons.stop_rounded),
              tooltip: 'Stop rest',
              style: IconButton.styleFrom(
                foregroundColor: colorScheme.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildTimeAdjustButton(
                '-30s', () => controller.adjust(const Duration(seconds: -30))),
            _buildTimeAdjustButton(
                '-15s', () => controller.adjust(const Duration(seconds: -15))),
            _buildTimeAdjustButton(
                '+15s', () => controller.adjust(const Duration(seconds: 15))),
            _buildTimeAdjustButton(
                '+30s', () => controller.adjust(const Duration(seconds: 30))),
          ],
        ),
      ],
    );
  }

  Widget _buildCompleted(BuildContext context, RestTimerController controller) {
    final success = context.semanticColors;
    // Captured before "Done" resets the controller, so the caption doesn't
    // blank out during the dismissal frame.
    final total = controller.totalDuration;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context,
            title: 'Rest Complete!',
            icon: Icons.check_circle,
            color: success.success),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: 180,
          height: 180,
          child: AnimatedBuilder(
            animation: _completeController,
            builder: (context, child) {
              final t = _completeController.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  _burstRing(t, delay: 0.0, color: success.success),
                  _burstRing(t, delay: 0.2, color: success.success),
                  Transform.scale(
                    scale: Curves.elasticOut.transform(t.clamp(0.0, 1.0)),
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: success.successContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check_rounded,
                          size: 52, color: success.onSuccessContainer),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '${_formatDuration(total)} rest finished',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  controller.acknowledgeCompletion();
                  _dismiss();
                },
                child: const Text('Done'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                // Back to idle, which is the setup view.
                onPressed: controller.stop,
                icon: const Icon(Icons.replay),
                label: const Text('Start New Timer'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _burstRing(double t, {required double delay, required Color color}) {
    final local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
    final scale = 0.4 + local * 1.0;
    final opacity = (1 - local) * 0.5;
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeAdjustButton(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(50, 35),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  String _formatDuration(Duration duration, {bool roundUp = false}) =>
      formatRestDuration(duration, roundUp: roundUp);
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onTap,
      icon: Icon(icon),
      tooltip: icon == Icons.add ? '+15s' : '-15s',
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    );
  }
}

/// Draws the countdown ring: a faint full track plus a gradient progress
/// arc (rounded caps) that sweeps clockwise from the top as time elapses.
class _TimerRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color startColor;
  final Color endColor;
  final double strokeWidth;

  _TimerRingPainter({
    required this.progress,
    required this.trackColor,
    required this.startColor,
    required this.endColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
    if (sweepAngle <= 0) return;

    final progressPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.max(sweepAngle, 0.001),
        colors: [startColor, endColor],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, sweepAngle, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _TimerRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.startColor != startColor ||
      oldDelegate.endColor != endColor ||
      oldDelegate.trackColor != trackColor;
}
