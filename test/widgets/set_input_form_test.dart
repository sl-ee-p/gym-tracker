// Covers the post-set SnackBar's rest-timer action, which is what the
// superset/circuit "Quick Rest" auto-adjust hinges on: isLastInGroup true (or
// the default) must keep today's exact "Start Rest Timer" behavior, and only
// isLastInGroup false with onQuickRestRequested wired switches to the
// shortened "Quick Rest (20s)" action.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:gym_app/models/exercise.dart';
import 'package:gym_app/models/user_profile.dart';
import 'package:gym_app/providers/user_provider.dart';
import 'package:gym_app/widgets/set_input_form.dart';

void main() {
  final exercise = Exercise(id: 1, name: 'Bench Press', categoryId: 1);

  Widget host(Widget child) => MaterialApp(
        home: ChangeNotifierProvider<UserProvider>(
          create: (_) => UserProvider(),
          child: Scaffold(body: child),
        ),
      );

  Future<void> fillAndSubmit(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), '100');
    await tester.enterText(find.byType(TextFormField).at(1), '5');
    await tester.tap(find.widgetWithText(FilledButton, 'Add Set'));
    await tester.pump();
  }

  group('SetInputForm post-set SnackBar', () {
    testWidgets('shows "Start Rest Timer" when isLastInGroup defaults to true',
        (tester) async {
      await tester.pumpWidget(host(SetInputForm(
        exercise: exercise,
        onSetAdded: (weight, reps, duration, notes, isWarmup, partialReps, rpe) {},
        onRestTimerRequested: () {},
      )));

      await fillAndSubmit(tester);

      expect(find.text('Start Rest Timer'), findsOneWidget);
      expect(find.text('Quick Rest (20s)'), findsNothing);
    });

    testWidgets('shows "Start Rest Timer" when isLastInGroup is explicitly true',
        (tester) async {
      await tester.pumpWidget(host(SetInputForm(
        exercise: exercise,
        onSetAdded: (weight, reps, duration, notes, isWarmup, partialReps, rpe) {},
        onRestTimerRequested: () {},
        isLastInGroup: true,
        onQuickRestRequested: () {},
      )));

      await fillAndSubmit(tester);

      expect(find.text('Start Rest Timer'), findsOneWidget);
      expect(find.text('Quick Rest (20s)'), findsNothing);
    });

    testWidgets(
        'shows "Quick Rest (20s)" when isLastInGroup is false and '
        'onQuickRestRequested is wired', (tester) async {
      var quickRestRequested = false;
      await tester.pumpWidget(host(SetInputForm(
        exercise: exercise,
        onSetAdded: (weight, reps, duration, notes, isWarmup, partialReps, rpe) {},
        onRestTimerRequested: () {},
        isLastInGroup: false,
        onQuickRestRequested: () => quickRestRequested = true,
      )));

      await fillAndSubmit(tester);

      expect(find.text('Quick Rest (20s)'), findsOneWidget);
      expect(find.text('Start Rest Timer'), findsNothing);

      // Invoked directly rather than tapped: the SnackBar's action can sit
      // outside the small test viewport, which fails tester.tap's hit test
      // without saying anything about whether the callback is wired.
      final action = tester.widget<SnackBarAction>(find.byWidgetPredicate(
          (widget) => widget is SnackBarAction && widget.label == 'Quick Rest (20s)'));
      action.onPressed();
      expect(quickRestRequested, isTrue);
    });

    testWidgets(
        'falls back to the plain SnackBar when isLastInGroup is false but '
        'onQuickRestRequested is null', (tester) async {
      await tester.pumpWidget(host(SetInputForm(
        exercise: exercise,
        onSetAdded: (weight, reps, duration, notes, isWarmup, partialReps, rpe) {},
        onRestTimerRequested: () {},
        isLastInGroup: false,
      )));

      await fillAndSubmit(tester);

      expect(find.text('Quick Rest (20s)'), findsNothing);
      expect(find.text('Start Rest Timer'), findsNothing);
      expect(find.text('Set added successfully!'), findsOneWidget);
    });
  });

  group('SetInputForm partial reps and RPE', () {
    Widget hostWith({
      required bool partials,
      required bool rpe,
      required void Function(int? partialReps, double? rpe) onAdded,
    }) {
      final userProvider = UserProvider()
        ..setProfileForTesting(UserProfile(
          name: 'Sam',
          createdDate: DateTime(2025, 1, 1),
          partialRepsEnabled: partials,
          rpeEnabled: rpe,
        ));
      return MaterialApp(
        home: ChangeNotifierProvider<UserProvider>.value(
          value: userProvider,
          child: Scaffold(
            body: SingleChildScrollView(
              child: SetInputForm(
                exercise: exercise,
                onSetAdded: (weight, reps, duration, notes, isWarmup,
                        partialReps, rpe) =>
                    onAdded(partialReps, rpe),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('hides both inputs when the settings are off', (tester) async {
      int? loggedPartials = -1;
      await tester.pumpWidget(hostWith(
        partials: false,
        rpe: false,
        onAdded: (partialReps, rpe) => loggedPartials = partialReps,
      ));

      expect(find.widgetWithText(TextFormField, 'Partials'), findsNothing);
      expect(find.widgetWithText(ActionChip, 'RPE'), findsNothing);

      await fillAndSubmit(tester);
      expect(loggedPartials, isNull);
    });

    testWidgets('logs typed partials and the picked RPE when enabled',
        (tester) async {
      int? loggedPartials;
      double? loggedRpe;
      await tester.pumpWidget(hostWith(
        partials: true,
        rpe: true,
        onAdded: (partialReps, rpe) {
          loggedPartials = partialReps;
          loggedRpe = rpe;
        },
      ));

      await tester.tap(find.widgetWithText(ActionChip, 'RPE'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '8.5'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, 'RPE 8.5'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Partials'), '3');
      await fillAndSubmit(tester);

      expect(loggedPartials, 3);
      expect(loggedRpe, 8.5);
    });

    testWidgets('treats 0 partials as none', (tester) async {
      int? loggedPartials = -1;
      await tester.pumpWidget(hostWith(
        partials: true,
        rpe: false,
        onAdded: (partialReps, rpe) => loggedPartials = partialReps,
      ));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Partials'), '0');
      await fillAndSubmit(tester);

      expect(loggedPartials, isNull);
    });
  });
}
