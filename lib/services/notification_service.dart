import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder_schedule.dart';
import '../theme/app_theme.dart';
import '../utils/rest_duration_format.dart';

/// The name the main isolate's action port is registered under.
///
/// Top-level because both sides need it and one of them is not an instance of
/// anything: the tap handler runs on a throwaway isolate with no access to
/// [NotificationService.instance].
const String _restActionPortName = 'gym_app/rest_timer_action';

/// Receives a tap on one of the ongoing notification's buttons.
///
/// This does *not* run in the app. `ActionBroadcastReceiver` starts a separate,
/// short-lived `FlutterEngine` for every tap on an action whose
/// `showsUserInterface` is false — even when the app is in the foreground — so
/// this executes on an isolate that shares no memory with the running app and
/// cannot see the rest timer. All it can do is forward the id over a named port
/// and let the live isolate act on it.
///
/// A null lookup means the app isn't alive. That is the accepted outcome of
/// having no foreground service: the tap is dropped rather than applied to a
/// timer that no longer exists.
@pragma('vm:entry-point')
void restNotificationActionCallback(NotificationResponse response) {
  final actionId = response.actionId;
  if (actionId == null) return;
  IsolateNameServer.lookupPortByName(_restActionPortName)?.send(actionId);
}

/// The two notifications this app posts.
///
/// **The alert** — "your rest is over" — exists because the in-app chime
/// physically cannot fire while the app is backgrounded: frames stop, so the
/// countdown is only noticed on resume, by which point the rest is long over.
/// An OS alarm survives that, and survives the process being killed.
///
/// **The ongoing notification** is a control surface, not an alert: while the
/// app is backgrounded and a rest is running or paused, it counts down live
/// and carries -15s / Pause·Resume / +15s buttons that drive the real timer.
/// It stays down while the app is foregrounded, where the in-app modal/header
/// pill already fills that role. It is tied to the live app — deliberately,
/// since there is no foreground service — so it goes stale if the process is
/// killed, matching the fact that the timer state itself isn't persisted
/// across a cold start.
///
/// The two are separate ids on separate channels because a channel's importance
/// and sound are immutable once created: the alert has to shout (max
/// importance, custom sound), and something permanent in the shade must never
/// shout at all.
///
/// Every method swallows its own failures. A notification that can't be posted
/// must never break starting or stopping a rest timer; the in-app chime and
/// controls are still there whenever the app is open.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const int _restTimerId = 1001;
  static const int _restOngoingId = 1002;

  static const String _channelId = 'rest_timer';
  static const String _channelName = 'Rest timer';
  static const String _channelDescription =
      'Alerts you when a rest period ends.';

  static const String _ongoingChannelId = 'rest_timer_ongoing';
  static const String _ongoingChannelName = 'Rest timer controls';
  static const String _ongoingChannelDescription =
      'The live rest countdown and its buttons, while a rest is running.';

  static const String _reminderChannelId = 'reminders';
  static const String _reminderChannelName = 'Reminders';
  static const String _reminderChannelDescription =
      'Your weekly workout and weigh-in reminders.';

  /// Reminder ids are base + ISO weekday, so each weekday is its own
  /// repeating notification and can be cancelled on its own.
  static const int _workoutReminderBaseId = 2000;
  static const int _weighInReminderBaseId = 2100;

  /// Ids of the ongoing notification's buttons. Part of this class's public
  /// contract rather than an implementation detail: they cross a broadcast
  /// receiver and an isolate boundary as bare strings, and the app's wiring
  /// maps them back onto timer controls.
  static const String restMinus15ActionId = 'rest_minus_15';
  static const String restPauseActionId = 'rest_pause';
  static const String restResumeActionId = 'rest_resume';
  static const String restPlus15ActionId = 'rest_plus_15';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionRequested = false;

  /// Whether exact alarms are allowed. Re-checked on resume, because the
  /// Android 12/13 permission request opens a settings screen and returns
  /// immediately with the *old* value.
  bool _exactAlarmsAllowed = false;

  ReceivePort? _actionPort;

  /// In flight or completed [initialize] call.
  ///
  /// [_syncNotification] fires the alarm and the ongoing notification
  /// concurrently, so on the very first rest two callers reach here at once.
  /// Without this they would both run the whole body, and the stale-notification
  /// sweep below could land *after* the other had already posted a live one.
  Future<void>? _initializing;

  /// Invoked on the main isolate with the id of a tapped notification button.
  ///
  /// Set by the app's wiring, which owns the mapping from an id to a timer
  /// control; this service deliberately knows nothing about the timer. Null
  /// until then, and in tests.
  void Function(String actionId)? onRestAction;

  Future<void> initialize() {
    final pending = _initializing;
    if (pending != null) return pending;
    return _initializing = _initialize();
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    try {
      tz_data.initializeTimeZones();
      await _setLocalTimezone();

      _bindActionPort();

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_rest_timer'),
          // All false: permission is asked for at the moment the user starts
          // their first rest, where it has obvious context, rather than in a
          // launch-time prompt that gets reflexively denied.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _onNotificationResponse,
        // Registered so the plugin stores a callback handle for the isolate
        // that `ActionBroadcastReceiver` spins up. Without this, the buttons
        // render and dispatch nothing.
        onDidReceiveBackgroundNotificationResponse:
            restNotificationActionCallback,
      );

      // Created eagerly: a channel's importance and sound are immutable once
      // it exists, and this way the user can find and tune it in system
      // settings before their first rest rather than after.
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('timer_complete'),
          enableVibration: true,
        ),
      );

      // Low, silent, and separate from the alert channel above. This one is
      // re-posted on every pause, resume and ±15 s; on a max-importance
      // channel each of those would be a heads-up banner with an alarm sound.
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _ongoingChannelId,
          _ongoingChannelName,
          description: _ongoingChannelDescription,
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
        ),
      );

      // Default importance: a reminder should show up in the shade and make
      // its sound, but it isn't an alarm and shouldn't pop over whatever is
      // on screen the way the rest-complete alert does.
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _reminderChannelId,
          _reminderChannelName,
          description: _reminderChannelDescription,
          importance: Importance.defaultImportance,
        ),
      );

      // Anything left under the ongoing id was posted by a previous process:
      // reaching here means this one has only just started, so no rest can be
      // running. It matters because that notification is deliberately not
      // swipeable — without this sweep, a rest interrupted by the app being
      // killed would strand it in the shade with dead buttons.
      await _plugin.cancel(id: _restOngoingId);

      await refreshExactAlarmCapability();
      _initialized = true;
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
      // Dropped so a later call retries: a half-initialised plugin posts
      // nothing, and the next rest is a perfectly good moment to try again.
      _initializing = null;
    }
  }

  /// Points `tz.local` at the device's zone. It defaults to UTC, which was
  /// fine while every schedule was a relative offset (the rest timer), but a
  /// weekly "18:00" reminder is wall-clock and needs the real zone — or it
  /// fires at 18:00 UTC and drifts an hour at each DST change.
  Future<void> _setLocalTimezone() async {
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (e) {
      // Unknown zone names do happen on some devices. UTC keeps the rest
      // timer correct; only reminders are affected.
      debugPrint('Could not resolve the local timezone: $e');
    }
  }

  /// Schedules the weekly reminders to match [workout] and [weighIn],
  /// replacing whatever was scheduled before. Safe to call repeatedly — at
  /// startup, after a setting changes, after a restore.
  ///
  /// Inexact on purpose: a reminder a few minutes late is fine, and exact
  /// alarms need a permission the user may have (rightly) refused.
  Future<void> syncReminders({
    required ReminderSchedule workout,
    required ReminderSchedule weighIn,
  }) async {
    if (!_initialized) await initialize();
    try {
      for (var day = DateTime.monday; day <= DateTime.sunday; day++) {
        await _plugin.cancel(id: _workoutReminderBaseId + day);
        await _plugin.cancel(id: _weighInReminderBaseId + day);
      }
      await _scheduleWeekly(
        schedule: workout,
        baseId: _workoutReminderBaseId,
        title: 'Time to train',
        body: 'Your workout is on the schedule for today.',
      );
      await _scheduleWeekly(
        schedule: weighIn,
        baseId: _weighInReminderBaseId,
        title: 'Morning weigh-in',
        body: 'Log your body weight while it is fresh.',
      );
    } catch (e) {
      debugPrint('Error scheduling reminders: $e');
    }
  }

  Future<void> _scheduleWeekly({
    required ReminderSchedule schedule,
    required int baseId,
    required String title,
    required String body,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    for (final day in schedule.days) {
      final next = schedule.nextOccurrence(now, day);
      await _plugin.zonedSchedule(
        id: baseId + day,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime(
            tz.local, next.year, next.month, next.day, next.hour, next.minute),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _reminderChannelId,
            _reminderChannelName,
            channelDescription: _reminderChannelDescription,
            autoCancel: true,
          ),
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // Repeats every week on this weekday at this local time.
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Opens the main isolate's end of the channel that
  /// [restNotificationActionCallback] sends to.
  void _bindActionPort() {
    // A hot restart leaves the previous mapping in place, and
    // registerPortWithName refuses to overwrite an existing name.
    IsolateNameServer.removePortNameMapping(_restActionPortName);
    _actionPort?.close();

    final port = ReceivePort();
    _actionPort = port;
    IsolateNameServer.registerPortWithName(port.sendPort, _restActionPortName);
    port.listen((dynamic message) {
      if (message is String) onRestAction?.call(message);
    });
  }

  /// Fires when a notification the user tapped brought the app forward. Action
  /// buttons normally arrive over the port instead — they never show the UI —
  /// but an id landing here is still an id worth applying.
  void _onNotificationResponse(NotificationResponse response) {
    final actionId = response.actionId;
    if (actionId != null) onRestAction?.call(actionId);
  }

  /// Asks for notification permission, once, the first time a rest starts.
  /// Never awaited by the caller — a permission dialog must not delay a timer.
  Future<void> ensurePermissions() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    try {
      await _android?.requestNotificationsPermission();
      await _android?.requestExactAlarmsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: false, sound: true);
      await refreshExactAlarmCapability();
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
    }
  }

  /// Asks only for permission to post notifications — for turning on a
  /// reminder. Unlike [ensurePermissions] it never asks for exact alarms:
  /// reminders don't need them, and on Android 12+ that request throws the
  /// user out to a system settings screen.
  Future<void> requestNotificationPermission() async {
    if (!_initialized) await initialize();
    try {
      await _android?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: false, sound: true);
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
    }
  }

  Future<bool> refreshExactAlarmCapability() async {
    try {
      _exactAlarmsAllowed =
          await _android?.canScheduleExactNotifications() ?? false;
    } catch (e) {
      debugPrint('Error checking exact alarm permission: $e');
      _exactAlarmsAllowed = false;
    }
    return _exactAlarmsAllowed;
  }

  Future<void> scheduleRestComplete(DateTime at) async {
    if (!_initialized) await initialize();

    final delay = at.difference(DateTime.now());
    if (delay <= Duration.zero) return;

    // Re-checked every time rather than trusted from initialize(): on Android
    // 12/13 requestExactAlarmsPermission opens a settings screen and returns
    // immediately with the stale value, so the grant only becomes visible
    // later. This is the last moment before it matters.
    await refreshExactAlarmCapability();

    try {
      await _plugin.zonedSchedule(
        id: _restTimerId,
        title: 'Rest complete',
        body: 'Time for your next set.',
        // No flutter_timezone dependency: every instant scheduled here is a
        // relative offset of at most 15 minutes from now, so adding the delta
        // to tz.now() gives the correct absolute instant whatever tz.local
        // happens to be. The zone would only matter for rendering a calendar
        // date, which this notification never does.
        scheduledDate: tz.TZDateTime.now(tz.local).add(delay),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            sound: RawResourceAndroidNotificationSound('timer_complete'),
            playSound: true,
            enableVibration: true,
            autoCancel: true,
            visibility: NotificationVisibility.public,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        // allowWhileIdle is the point: a plain exact alarm is still deferred
        // by Doze, and a phone in a pocket with the screen off is exactly the
        // situation this notification exists for. Falls back to inexact when
        // the user hasn't granted the exact-alarm permission — that can drift
        // by minutes, which is worse than exact but far better than throwing.
        androidScheduleMode: _exactAlarmsAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        // Absolute, not wall-clock: a rest is an interval from now, so it
        // must not shift if the device crosses a timezone or a DST boundary
        // mid-countdown. This used to be spelled
        // `uiLocalNotificationDateInterpretation: absoluteTime`; v22 removed
        // the parameter because absolute is now the only interpretation, so
        // the behaviour this comment describes is the default rather than a
        // choice. Kept as a note so nobody "restores" wall-clock scheduling.
      );
    } catch (e) {
      debugPrint('Error scheduling rest notification: $e');
    }
  }

  /// Cancels a pending alarm *and* dismisses an already-posted notification
  /// from the shade. Both are wanted: stopping a timer should clear a stale
  /// "Rest complete" the user never tapped.
  Future<void> cancelRestComplete() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _restTimerId);
    } catch (e) {
      debugPrint('Error cancelling rest notification: $e');
    }
  }

  /// Posts, or updates in place, the notification that mirrors a live rest.
  ///
  /// Android-only in effect: iOS has no ongoing-notification concept and every
  /// detail below sits in the Android block. Left unconditional rather than
  /// platform-branched because the caller is the timer, which has no business
  /// knowing the platform.
  Future<void> showRestOngoing({
    required bool running,
    required DateTime? endTime,
    required Duration remaining,
  }) async {
    if (!_initialized) await initialize();

    try {
      await _plugin.show(
        id: _restOngoingId,
        title: running ? 'Resting' : 'Rest paused',
        // Running needs no body: the countdown is the chronometer, and text
        // here would be a second, frozen copy of it.
        body: running ? null : '${formatRestDuration(remaining)} left',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _ongoingChannelId,
            _ongoingChannelName,
            channelDescription: _ongoingChannelDescription,
            importance: Importance.low,
            priority: Priority.low,
            category: AndroidNotificationCategory.stopwatch,
            // The whole point of this notification: not swipeable, and not
            // dismissed by a tap on it or on one of its own buttons.
            ongoing: true,
            autoCancel: false,
            playSound: false,
            enableVibration: false,
            // Tints the whole card with the app's brand colour instead of the
            // default flat grey — the single visual difference between "some
            // notification" and "this app's timer". AppTheme.defaultAccent
            // rather than the user's live theme, so this service stays
            // decoupled from UserProvider for one cosmetic touch.
            colorized: true,
            color: AppTheme.defaultAccent,
            // Every state change re-posts this same id. Without this, Android
            // treats each re-post as a fresh notification to announce.
            onlyAlertOnce: true,
            visibility: NotificationVisibility.public,
            // The countdown is drawn by the system from [when], which is why
            // nothing here has to re-post once a second to keep it honest.
            //
            // A chronometer cannot be frozen, so a paused rest drops it and
            // states the remaining time as text instead — correct precisely
            // because a paused timer doesn't move.
            showWhen: running,
            when: running ? endTime?.millisecondsSinceEpoch : null,
            usesChronometer: running,
            chronometerCountDown: running,
            // The second half of the not-swipeable bargain. If this process
            // dies mid-rest, nothing is left to take the notification down and
            // the user cannot swipe it away, so the OS is asked to drop it on
            // its own. Every state change re-posts and so re-arms this, which
            // is why a running rest can afford a tight grace period while a
            // paused one — with no end time to reason from — gets an hour.
            timeoutAfter: running
                ? (remaining + const Duration(minutes: 1)).inMilliseconds
                : const Duration(hours: 1).inMilliseconds,
            actions: _restActions(running: running),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error posting ongoing rest notification: $e');
    }
  }

  /// The three buttons, mirroring the modal's controls. Three is the practical
  /// Android limit, so the modal's "change time" and its ±30 s pair are left
  /// out; pause/resume is one slot that swaps label with the phase, exactly as
  /// the modal's toggle does.
  ///
  /// `cancelNotification: false` on all of them is load-bearing — it defaults
  /// to true, which would tear the notification down on the first tap.
  /// `showsUserInterface: false` is what keeps a ±15 s tap from hauling the app
  /// into the foreground; it is also what routes the tap to
  /// [restNotificationActionCallback] rather than to the running app.
  List<AndroidNotificationAction> _restActions({required bool running}) =>
      <AndroidNotificationAction>[
        const AndroidNotificationAction(
          restMinus15ActionId,
          '-15s',
          showsUserInterface: false,
          cancelNotification: false,
        ),
        if (running)
          const AndroidNotificationAction(
            restPauseActionId,
            'Pause',
            showsUserInterface: false,
            cancelNotification: false,
          )
        else
          const AndroidNotificationAction(
            restResumeActionId,
            'Resume',
            showsUserInterface: false,
            cancelNotification: false,
          ),
        const AndroidNotificationAction(
          restPlus15ActionId,
          '+15s',
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ];

  /// Takes the ongoing notification down. Called for every phase that isn't a
  /// live rest, "completed" included — at that point the alert is the thing
  /// with something to say.
  Future<void> cancelRestOngoing() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _restOngoingId);
    } catch (e) {
      debugPrint('Error cancelling ongoing rest notification: $e');
    }
  }
}
