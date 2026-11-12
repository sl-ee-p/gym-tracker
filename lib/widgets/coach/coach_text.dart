import 'package:flutter/material.dart';

import '../../coach/coach_models.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/weight_format.dart';

/// Turns the engine's codes and numbers into localised text. The engine
/// never produces strings (see docs/COACH.md), so this is the one place
/// where coach wording lives.
class CoachText {
  CoachText(this.l10n, this.unit);

  factory CoachText.of(BuildContext context, String unit) =>
      CoachText(AppLocalizations.of(context), unit);

  final AppLocalizations l10n;
  final String unit;

  /// A display-unit weight, e.g. "92.5 kg".
  String weight(double displayWeight) =>
      '${formatDecimal(displayWeight)} $unit';

  String percent(double fraction) =>
      formatDecimal((fraction.abs() * 100).roundToDouble());

  String status(CoachStatus s) => switch (s) {
    CoachStatus.baseline || CoachStatus.noData => l10n.coachStatusBaseline,
    CoachStatus.progressing => l10n.coachStatusProgressing,
    CoachStatus.holding || CoachStatus.unsupported => l10n.coachStatusHolding,
    CoachStatus.stalled => l10n.coachStatusStalled,
    CoachStatus.deloading => l10n.coachStatusDeloading,
  };

  /// "92.5 kg × 6–8" or "92.5 kg × 8".
  String suggestion(CoachSuggestion s) => l10n.coachWeightTimesReps(
    weight(s.weight),
    s.repsMin == s.repsMax
        ? '${s.repsMin}'
        : l10n.coachRepsRange(s.repsMin, s.repsMax),
  );

  String deload(DeloadAdvice d) =>
      l10n.coachDeloadAdvice(weight(d.weight), d.reps, d.sessions);

  String? banner(CoachReport r) {
    final d = r.deload;
    if (d == null) return null;
    return d.trigger.code == CoachReasonCode.regressed
        ? l10n.coachRegressedBanner(percent(d.trigger.percent ?? 0))
        : l10n.coachStalledBanner(d.trigger.sessions ?? r.stalledSessions);
  }

  String reason(CoachReason r) {
    final w = r.weight == null ? '' : weight(r.weight!);
    final reps = r.reps ?? 0;
    final target = r.target ?? 0;
    return switch (r.code) {
      CoachReasonCode.baselineSessions => l10n.coachReasonBaselineSessions,
      CoachReasonCode.hitTopOfRange => l10n.coachReasonHitTopOfRange(w, reps),
      CoachReasonCode.secondSetShort => l10n.coachReasonSecondSetShort(target),
      CoachReasonCode.climbingReps => l10n.coachReasonClimbingReps(
        reps,
        target,
      ),
      CoachReasonCode.belowRange => l10n.coachReasonBelowRange(reps, target),
      CoachReasonCode.missedTwice => l10n.coachReasonMissedTwice(target),
      CoachReasonCode.bigStepRepsFirst => l10n.coachReasonBigStepRepsFirst(
        weight(r.step ?? 0),
        target,
      ),
      CoachReasonCode.stalled => l10n.coachReasonStalled(r.sessions ?? 0),
      CoachReasonCode.regressed => l10n.coachReasonRegressed(
        percent(r.percent ?? 0),
      ),
      CoachReasonCode.deloadContinue => l10n.coachReasonDeloadContinue(
        r.sessions ?? 0,
        target,
      ),
      CoachReasonCode.deloadDone => l10n.coachReasonDeloadDone(w),
      CoachReasonCode.lightSessionIgnored =>
        l10n.coachReasonLightSessionIgnored(w),
      CoachReasonCode.welcomeBack => l10n.coachReasonWelcomeBack(
        r.days ?? 0,
        percent(r.percent ?? 0),
      ),
    };
  }

  /// The most specific reason, for the one-line summary under a suggestion.
  /// "Welcome back" wins because it changes the weight the most.
  String? headlineReason(CoachSuggestion s) {
    if (s.reasons.isEmpty) return null;
    final back = s.reasons
        .where((r) => r.code == CoachReasonCode.welcomeBack)
        .firstOrNull;
    return reason(back ?? s.reasons.last);
  }
}
