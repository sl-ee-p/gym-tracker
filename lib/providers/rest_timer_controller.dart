import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Where a rest timer is in its life.
///
/// [completed] is a real state rather than a return to [idle] because the
/// "Rest done!" signal has to survive until the user acknowledges it — that is
/// the whole point of it: the modal is usually closed when the timer ends.
enum RestTimerPhase { idle, running, paused, completed }

/// The chime and haptic fired on completion.
///
/// Behind an interface so [RestTimerController] is constructible in a plain
/// unit test: an eagerly-built [AudioPlayer] would drag platform-channel mocks
/// into every test of the countdown maths.
abstract class RestTimerAlerts {
  void haptic();
  Future<void> chime();
  void dispose();
}

/// The real one. Owns a single long-lived player rather than one per modal.
class AudioRestTimerAlerts implements RestTimerAlerts {
  final AudioPlayer _player = AudioPlayer();

  @override
  void haptic() => HapticFeedback.mediumImpact();

  @override
  Future<void> chime() => _player.play(AssetSource('sounds/timer_complete.wav'));

  @override
  void dispose() => _player.dispose();
}

/// Read/write access to the persisted last-used duration.
abstract class RestTimerSettings {
  Duration read();
  Future<void> write(Duration duration);
}

/// The controller's two OS-notification outputs.
///
/// [schedule]/[cancel] arm the one-shot alarm that announces the end of a rest
/// while the app is backgrounded. [showOngoing]/[hideOngoing] drive the
/// permanent notification that mirrors a live rest and carries its controls.
/// They are independent: a backgrounded running timer has both.
abstract class RestTimerScheduler {
  Future<void> schedule(DateTime at);
  Future<void> cancel();

  /// Asked for once, when the user starts their first rest — a moment where
  /// the request has obvious context, unlike a prompt at app launch.
  Future<void> ensurePermissions();

  /// Posts or updates the ongoing notification. [endTime] is null while
  /// paused, which is exactly when [remaining] is the only truth about how
  /// much rest is left.
  Future<void> showOngoing({
    required bool running,
    required DateTime? endTime,
    required Duration remaining,
  });

  /// Takes the ongoing notification down.
  Future<void> hideOngoing();
}

class _NoRestTimerSettings implements RestTimerSettings {
  const _NoRestTimerSettings();
  @override
  Duration read() => RestTimerController.defaultDuration;
  @override
  Future<void> write(Duration duration) async {}
}

class _NoRestTimerScheduler implements RestTimerScheduler {
  const _NoRestTimerScheduler();
  @override
  Future<void> schedule(DateTime at) async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<void> ensurePermissions() async {}
  @override
  Future<void> showOngoing({
    required bool running,
    required DateTime? endTime,
    required Duration remaining,
  }) async {}
  @override
  Future<void> hideOngoing() async {}
}

/// The rest timer, hoisted out of the widget that used to own it.
///
/// It lived entirely in `_RestTimerWidgetState`, which is rendered inside the
/// workout screen's body. The nav shell rebuilds tabs through an
/// AnimatedSwitcher, so switching away unmounted the widget and destroyed the
/// countdown — you could not check your progress mid-rest without losing the
/// rest. Registered in the root MultiProvider instead, it now outlives every
/// screen.
///
/// Named `Controller` rather than `Provider` (the convention for the other
/// four files here) because it owns behaviour and a ticker, not loaded data.
///
/// Known limit: the running timer is *not* persisted. It survives navigation
/// and backgrounding, but a cold start finds it idle. The scheduled
/// notification still fires from the OS in that case, so the user is told the
/// rest ended — only the in-app "Rest done!" state is lost. Fixing it properly
/// means writing `_endTime` to the profile row and restoring on launch.
class RestTimerController extends ChangeNotifier with WidgetsBindingObserver {
  static const Duration minDuration = Duration(seconds: 15);
  static const Duration maxDuration = Duration(minutes: 15);
  static const Duration defaultDuration = Duration(seconds: 90);

  /// The shortened rest offered between two exercises in the same
  /// superset/circuit — everywhere but after the group's last exercise,
  /// which still gets [defaultDuration] (or whatever the user last picked).
  /// Just `start(quickRestDuration)`; nothing else about the timer changes.
  static const Duration quickRestDuration = Duration(seconds: 20);

  /// How often the wall clock is checked. Not the rebuild rate — see
  /// [_onTick]. 200 ms rather than a full second so that a timer started
  /// mid-second still completes within 200 ms of its true end; at 1 Hz the
  /// chime could land a beat after the notification that announced it.
  static const Duration _tickInterval = Duration(milliseconds: 200);

  RestTimerController({
    RestTimerAlerts? alerts,
    RestTimerSettings? settings,
    RestTimerScheduler? scheduler,
    DateTime Function()? now,
  })  : _alerts = alerts ?? AudioRestTimerAlerts(),
        _settings = settings ?? const _NoRestTimerSettings(),
        _scheduler = scheduler ?? const _NoRestTimerScheduler(),
        _now = now ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
  }

  final RestTimerAlerts _alerts;
  final RestTimerSettings _settings;
  final RestTimerScheduler _scheduler;
  final DateTime Function() _now;

  RestTimerPhase _phase = RestTimerPhase.idle;
  DateTime? _endTime;
  Duration _totalDuration = Duration.zero;
  Duration _pausedRemaining = Duration.zero;
  Duration? _lastUsed;
  Timer? _ticker;

  /// Gates [notifyListeners] to at most once per displayed second. This is the
  /// "only setState when the second changes" optimisation the widget used to
  /// do locally, moved up a layer — without it every listener would rebuild
  /// five times a second.
  int _lastNotifiedSecond = -1;

  /// So a completion announces exactly once, however it is detected.
  bool _alertsFired = false;

  bool _isForeground = true;

  RestTimerPhase get phase => _phase;
  bool get isRunning => _phase == RestTimerPhase.running;
  bool get isPaused => _phase == RestTimerPhase.paused;
  bool get isCompleted => _phase == RestTimerPhase.completed;

  /// Whether the timer is worth showing anywhere — running, paused, or
  /// finished but not yet acknowledged.
  bool get isActive => _phase != RestTimerPhase.idle;

  Duration get totalDuration => _totalDuration;

  /// The duration the picker should open on. Read lazily so a profile that
  /// loads after this controller is constructed is still honoured.
  Duration get lastUsedDuration => _lastUsed ?? _settings.read();

  /// Always derived from the wall clock, never from a stored countdown. That
  /// is what lets the timer be right after the widget was unmounted for two
  /// minutes, or the app backgrounded and no tick ever fired.
  Duration get remaining {
    switch (_phase) {
      case RestTimerPhase.idle:
      case RestTimerPhase.completed:
        return Duration.zero;
      case RestTimerPhase.paused:
        return _pausedRemaining;
      case RestTimerPhase.running:
        final endTime = _endTime;
        if (endTime == null) return Duration.zero;
        final left = endTime.difference(_now());
        return left.isNegative ? Duration.zero : left;
    }
  }

  /// The ring's 0..1 fill now.
  double get progress => progressAt(_now());

  /// The ring's 0..1 fill at [instant], so the modal can repaint smoothly at
  /// frame rate without this controller notifying at 60 Hz.
  double progressAt(DateTime instant) {
    final total = _totalDuration.inMilliseconds;
    if (total <= 0) return _phase == RestTimerPhase.completed ? 1.0 : 0.0;

    final Duration left;
    if (_phase == RestTimerPhase.running && _endTime != null) {
      final raw = _endTime!.difference(instant);
      left = raw.isNegative ? Duration.zero : raw;
    } else {
      left = remaining;
    }
    return 1.0 - (left.inMilliseconds / total).clamp(0.0, 1.0);
  }

  static Duration clampDuration(Duration duration) {
    if (duration < minDuration) return minDuration;
    if (duration > maxDuration) return maxDuration;
    return duration;
  }

  void start(Duration duration) {
    final clamped = clampDuration(duration);
    _lastUsed = clamped;
    unawaited(_settings.write(clamped));
    // Fire and forget: a permission dialog must never delay the countdown,
    // and denial only costs the backgrounded alert, not the timer.
    unawaited(_scheduler.ensurePermissions());

    _totalDuration = clamped;
    _endTime = _now().add(clamped);
    _phase = RestTimerPhase.running;
    _alertsFired = false;
    _startTicking();
    _afterMutation();
  }

  void pause() {
    if (_phase != RestTimerPhase.running) return;
    _pausedRemaining = remaining;
    _endTime = null;
    _phase = RestTimerPhase.paused;
    _stopTicking();
    _afterMutation();
  }

  void resume() {
    if (_phase != RestTimerPhase.paused) return;
    _endTime = _now().add(_pausedRemaining);
    _phase = RestTimerPhase.running;
    _startTicking();
    _afterMutation();
  }

  /// The ±15/30 s buttons. Growing past the original total stretches the ring
  /// rather than overfilling it, matching what the widget did before.
  void adjust(Duration delta) {
    if (_phase != RestTimerPhase.running && _phase != RestTimerPhase.paused) {
      return;
    }

    final next = remaining + delta;
    if (next <= Duration.zero) {
      if (_phase == RestTimerPhase.running) {
        _complete();
      } else {
        _pausedRemaining = Duration.zero;
        _afterMutation();
      }
      return;
    }

    if (next > _totalDuration) _totalDuration = next;
    if (_phase == RestTimerPhase.running) {
      _endTime = _now().add(next);
    } else {
      _pausedRemaining = next;
    }
    _afterMutation();
  }

  /// Hard cancel from any phase. The only thing that stops a running timer —
  /// closing the modal deliberately does not.
  void stop() {
    if (_phase == RestTimerPhase.idle) return;
    _resetToIdle();
    _afterMutation();
  }

  /// Dismisses the "Rest done!" state. No-op in any other phase, so callers
  /// (the pill's tap, logging the next set) can fire it unconditionally.
  void acknowledgeCompletion() {
    if (_phase != RestTimerPhase.completed) return;
    _resetToIdle();
    _afterMutation();
  }

  void _resetToIdle() {
    _stopTicking();
    _phase = RestTimerPhase.idle;
    _endTime = null;
    _totalDuration = Duration.zero;
    _pausedRemaining = Duration.zero;
    _alertsFired = false;
  }

  void _startTicking() {
    _stopTicking();
    _lastNotifiedSecond = -1;
    _ticker = Timer.periodic(_tickInterval, (_) => _onTick());
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _onTick() {
    if (_phase != RestTimerPhase.running) return;

    final left = remaining;
    if (left <= Duration.zero) {
      _complete();
      return;
    }

    if (left.inSeconds != _lastNotifiedSecond) {
      _lastNotifiedSecond = left.inSeconds;
      notifyListeners();
    }
  }

  /// [silent] suppresses the chime for a completion that happened while the
  /// app was backgrounded — the scheduled notification already announced it,
  /// and chiming again on resume would announce the same rest twice.
  void _complete({bool silent = false}) {
    _stopTicking();
    _phase = RestTimerPhase.completed;
    _endTime = null;

    if (!_alertsFired && !silent) {
      _alertsFired = true;
      _alerts.haptic();
      unawaited(_alerts.chime());
    }
    _afterMutation();
  }

  void _afterMutation() {
    unawaited(_syncNotification());
    notifyListeners();
  }

  /// Every OS-notification decision, in one place. Two independent outputs:
  ///
  /// The **completion alarm** is still the background announcement channel,
  /// paired with the in-app chime as the foreground one, and exactly one of
  /// them is ever armed — which is why there is no "did it already fire"
  /// bookkeeping. Note that ±15 s *does* now need the reschedule below: it
  /// used to be reachable only from the open modal, i.e. foregrounded, i.e.
  /// with no alarm armed, but the notification's buttons reach it while
  /// backgrounded. Re-arming under the same id replaces the pending alarm, so
  /// the new end time simply wins.
  ///
  /// The **ongoing notification** is not a channel in that sense at all. It is
  /// a control surface for a running or paused rest — but only while
  /// backgrounded, since the in-app modal/header pill already covers that role
  /// in the foreground and a duplicate notification there is just noise. Every
  /// phase that isn't a live, backgrounded rest takes it down, "completed" and
  /// "foregrounded" included: from there the alarm and the chime (or the
  /// visible modal) have the announcing to do.
  ///
  /// Both are started before either is awaited. They are independent platform
  /// calls, so serialising them would make the notification the user is
  /// looking at wait on an alarm they cannot see — and would leave the two
  /// briefly disagreeing about the phase.
  Future<void> _syncNotification() async {
    final endTime = _endTime;

    final alarm =
        _phase == RestTimerPhase.running && !_isForeground && endTime != null
            ? _scheduler.schedule(endTime)
            : _scheduler.cancel();

    final ongoing =
        (_phase == RestTimerPhase.running || _phase == RestTimerPhase.paused) &&
                !_isForeground
            ? _scheduler.showOngoing(
                running: _phase == RestTimerPhase.running,
                endTime: endTime,
                remaining: remaining,
              )
            : _scheduler.hideOngoing();

    await Future.wait(<Future<void>>[alarm, ongoing]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` is transient — an iOS control-centre swipe, an Android
    // permission dialog. Treating it as backgrounded would schedule and
    // cancel a notification on every glance.
    if (state == AppLifecycleState.inactive) return;

    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      // No tick fired while we were away, so a rest that ended in the
      // meantime is only noticed here. Silent: the notification announced it.
      if (_phase == RestTimerPhase.running && remaining <= Duration.zero) {
        _complete(silent: true);
        return;
      }
    } else {
      _isForeground = false;
    }

    unawaited(_syncNotification());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTicking();
    _alerts.dispose();
    super.dispose();
  }
}
