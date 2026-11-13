import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Title of the progressive-overload coach card and suggestion row.
  ///
  /// In en, this message translates to:
  /// **'Coach'**
  String get coachTitle;

  /// Status chip: fewer than three sessions logged.
  ///
  /// In en, this message translates to:
  /// **'Baseline'**
  String get coachStatusBaseline;

  /// Status chip: a new best in the last few sessions.
  ///
  /// In en, this message translates to:
  /// **'Progressing'**
  String get coachStatusProgressing;

  /// Status chip: no recent best, but not stalled.
  ///
  /// In en, this message translates to:
  /// **'Holding'**
  String get coachStatusHolding;

  /// Status chip: no progress for weeks; a deload is suggested.
  ///
  /// In en, this message translates to:
  /// **'Stalled'**
  String get coachStatusStalled;

  /// Status chip: in the middle of a deload.
  ///
  /// In en, this message translates to:
  /// **'Deload'**
  String get coachStatusDeloading;

  /// Label above the estimated one-rep max.
  ///
  /// In en, this message translates to:
  /// **'Estimated 1RM'**
  String get coachEstimatedOneRepMax;

  /// Label above the best set of the last session (shown instead of a 1RM for high-rep exercises).
  ///
  /// In en, this message translates to:
  /// **'Last top set'**
  String get coachLastTopSet;

  /// Trend change, positive.
  ///
  /// In en, this message translates to:
  /// **'+{percent}% in 4 weeks'**
  String coachChangeUp(String percent);

  /// Trend change, negative.
  ///
  /// In en, this message translates to:
  /// **'−{percent}% in 4 weeks'**
  String coachChangeDown(String percent);

  /// Trend change under 1%.
  ///
  /// In en, this message translates to:
  /// **'Flat over 4 weeks'**
  String get coachChangeFlat;

  /// Heading of the suggestion block.
  ///
  /// In en, this message translates to:
  /// **'Next session'**
  String get coachNextSession;

  /// A weight and a rep count, e.g. '92.5 kg × 8'.
  ///
  /// In en, this message translates to:
  /// **'{weight} × {reps}'**
  String coachWeightTimesReps(String weight, String reps);

  /// A rep range, e.g. '6–8'.
  ///
  /// In en, this message translates to:
  /// **'{min}–{max}'**
  String coachRepsRange(int min, int max);

  /// Target for the second set at the same weight.
  ///
  /// In en, this message translates to:
  /// **'Set 2: aim for {reps}+'**
  String coachSecondSet(int reps);

  /// Footer of the suggestion block.
  ///
  /// In en, this message translates to:
  /// **'Rep range {min}–{max}, learned from your sessions'**
  String coachRepRangeLearned(int min, int max);

  /// Footer while the rep range is still the default.
  ///
  /// In en, this message translates to:
  /// **'Rep range {min}–{max} until you have 3 sessions'**
  String coachRepRangeDefault(int min, int max);

  /// Why-sheet line about the weight increment on machines and dumbbells.
  ///
  /// In en, this message translates to:
  /// **'Weight step {step}, from the weights you use'**
  String coachWeightStepLearned(String step);

  /// Why-sheet line about the weight increment on plate-loaded lifts.
  ///
  /// In en, this message translates to:
  /// **'Weight step {step}, the smallest plate pair'**
  String coachWeightStepPlates(String step);

  /// Button that opens the explanation sheet.
  ///
  /// In en, this message translates to:
  /// **'Why?'**
  String get coachWhy;

  /// Title of the explanation sheet.
  ///
  /// In en, this message translates to:
  /// **'Why this suggestion'**
  String get coachWhyTitle;

  /// Caption of the chart in the explanation sheet.
  ///
  /// In en, this message translates to:
  /// **'Estimated 1RM, last {count} sessions'**
  String coachTrendOneRepMax(int count);

  /// Caption of the chart for high-rep exercises.
  ///
  /// In en, this message translates to:
  /// **'Strength trend, last {count} sessions'**
  String coachTrendIndex(int count);

  /// Legend for the moving-average line.
  ///
  /// In en, this message translates to:
  /// **'Line: average of the last 3 sessions'**
  String get coachTrendAverage;

  /// Empty state title.
  ///
  /// In en, this message translates to:
  /// **'No sessions yet'**
  String get coachEmptyTitle;

  /// Empty state body.
  ///
  /// In en, this message translates to:
  /// **'Log this exercise in a workout and the coach will suggest your next weight and reps.'**
  String get coachEmptyBody;

  /// Title while fewer than three sessions are logged.
  ///
  /// In en, this message translates to:
  /// **'Building your baseline'**
  String get coachBaselineTitle;

  /// Body while fewer than three sessions are logged.
  ///
  /// In en, this message translates to:
  /// **'{count} of {target} sessions logged. Trends and stall checks start after {target}.'**
  String coachBaselineBody(int count, int target);

  /// Shown for exercises the coach can't steer.
  ///
  /// In en, this message translates to:
  /// **'The coach works with weight × reps exercises. This one is timed, unweighted or logged without a real weight.'**
  String get coachUnsupported;

  /// Stall banner title.
  ///
  /// In en, this message translates to:
  /// **'No progress for {sessions, plural, =1{1 session} other{{sessions} sessions}}'**
  String coachStalledBanner(int sessions);

  /// Regression banner title.
  ///
  /// In en, this message translates to:
  /// **'Recent sessions are down {percent}%'**
  String coachRegressedBanner(String percent);

  /// Deload recommendation.
  ///
  /// In en, this message translates to:
  /// **'Deload suggested: {weight} × {reps} for {sessions, plural, =1{1 session} other{{sessions} sessions}}, leaving 2–3 reps in the tank.'**
  String coachDeloadAdvice(String weight, int reps, int sessions);

  /// Banner during a deload.
  ///
  /// In en, this message translates to:
  /// **'Deload session {done} of {total}'**
  String coachDeloadInProgress(int done, int total);

  /// Accept the suggested deload.
  ///
  /// In en, this message translates to:
  /// **'Start deload'**
  String get coachStartDeload;

  /// Dismiss a suggestion for this workout.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get coachNotNow;

  /// Fill the set fields with the suggestion.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get coachUse;

  /// Shown if the history can't be read.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the coach. Try again later.'**
  String get coachLoadError;

  /// Reason while fewer than three sessions are logged (the card already shows the count).
  ///
  /// In en, this message translates to:
  /// **'Early days: add one rep to what you did last time.'**
  String get coachReasonBaselineSessions;

  /// Reason.
  ///
  /// In en, this message translates to:
  /// **'Last time you hit {weight} × {reps}, the top of your range. Time to add weight.'**
  String coachReasonHitTopOfRange(String weight, int reps);

  /// Reason.
  ///
  /// In en, this message translates to:
  /// **'Your first set reached the top of the range, but set 2 needs {target} reps before the weight goes up.'**
  String coachReasonSecondSetShort(int target);

  /// Reason.
  ///
  /// In en, this message translates to:
  /// **'Last time: {reps} reps. Add a rep before adding weight; the top of your range is {target}.'**
  String coachReasonClimbingReps(int reps, int target);

  /// Reason.
  ///
  /// In en, this message translates to:
  /// **'Last time: {reps} reps, under your range. Keep the weight and aim for {target}.'**
  String coachReasonBelowRange(int reps, int target);

  /// Reason.
  ///
  /// In en, this message translates to:
  /// **'Two sessions under {target} reps at this weight. Step back one notch and build up again.'**
  String coachReasonMissedTwice(int target);

  /// Reason.
  ///
  /// In en, this message translates to:
  /// **'The next weight is a big jump ({step}), so build up to {target} reps first.'**
  String coachReasonBigStepRepsFirst(String step, int target);

  /// Reason.
  ///
  /// In en, this message translates to:
  /// **'No new best in {sessions, plural, =1{1 session} other{{sessions} sessions}}.'**
  String coachReasonStalled(int sessions);

  /// Reason.
  ///
  /// In en, this message translates to:
  /// **'Your recent sessions are {percent}% below your best at this weight.'**
  String coachReasonRegressed(String percent);

  /// Reason.
  ///
  /// In en, this message translates to:
  /// **'Deload session {sessions} of {target} done. Keep this one light too.'**
  String coachReasonDeloadContinue(int sessions, int target);

  /// Reason.
  ///
  /// In en, this message translates to:
  /// **'Deload done. Restart just under your previous {weight}.'**
  String coachReasonDeloadDone(String weight);

  /// Reason.
  ///
  /// In en, this message translates to:
  /// **'Your last session ({weight}) looked like a light day, so the suggestion builds on the one before.'**
  String coachReasonLightSessionIgnored(String weight);

  /// Reason.
  ///
  /// In en, this message translates to:
  /// **'{days} days since you last trained this, so start {percent}% lighter.'**
  String coachReasonWelcomeBack(int days, String percent);

  /// Label of the workout-screen suggestion before any working set is logged.
  ///
  /// In en, this message translates to:
  /// **'Coach · top set'**
  String get coachRowTopSet;

  /// Label of the workout-screen suggestion for a later set.
  ///
  /// In en, this message translates to:
  /// **'Coach · set {number}'**
  String coachRowSet(int number);

  /// Label of the workout-screen suggestion while deloading.
  ///
  /// In en, this message translates to:
  /// **'Coach · deload'**
  String get coachRowDeload;

  /// Screen-reader label of the Use button.
  ///
  /// In en, this message translates to:
  /// **'Fill in {weight} for {reps} reps'**
  String coachUseSemantics(String weight, int reps);

  /// Settings switch that turns the progressive-overload coach on or off.
  ///
  /// In en, this message translates to:
  /// **'Coach'**
  String get coachSettingTitle;

  /// Subtitle of the coach switch in Settings.
  ///
  /// In en, this message translates to:
  /// **'Suggests weights and reps from your history'**
  String get coachSettingSubtitle;

  /// Reason: the lifter's ratings made the coach more careful.
  ///
  /// In en, this message translates to:
  /// **'You rated {agreeing} of your last {sessions} suggestions too hard, so weight now goes up only after both sets reach the top of the range.'**
  String coachReasonFeedbackEasier(int agreeing, int sessions);

  /// Reason: the lifter's ratings made the coach push harder.
  ///
  /// In en, this message translates to:
  /// **'You rated {agreeing} of your last {sessions} suggestions too easy, so weight now goes up one rep short of the top of the range.'**
  String coachReasonFeedbackHarder(int agreeing, int sessions);

  /// Reason: no ratings for this exercise yet; the ratings of other exercises made the coach more careful.
  ///
  /// In en, this message translates to:
  /// **'You often rate other exercises too hard, so this one adds weight carefully too.'**
  String get coachReasonPriorEasier;

  /// Reason: no ratings for this exercise yet; the ratings of other exercises made the coach push harder.
  ///
  /// In en, this message translates to:
  /// **'You often rate other exercises too easy, so this one adds weight sooner too.'**
  String get coachReasonPriorHarder;

  /// Reason: the last session was rated too hard.
  ///
  /// In en, this message translates to:
  /// **'You rated last session too hard, so the weight stays the same.'**
  String get coachReasonLastTooHard;

  /// Reason: the last session was rated too easy.
  ///
  /// In en, this message translates to:
  /// **'You rated last session too easy, so the weight goes up now.'**
  String get coachReasonLastTooEasy;

  /// Asked in the workout row after a set, about the coach's top-set suggestion, e.g. "How did 92.5 kg × 6–8 feel?".
  ///
  /// In en, this message translates to:
  /// **'How did {target} feel?'**
  String coachRateQuestion(String target);

  /// Rating chip: the suggestion was too light.
  ///
  /// In en, this message translates to:
  /// **'Too easy'**
  String get coachRateTooEasy;

  /// Rating chip: the suggestion fit.
  ///
  /// In en, this message translates to:
  /// **'About right'**
  String get coachRateRight;

  /// Rating chip: the suggestion was too heavy.
  ///
  /// In en, this message translates to:
  /// **'Too hard'**
  String get coachRateTooHard;

  /// Screen-reader label of a rating chip, e.g. "Rate 92.5 kg × 6–8 as too hard".
  ///
  /// In en, this message translates to:
  /// **'Rate {target} as {rating}'**
  String coachRateSemantics(String target, String rating);

  /// Shown after rating the suggestion.
  ///
  /// In en, this message translates to:
  /// **'Noted: {rating}. The coach uses it from your next session.'**
  String coachRatedNoted(String rating);

  /// Button that reopens the rating chips.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get coachRateChange;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
