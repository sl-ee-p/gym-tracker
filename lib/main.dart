import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'providers/user_provider.dart';
import 'providers/exercise_provider.dart';
import 'providers/workout_provider.dart';
import 'providers/progress_provider.dart';
import 'providers/rest_timer_controller.dart';
import 'screens/home_screen.dart';
import 'services/home_widget_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ExerciseProvider()),
        ChangeNotifierProvider(create: (_) => WorkoutProvider()),
        ChangeNotifierProvider(create: (_) => ProgressProvider()),
        // Left lazy: the first read is the workout screen's header pill, long
        // after UserProvider.initialize() has loaded the persisted duration,
        // and no timer can be running before something has constructed this.
        ChangeNotifierProvider(
          create: (context) {
            final controller = RestTimerController(
              settings:
                  UserProfileRestTimerSettings(context.read<UserProvider>()),
              scheduler: const NotificationRestTimerScheduler(),
            );
            // The ongoing notification's buttons are handled on a throwaway
            // isolate and forwarded here over a port, so they need a live
            // controller to land on. Bound at construction because this
            // provider is the only thing that ever owns one.
            NotificationService.instance.onRestAction =
                (actionId) => _applyRestNotificationAction(controller, actionId);
            return controller;
          },
        ),
      ],
      child: Consumer<UserProvider>(
        builder: (context, userProvider, child) {
          return MaterialApp(
            title: 'PlateLog',
            // Custom colours are stored per brightness, so light and dark can
            // be tuned independently — the same accent rarely works in both.
            // Null values fall through to AppTheme's built-in palette.
            theme: AppTheme.light(
              accent: _colorOrNull(userProvider.accentColorLight),
              highlight: _colorOrNull(userProvider.highlightColorLight),
            ),
            darkTheme: AppTheme.dark(
              accent: _colorOrNull(userProvider.accentColorDark),
              highlight: _colorOrNull(userProvider.highlightColorDark),
            ),
            themeMode: userProvider.themeMode,
            home: const AppInitializer(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer>
    with WidgetsBindingObserver {
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Defer initialization until after the first frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The home-screen widget is a baked PNG, so it goes stale in two ways the
  /// app can't push against: the calendar day rolls over (its "today" column
  /// stops advancing) and the system flips dark mode (its colours are baked
  /// in). Both are caught cheaply here rather than with a background worker.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isInitialized) {
      _refreshHomeWidget();
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (_isInitialized) _refreshHomeWidget();
  }

  void _refreshHomeWidget() {
    if (!mounted) return;
    final userProvider = context.read<UserProvider>();
    final progressProvider = context.read<ProgressProvider>();
    unawaited(HomeWidgetService.refresh(
      workoutDays: progressProvider.workoutDates.toSet(),
      workoutsThisWeek: progressProvider.workoutsThisWeek,
      weeklyGoal: userProvider.weeklyWorkoutGoal,
      themeMode: userProvider.themeMode,
      accentLight: userProvider.accentColorLight,
      accentDark: userProvider.accentColorDark,
      highlightLight: userProvider.highlightColorLight,
      highlightDark: userProvider.highlightColorDark,
    ));
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize all providers
      final userProvider = context.read<UserProvider>();
      final exerciseProvider = context.read<ExerciseProvider>();
      final workoutProvider = context.read<WorkoutProvider>();
      final progressProvider = context.read<ProgressProvider>();

      // UserProvider first, on its own: it holds the persisted Progress date
      // range, and ProgressProvider needs that before it loads anything —
      // inside a Future.wait the order isn't guaranteed, so the range would
      // sometimes arrive after the first load had already used the default.
      await userProvider.initialize();

      await Future.wait([
        exerciseProvider.initialize(),
        workoutProvider.initialize(),
        progressProvider.initialize(
          savedDateRange: userProvider.progressDateRange,
        ),
      ]);

      // Not awaited: channel setup must not delay the splash coming down.
      // NotificationService swallows its own failures too, so a device that
      // refuses to create the channel can't land the user on the "Failed to
      // initialize app" screen over a feature they may never use.
      unawaited(NotificationService.instance.initialize());

      // Re-applied every launch rather than trusted from last time: it picks
      // up a timezone change, and it costs nothing when nothing changed.
      // syncReminders awaits the initialize above itself.
      unawaited(userProvider.syncReminders());

      // Same treatment for the home-screen widget: renders a PNG, so it must
      // not sit between the user and the first frame. Refreshing here also
      // means an image exists before the user can add the widget at all —
      // otherwise it can only ever show its placeholder.
      _refreshHomeWidget();

      setState(() {
        _isInitialized = true;
      });
      
      // Remove splash screen when initialization is complete
      FlutterNativeSplash.remove();
    } catch (e) {
      debugPrint('Error initializing app: $e');
      setState(() {
        _hasError = true;
        _isInitialized = true;
      });
      
      // Remove splash screen even if there's an error
      FlutterNativeSplash.remove();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading PlateLog...'),
            ],
          ),
        ),
      );
    }

    if (_hasError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              const Text(
                'Failed to initialize app',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text('Please restart the application'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _isInitialized = false;
                    _hasError = false;
                  });
                  _initializeApp();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return const HomeScreen();
  }
}

/// Stored theme colours are nullable ARGB ints — null means "use the built-in
/// palette", which is what AppTheme already does with a null [Color].
Color? _colorOrNull(int? value) => value == null ? null : Color(value);

/// Backs the rest timer's remembered duration with the `user_profiles` row,
/// the same place every other preference lives.
///
/// The adapter sits here, in the wiring, rather than in either provider:
/// RestTimerController stays independent of how it is persisted (so it is
/// constructible with an in-memory fake in tests), and UserProvider stays
/// unaware that a rest timer exists.
class UserProfileRestTimerSettings implements RestTimerSettings {
  const UserProfileRestTimerSettings(this._userProvider);

  final UserProvider _userProvider;

  @override
  Duration read() => _userProvider.restTimerDuration;

  @override
  Future<void> write(Duration duration) =>
      _userProvider.updateRestTimerDuration(duration);
}

/// Hands the controller's notification decisions to the OS.
class NotificationRestTimerScheduler implements RestTimerScheduler {
  const NotificationRestTimerScheduler();

  @override
  Future<void> schedule(DateTime at) =>
      NotificationService.instance.scheduleRestComplete(at);

  @override
  Future<void> cancel() => NotificationService.instance.cancelRestComplete();

  @override
  Future<void> ensurePermissions() =>
      NotificationService.instance.ensurePermissions();

  @override
  Future<void> showOngoing({
    required bool running,
    required DateTime? endTime,
    required Duration remaining,
  }) =>
      NotificationService.instance.showRestOngoing(
        running: running,
        endTime: endTime,
        remaining: remaining,
      );

  @override
  Future<void> hideOngoing() =>
      NotificationService.instance.cancelRestOngoing();
}

/// Turns a tapped notification button back into a timer control.
///
/// This mapping lives here rather than in either half it joins:
/// [NotificationService] has no business knowing what a rest timer is, and
/// [RestTimerController] is kept free of notification imports so it stays
/// constructible in a plain unit test.
///
/// -15 s deliberately inherits [RestTimerController.adjust]'s behaviour of
/// ending a rest that it would take below zero, because that is exactly what
/// the modal's own -15 s button does.
void _applyRestNotificationAction(
  RestTimerController controller,
  String actionId,
) {
  switch (actionId) {
    case NotificationService.restPauseActionId:
      controller.pause();
    case NotificationService.restResumeActionId:
      controller.resume();
    case NotificationService.restMinus15ActionId:
      controller.adjust(const Duration(seconds: -15));
    case NotificationService.restPlus15ActionId:
      controller.adjust(const Duration(seconds: 15));
  }
}
