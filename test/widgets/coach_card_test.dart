// The Coach card's states, fed by a fake CoachService so each test pins one
// CoachReport: loading, empty, unsupported, baseline, progressing (with the
// "Why?" sheet) and a stall with a deload suggestion.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/coach/coach_models.dart';
import 'package:gym_app/l10n/app_localizations.dart';
import 'package:gym_app/models/exercise.dart';
import 'package:gym_app/providers/coach_provider.dart';
import 'package:gym_app/services/coach_service.dart';
import 'package:gym_app/theme/app_theme.dart';
import 'package:gym_app/widgets/coach/coach_card.dart';
import 'package:provider/provider.dart';

class _FakeService extends CoachService {
  _FakeService(this.result);
  final Future<CoachReport> result;

  @override
  Future<CoachReport> reportFor(
    Exercise exercise, {
    required String unit,
    required double defaultBarWeightKg,
    DateTime? now,
  }) => result;
}

final _exercise = Exercise(id: 1, name: 'Chest Press', categoryId: 1);
final _day = DateTime(2026, 10, 1);

List<CoachTrendPoint> _trend(List<double> values) => [
  for (var i = 0; i < values.length; i++)
    CoachTrendPoint(
      date: _day.add(Duration(days: 7 * i)),
      valueKg: values[i],
      averageKg: values[i],
    ),
];

CoachReport _report(
  CoachStatus status, {
  CoachSuggestion? suggestion,
  DeloadAdvice? deload,
  int exposures = 6,
  bool learned = true,
  int feedbackCount = 0,
}) => CoachReport(
  status: status,
  range: RepRange(6, 8, learned: learned),
  step: 2.5,
  unit: 'kg',
  exposures: exposures,
  suggestion: suggestion,
  deload: deload,
  trend: _trend([108, 110, 111, 112.5, 114]),
  changePercent: 0.031,
  lastTopSet: const CoachSet(weightKg: 90, reps: 8),
  stalledSessions: 5,
  feedbackCount: feedbackCount,
);

const _addWeight = CoachSuggestion(
  action: CoachAction.addWeight,
  weight: 92.5,
  weightKg: 92.5,
  repsMin: 6,
  repsMax: 8,
  reasons: [
    CoachReason(CoachReasonCode.hitTopOfRange, weight: 90, reps: 8, target: 8),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  Future<CoachReport> result, {
  bool enabled = true,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) =>
          CoachProvider(service: _FakeService(result))
            ..update(unit: 'kg', defaultBarWeightKg: 20, enabled: enabled),
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: CoachCard(exercise: _exercise)),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('switched off in Settings: shows nothing', (tester) async {
    await _pump(
      tester,
      Future.value(_report(CoachStatus.progressing, suggestion: _addWeight)),
      enabled: false,
    );
    expect(find.text('Coach'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('shows a skeleton while the first report loads', (tester) async {
    final pending = Completer<CoachReport>();
    await _pump(tester, pending.future);
    expect(find.text('Coach'), findsOneWidget);
    expect(find.text('Next session'), findsNothing);
    pending.complete(_report(CoachStatus.progressing, suggestion: _addWeight));
    await tester.pumpAndSettle();
    expect(find.text('Next session'), findsOneWidget);
  });

  testWidgets('no history: empty state', (tester) async {
    await _pump(
      tester,
      Future.value(_report(CoachStatus.noData, exposures: 0)),
    );
    expect(find.text('No sessions yet'), findsOneWidget);
    expect(find.text('Why?'), findsNothing);
  });

  testWidgets('unsupported exercise explains itself', (tester) async {
    await _pump(tester, Future.value(_report(CoachStatus.unsupported)));
    expect(find.textContaining('weight × reps exercises'), findsOneWidget);
  });

  testWidgets('baseline shows progress and a suggestion', (tester) async {
    await _pump(
      tester,
      Future.value(
        _report(
          CoachStatus.baseline,
          exposures: 2,
          learned: false,
          suggestion: const CoachSuggestion(
            action: CoachAction.baseline,
            weight: 90,
            weightKg: 90,
            repsMin: 9,
            repsMax: 9,
            reasons: [
              CoachReason(
                CoachReasonCode.baselineSessions,
                sessions: 2,
                target: 3,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Building your baseline'), findsOneWidget);
    expect(find.textContaining('2 of 3 sessions logged'), findsOneWidget);
    expect(find.text('90 kg × 9'), findsOneWidget);
    expect(find.textContaining('until you have 3 sessions'), findsOneWidget);
  });

  testWidgets('progressing: 1RM, change, suggestion and the Why sheet', (
    tester,
  ) async {
    await _pump(
      tester,
      Future.value(_report(CoachStatus.progressing, suggestion: _addWeight)),
    );
    expect(find.text('Progressing'), findsOneWidget);
    expect(find.text('Estimated 1RM'), findsOneWidget);
    expect(find.text('114 kg'), findsOneWidget);
    expect(
      find.textContaining('+3% in 4 weeks', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('92.5 kg × 6–8'), findsOneWidget);
    expect(find.textContaining('Time to add weight'), findsOneWidget);

    await tester.ensureVisible(find.text('Why?'));
    await tester.tap(find.text('Why?'));
    await tester.pumpAndSettle();
    expect(find.text('Why this suggestion'), findsOneWidget);
    expect(find.textContaining('Weight step 2.5 kg'), findsOneWidget);
    // No ratings yet: the sheet says how to give some.
    expect(find.text('What the coach learned'), findsOneWidget);
    expect(find.textContaining('rate the suggestion'), findsOneWidget);
    expect(find.text('Tuned to your ratings'), findsNothing);
  });

  testWidgets('tuned by ratings: the card says so and the sheet explains', (
    tester,
  ) async {
    const tuned = CoachSuggestion(
      action: CoachAction.repeat,
      weight: 90,
      weightKg: 90,
      repsMin: 6,
      repsMax: 8,
      secondSetReps: 8,
      reasons: [
        CoachReason(
          CoachReasonCode.feedbackAdjusted,
          sessions: 4,
          reps: 3,
          direction: -1,
        ),
        CoachReason(CoachReasonCode.secondSetShort, reps: 7, target: 8),
      ],
    );
    await _pump(
      tester,
      Future.value(
        _report(CoachStatus.holding, suggestion: tuned, feedbackCount: 4),
      ),
    );
    expect(find.text('Tuned to your ratings'), findsOneWidget);
    // The headline stays the rule that decided the suggestion.
    expect(find.textContaining('set 2 needs 8 reps'), findsOneWidget);

    await tester.ensureVisible(find.text('Why?'));
    await tester.tap(find.text('Why?'));
    await tester.pumpAndSettle();
    expect(find.text('What the coach learned'), findsOneWidget);
    expect(
      find.textContaining('You rated 3 of your last 4 suggestions too hard'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '4 ratings of this exercise so far. Weight goes up '
        'more carefully',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a "too hard" last session is the headline', (tester) async {
    const held = CoachSuggestion(
      action: CoachAction.repeat,
      weight: 90,
      weightKg: 90,
      repsMin: 6,
      repsMax: 8,
      reasons: [
        CoachReason(CoachReasonCode.hitTopOfRange, weight: 90, reps: 8),
        CoachReason(CoachReasonCode.lastRating, direction: -1),
      ],
    );
    await _pump(
      tester,
      Future.value(
        _report(CoachStatus.holding, suggestion: held, feedbackCount: 1),
      ),
    );
    expect(
      find.text(
        'You rated last session too hard, so the weight stays the same.',
      ),
      findsOneWidget,
    );
    expect(find.text('Tuned to your ratings'), findsOneWidget);
  });

  testWidgets('stalled: deload banner with the advice', (tester) async {
    await _pump(
      tester,
      Future.value(
        _report(
          CoachStatus.stalled,
          suggestion: const CoachSuggestion(
            action: CoachAction.repeat,
            weight: 90,
            weightKg: 90,
            repsMin: 8,
            repsMax: 8,
            secondSetReps: 7,
          ),
          deload: const DeloadAdvice(
            weight: 80,
            weightKg: 80,
            reps: 6,
            sessions: 1,
            trigger: CoachReason(CoachReasonCode.stalled, sessions: 5),
          ),
        ),
      ),
    );
    expect(find.text('Stalled'), findsOneWidget);
    expect(find.text('No progress for 5 sessions'), findsOneWidget);
    expect(
      find.textContaining('Deload suggested: 80 kg × 6 for 1 session'),
      findsOneWidget,
    );
    expect(find.text('Set 2: aim for 7+'), findsOneWidget);
  });
}
