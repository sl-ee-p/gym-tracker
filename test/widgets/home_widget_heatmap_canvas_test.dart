// The home-screen widget's PNG is rendered outside the widget tree, where
// there is no ancestor Theme, no ticker, and no repaint if anything resolves
// late. These tests pin the ways that goes wrong: a missing Theme
// (context.semanticColors throws), a text style resolved through GoogleFonts
// (which fetches a font over the network and would silently fall back in a
// one-shot render), and — because the bitmap is a fixed size with nowhere to
// reflow — a layout that no longer fits inside it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/services/home_widget_service.dart';
import 'package:gym_app/theme/app_theme.dart';
import 'package:gym_app/widgets/home_widget_heatmap_canvas.dart';
import 'package:gym_app/widgets/workout_heatmap.dart';

void main() {
  // AppTheme goes through GoogleFonts, which reaches for the asset bundle —
  // so a ThemeData cannot be built before the binding exists. That also means
  // the themes below must be built inside test bodies, not at collection time.
  TestWidgetsFlutterBinding.ensureInitialized();

  // A Thursday, so "days left" and the grid's trailing column are stable.
  final thursday = DateTime(2026, 9, 3, 18);

  Widget canvas(
    ThemeData theme, {
    Set<DateTime>? days,
    int completed = 2,
    int goal = 4,
  }) =>
      HomeWidgetHeatmapCanvas(
        theme: theme,
        workoutDays: days ??
            {
              DateTime(2026, 9, 1),
              DateTime(2026, 9, 3),
              DateTime(2026, 8, 27),
            },
        workoutsThisWeek: completed,
        weeklyGoal: goal,
        today: thursday,
      );

  // Deliberately not wrapped in MaterialApp: this is how
  // HomeWidget.renderFlutterWidget builds it — a Directionality under a
  // centring box, and nothing else. If the canvas ever starts reaching for an
  // inherited Theme, these fail.
  //
  // The Center is load-bearing, not decoration: pumpWidget gives the root
  // child *tight* 800x600 constraints, which would let the canvas expand to
  // the test surface and quietly hide every overflow the tests below are
  // there to catch. renderFlutterWidget lays the tree out under a
  // RenderPositionedBox, so the real constraints are loose.
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: child),
        ),
      );

  group('renders standalone', () {
    final variants = <String, ThemeData Function()>{
      'light': AppTheme.light,
      'dark': AppTheme.dark,
      'custom accent': () => AppTheme.light(accent: const Color(0xFF7B3FA0)),
    };

    for (final entry in variants.entries) {
      testWidgets('with no ancestor Theme (${entry.key})', (tester) async {
        await pump(tester, canvas(entry.value()));

        expect(tester.takeException(), isNull);
        expect(find.byType(WorkoutHeatmap), findsOneWidget);
        // The weekly goal, shown the way the dashboard card shows it: the
        // count inside the ring, the target beside it.
        expect(find.text('2'), findsOneWidget);
        expect(find.text('of 4'), findsOneWidget);
        expect(find.text('workouts'), findsOneWidget);
        expect(find.text('THIS WEEK'), findsOneWidget);
        expect(find.text('LAST 12 WEEKS'), findsOneWidget);
      });
    }

    testWidgets('with no workouts logged at all', (tester) async {
      await pump(tester, canvas(AppTheme.light(), days: const {}, completed: 0));

      expect(tester.takeException(), isNull);
      expect(find.text('0 sessions'), findsOneWidget);
    });
  });

  group('layout fits the bitmap it is rendered into', () {
    // The PNG is a fixed size and the launcher scales it whole, so an
    // overflow here is not a debug stripe the user can ignore — it is
    // permanently clipped content on their home screen.
    test('the grid is narrower than the column it sits in', () {
      final metrics = HomeWidgetHeatmapCanvas.debugMetrics;

      expect(metrics.heatmap.width, lessThanOrEqualTo(metrics.gridColumn));
    });

    testWidgets('no child overflows, in either theme', (tester) async {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        // 12 of 12 weeks filled and a two-digit count: the widest the goal
        // block and the densest the grid can get.
        await pump(
          tester,
          canvas(
            theme,
            days: {
              for (var i = 0; i < 84; i++)
                DateTime(thursday.year, thursday.month, thursday.day - i),
            },
            completed: 12,
            goal: 12,
          ),
        );

        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('paints exactly the size the caller renders at',
        (tester) async {
      await pump(tester, canvas(AppTheme.light()));

      expect(
        tester.getSize(find.byType(HomeWidgetHeatmapCanvas)),
        HomeWidgetHeatmapCanvas.logicalSize,
      );
    });
  });

  group('weekly goal', () {
    testWidgets('swaps the count for a tick once the goal is met',
        (tester) async {
      await pump(tester, canvas(AppTheme.light(), completed: 4, goal: 4));

      expect(find.text('Goal reached'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('4'), findsNothing, reason: 'replaced by the tick');
    });

    testWidgets('counts down the days left otherwise', (tester) async {
      await pump(tester, canvas(AppTheme.light(), completed: 1, goal: 4));

      // Thursday: Thu/Fri/Sat/Sun still to come.
      expect(find.text('4 days left'), findsOneWidget);
    });

    testWidgets('never reads as "of 0" for an unset goal', (tester) async {
      await pump(tester, canvas(AppTheme.light(), completed: 0, goal: 0));

      expect(tester.takeException(), isNull);
      expect(find.text('of 1'), findsOneWidget);
      expect(find.text('workout'), findsOneWidget);
    });
  });

  testWidgets('counts only the sessions the grid shows', (tester) async {
    // ProgressProvider hands over a full year; captioning the 12-week grid
    // with all of it would contradict the cells above the caption.
    await pump(
      tester,
      canvas(AppTheme.light(), days: {
        DateTime(2026, 9, 1),
        DateTime(2026, 8, 27),
        DateTime(2025, 12, 1), // well outside the 12-week window
      }),
    );

    expect(find.text('2 sessions'), findsOneWidget);
  });

  testWidgets('every text style is resolved locally, not from textTheme',
      (tester) async {
    // GoogleFonts.inter backs every entry in AppTheme's textTheme and resolves
    // asynchronously. An off-tree render paints once, so a style taken from
    // there could render in a fallback font — or fail outright.
    await pump(tester, canvas(AppTheme.light()));

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.fontSize, isNotNull,
          reason: '"${text.data}" must carry an explicit style');
      expect(text.style?.fontFamily, isNull,
          reason: '"${text.data}" must not name a downloadable font family');
    }
  });

  testWidgets('needs no ticker', (tester) async {
    // The ring is a CustomPaint, not a CircularProgressIndicator: the latter
    // builds an AnimationController, and renderFlutterWidget pumps a single
    // frame with no ticker provider behind it.
    await pump(tester, canvas(AppTheme.light()));

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  group('themeFor', () {
    test('honours an explicit light or dark choice', () {
      expect(HomeWidgetService.themeFor(themeMode: ThemeMode.dark).brightness,
          Brightness.dark);
      expect(HomeWidgetService.themeFor(themeMode: ThemeMode.light).brightness,
          Brightness.light);
    });

    test('applies the user custom accent for the resolved brightness', () {
      // The accent is a ColorScheme.fromSeed seed, not the primary colour
      // itself, so this asserts that it *reaches* the scheme rather than
      // pinning the tonal value AppTheme derives from it.
      const accentLight = Color(0xFF7B3FA0);
      const accentDark = Color(0xFF2E7D32);

      final light = HomeWidgetService.themeFor(
        themeMode: ThemeMode.light,
        accentLight: accentLight.toARGB32(),
        accentDark: accentDark.toARGB32(),
      );

      expect(light.colorScheme.primary,
          isNot(HomeWidgetService.themeFor(themeMode: ThemeMode.light)
              .colorScheme
              .primary),
          reason: 'a custom accent must change the palette');

      // The dark accent must be ignored when the resolved brightness is light
      // — the two are stored separately precisely so they can differ.
      final lightWithOtherDark = HomeWidgetService.themeFor(
        themeMode: ThemeMode.light,
        accentLight: accentLight.toARGB32(),
        accentDark: const Color(0xFFFF0000).toARGB32(),
      );
      expect(lightWithOtherDark.colorScheme.primary, light.colorScheme.primary);
    });

    test('carries the semantic colours the heatmap paints cells with', () {
      final theme = HomeWidgetService.themeFor(themeMode: ThemeMode.dark);

      expect(theme.extension<AppSemanticColors>(), isNotNull,
          reason: 'WorkoutHeatmap reads success from this extension');
    });
  });
}
