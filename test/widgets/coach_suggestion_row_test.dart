// The coach row inside the real SetInputForm: "Use" is the only thing that
// fills the fields, "Not now" hides the row, and a stall offers a deload
// that switches the target when started.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/coach/coach_models.dart';
import 'package:gym_app/l10n/app_localizations.dart';
import 'package:gym_app/models/exercise.dart';
import 'package:gym_app/providers/coach_provider.dart';
import 'package:gym_app/providers/user_provider.dart';
import 'package:gym_app/services/coach_service.dart';
import 'package:gym_app/theme/app_theme.dart';
import 'package:gym_app/widgets/coach/coach_suggestion_row.dart';
import 'package:gym_app/widgets/set_input_form.dart';
import 'package:provider/provider.dart';

class _FakeService extends CoachService {
  _FakeService(this.report, {this.stored});
  final CoachReport report;

  /// The rating "in the database".
  CoachRating? stored;
  CoachFeedback? saved;

  @override
  Future<CoachRating?> ratingFor(int workoutId, int exerciseId) async => stored;

  @override
  Future<void> rate({
    required int workoutId,
    required int exerciseId,
    required CoachFeedback feedback,
  }) async {
    saved = feedback;
    stored = feedback.rating;
  }

  @override
  Future<CoachReport> reportFor(
    Exercise exercise, {
    required String unit,
    required double defaultBarWeightKg,
    DateTime? now,
  }) async => report;
}

final _exercise = Exercise(id: 7, name: 'Chest Press', categoryId: 1);

CoachReport _report({
  DeloadAdvice? deload,
  CoachAction action = CoachAction.repeat,
}) => CoachReport(
  status: deload == null ? CoachStatus.progressing : CoachStatus.stalled,
  range: const RepRange(6, 8, learned: true),
  step: 2.5,
  unit: 'kg',
  exposures: 8,
  deload: deload,
  suggestion: CoachSuggestion(
    action: action,
    weight: 92.5,
    weightKg: 92.5,
    repsMin: 8,
    repsMax: 8,
    secondSetReps: 7,
  ),
);

const _deload = DeloadAdvice(
  weight: 82.5,
  weightKg: 82.5,
  reps: 6,
  sessions: 1,
  trigger: CoachReason(CoachReasonCode.stalled, sessions: 5),
);

Future<void> _pump(
  WidgetTester tester,
  CoachReport report, {
  int logged = 0,
  bool enabled = true,
  _FakeService? service,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (_) =>
              CoachProvider(service: service ?? _FakeService(report))
                ..update(unit: 'kg', defaultBarWeightKg: 20, enabled: enabled),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SetInputForm(
              exercise: _exercise,
              onSetAdded: (_, _, _, _, _, _, _) {},
              suggestionBuilder: (apply) => CoachSuggestionRow(
                exercise: _exercise,
                workoutId: 1,
                workingSetsLogged: logged,
                apply: apply,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

String _field(WidgetTester tester, int index) => tester
    .widget<TextFormField>(find.byType(TextFormField).at(index))
    .controller!
    .text;

void main() {
  testWidgets('switched off in Settings: no row', (tester) async {
    await _pump(tester, _report(), enabled: false);
    expect(find.text('Use'), findsNothing);
    expect(find.textContaining('Coach'), findsNothing);
  });

  testWidgets('fields stay empty until Use is tapped', (tester) async {
    await _pump(tester, _report());
    expect(find.text('Coach · top set'), findsOneWidget);
    expect(find.text('92.5 kg × 8'), findsOneWidget);
    expect(_field(tester, 0), isEmpty);
    expect(_field(tester, 1), isEmpty);

    await tester.tap(find.text('Use'));
    await tester.pump();
    expect(_field(tester, 0), '92.5');
    expect(_field(tester, 1), '8');
  });

  testWidgets('second set gets the set-2 target', (tester) async {
    await _pump(tester, _report(), logged: 1);
    expect(find.text('Coach · set 2'), findsOneWidget);
    expect(find.text('92.5 kg × 7'), findsOneWidget);
  });

  testWidgets('Not now hides the row for this workout', (tester) async {
    await _pump(tester, _report());
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('92.5 kg × 8'), findsNothing);
    expect(find.text('Use'), findsNothing);
  });

  testWidgets('stall: Start deload switches the target', (tester) async {
    await _pump(tester, _report(deload: _deload));
    expect(find.text('No progress for 5 sessions'), findsOneWidget);

    await tester.tap(find.text('Start deload'));
    await tester.pumpAndSettle();
    expect(find.text('No progress for 5 sessions'), findsNothing);
    expect(find.text('Coach · deload'), findsOneWidget);
    expect(find.text('82.5 kg × 6'), findsOneWidget);

    await tester.tap(find.text('Use'));
    await tester.pump();
    expect(_field(tester, 0), '82.5');
    expect(_field(tester, 1), '6');
  });

  testWidgets('stall: Not now on the banner keeps the normal target', (
    tester,
  ) async {
    await _pump(tester, _report(deload: _deload));
    await tester.tap(find.text('Not now').first);
    await tester.pumpAndSettle();
    expect(find.text('No progress for 5 sessions'), findsNothing);
    expect(find.text('92.5 kg × 8'), findsOneWidget);
  });

  group('rating', () {
    testWidgets('not asked before the first working set', (tester) async {
      await _pump(tester, _report());
      expect(find.text('How did 92.5 kg × 8 feel?'), findsNothing);
    });

    testWidgets('asked after a set; the answer is saved and can be changed', (
      tester,
    ) async {
      final service = _FakeService(_report());
      await _pump(tester, _report(), logged: 1, service: service);
      expect(find.text('How did 92.5 kg × 8 feel?'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Rate 92.5 kg × 8 as too hard'),
        findsOneWidget,
      );

      await tester.tap(find.text('Too hard'));
      await tester.pumpAndSettle();
      expect(service.stored, CoachRating.tooHard);
      expect(service.saved!.weightKg, 92.5);
      expect(service.saved!.repsMin, 8);
      expect(service.saved!.action, CoachAction.repeat);
      expect(find.textContaining('Noted: Too hard'), findsOneWidget);
      expect(find.text('About right'), findsNothing);

      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('About right'));
      await tester.pumpAndSettle();
      expect(service.stored, CoachRating.right);
      expect(find.textContaining('Noted: About right'), findsOneWidget);
    });

    testWidgets('a saved answer shows after a rebuild', (tester) async {
      final service = _FakeService(_report(), stored: CoachRating.tooEasy);
      await _pump(tester, _report(), logged: 2, service: service);
      expect(find.textContaining('Noted: Too easy'), findsOneWidget);
    });

    testWidgets('deload sessions are not rated', (tester) async {
      await _pump(tester, _report(action: CoachAction.deload), logged: 1);
      expect(find.text('Coach · deload'), findsOneWidget);
      expect(find.textContaining('feel?'), findsNothing);
    });

    testWidgets('Not now hides the question too', (tester) async {
      await _pump(tester, _report(), logged: 1);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.textContaining('feel?'), findsNothing);
    });
  });
}
