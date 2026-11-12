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
  String get coachTrendAverage => 'Line: average of the last 3 sessions';

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
    return 'Last time: $reps reps. Add a rep before adding weight; the top of your range is $target.';
  }

  @override
  String coachReasonBelowRange(int reps, int target) {
    return 'Last time: $reps reps, under your range. Keep the weight and aim for $target.';
  }

  @override
  String coachReasonMissedTwice(int target) {
    return 'Two sessions under $target reps at this weight. Step back one notch and build up again.';
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
}
