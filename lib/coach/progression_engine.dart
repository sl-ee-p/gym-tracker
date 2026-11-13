import 'dart:math' as math;

import '../models/analytics.dart';
import 'coach_models.dart';
import 'load_grid.dart';

/// Every tunable threshold of the coach, so the backtest can try variants.
/// The defaults are the rules in docs/COACH.md.
class CoachConfig {
  const CoachConfig({
    this.baselineExposures = 3,
    this.rangeWindow = 8,
    this.rangePercentile = 0.75,
    this.defaultRange = const RepRange(8, 12, learned: false),
    this.secondSetSlack = 1,
    this.doubleStepExtraReps = 3,
    this.bigStepFraction = 0.125,
    this.bigStepExtraReps = 4,
    this.ladderWindowDays = 84,
    this.bestWindowDays = 84,
    this.newBestMargin = 0.005,
    this.stallExposures = 5,
    this.stallDays = 21,
    this.regressionWindowDays = 42,
    this.regressionDrop = 0.05,
    this.lightSessionRatio = 0.925,
    this.deloadFraction = 0.10,
    this.shortBreakDays = 14,
    this.shortBreakCut = 0.05,
    this.longBreakDays = 28,
    this.longBreakCut = 0.10,
    this.progressingLookback = 3,
    this.minRealWeightKg = 1,
    this.recentLightDays = 14,
    this.trendLength = 12,
    this.averageWindow = 3,
    this.changeLookbackDays = 28,
    this.feedbackWindow = 6,
    this.feedbackDecay = 0.75,
    this.feedbackFullCount = 3,
    this.feedbackThreshold = 1,
    this.loggedSignalWeight = 0.5,
  });

  /// Sessions needed before trend, stall and the learned rep range apply.
  final int baselineExposures;

  /// The rep range is learned from the top sets of this many recent sessions.
  final int rangeWindow;
  final double rangePercentile;
  final RepRange defaultRange;

  /// The 2nd set must reach top-of-range minus this before weight goes up.
  final int secondSetSlack;

  /// Beating the top of the range by this many reps earns two steps.
  final int doubleStepExtraReps;

  /// A step bigger than this fraction of the weight extends the range.
  final double bigStepFraction;
  final int bigStepExtraReps;
  final int ladderWindowDays;

  /// A "new best" is compared with the best of this many days before it.
  final int bestWindowDays;
  final double newBestMargin;

  /// A stall compares the recent block of sessions with the block before
  /// it. A block spans [stallDays] (so it holds more sessions for lifts
  /// trained more often) and never fewer than [stallExposures] sessions.
  final int stallExposures;
  final int stallDays;
  final int regressionWindowDays;
  final double regressionDrop;

  /// A session whose top weight is at or below this fraction of the recent
  /// median is light: a deload if one was due, otherwise ignored.
  final double lightSessionRatio;
  final double deloadFraction;
  final int shortBreakDays;
  final double shortBreakCut;
  final int longBreakDays;
  final double longBreakCut;
  final int progressingLookback;

  /// Below this every working weight is taken as a placeholder.
  final double minRealWeightKg;

  /// No deload call within this many days of a light session.
  final int recentLightDays;
  final int trendLength;
  final int averageWindow;
  final int changeLookbackDays;

  /// Ratings counted for the calibration: the most recent this many.
  final int feedbackWindow;

  /// Each older rating counts this much less than the one after it.
  final double feedbackDecay;

  /// Fewer ratings than this count proportionally less, so one tap can't
  /// swing the rules on its own (the last rating still acts directly).
  final int feedbackFullCount;

  /// The calibration has to reach this (either way) to change the rules.
  final double feedbackThreshold;

  /// How much what was actually logged at the rated weight (top set above
  /// or below the target) adds to a rating.
  final double loggedSignalWeight;
}

/// The result of [ProgressionEngine]'s feedback calibration.
class _Calibration {
  const _Calibration(this.value, this.counted, this.agreeing);

  static const none = _Calibration(0, 0, 0);

  /// -2 (ease off) to 2 (push harder).
  final double value;
  final int counted;

  /// Ratings in [counted] that point the same way as [value].
  final int agreeing;
}

/// One exposure reduced to what the rules need.
class _Session {
  _Session(this.date, this.top, this.second, this.working);

  final DateTime date;

  /// First set at the heaviest non-fragment weight.
  final CoachSet top;

  /// Next non-fragment set at the top weight, if any.
  final CoachSet? second;

  /// Sets that aren't fatigue fragments.
  final List<CoachSet> working;

  double? value;

  /// Mean e1RM of the two best sets: unlike [value] it rises when the 2nd
  /// set gains reps, which is how a double progression moves.
  double? score;
  bool light = false;
  bool deload = false;
  bool newBest = false;
  bool flagged = false;
  bool stalled = false;
  bool regressed = false;
  double regressionPercent = 0;
  int stallCount = 0;
}

/// The progressive-overload rules from docs/COACH.md as a pure function of
/// history. Stateless: deloads and layoffs are recognised from the logged
/// weights, so the result survives backup/restore and needs no schema.
class ProgressionEngine {
  const ProgressionEngine([this.config = const CoachConfig()]);

  final CoachConfig config;

  /// [feedback] holds this exercise's ratings in any order. [prior] is the
  /// calibration to lean on while it has few: the service passes half the
  /// lifter's average over all exercises. Without either, the result is
  /// exactly the stateless rules.
  CoachReport analyze(
    List<CoachExposure> history, {
    required DateTime now,
    required String unit,
    CoachEquipment equipment = const CoachEquipment.stack(),
    List<CoachFeedback> feedback = const [],
    double prior = 0,
  }) {
    final c = config;
    double toUnit(double kg) =>
        _round2(unit == 'lbs' ? kg * coachLbsPerKg : kg);
    double toKg(double w) => unit == 'lbs' ? w / coachLbsPerKg : w;

    final sessions = <_Session>[];
    final sorted = [...history]..sort((a, b) => a.date.compareTo(b.date));
    for (final e in sorted) {
      final s = _summarise(e);
      if (s != null) sessions.add(s);
    }

    if (sessions.isEmpty) {
      return CoachReport(
        status: CoachStatus.noData,
        range: c.defaultRange,
        step: equipment.plateLoaded
            ? LoadGrid.learn(
                usedWeights: const [],
                unit: unit,
                equipment: equipment,
              ).step
            : LoadGrid.defaultStep(unit),
        unit: unit,
        exposures: 0,
      );
    }

    // Bodyweight lifts logged with a token weight (0.1 kg) are not weight x
    // reps work the coach can steer.
    final recentMax = sessions.reversed
        .take(c.rangeWindow)
        .expand((s) => s.working)
        .map((s) => s.weightKg)
        .reduce(math.max);
    if (recentMax < c.minRealWeightKg) {
      return CoachReport(
        status: CoachStatus.unsupported,
        range: c.defaultRange,
        step: LoadGrid.defaultStep(unit),
        unit: unit,
        exposures: sessions.length,
      );
    }

    final range = _learnRange(sessions);
    final last = sessions.last;
    final ladderFrom = last.date.subtract(Duration(days: c.ladderWindowDays));
    final grid = LoadGrid.learn(
      usedWeights: [
        for (final s in sessions)
          if (!s.date.isBefore(ladderFrom))
            for (final set in s.working) toUnit(set.weightKg),
      ],
      unit: unit,
      equipment: equipment,
    );

    final showsOneRepMax = range.hi <= 12;
    final repCap = showsOneRepMax ? 12 : 20;
    // A one-set session of a lift normally done for 2+ sets has no fair
    // score: its single best set would beat every normal session's average.
    final usualSets = _median([
      for (final s in sessions) s.working.length.toDouble(),
    ]);
    for (final s in sessions) {
      double? best;
      final values = <double>[];
      for (final set in s.working) {
        final v = estimateOneRepMax(
          set.weightKg,
          set.reps,
          maxMeaningfulReps: repCap,
        );
        if (v != null && (best == null || v > best)) best = v;
        if (v != null) values.add(v);
      }
      s.value = best;
      values.sort((a, b) => b.compareTo(a));
      s.score = values.isEmpty || (usualSets >= 2 && values.length < 2)
          ? null
          : values.length == 1
          ? values.first
          : (values[0] + values[1]) / 2;
    }

    final deloadLength = _replay(sessions, range);
    final calibration = _calibrate(feedback, sessions, prior);
    final easeOff = calibration.value <= -c.feedbackThreshold;
    final push = calibration.value >= c.feedbackThreshold;
    final secondSetSlack = easeOff
        ? 0
        : push
        ? c.secondSetSlack + 1
        : c.secondSetSlack;
    final doubleStepExtraReps = easeOff
        ? 1 <<
              20 // never two steps at once
        : push
        ? c.doubleStepExtraReps - 1
        : c.doubleStepExtraReps;

    // ----- Trend -----
    final valued = sessions.where((s) => s.value != null).toList();
    final trend = <CoachTrendPoint>[];
    for (var i = 0; i < valued.length; i++) {
      final from = math.max(0, i - c.averageWindow + 1);
      final window = valued.sublist(from, i + 1);
      final avg =
          window.map((s) => s.value!).reduce((a, b) => a + b) / window.length;
      trend.add(
        CoachTrendPoint(
          date: valued[i].date,
          valueKg: valued[i].value!,
          averageKg: avg,
        ),
      );
    }
    double? change;
    if (trend.length >= 2) {
      final cutoff = trend.last.date.subtract(
        Duration(days: c.changeLookbackDays),
      );
      final earlier = trend.lastWhere(
        (p) => !p.date.isAfter(cutoff),
        orElse: () => trend.first,
      );
      if (!identical(earlier, trend.last) && earlier.averageKg > 0) {
        change = trend.last.averageKg / earlier.averageKg - 1;
      }
    }
    final shownTrend = trend.length > c.trendLength
        ? trend.sublist(trend.length - c.trendLength)
        : trend;

    // ----- Suggestion -----
    final reasons = <CoachReason>[];
    CoachSuggestion make(
      CoachAction action,
      double w,
      int lo,
      int hi, {
      int? second,
    }) {
      return CoachSuggestion(
        action: action,
        weight: w,
        weightKg: toKg(w),
        repsMin: lo,
        repsMax: math.max(lo, hi),
        secondSetReps: second,
        reasons: List.unmodifiable(reasons),
      );
    }

    final daysSince = _days(last.date, now);
    CoachStatus status;
    CoachSuggestion suggestion;
    DeloadAdvice? deload;

    if (sessions.length < c.baselineExposures) {
      status = CoachStatus.baseline;
      reasons.add(
        CoachReason(
          CoachReasonCode.baselineSessions,
          sessions: sessions.length,
          target: c.baselineExposures,
        ),
      );
      final w = toUnit(last.top.weightKg);
      suggestion = make(
        CoachAction.baseline,
        w,
        last.top.reps + 1,
        last.top.reps + 1,
      );
    } else if (last.deload) {
      // Mid-deload or just finished one.
      var done = 0;
      for (var i = sessions.length - 1; i >= 0 && sessions[i].deload; i--) {
        done++;
      }
      final pre = _preDeloadWeight(sessions);
      if (done < deloadLength) {
        status = CoachStatus.deloading;
        reasons.add(
          CoachReason(
            CoachReasonCode.deloadContinue,
            sessions: done,
            target: deloadLength,
          ),
        );
        suggestion = make(
          CoachAction.deload,
          toUnit(last.top.weightKg),
          range.lo,
          range.lo,
        );
      } else {
        status = CoachStatus.holding;
        final preU = toUnit(pre);
        reasons.add(CoachReason(CoachReasonCode.deloadDone, weight: preU));
        suggestion = make(
          CoachAction.resume,
          grid.down(preU, preU - grid.step),
          range.lo,
          range.hi,
        );
      }
    } else {
      // Normal double progression from the last non-light session.
      // Only a one-off light session is ignored; two in a row are the new
      // normal and the suggestion builds on them.
      final oneOffLight =
          last.light &&
          sessions.length > 1 &&
          !sessions[sessions.length - 2].light;
      final baseIndex = oneOffLight ? sessions.length - 2 : sessions.length - 1;
      final base = sessions[baseIndex < 0 ? sessions.length - 1 : baseIndex];
      if (!identical(base, last)) {
        reasons.add(
          CoachReason(
            CoachReasonCode.lightSessionIgnored,
            weight: toUnit(last.top.weightKg),
          ),
        );
      }
      final w = toUnit(base.top.weightKg);
      final r = base.top.reps;
      var hi = range.hi;
      final lo = range.lo;
      if (w > 0 && grid.step / w > c.bigStepFraction) {
        hi += c.bigStepExtraReps;
        reasons.add(
          CoachReason(
            CoachReasonCode.bigStepRepsFirst,
            step: grid.step,
            target: hi,
          ),
        );
      }
      final r2 = base.second?.reps;
      if (easeOff || push) {
        reasons.add(
          CoachReason(
            CoachReasonCode.feedbackAdjusted,
            sessions: calibration.counted,
            reps: calibration.agreeing,
            direction: push ? 1 : -1,
          ),
        );
      }
      // Pushing: one rep short of the top is close enough to add weight.
      final topReached = push ? r >= hi - 1 : r >= hi;

      if (topReached && (r2 == null || r2 >= hi - secondSetSlack)) {
        reasons.add(
          CoachReason(
            CoachReasonCode.hitTopOfRange,
            weight: w,
            reps: r,
            target: hi,
          ),
        );
        final steps = r >= hi + doubleStepExtraReps ? 2 : 1;
        suggestion = make(
          CoachAction.addWeight,
          grid.up(w, steps: steps),
          lo,
          range.hi,
        );
      } else if (r >= hi) {
        reasons.add(
          CoachReason(
            CoachReasonCode.secondSetShort,
            reps: r2,
            target: hi - secondSetSlack,
          ),
        );
        suggestion = make(CoachAction.repeat, w, hi, hi, second: r2! + 1);
      } else if (r >= lo) {
        reasons.add(
          CoachReason(CoachReasonCode.climbingReps, reps: r, target: hi),
        );
        suggestion = make(CoachAction.addReps, w, r + 1, hi);
      } else {
        final prevIndex = sessions.lastIndexWhere(
          (s) => !identical(s, base),
          baseIndex < 0 ? sessions.length - 1 : baseIndex,
        );
        final prev = prevIndex < 0 ? null : sessions[prevIndex];
        final missedBefore =
            prev != null &&
            (toUnit(prev.top.weightKg) - w).abs() < 0.01 &&
            prev.top.reps < lo;
        // Easing off: one miss is enough to step back.
        if (missedBefore || easeOff) {
          reasons.add(
            missedBefore
                ? CoachReason(CoachReasonCode.missedTwice, target: lo)
                : CoachReason(
                    CoachReasonCode.missedEaseOff,
                    reps: r,
                    target: lo,
                  ),
          );
          suggestion = make(
            CoachAction.stepBack,
            grid.down(w, w - grid.step),
            hi - 1,
            hi - 1,
          );
        } else {
          reasons.add(
            CoachReason(CoachReasonCode.belowRange, reps: r, target: lo),
          );
          suggestion = make(CoachAction.repeat, w, lo, range.hi);
        }
      }

      // The rating of the session this builds on acts directly: "too easy"
      // after a hold means the weight goes up now, "too hard" after a jump
      // means it stays where it is.
      final rated = _ratingOf(feedback, base);
      if (rated == CoachRating.tooEasy &&
          (suggestion.action == CoachAction.repeat ||
              suggestion.action == CoachAction.addReps)) {
        reasons.add(
          const CoachReason(CoachReasonCode.lastRating, direction: 1),
        );
        suggestion = make(CoachAction.addWeight, grid.up(w), lo, range.hi);
      } else if (rated == CoachRating.tooHard &&
          suggestion.action == CoachAction.addWeight) {
        reasons.add(
          const CoachReason(CoachReasonCode.lastRating, direction: -1),
        );
        suggestion = make(CoachAction.repeat, w, lo, range.hi);
      }

      // Hitting the top of the range means the weight should go up, not
      // that the lifter needs a deload.
      // A light session in the last two weeks means the lifter already
      // backed off; calling a deload on top of it would be noise.
      final recentLight = sessions.any(
        (s) => s.light && _days(s.date, last.date) <= c.recentLightDays,
      );
      final flaggedNow =
          base.flagged &&
          !recentLight &&
          suggestion.action != CoachAction.addWeight;
      if (flaggedNow) {
        status = CoachStatus.stalled;
        final trigger = base.stalled
            ? CoachReason(CoachReasonCode.stalled, sessions: base.stallCount)
            : CoachReason(
                CoachReasonCode.regressed,
                percent: base.regressionPercent,
              );
        final dw = grid.down(w, w * (1 - c.deloadFraction));
        deload = DeloadAdvice(
          weight: dw,
          weightKg: toKg(dw),
          reps: range.lo,
          sessions: _deloadLengthAt(sessions, sessions.length),
          trigger: trigger,
        );
      } else {
        final recent = sessions
            .where((s) => !s.light)
            .toList()
            .reversed
            .take(c.progressingLookback);
        status = recent.any((s) => s.newBest)
            ? CoachStatus.progressing
            : CoachStatus.holding;
      }
    }

    // ----- Layoffs -----
    final usualGap = _usualGap(sessions);
    final shortBreak = math.max(c.shortBreakDays, 2 * usualGap);
    final longBreak = math.max(c.longBreakDays, 4 * usualGap);
    if (status != CoachStatus.baseline && daysSince > shortBreak) {
      final cut = daysSince > longBreak ? c.longBreakCut : c.shortBreakCut;
      reasons.add(
        CoachReason(CoachReasonCode.welcomeBack, days: daysSince, percent: cut),
      );
      final from = suggestion.weight;
      suggestion = CoachSuggestion(
        action: suggestion.action,
        weight: grid.down(from, from * (1 - cut)),
        weightKg: toKg(grid.down(from, from * (1 - cut))),
        repsMin: suggestion.repsMin,
        repsMax: suggestion.repsMax,
        secondSetReps: suggestion.secondSetReps,
        reasons: List.unmodifiable(reasons),
      );
      // The break was the deload; start counting afresh.
      deload = null;
      if (status == CoachStatus.stalled) status = CoachStatus.holding;
    }

    return CoachReport(
      status: status,
      suggestion: suggestion,
      deload: deload,
      range: range,
      step: grid.step,
      unit: unit,
      exposures: sessions.length,
      trend: shownTrend,
      showsOneRepMax: showsOneRepMax,
      changePercent: change,
      lastTopSet: last.top,
      stalledSessions: last.light ? 0 : last.stallCount,
      calibration: calibration.value,
      feedbackCount: calibration.counted,
    );
  }

  /// The rating given to [session]'s workout, if any. Deloads are never
  /// rated: an easy deload is the point of it.
  CoachRating? _ratingOf(List<CoachFeedback> feedback, _Session session) {
    for (final f in feedback.reversed) {
      if (f.action != CoachAction.deload && _days(f.date, session.date) == 0) {
        return f.rating;
      }
    }
    return null;
  }

  /// Turns the recent ratings into one number from -2 to 2. Each rating is
  /// -1/0/1, plus [CoachConfig.loggedSignalWeight] when the top set at the
  /// rated weight landed above or below the target: "too hard" with every
  /// rep made counts for less, "about right" with reps missed leans easier.
  _Calibration _calibrate(
    List<CoachFeedback> feedback,
    List<_Session> sessions,
    double prior,
  ) {
    final c = config;
    final rated = feedback.where((f) => f.action != CoachAction.deload).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final recent = rated.take(c.feedbackWindow).toList();
    if (recent.isEmpty) {
      return prior == 0
          ? _Calibration.none
          : _Calibration(prior.clamp(-2.0, 2.0), 0, 0);
    }
    var sum = 0.0;
    var weights = 0.0;
    var weight = 1.0;
    final signals = <double>[];
    for (final f in recent) {
      var signal = f.rating.value.toDouble();
      for (final s in sessions) {
        if (_days(f.date, s.date) != 0) continue;
        final atWeight =
            (s.top.weightKg - f.weightKg).abs() <=
            math.max(0.3, f.weightKg * 0.01);
        if (atWeight && s.top.reps > f.repsMax) {
          signal += c.loggedSignalWeight;
        } else if (atWeight && s.top.reps < f.repsMin) {
          signal -= c.loggedSignalWeight;
        }
        break;
      }
      signals.add(signal);
      sum += weight * signal;
      weights += weight;
      weight *= c.feedbackDecay;
    }
    final confidence = math.min(1.0, recent.length / c.feedbackFullCount);
    final value = (2 * (sum / weights) * confidence + prior * (1 - confidence))
        .clamp(-2.0, 2.0);
    final agreeing = value == 0
        ? 0
        : signals.where((s) => s != 0 && s.sign == value.sign).length;
    return _Calibration(value, recent.length, agreeing);
  }

  /// Drops non-working sets and fatigue fragments (sets under half the
  /// session's best reps), then picks the top set.
  _Session? _summarise(CoachExposure e) {
    final sets = e.sets.where((s) => s.weightKg > 0 && s.reps >= 1).toList();
    if (sets.isEmpty) return null;
    final maxReps = sets.map((s) => s.reps).reduce(math.max);
    final working = sets.where((s) => s.reps * 2 >= maxReps).toList();
    final topWeight = working.map((s) => s.weightKg).reduce(math.max);
    final topIndex = working.indexWhere((s) => s.weightKg == topWeight);
    CoachSet? second;
    for (var i = topIndex + 1; i < working.length; i++) {
      if ((working[i].weightKg - topWeight).abs() < 0.001) {
        second = working[i];
        break;
      }
    }
    return _Session(e.date, working[topIndex], second, working);
  }

  RepRange _learnRange(List<_Session> sessions) {
    final c = config;
    if (sessions.length < c.baselineExposures) return c.defaultRange;
    final recent = sessions.length > c.rangeWindow
        ? sessions.sublist(sessions.length - c.rangeWindow)
        : sessions;
    final reps = recent.map((s) => s.top.reps).toList()..sort();
    final int rank = (c.rangePercentile * reps.length).ceil().clamp(
      1,
      reps.length,
    );
    final hi = reps[rank - 1];
    final int lo = math.max(1, hi - math.max(2, (0.2 * hi).round()));
    return RepRange(lo, hi, learned: true);
  }

  /// Walks history oldest-first, marking light sessions, deloads, new bests,
  /// stalls and regressions. Returns the deload length in force at the end.
  int _replay(List<_Session> sessions, RepRange range) {
    final c = config;
    var start = 0; // first index of the current comparison window
    var deloadDone = 0;
    var deloadLength = 1;
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      // A break long enough to earn a "welcome back" cut also acts as a
      // deload: the comparison window starts again after it.
      if (i > 0 &&
          _days(sessions[i - 1].date, s.date) >
              math.max(
                c.shortBreakDays,
                2 * _usualGap(sessions.sublist(0, i)),
              )) {
        start = i;
      }

      final prevTops = <double>[
        for (var j = i - 1; j >= 0 && j >= i - 8; j--) sessions[j].top.weightKg,
      ].take(4).toList();
      if (prevTops.length >= 2 &&
          s.top.weightKg <= c.lightSessionRatio * _median(prevTops)) {
        s.light = true;
        final prev = i > 0 ? sessions[i - 1] : null;
        final continuing =
            prev != null && prev.deload && deloadDone < deloadLength;
        final due = _lastNonLight(sessions, i)?.flagged ?? false;
        if (continuing || (due && !(prev?.deload ?? false))) {
          if (!continuing) {
            deloadDone = 0;
            deloadLength = _deloadLengthAt(sessions, i);
          }
          s.deload = true;
          deloadDone++;
          if (deloadDone >= deloadLength) start = i + 1;
        }
        continue;
      }

      final window = <_Session>[
        for (var j = start; j < i; j++)
          if (!sessions[j].light && sessions[j].score != null) sessions[j],
      ];
      final bestFrom = s.date.subtract(Duration(days: c.bestWindowDays));
      final priorBest = window
          .where((p) => !p.date.isBefore(bestFrom))
          .map((p) => p.score!)
          .fold<double?>(null, (m, v) => m == null || v > m ? v : m);
      // The first session of a window is the baseline: neither a best nor
      // a step towards a stall.
      final baseline = priorBest == null;
      s.newBest =
          !baseline &&
          s.score != null &&
          s.score! > priorBest * (1 + c.newBestMargin);
      final prevCounted = _lastNonLight(sessions, i);
      final prevInWindow =
          prevCounted != null && sessions.indexOf(prevCounted) >= start;
      s.stallCount = s.newBest || baseline
          ? 0
          : (prevInWindow ? prevCounted.stallCount : 0) + 1;
      // Stall: the recent block is no better than the block before it.
      final counted = [...window, if (s.score != null) s];
      final recentFrom = s.date.subtract(Duration(days: c.stallDays));
      final block = math.max(
        c.stallExposures,
        counted.where((p) => p.date.isAfter(recentFrom)).length,
      );
      if (s.score != null && counted.length >= 2 * block) {
        double best(Iterable<_Session> xs) =>
            xs.map((p) => p.score!).reduce(math.max);
        final recent = counted.sublist(counted.length - block);
        final before = counted.sublist(
          counted.length - 2 * block,
          counted.length - block,
        );
        s.stalled = best(recent) <= best(before) * (1 + c.newBestMargin);
      }

      // Regression: this and the previous counted session both clearly
      // below the best of the weeks before them.
      if (prevInWindow && s.score != null && prevCounted.score != null) {
        final regFrom = prevCounted.date.subtract(
          Duration(days: c.regressionWindowDays),
        );
        _Session? ref;
        for (final p in window) {
          if (identical(p, prevCounted) || p.date.isBefore(regFrom)) continue;
          if (ref == null || p.score! > ref.score!) ref = p;
        }
        // Regression means doing worse at the same weight. Lighter sessions
        // score lower by design, and a failed attempt at a heavier weight is
        // handled by the rep rules.
        final refWeight = ref?.top.weightKg ?? 0;
        final otherWeight =
            (s.top.weightKg - refWeight).abs() > 0.001 ||
            (prevCounted.top.weightKg - refWeight).abs() > 0.001;
        if (ref != null && !otherWeight) {
          final worst = math.max(s.score!, prevCounted.score!);
          final drop = 1 - worst / ref.score!;
          if (drop >= c.regressionDrop) {
            s.regressed = true;
            s.regressionPercent = drop;
          }
        }
      }
      s.flagged = s.stalled || s.regressed;
    }
    return deloadLength;
  }

  /// One deload session for exercises trained about weekly or less, two for
  /// anything more frequent: roughly a week either way.
  int _deloadLengthAt(List<_Session> sessions, int index) {
    if (index == 0) return 1;
    final ref = sessions[index - 1].date;
    final from = ref.subtract(const Duration(days: 28));
    var count = 0;
    for (var j = index - 1; j >= 0 && sessions[j].date.isAfter(from); j--) {
      count++;
    }
    return count > 4 ? 2 : 1;
  }

  double _preDeloadWeight(List<_Session> sessions) {
    for (var i = sessions.length - 1; i >= 0; i--) {
      if (!sessions[i].light) return sessions[i].top.weightKg;
    }
    return sessions.first.top.weightKg;
  }

  _Session? _lastNonLight(List<_Session> sessions, int before) {
    for (var j = before - 1; j >= 0; j--) {
      if (!sessions[j].light) return sessions[j];
    }
    return null;
  }

  /// Median days between the last few sessions.
  int _usualGap(List<_Session> sessions) {
    final gaps = <double>[
      for (var i = math.max(1, sessions.length - 8); i < sessions.length; i++)
        _days(sessions[i - 1].date, sessions[i].date).toDouble(),
    ];
    return gaps.isEmpty ? 0 : _median(gaps).round();
  }

  static double _median(List<double> xs) {
    final s = [...xs]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  static int _days(DateTime a, DateTime b) => DateTime(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime(a.year, a.month, a.day)).inDays;

  static double _round2(double v) => (v * 100).roundToDouble() / 100;
}
