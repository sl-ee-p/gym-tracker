import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import '../utils/app_date.dart';
import '../widgets/home_widget_heatmap_canvas.dart';
import 'workout_repository.dart';

/// Keeps the Android home-screen widget's image up to date.
///
/// Follows BackupService's shape: all-static, and it never throws. A widget
/// that fails to refresh must not be able to fail the workout that triggered
/// it, so every path here logs and returns.
class HomeWidgetService {
  const HomeWidgetService._();

  /// Must match HeatmapWidgetProvider.IMAGE_KEY on the Kotlin side.
  static const String imageKey = 'hw_heatmap_image';

  /// The card behind the image, tinted natively — see
  /// [HomeWidgetHeatmapCanvas] for why the frame is not drawn into the PNG.
  /// Both must match HeatmapWidgetProvider's keys.
  static const String backgroundColorKey = 'hw_background_color';
  static const String borderColorKey = 'hw_border_color';
  static const String textColorKey = 'hw_text_color';

  /// Fully qualified, not the short name. home_widget resolves a short
  /// `androidName` against the *applicationId*, which equals the namespace
  /// today but would silently break the day a flavour adds a suffix.
  static const String androidProvider =
      'com.example.gym_app.HeatmapWidgetProvider';

  static final WorkoutRepository _workoutRepository = WorkoutRepository();

  /// Renders the heatmap and pushes it to any placed widget.
  ///
  /// [workoutDays] is the same set the dashboard card draws — callers that
  /// already have ProgressProvider loaded should pass it rather than making
  /// this re-query.
  static Future<void> refresh({
    required Set<DateTime> workoutDays,
    required int workoutsThisWeek,
    required int weeklyGoal,
    required ThemeMode themeMode,
    int? accentLight,
    int? accentDark,
    int? highlightLight,
    int? highlightDark,
  }) async {
    // defaultTargetPlatform rather than dart:io, so `flutter test` on any
    // desktop short-circuits cleanly instead of reaching for a channel.
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final theme = themeFor(
        themeMode: themeMode,
        accentLight: accentLight,
        accentDark: accentDark,
        highlightLight: highlightLight,
        highlightDark: highlightDark,
      );

      // Saved before the render so a launcher that redraws between the two
      // calls picks up a card matching the image it already has, rather than
      // last theme's card around this theme's content.
      await _saveFrameColors(theme);

      await HomeWidget.renderFlutterWidget(
        HomeWidgetHeatmapCanvas(
          theme: theme,
          workoutDays: workoutDays,
          workoutsThisWeek: workoutsThisWeek,
          weeklyGoal: weeklyGoal,
        ),
        key: imageKey,
        logicalSize: HomeWidgetHeatmapCanvas.logicalSize,
        // Passed explicitly rather than relying on the package default, which
        // moved between releases. Capped at 3: beyond that the bitmap crosses
        // 2 MB and starts risking a TransactionTooLargeException in heavier
        // launchers, for no visible gain.
        pixelRatio: _devicePixelRatio().clamp(1.0, 3.0),
      );

      await HomeWidget.updateWidget(qualifiedAndroidName: androidProvider);
    } catch (e) {
      debugPrint('Error refreshing home widget: $e');
    }
  }

  /// The card colours the native provider tints its rounded background and
  /// hairline border with — the same two the app's `Card` uses, so the widget
  /// and the dashboard read as the same surface.
  ///
  /// Stored as decimal strings rather than ints on purpose: an ARGB value
  /// with a full alpha byte exceeds 32-bit signed range, so it crosses the
  /// platform channel as an Int on some values and a Long on others, and
  /// SharedPreferences then throws a ClassCastException on whichever one the
  /// Kotlin side didn't expect.
  static Future<void> _saveFrameColors(ThemeData theme) async {
    final colors = theme.colorScheme;
    await HomeWidget.saveWidgetData<String>(
      backgroundColorKey,
      '${colors.surfaceContainerLow.toARGB32()}',
    );
    await HomeWidget.saveWidgetData<String>(
      borderColorKey,
      // Matches AppTheme's cardTheme border, which is outlineVariant at 60%.
      '${colors.outlineVariant.withValues(alpha: 0.6).toARGB32()}',
    );
    await HomeWidget.saveWidgetData<String>(
      // Only the "open the app to load" placeholder uses this, but it sits on
      // the tinted card, so it has to come from the same theme rather than
      // from the system's night qualifier.
      textColorKey,
      '${colors.onSurfaceVariant.toARGB32()}',
    );
  }

  /// The escape hatch for callers with no provider in scope — app start
  /// before the dashboard has ever been built. Reuses the same repository
  /// query the heatmap already runs; no widget-specific SQL.
  static Future<void> refreshFromDatabase(UserProfile? profile) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final now = DateTime.now();
      final dates =
          await _workoutRepository.getWorkoutDates(start: addDays(now, -365));
      final weekStart = startOfWeek(now);
      final thisWeek = await _workoutRepository.countCompletedWorkouts(
        start: weekStart,
        end: addDays(weekStart, 7),
      );

      await refresh(
        workoutDays: dates.toSet(),
        workoutsThisWeek: thisWeek,
        weeklyGoal: profile?.weeklyWorkoutGoal ?? 3,
        themeMode: _themeModeOf(profile?.themeMode),
        accentLight: profile?.accentColorLight,
        accentDark: profile?.accentColorDark,
        highlightLight: profile?.highlightColorLight,
        highlightDark: profile?.highlightColorDark,
      );
    } catch (e) {
      debugPrint('Error refreshing home widget from database: $e');
    }
  }

  /// Whether the launcher can offer an "add to home screen" prompt.
  static Future<bool> isPinSupported() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await HomeWidget.isRequestPinWidgetSupported() ?? false;
    } catch (e) {
      debugPrint('Error checking widget pin support: $e');
      return false;
    }
  }

  static Future<void> requestPin() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await HomeWidget.requestPinWidget(qualifiedAndroidName: androidProvider);
    } catch (e) {
      debugPrint('Error requesting widget pin: $e');
    }
  }

  /// The theme the PNG is baked with.
  ///
  /// It follows the *app's* setting rather than the system's: someone who has
  /// explicitly forced Light in Settings would find a dark widget
  /// inconsistent. `ThemeMode.system` resolves to the platform brightness, so
  /// the common case still tracks the OS.
  ///
  /// Consequence worth knowing: brightness is baked in, so flipping system
  /// dark mode while the app is closed leaves the widget mismatched until the
  /// next refresh.
  @visibleForTesting
  static ThemeData themeFor({
    required ThemeMode themeMode,
    int? accentLight,
    int? accentDark,
    int? highlightLight,
    int? highlightDark,
  }) {
    final brightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => _platformBrightness(),
    };

    Color? color(int? value) => value == null ? null : Color(value);

    return brightness == Brightness.dark
        ? AppTheme.dark(
            accent: color(accentDark), highlight: color(highlightDark))
        : AppTheme.light(
            accent: color(accentLight), highlight: color(highlightLight));
  }

  static ThemeMode _themeModeOf(String? stored) => switch (stored) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static Brightness _platformBrightness() =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  static double _devicePixelRatio() =>
      WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio ??
      3.0;
}

