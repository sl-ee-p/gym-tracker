// The countdown maths, phase transitions and notification-scheduling
// invariant of RestTimerController.
//
// The whole reason the controller exists is that it must be correct without
// anything having ticked — the widget that used to own the timer is unmounted
// whenever you leave the Workout tab, and Dart timers are suspended while the
// app is backgrounded. So most of these tests advance a fake clock and assert
// the state read back, deliberately never letting the real ticker run.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/providers/rest_timer_controller.dart';

class _FakeAlerts implements RestTimerAlerts {
  int chimes = 0;
  int haptics = 0;
  bool disposed = false;

  @override
  Future<void> chime() async => chimes++;

  @override
  void haptic() => haptics++;

  @override
  void dispose() => disposed = true;
}

class _FakeSettings implements RestTimerSettings {
  Duration stored = const Duration(seconds: 90);

  int writes = 0;

  @override
  Duration read() => stored;

  @override
  Future<void> write(Duration duration) async {
    stored = duration;
    writes++;
  }
}

class _FakeScheduler implements RestTimerScheduler {
  int permissionRequests = 0;

  @override
  Future<void> ensurePermissions() async => permissionRequests++;

  DateTime? scheduledFor;
  int schedules = 0;
  int cancels = 0;

  @override
  Future<void> schedule(DateTime at) async {
    scheduledFor = at;
    schedules++;
  }

  @override
  Future<void> cancel() async {
    scheduledFor = null;
    cancels++;
  }

  bool? ongoingRunning;
  Duration? ongoingRemaining;
  int ongoingShows = 0;
  int ongoingHides = 0;

  @override
  Future<void> showOngoing({
    required bool running,
    required DateTime? endTime,
    required Duration remaining,
  }) async {
    ongoingRunning = running;
    ongoingRemaining = remaining;
    ongoingShows++;
  }

  @override
  Future<void> hideOngoing() async {
    ongoingRunning = null;
    ongoingRemaining = null;
    ongoingHides++;
  }
}

void main() {
  // The controller registers itself as a WidgetsBindingObserver.
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime clock;
  late _FakeAlerts alerts;
  late _FakeSettings settings;
  late _FakeScheduler scheduler;
  late RestTimerController controller;

  setUp(() {
    clock = DateTime(2026, 9, 4, 10, 0, 0);
    alerts = _FakeAlerts();
    settings = _FakeSettings();
    scheduler = _FakeScheduler();
    controller = RestTimerController(
      alerts: alerts,
      settings: settings,
      scheduler: scheduler,
      now: () => clock,
    );
  });

  tearDown(() => controller.dispose());

  void advance(Duration by) => clock = clock.add(by);

  group('countdown', () {
    test('starts running with the full duration remaining', () {
      controller.start(const Duration(seconds: 90));

      expect(controller.phase, RestTimerPhase.running);
      expect(controller.remaining, const Duration(seconds: 90));
      expect(controller.totalDuration, const Duration(seconds: 90));
      expect(controller.progress, 0);
    });

    test('remaining is correct after time passes with no tick at all', () {
      // The property the whole design hangs on: no ticker has run here, which
      // is exactly the situation after a tab switch or a spell backgrounded.
      controller.start(const Duration(seconds: 90));
      advance(const Duration(seconds: 40));

      expect(controller.remaining, const Duration(seconds: 50));
      expect(controller.progress, closeTo(40 / 90, 0.0001));
    });

    test('remaining never goes negative once the end time has passed', () {
      controller.start(const Duration(seconds: 30));
      advance(const Duration(minutes: 5));

      expect(controller.remaining, Duration.zero);
      expect(controller.progress, 1.0);
    });

    test('clamps the requested duration to the allowed range', () {
      controller.start(const Duration(seconds: 1));
      expect(controller.totalDuration, RestTimerController.minDuration);

      controller.stop();
      controller.start(const Duration(hours: 1));
      expect(controller.totalDuration, RestTimerController.maxDuration);
    });
  });

  group('pause and resume', () {
    test('pause freezes remaining while the clock keeps moving', () {
      controller.start(const Duration(seconds: 90));
      advance(const Duration(seconds: 30));
      controller.pause();

      advance(const Duration(seconds: 45));

      expect(controller.phase, RestTimerPhase.paused);
      expect(controller.remaining, const Duration(seconds: 60));
    });

    test('resume continues from where it was paused, not from wall time', () {
      controller.start(const Duration(seconds: 90));
      advance(const Duration(seconds: 30));
      controller.pause();
      advance(const Duration(seconds: 45));
      controller.resume();

      expect(controller.phase, RestTimerPhase.running);
      expect(controller.remaining, const Duration(seconds: 60));

      advance(const Duration(seconds: 10));
      expect(controller.remaining, const Duration(seconds: 50));
    });
  });

  group('adjust', () {
    test('extending past the original total stretches the ring', () {
      controller.start(const Duration(seconds: 60));
      advance(const Duration(seconds: 10));
      controller.adjust(const Duration(seconds: 30));

      expect(controller.remaining, const Duration(seconds: 80));
      expect(controller.totalDuration, const Duration(seconds: 80));
    });

    test('shortening below zero while running completes the timer', () {
      controller.start(const Duration(seconds: 30));
      controller.adjust(const Duration(seconds: -60));

      expect(controller.phase, RestTimerPhase.completed);
      expect(alerts.chimes, 1);
    });

    test('shortening below zero while paused stays paused at zero', () {
      controller.start(const Duration(seconds: 30));
      controller.pause();
      controller.adjust(const Duration(seconds: -60));

      expect(controller.phase, RestTimerPhase.paused);
      expect(controller.remaining, Duration.zero);
      expect(alerts.chimes, 0);
    });
  });

  group('completion', () {
    test('announces exactly once', () {
      controller.start(const Duration(seconds: 30));
      controller.adjust(const Duration(seconds: -60));

      expect(alerts.chimes, 1);
      expect(alerts.haptics, 1);
      expect(controller.isActive, isTrue,
          reason: 'completed must persist until acknowledged');
    });

    test('stays completed until acknowledged', () {
      controller.start(const Duration(seconds: 30));
      controller.adjust(const Duration(seconds: -60));
      advance(const Duration(minutes: 10));

      expect(controller.phase, RestTimerPhase.completed);

      controller.acknowledgeCompletion();
      expect(controller.phase, RestTimerPhase.idle);
      expect(controller.isActive, isFalse);
    });

    test('acknowledgeCompletion is a no-op in every other phase', () {
      controller.acknowledgeCompletion();
      expect(controller.phase, RestTimerPhase.idle);

      controller.start(const Duration(seconds: 60));
      controller.acknowledgeCompletion();
      expect(controller.phase, RestTimerPhase.running);
    });

    test('a rest that ended while backgrounded completes silently on resume',
        () {
      controller.start(const Duration(seconds: 60));
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      advance(const Duration(seconds: 90));
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(controller.phase, RestTimerPhase.completed);
      // The scheduled notification already announced it; chiming here would
      // announce the same rest twice.
      expect(alerts.chimes, 0);
    });
  });

  group('stop', () {
    test('returns to idle from any phase', () {
      for (final reach in <void Function()>[
        () => controller.start(const Duration(seconds: 60)),
        () {
          controller.start(const Duration(seconds: 60));
          controller.pause();
        },
        () {
          controller.start(const Duration(seconds: 30));
          controller.adjust(const Duration(seconds: -60));
        },
      ]) {
        reach();
        controller.stop();
        expect(controller.phase, RestTimerPhase.idle);
        expect(controller.remaining, Duration.zero);
      }
    });
  });

  group('notification scheduling', () {
    test('nothing is armed while the app is foregrounded', () {
      controller.start(const Duration(seconds: 90));

      expect(scheduler.scheduledFor, isNull);
    });

    test('schedules on backgrounding and cancels on resume', () {
      controller.start(const Duration(seconds: 90));
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);

      expect(scheduler.scheduledFor, clock.add(const Duration(seconds: 90)));

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(scheduler.scheduledFor, isNull);
    });

    test('inactive is ignored, so a glance does not churn the alarm', () {
      controller.start(const Duration(seconds: 90));
      final schedulesBefore = scheduler.schedules;
      final cancelsBefore = scheduler.cancels;

      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);

      expect(scheduler.schedules, schedulesBefore);
      expect(scheduler.cancels, cancelsBefore);
    });

    test('stopping while backgrounded cancels the pending notification', () {
      controller.start(const Duration(seconds: 90));
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(scheduler.scheduledFor, isNotNull);

      controller.stop();
      expect(scheduler.scheduledFor, isNull);
    });

    test('a paused timer arms nothing, since it has no end time', () {
      controller.start(const Duration(seconds: 90));
      controller.pause();
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);

      expect(scheduler.scheduledFor, isNull);
    });

    test('a shade adjustment while backgrounded re-arms the alarm', () {
      controller.start(const Duration(seconds: 90));
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(scheduler.scheduledFor, clock.add(const Duration(seconds: 90)));

      controller.adjust(const Duration(seconds: 15));

      expect(scheduler.scheduledFor, clock.add(const Duration(seconds: 105)));
    });
  });

  group('ongoing notification', () {
    test('is not posted for a foregrounded rest, matching the alarm', () {
      controller.start(const Duration(seconds: 90));

      expect(scheduler.ongoingRunning, isNull);
      expect(scheduler.scheduledFor, isNull);
    });

    test('appears on backgrounding and disappears on resume', () {
      controller.start(const Duration(seconds: 90));

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(scheduler.ongoingRunning, isTrue);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(scheduler.ongoingRunning, isNull);
    });

    test('reports the paused phase with the remaining time while backgrounded', () {
      controller.start(const Duration(seconds: 90));
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      advance(const Duration(seconds: 20));
      controller.pause();

      expect(scheduler.ongoingRunning, isFalse);
      expect(scheduler.ongoingRemaining, const Duration(seconds: 70));
    });

    test('comes back on resume while still backgrounded', () {
      controller.start(const Duration(seconds: 90));
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      controller.pause();
      controller.resume();

      expect(scheduler.ongoingRunning, isTrue);
    });

    test('is taken down by stopping', () {
      controller.start(const Duration(seconds: 90));
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      final hidesBefore = scheduler.ongoingHides;

      controller.stop();

      expect(scheduler.ongoingHides, hidesBefore + 1);
      expect(scheduler.ongoingRunning, isNull);
    });

    test('is taken down on completion, leaving the alert to announce it', () {
      controller.start(const Duration(seconds: 90));
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      advance(const Duration(seconds: 90));
      controller.adjust(const Duration(seconds: -15));

      expect(controller.isCompleted, isTrue);
      expect(scheduler.ongoingRunning, isNull);
    });

    test('is not posted before a timer ever runs', () {
      expect(scheduler.ongoingShows, 0);
    });
  });

  group('last used duration', () {
    test('falls back to the persisted value before any timer runs', () {
      settings.stored = const Duration(minutes: 2);
      expect(controller.lastUsedDuration, const Duration(minutes: 2));
    });

    test('starting a timer persists the duration', () {
      controller.start(const Duration(minutes: 3));

      expect(settings.stored, const Duration(minutes: 3));
      expect(controller.lastUsedDuration, const Duration(minutes: 3));
    });

    test('persists the clamped value, not the raw request', () {
      controller.start(const Duration(hours: 1));
      expect(settings.stored, RestTimerController.maxDuration);
    });
  });
}
