/// Data types for the progressive-overload coach.
///
/// Everything in `lib/coach/` is pure Dart (no Flutter imports) so that
/// `tool/coach_backtest.dart` can replay real history with `dart run`. The
/// engine never produces text: it returns [CoachReason] codes with numbers,
/// and the UI turns them into localised strings. See docs/COACH.md.
library;

/// Same factor as `lib/utils/weight_format.dart`, which can't be imported
/// here because it pulls in `flutter/services`.
const double coachLbsPerKg = 2.20462;

/// One working set: never a warm-up, and partial reps are not counted.
class CoachSet {
  const CoachSet({required this.weightKg, required this.reps});

  final double weightKg;
  final int reps;

  @override
  String toString() => '${weightKg}x$reps';
}

/// One completed workout's working sets for a single exercise, in the order
/// they were logged.
class CoachExposure {
  const CoachExposure({required this.date, required this.sets});

  final DateTime date;
  final List<CoachSet> sets;
}

/// How weight goes on the exercise, which decides how suggestions round.
class CoachEquipment {
  /// Machines, cables and dumbbells: steps are learned from the weights the
  /// lifter has actually used.
  const CoachEquipment.stack() : plateLoaded = false, barWeightKg = 0;

  /// Barbell-style lifts: suggestions are rounded down to what the bar plus
  /// the standard plate set can load.
  const CoachEquipment.plates({required this.barWeightKg}) : plateLoaded = true;

  final bool plateLoaded;
  final double barWeightKg;
}

enum CoachStatus {
  /// No usable sets logged yet.
  noData,

  /// Weights are placeholders (e.g. 0.1 kg for a bodyweight pull-up), so
  /// weight suggestions would be meaningless.
  unsupported,

  /// Fewer than [CoachConfig.baselineExposures] sessions: no trend or stall.
  baseline,

  /// A new best in one of the last few sessions.
  progressing,

  /// No recent best, but not stalled either.
  holding,

  /// Stalled or regressing: a deload is recommended ([CoachReport.deload]).
  stalled,

  /// In the middle of a deload.
  deloading,
}

enum CoachAction {
  baseline,
  addWeight,
  addReps,
  repeat,
  stepBack,
  deload,
  resume,
}

/// Why the coach said what it said. Which fields are set depends on [code].
enum CoachReasonCode {
  /// sessions = logged so far, target = sessions needed.
  baselineSessions,

  /// weight, reps (top set), target = top of the rep range.
  hitTopOfRange,

  /// reps = 2nd set reps, target = what it needs to reach.
  secondSetShort,

  /// reps (top set), target = top of the rep range.
  climbingReps,

  /// reps (top set), target = bottom of the rep range.
  belowRange,

  /// target = bottom of the rep range; missed twice in a row at this weight.
  missedTwice,

  /// step, target = extended top of the range: the weight jump is big
  /// relative to the load, so reps come first.
  bigStepRepsFirst,

  /// sessions = sessions without a new best.
  stalled,

  /// percent = how far the last two sessions fell below the recent best.
  regressed,

  /// sessions = deload sessions done, target = deload length.
  deloadContinue,

  /// weight = the working weight before the deload.
  deloadDone,

  /// weight = the light session's top weight, ignored as a one-off.
  lightSessionIgnored,

  /// days since the last session, percent = reduction applied.
  welcomeBack,

  /// The lifter's ratings changed the rules. sessions = recent ratings
  /// counted, reps = how many of them pointed in [CoachReason.direction]
  /// (1 = too easy, so the coach pushes; -1 = too hard, so it eases off).
  feedbackAdjusted,

  /// The last session was rated: direction 1 = too easy (weight goes up
  /// now), -1 = too hard (the weight holds).
  lastRating,
}

class CoachReason {
  const CoachReason(
    this.code, {
    this.weight,
    this.step,
    this.reps,
    this.target,
    this.sessions,
    this.days,
    this.percent,
    this.direction,
  });

  final CoachReasonCode code;

  /// Weights are in the display unit.
  final double? weight;
  final double? step;
  final int? reps;
  final int? target;
  final int? sessions;
  final int? days;
  final double? percent;
  final int? direction;

  @override
  String toString() => 'CoachReason(${code.name})';
}

/// How a suggestion felt, as the lifter rated it after their sets.
enum CoachRating {
  tooEasy(1),
  right(0),
  tooHard(-1);

  const CoachRating(this.value);

  /// Stored in the database; also the direction of the signal.
  final int value;

  static CoachRating fromValue(int value) =>
      values.firstWhere((r) => r.value == value, orElse: () => right);
}

/// One rating, with the suggestion it was about. [date] is the rated
/// workout's date, which is how the engine finds what was actually lifted.
class CoachFeedback {
  const CoachFeedback({
    required this.date,
    required this.action,
    required this.weightKg,
    required this.repsMin,
    required this.repsMax,
    required this.rating,
  });

  final DateTime date;
  final CoachAction action;
  final double weightKg;
  final int repsMin;
  final int repsMax;
  final CoachRating rating;
}

class CoachSuggestion {
  const CoachSuggestion({
    required this.action,
    required this.weight,
    required this.weightKg,
    required this.repsMin,
    required this.repsMax,
    this.secondSetReps,
    this.reasons = const [],
  });

  final CoachAction action;

  /// In the display unit, already rounded to something loadable.
  final double weight;
  final double weightKg;
  final int repsMin;
  final int repsMax;

  /// Target for the second set at the same weight, when the rule sets one.
  final int? secondSetReps;
  final List<CoachReason> reasons;

  @override
  String toString() =>
      'CoachSuggestion(${action.name} $weight x $repsMin-$repsMax'
      '${secondSetReps == null ? '' : ', then x $secondSetReps'})';
}

class DeloadAdvice {
  const DeloadAdvice({
    required this.weight,
    required this.weightKg,
    required this.reps,
    required this.sessions,
    required this.trigger,
  });

  /// In the display unit, rounded down to something loadable.
  final double weight;
  final double weightKg;
  final int reps;

  /// How many sessions the deload lasts.
  final int sessions;
  final CoachReason trigger;
}

class CoachTrendPoint {
  const CoachTrendPoint({
    required this.date,
    required this.valueKg,
    required this.averageKg,
  });

  final DateTime date;

  /// Session e1RM (or strength index for high-rep work), in kg.
  final double valueKg;

  /// Moving average over the last few sessions, in kg.
  final double averageKg;
}

class RepRange {
  const RepRange(this.lo, this.hi, {required this.learned});

  final int lo;
  final int hi;

  /// False when there was too little history and the default was used.
  final bool learned;

  @override
  String toString() => '$lo-$hi';
}

class CoachReport {
  const CoachReport({
    required this.status,
    required this.range,
    required this.step,
    required this.unit,
    required this.exposures,
    this.suggestion,
    this.deload,
    this.trend = const [],
    this.showsOneRepMax = true,
    this.changePercent,
    this.lastTopSet,
    this.stalledSessions = 0,
    this.calibration = 0,
    this.feedbackCount = 0,
  });

  final CoachStatus status;
  final CoachSuggestion? suggestion;

  /// Set when a new deload is recommended (status [CoachStatus.stalled]).
  final DeloadAdvice? deload;
  final RepRange range;

  /// Weight step in the display unit.
  final double step;
  final String unit;
  final int exposures;
  final List<CoachTrendPoint> trend;

  /// False for high-rep exercises: the trend is then a relative strength
  /// index and the UI shows the best set and a percentage, not a 1RM.
  final bool showsOneRepMax;

  /// Change of the moving average versus about four weeks earlier, as a
  /// fraction (0.03 = +3%).
  final double? changePercent;
  final CoachSet? lastTopSet;
  final int stalledSessions;

  /// How the lifter's ratings tune this exercise, from -2 (ease off) to 2
  /// (push harder). 0 without feedback. See docs/COACH.md § Feedback.
  final double calibration;

  /// Ratings for this exercise that the calibration counted.
  final int feedbackCount;

  double? get latestValueKg => trend.isEmpty ? null : trend.last.valueKg;
}
