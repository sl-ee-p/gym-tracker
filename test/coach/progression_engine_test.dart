import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/coach/coach_models.dart';
import 'package:gym_app/coach/progression_engine.dart';

final _day0 = DateTime(2026, 7, 1);

/// One session [day] days after day 0, sets as (weight, reps) in kg.
CoachExposure ex(int day, List<(double, int)> sets) => CoachExposure(
  date: _day0.add(Duration(days: day)),
  sets: [for (final (w, r) in sets) CoachSet(weightKg: w, reps: r)],
);

/// [n] identical weekly sessions starting at [startDay].
List<CoachExposure> flat(
  int n,
  List<(double, int)> sets, {
  int startDay = 0,
  int every = 7,
}) => [for (var i = 0; i < n; i++) ex(startDay + i * every, sets)];

class _Case {
  const _Case(
    this.name,
    this.history, {
    this.daysAfterLast = 3,
    this.unit = 'kg',
    this.equipment = const CoachEquipment.stack(),
    required this.status,
    this.action,
    this.weight,
    this.repsMin,
    this.repsMax,
    this.secondSet,
    this.reasons = const [],
    this.deloadWeight,
    this.deloadSessions,
    this.deloadTrigger,
    this.range,
  });

  final String name;
  final List<CoachExposure> history;
  final int daysAfterLast;
  final String unit;
  final CoachEquipment equipment;
  final CoachStatus status;
  final CoachAction? action;
  final double? weight;
  final int? repsMin;
  final int? repsMax;
  final int? secondSet;
  final List<CoachReasonCode> reasons;
  final double? deloadWeight;
  final int? deloadSessions;
  final CoachReasonCode? deloadTrigger;
  final String? range;
}

/// 85 -> 87.5 -> 90 kg, top set always 8 and the 2nd set 7: range 6-8.
final _climb = [
  ex(0, [(85, 8), (85, 7)]),
  ex(7, [(87.5, 8), (87.5, 7)]),
  ex(14, [(90, 8), (90, 7)]),
];

/// Eight weekly sessions with no change: four flat weeks after four flat
/// weeks is a stall.
final _stalled = flat(8, [(90, 8), (90, 6)]);

final _cases = <_Case>[
  // ----- Sparse data -----
  const _Case('no history', [], status: CoachStatus.noData),
  _Case(
    'one session: repeat the weight, one more rep',
    [
      ex(0, [(90, 8), (90, 6)]),
    ],
    status: CoachStatus.baseline,
    action: CoachAction.baseline,
    weight: 90,
    repsMin: 9,
    reasons: [CoachReasonCode.baselineSessions],
    range: '8-12',
  ),
  _Case('sets with no weight or reps are ignored', [
    ex(0, [(0, 10), (60, 0)]),
  ], status: CoachStatus.noData),

  _Case(
    'bodyweight logged as 0.1 kg is not coached',
    flat(6, [(0.1, 10), (0.1, 9)]),
    status: CoachStatus.unsupported,
  ),

  // ----- Normal double progression -----
  _Case(
    'top of range on both sets: add one step',
    _climb,
    status: CoachStatus.progressing,
    action: CoachAction.addWeight,
    weight: 92.5,
    repsMin: 6,
    repsMax: 8,
    reasons: [CoachReasonCode.hitTopOfRange],
    range: '6-8',
  ),
  _Case(
    'a fatigue fragment after the main sets is ignored',
    [
      ..._climb.take(2),
      ex(14, [(90, 8), (90, 7), (80, 2)]),
    ],
    status: CoachStatus.progressing,
    action: CoachAction.addWeight,
    weight: 92.5,
  ),
  _Case(
    '2nd set short: hold, push the 2nd set',
    [
      ..._climb.take(2),
      ex(14, [(90, 8), (90, 5)]),
    ],
    status: CoachStatus.progressing,
    action: CoachAction.repeat,
    weight: 90,
    repsMin: 8,
    secondSet: 6,
    reasons: [CoachReasonCode.secondSetShort],
  ),
  _Case(
    'inside the range: one more rep',
    [
      ..._climb.take(2),
      ex(14, [(90, 6), (90, 6)]),
    ],
    status: CoachStatus.progressing,
    action: CoachAction.addReps,
    weight: 90,
    repsMin: 7,
    repsMax: 8,
    reasons: [CoachReasonCode.climbingReps],
  ),
  _Case(
    'blew past the range: two steps',
    [
      ..._climb,
      ex(21, [(92.5, 11), (92.5, 10)]),
    ],
    status: CoachStatus.progressing,
    action: CoachAction.addWeight,
    weight: 97.5,
  ),
  _Case(
    'below the range once: hold and aim for the bottom',
    [
      ..._climb,
      ex(21, [(92.5, 4), (92.5, 4)]),
    ],
    status: CoachStatus.progressing,
    action: CoachAction.repeat,
    weight: 92.5,
    repsMin: 6,
    reasons: [CoachReasonCode.belowRange],
  ),
  _Case(
    'below the range twice at the same weight: step back',
    [
      ..._climb,
      ex(21, [(92.5, 4), (92.5, 4)]),
      ex(28, [(92.5, 5), (92.5, 4)]),
    ],
    status: CoachStatus.progressing,
    action: CoachAction.stepBack,
    weight: 90,
    repsMin: 7,
    reasons: [CoachReasonCode.missedTwice],
  ),
  _Case(
    'heavy step for a light dumbbell: reps first',
    [
      ex(0, [(8, 10)]),
      ex(7, [(8, 12)]),
      ex(14, [(8, 12)]),
    ],
    status: CoachStatus.progressing,
    action: CoachAction.addReps,
    weight: 8,
    repsMin: 13,
    repsMax: 16,
    reasons: [CoachReasonCode.bigStepRepsFirst, CoachReasonCode.climbingReps],
    range: '10-12',
  ),

  // ----- Rounding -----
  _Case(
    'dumbbell rack: steps learned from used weights (2 kg)',
    [
      ex(0, [(16, 16), (16, 16)]),
      ex(7, [(18, 16), (18, 15)]),
      ex(14, [(20, 16), (20, 16)]),
    ],
    status: CoachStatus.progressing,
    action: CoachAction.addWeight,
    weight: 22,
    range: '13-16',
  ),
  _Case(
    'lb user: suggestions land on 5 lb steps',
    [
      ex(0, [(85 / coachLbsPerKg, 8), (85 / coachLbsPerKg, 7)]),
      ex(7, [(90 / coachLbsPerKg, 8), (90 / coachLbsPerKg, 7)]),
      ex(14, [(95 / coachLbsPerKg, 8), (95 / coachLbsPerKg, 7)]),
    ],
    unit: 'lbs',
    status: CoachStatus.progressing,
    action: CoachAction.addWeight,
    weight: 100,
  ),
  _Case(
    'barbell: rounded to what the bar and plates can load',
    [
      ex(0, [(95, 5), (95, 5)]),
      ex(7, [(97.5, 5), (97.5, 5)]),
      ex(14, [(100, 5), (100, 5)]),
    ],
    equipment: const CoachEquipment.plates(barWeightKg: 20),
    status: CoachStatus.progressing,
    action: CoachAction.addWeight,
    weight: 102.5,
    range: '3-5',
  ),

  // ----- Stall and deload -----
  _Case(
    'eight flat weekly sessions: stalled, one-session deload',
    _stalled,
    status: CoachStatus.stalled,
    action: CoachAction.repeat,
    weight: 90,
    deloadWeight: 80,
    deloadSessions: 1,
    deloadTrigger: CoachReasonCode.stalled,
  ),
  _Case(
    'three flat sessions are not a stall yet',
    flat(3, [(90, 8), (90, 6)]),
    status: CoachStatus.holding,
    action: CoachAction.repeat,
    weight: 90,
  ),
  _Case(
    'two clearly worse sessions: regression triggers a deload',
    [
      ..._climb,
      ex(21, [(90, 5), (90, 4)]),
      ex(28, [(90, 4), (90, 4)]),
    ],
    status: CoachStatus.stalled,
    action: CoachAction.stepBack,
    weight: 87.5,
    deloadTrigger: CoachReasonCode.regressed,
  ),
  _Case(
    'deload done (weekly lifter): resume one step under',
    [
      ..._stalled,
      ex(56, [(80, 6), (80, 6)]),
    ],
    status: CoachStatus.holding,
    action: CoachAction.resume,
    weight: 87.5,
    repsMin: 6,
    repsMax: 8,
    reasons: [CoachReasonCode.deloadDone],
  ),
  _Case(
    'deload half done (twice-weekly lifter): deload again',
    [
      ...flat(14, [(90, 8), (90, 6)], every: 3),
      ex(42, [(80, 6), (80, 6)]),
    ],
    status: CoachStatus.deloading,
    action: CoachAction.deload,
    weight: 80,
    repsMin: 6,
    reasons: [CoachReasonCode.deloadContinue],
  ),
  _Case(
    'after the deload the stall counter starts again',
    [
      ..._stalled,
      ex(56, [(80, 6), (80, 6)]),
      ex(63, [(87.5, 8), (87.5, 7)]),
      ex(70, [(87.5, 8), (87.5, 7)]),
    ],
    status: CoachStatus.holding,
    action: CoachAction.addWeight,
    weight: 90,
  ),
  _Case(
    'a light day without a stall is ignored',
    [
      ..._climb,
      ex(21, [(70, 10), (70, 10)]),
    ],
    status: CoachStatus.progressing,
    action: CoachAction.addWeight,
    weight: 92.5,
    reasons: [
      CoachReasonCode.lightSessionIgnored,
      CoachReasonCode.hitTopOfRange,
    ],
  ),

  // ----- Missed sessions -----
  _Case(
    '20 days off after a stall: the break was the deload',
    _stalled,
    daysAfterLast: 20,
    status: CoachStatus.holding,
    action: CoachAction.repeat,
    weight: 85,
  ),
  _Case(
    '20 days off: 5% lighter',
    _climb,
    daysAfterLast: 20,
    status: CoachStatus.progressing,
    action: CoachAction.addWeight,
    weight: 87.5,
    reasons: [CoachReasonCode.hitTopOfRange, CoachReasonCode.welcomeBack],
  ),
  _Case(
    '40 days off: 10% lighter and no deload call',
    _stalled,
    daysAfterLast: 40,
    status: CoachStatus.holding,
    action: CoachAction.repeat,
    weight: 80,
  ),
  _Case(
    'a long gap in the history resets the stall window',
    [
      ...flat(3, [(90, 8), (90, 6)]),
      ...flat(3, [(90, 8), (90, 6)], startDay: 60),
    ],
    status: CoachStatus.holding,
    action: CoachAction.repeat,
    weight: 90,
  ),
];

void main() {
  const engine = ProgressionEngine();

  group('ProgressionEngine rules', () {
    for (final c in _cases) {
      test(c.name, () {
        final now = c.history.isEmpty
            ? _day0
            : c.history.last.date.add(Duration(days: c.daysAfterLast));
        final r = engine.analyze(
          c.history,
          now: now,
          unit: c.unit,
          equipment: c.equipment,
        );
        final s = r.suggestion;
        expect(r.status, c.status, reason: 'status; got $s');
        if (c.action != null) expect(s?.action, c.action, reason: '$s');
        if (c.weight != null) {
          expect(s?.weight, closeTo(c.weight!, 0.001), reason: '$s');
        }
        if (c.repsMin != null) expect(s?.repsMin, c.repsMin, reason: '$s');
        if (c.repsMax != null) expect(s?.repsMax, c.repsMax, reason: '$s');
        if (c.secondSet != null) {
          expect(s?.secondSetReps, c.secondSet, reason: '$s');
        }
        if (c.reasons.isNotEmpty) {
          expect(s?.reasons.map((x) => x.code), c.reasons);
        }
        if (c.range != null) expect(r.range.toString(), c.range);
        if (c.deloadWeight != null) {
          expect(r.deload?.weight, closeTo(c.deloadWeight!, 0.001));
        }
        if (c.deloadSessions != null) {
          expect(r.deload?.sessions, c.deloadSessions);
        }
        if (c.deloadTrigger != null) {
          expect(r.deload?.trigger.code, c.deloadTrigger);
        }
        if (c.status != CoachStatus.stalled) expect(r.deload, isNull);
      });
    }
  });

  group('ProgressionEngine trend', () {
    test('kg weightKg mirrors the display weight', () {
      final r = engine.analyze(_climb, now: DateTime(2026, 7, 20), unit: 'kg');
      expect(r.suggestion!.weightKg, r.suggestion!.weight);
    });

    test('lb suggestions convert back to kg', () {
      final r = engine.analyze(
        [
          for (var i = 0; i < 3; i++)
            ex(i * 7, [(100 / coachLbsPerKg, 8), (100 / coachLbsPerKg, 8)]),
        ],
        now: DateTime(2026, 7, 20),
        unit: 'lbs',
      );
      expect(r.suggestion!.weight, 105);
      expect(r.suggestion!.weightKg, closeTo(105 / coachLbsPerKg, 1e-6));
    });

    test('e1RM uses Epley and the trend averages the last three', () {
      final r = engine.analyze(_climb, now: DateTime(2026, 7, 20), unit: 'kg');
      expect(r.showsOneRepMax, isTrue);
      expect(r.trend.map((p) => p.valueKg), [
        for (final w in [85.0, 87.5, 90.0]) w * (1 + 8 / 30),
      ]);
      expect(r.trend.last.averageKg, closeTo(87.5 * (1 + 8 / 30), 1e-9));
    });

    test('high-rep work shows a strength index, not a 1RM', () {
      final r = engine.analyze(
        flat(3, [(90, 16), (90, 16)]),
        now: DateTime(2026, 7, 20),
        unit: 'kg',
      );
      expect(r.showsOneRepMax, isFalse);
      expect(r.trend.last.valueKg, closeTo(90 * (1 + 16 / 30), 1e-9));
    });

    test('change is measured against about four weeks earlier', () {
      final history = [
        for (var i = 0; i < 6; i++) ex(i * 7, [(80.0 + i * 2.5, 8)]),
      ];
      final r = engine.analyze(history, now: DateTime(2026, 8, 10), unit: 'kg');
      final vals = [for (var i = 0; i < 6; i++) 80.0 + i * 2.5];
      double avg(int i) =>
          vals.sublist(i - 2, i + 1).reduce((a, b) => a + b) / 3;
      // Last session is day 35; four weeks earlier is day 7 (index 1),
      // whose average covers indices 0..1.
      final then = (vals[0] + vals[1]) / 2;
      expect(r.changePercent, closeTo(avg(5) / then - 1, 1e-9));
    });

    test('the trend keeps at most 12 points', () {
      final r = engine.analyze(
        flat(20, [(50, 10)], every: 3),
        now: DateTime(2026, 9, 1),
        unit: 'kg',
      );
      expect(r.trend, hasLength(12));
      expect(r.exposures, 20);
    });
  });
}
