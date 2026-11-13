// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get coachTitle => 'Coach';

  @override
  String get coachStatusBaseline => 'Baseline';

  @override
  String get coachStatusProgressing => 'Progressing';

  @override
  String get coachStatusHolding => 'Holding';

  @override
  String get coachStatusStalled => 'Stalled';

  @override
  String get coachStatusDeloading => 'Deload';

  @override
  String get coachEstimatedOneRepMax => 'Estimated 1RM';

  @override
  String get coachLastTopSet => 'Last top set';

  @override
  String coachChangeUp(String percent) {
    return '+$percent% in 4 weeks';
  }

  @override
  String coachChangeDown(String percent) {
    return '−$percent% in 4 weeks';
  }

  @override
  String get coachChangeFlat => 'Flat over 4 weeks';

  @override
  String get coachNextSession => 'Next session';

  @override
  String coachWeightTimesReps(String weight, String reps) {
    return '$weight × $reps';
  }

  @override
  String coachRepsRange(int min, int max) {
    return '$min–$max';
  }

  @override
  String coachSecondSet(int reps) {
    return 'Set 2: aim for $reps+';
  }

  @override
  String coachRepRangeLearned(int min, int max) {
    return 'Rep range $min–$max, learned from your sessions';
  }

  @override
  String coachRepRangeDefault(int min, int max) {
    return 'Rep range $min–$max until you have 3 sessions';
  }

  @override
  String coachWeightStepLearned(String step) {
    return 'Weight step $step, from the weights you use';
  }

  @override
  String coachWeightStepPlates(String step) {
    return 'Weight step $step, the smallest plate pair';
  }

  @override
  String get coachWhy => 'Why?';

  @override
  String get coachWhyTitle => 'Why this suggestion';

  @override
  String coachTrendOneRepMax(int count) {
    return 'Estimated 1RM, last $count sessions';
  }

  @override
  String coachTrendIndex(int count) {
    return 'Strength trend, last $count sessions';
  }

  @override
  String get coachTrendAverage =>
      'The line is the average of your last 3 sessions.';

  @override
  String get coachEmptyTitle => 'No sessions yet';

  @override
  String get coachEmptyBody =>
      'Log this exercise in a workout and the coach will suggest your next weight and reps.';

  @override
  String get coachBaselineTitle => 'Building your baseline';

  @override
  String coachBaselineBody(int count, int target) {
    return '$count of $target sessions logged. Trends and stall checks start after $target.';
  }

  @override
  String get coachUnsupported =>
      'The coach works with weight × reps exercises. This one is timed, unweighted or logged without a real weight.';

  @override
  String coachStalledBanner(int sessions) {
    String _temp0 = intl.Intl.pluralLogic(
      sessions,
      locale: localeName,
      other: '$sessions sessions',
      one: '1 session',
    );
    return 'No progress for $_temp0';
  }

  @override
  String coachRegressedBanner(String percent) {
    return 'Recent sessions are down $percent%';
  }

  @override
  String coachDeloadAdvice(String weight, int reps, int sessions) {
    String _temp0 = intl.Intl.pluralLogic(
      sessions,
      locale: localeName,
      other: '$sessions sessions',
      one: '1 session',
    );
    return 'Deload suggested: $weight × $reps for $_temp0, leaving 2–3 reps in the tank.';
  }

  @override
  String coachDeloadInProgress(int done, int total) {
    return 'Deload session $done of $total';
  }

  @override
  String get coachStartDeload => 'Start deload';

  @override
  String get coachNotNow => 'Not now';

  @override
  String get coachUse => 'Use';

  @override
  String get coachLoadError => 'Couldn\'t load the coach. Try again later.';

  @override
  String get coachReasonBaselineSessions =>
      'Early days: add one rep to what you did last time.';

  @override
  String coachReasonHitTopOfRange(String weight, int reps) {
    return 'Last time you hit $weight × $reps, the top of your range. Time to add weight.';
  }

  @override
  String coachReasonSecondSetShort(int target) {
    return 'Your first set reached the top of the range, but set 2 needs $target reps before the weight goes up.';
  }

  @override
  String coachReasonClimbingReps(int reps, int target) {
    return 'Last time you did $reps reps. Add one more before adding weight; your range tops out at $target.';
  }

  @override
  String coachReasonBelowRange(int reps, int target) {
    return 'Last time you did $reps reps, below your range. Keep the weight and aim for $target.';
  }

  @override
  String coachReasonMissedTwice(int target) {
    return 'Two sessions in a row under $target reps at this weight. Drop one step and build back up.';
  }

  @override
  String coachReasonBigStepRepsFirst(String step, int target) {
    return 'The next weight is a big jump ($step), so build up to $target reps first.';
  }

  @override
  String coachReasonStalled(int sessions) {
    String _temp0 = intl.Intl.pluralLogic(
      sessions,
      locale: localeName,
      other: '$sessions sessions',
      one: '1 session',
    );
    return 'No new best in $_temp0.';
  }

  @override
  String coachReasonRegressed(String percent) {
    return 'Your recent sessions are $percent% below your best at this weight.';
  }

  @override
  String coachReasonDeloadContinue(int sessions, int target) {
    return 'Deload session $sessions of $target done. Keep this one light too.';
  }

  @override
  String coachReasonDeloadDone(String weight) {
    return 'Deload done. Restart just under your previous $weight.';
  }

  @override
  String coachReasonLightSessionIgnored(String weight) {
    return 'Your last session ($weight) looked like a light day, so the suggestion builds on the one before.';
  }

  @override
  String coachReasonWelcomeBack(int days, String percent) {
    return '$days days since you last trained this, so start $percent% lighter.';
  }

  @override
  String get coachRowTopSet => 'Coach · top set';

  @override
  String coachRowSet(int number) {
    return 'Coach · set $number';
  }

  @override
  String get coachRowDeload => 'Coach · deload';

  @override
  String coachUseSemantics(String weight, int reps) {
    return 'Fill in $weight for $reps reps';
  }

  @override
  String get coachSettingTitle => 'Coach';

  @override
  String get coachSettingSubtitle =>
      'Suggests weights and reps from your history';

  @override
  String coachReasonFeedbackEasier(int agreeing, int sessions) {
    return 'You rated $agreeing of your last $sessions suggestions too hard, so weight now goes up only after both sets reach the top of the range.';
  }

  @override
  String coachReasonFeedbackHarder(int agreeing, int sessions) {
    return 'You rated $agreeing of your last $sessions suggestions too easy, so weight now goes up one rep short of the top of the range.';
  }

  @override
  String get coachReasonPriorEasier =>
      'You often rate other exercises too hard, so this one adds weight carefully too.';

  @override
  String get coachReasonPriorHarder =>
      'You often rate other exercises too easy, so this one adds weight sooner too.';

  @override
  String coachReasonLastTooHard(String weight, int reps) {
    return 'Last time you did $weight × $reps, the top of your range, but rated it too hard. The weight stays the same until it feels right.';
  }

  @override
  String coachReasonLastTooEasy(String weight, int reps) {
    return 'Last time you did $weight × $reps and rated it too easy, so the weight goes up now.';
  }

  @override
  String coachRateQuestion(String target) {
    return 'How did $target feel?';
  }

  @override
  String get coachRateTooEasy => 'Too easy';

  @override
  String get coachRateRight => 'About right';

  @override
  String get coachRateTooHard => 'Too hard';

  @override
  String coachRateSemantics(String target, String rating) {
    return 'Rate $target as $rating';
  }

  @override
  String coachRatedNoted(String rating) {
    return 'Noted: $rating. The coach uses it from your next session.';
  }

  @override
  String get coachRateChange => 'Change';

  @override
  String get coachLearnedTitle => 'What the coach learned';

  @override
  String get coachLearnedNone =>
      'After your sets, rate the suggestion (too easy, about right or too hard) and the coach tunes itself to you.';

  @override
  String coachLearnedCareful(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ratings of this exercise',
      one: '1 rating of this exercise',
    );
    return '$_temp0 so far. Weight goes up more carefully for you.';
  }

  @override
  String coachLearnedStandard(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ratings of this exercise',
      one: '1 rating of this exercise',
    );
    return '$_temp0 so far. Not a clear lean either way yet, so the standard rules apply; your latest rating still counts.';
  }

  @override
  String coachLearnedPush(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ratings of this exercise',
      one: '1 rating of this exercise',
    );
    return '$_temp0 so far. Weight goes up sooner for you.';
  }

  @override
  String get coachTunedToRatings => 'Tuned to your ratings';

  @override
  String coachReasonMissedEaseOff(int reps, int target) {
    return 'Last time you did $reps reps, under your target of $target. Your ratings say ease off, so drop one step and build back up.';
  }
}
