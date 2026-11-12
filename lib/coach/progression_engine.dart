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
    this.stallExposures = 4,
    this.regressionWindowDays = 42,
    this.regressionDrop = 0.05,
    this.lightSessionRatio = 0.925,
    this.deloadFraction = 0.10,
    this.shortBreakDays = 14,
    this.shortBreakCut = 0.05,
    this.longBreakDays = 28,
    this.longBreakCut = 0.10,
    this.progressingLookback = 3,
    this.trendLength = 12,
    this.averageWindow = 3,
    this.changeLookbackDays = 28,
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

  /// Sessions in a row without a new best that count as a stall.
  final int stallExposures;
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
  final int trendLength;
  final int averageWindow;
  final int changeLookbackDays;
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

  CoachReport analyze(
    List<CoachExposure> history, {
    required DateTime now,
    required String unit,
    CoachEquipment equipment = const CoachEquipment.stack(),
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
    for (final s in sessions) {
      double? best;
      for (final set in s.working) {
        final v = estimateOneRepMax(
          set.weightKg,
          set.reps,
          maxMeaningfulReps: repCap,
        );
        if (v != null && (best == null || v > best)) best = v;
      }
      s.value = best;
    }

    final deloadLength = _replay(sessions, range);

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
      final baseIndex = sessions.lastIndexWhere((s) => !s.light);
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

      if (r >= hi && (r2 == null || r2 >= hi - c.secondSetSlack)) {
        reasons.add(
          CoachReason(
            CoachReasonCode.hitTopOfRange,
            weight: w,
            reps: r,
            target: hi,
          ),
        );
        final steps = r >= hi + c.doubleStepExtraReps ? 2 : 1;
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
            target: hi - c.secondSetSlack,
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
          (s) => !s.light && !identical(s, base),
          baseIndex < 0 ? sessions.length - 1 : baseIndex,
        );
        final prev = prevIndex < 0 ? null : sessions[prevIndex];
        final missedBefore =
            prev != null &&
            (toUnit(prev.top.weightKg) - w).abs() < 0.01 &&
            prev.top.reps < lo;
        if (missedBefore) {
          reasons.add(CoachReason(CoachReasonCode.missedTwice, target: lo));
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

      final flaggedNow = base.flagged;
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
    if (status != CoachStatus.baseline && daysSince > c.shortBreakDays) {
      final cut = daysSince > c.longBreakDays
          ? c.longBreakCut
          : c.shortBreakCut;
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
      if (daysSince > c.longBreakDays) {
        // The layoff was the deload; start counting afresh.
        deload = null;
        if (status == CoachStatus.stalled) status = CoachStatus.holding;
      }
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
    );
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
      if (i > 0 && _days(sessions[i - 1].date, s.date) > c.longBreakDays) {
        start = i;
      }

      final prevTops = <double>[
        for (var j = i - 1; j >= 0 && j >= i - 8; j--)
          if (!sessions[j].light) sessions[j].top.weightKg,
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
          if (!sessions[j].light && sessions[j].value != null) sessions[j],
      ];
      final bestFrom = s.date.subtract(Duration(days: c.bestWindowDays));
      final priorBest = window
          .where((p) => !p.date.isBefore(bestFrom))
          .map((p) => p.value!)
          .fold<double?>(null, (m, v) => m == null || v > m ? v : m);
      // The first session of a window is the baseline: neither a best nor
      // a step towards a stall.
      final baseline = priorBest == null;
      s.newBest =
          !baseline &&
          s.value != null &&
          s.value! > priorBest * (1 + c.newBestMargin);
      final prevCounted = _lastNonLight(sessions, i);
      final prevInWindow =
          prevCounted != null && sessions.indexOf(prevCounted) >= start;
      s.stallCount = s.newBest || baseline
          ? 0
          : (prevInWindow ? prevCounted.stallCount : 0) + 1;
      s.stalled = s.stallCount >= c.stallExposures;

      // Regression: this and the previous counted session both clearly
      // below the best of the weeks before them.
      if (prevInWindow && s.value != null && prevCounted.value != null) {
        final regFrom = prevCounted.date.subtract(
          Duration(days: c.regressionWindowDays),
        );
        _Session? ref;
        for (final p in window) {
          if (identical(p, prevCounted) || p.date.isBefore(regFrom)) continue;
          if (ref == null || p.value! > ref.value!) ref = p;
        }
        // Only a drop at the same or a lighter weight is regression; a
        // failed attempt at a heavier weight is handled by the rep rules.
        final refWeight = ref?.top.weightKg ?? 0;
        final heavier =
            s.top.weightKg > refWeight + 0.001 ||
            prevCounted.top.weightKg > refWeight + 0.001;
        if (ref != null && !heavier) {
          final worst = math.max(s.value!, prevCounted.value!);
          final drop = 1 - worst / ref.value!;
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
