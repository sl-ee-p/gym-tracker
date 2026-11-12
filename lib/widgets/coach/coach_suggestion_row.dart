import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../coach/coach_models.dart';
import '../../l10n/app_localizations.dart';
import '../../models/exercise.dart';
import '../../providers/coach_provider.dart';
import '../../services/coach_service.dart';
import '../../theme/numeric_text_styles.dart';
import '../../utils/app_spacing.dart';
import 'coach_text.dart';
import 'coach_why_sheet.dart';

/// The coach's suggestion inside the workout screen's set form.
///
/// Shows the target for the next working set; "Use" fills the form (the
/// only way the form is ever filled), "Not now" hides it for this workout,
/// and a stall shows a deload banner with "Start deload" / "Not now".
class CoachSuggestionRow extends StatelessWidget {
  const CoachSuggestionRow({
    super.key,
    required this.exercise,
    required this.workoutId,
    required this.workingSetsLogged,
    required this.apply,
  });

  final Exercise exercise;
  final int? workoutId;

  /// Non-warm-up sets already logged for this exercise in this workout.
  final int workingSetsLogged;

  /// Fills the set form with a weight in kilograms and a rep count.
  final void Function(double weightKg, int reps) apply;

  @override
  Widget build(BuildContext context) {
    if (!CoachService.supports(exercise) || exercise.id == null) {
      return const SizedBox.shrink();
    }
    final coach = context.watch<CoachProvider>();
    final id = exercise.id!;
    final report = coach.reportFor(exercise);
    final s = report?.suggestion;
    if (report == null ||
        s == null ||
        report.status == CoachStatus.unsupported ||
        coach.isDismissed(workoutId, id)) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final text = CoachText(l10n, report.unit);
    final deloadStarted = coach.isDeloadStarted(workoutId, id);
    final offerDeload =
        report.deload != null &&
        !deloadStarted &&
        !coach.isDeloadDeclined(workoutId, id) &&
        workingSetsLogged == 0;
    final target = _target(report, deloadStarted);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (offerDeload) ...[
            _DeloadOffer(
              title: text.banner(report)!,
              body: text.deload(report.deload!),
              onStart: () => coach.startDeload(workoutId, id),
              onDecline: () => coach.declineDeload(workoutId, id),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          _TargetRow(
            label: target.deload
                ? l10n.coachRowDeload
                : workingSetsLogged == 0
                ? l10n.coachRowTopSet
                : l10n.coachRowSet(workingSetsLogged + 1),
            value: l10n.coachWeightTimesReps(
              text.weight(target.weight),
              target.repsMin == target.repsMax
                  ? '${target.repsMin}'
                  : l10n.coachRepsRange(target.repsMin, target.repsMax),
            ),
            deload: target.deload,
            useSemantics: l10n.coachUseSemantics(
              text.weight(target.weight),
              target.repsMin,
            ),
            onUse: () => apply(
              report.unit == 'lbs'
                  ? target.weight / coachLbsPerKg
                  : target.weight,
              target.repsMin,
            ),
            onWhy: () => showCoachWhySheet(
              context,
              report: report,
              plateLoaded: exercise.usesPlateCalculator,
            ),
            onDismiss: () => coach.dismiss(workoutId, id),
          ),
        ],
      ),
    );
  }

  ({double weight, int repsMin, int repsMax, bool deload}) _target(
    CoachReport report,
    bool deloadStarted,
  ) {
    final d = report.deload;
    if (deloadStarted && d != null) {
      return (weight: d.weight, repsMin: d.reps, repsMax: d.reps, deload: true);
    }
    final s = report.suggestion!;
    final deload = s.action == CoachAction.deload;
    if (workingSetsLogged == 1 && s.secondSetReps != null) {
      return (
        weight: s.weight,
        repsMin: s.secondSetReps!,
        repsMax: s.secondSetReps!,
        deload: deload,
      );
    }
    return (
      weight: s.weight,
      repsMin: s.repsMin,
      repsMax: s.repsMax,
      deload: deload,
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.label,
    required this.value,
    required this.deload,
    required this.useSemantics,
    required this.onUse,
    required this.onWhy,
    required this.onDismiss,
  });

  final String label;
  final String value;
  final bool deload;
  final String useSemantics;
  final VoidCallback onUse;
  final VoidCallback onWhy;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final bg = deload ? scheme.tertiaryContainer : scheme.surfaceContainerHigh;
    final fg = deload ? scheme.onTertiaryContainer : scheme.primary;
    final muted = deload ? scheme.onTertiaryContainer : scheme.onSurfaceVariant;
    // On the tinted deload row the text buttons take the banner's colour.
    final textStyle = deload
        ? TextButton.styleFrom(foregroundColor: scheme.onTertiaryContainer)
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  deload ? Icons.battery_charging_full : Icons.auto_graph,
                  size: 18,
                  color: fg,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(value, style: NumericTextStyles.body(color: fg)),
                  ],
                ),
              ),
            ],
          ),
          // Actions on their own line so they never squeeze the target at
          // large font sizes.
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.xs,
              children: [
                TextButton(
                  onPressed: onWhy,
                  style: textStyle,
                  child: Text(l10n.coachWhy),
                ),
                TextButton(
                  onPressed: onDismiss,
                  style: textStyle,
                  child: Text(l10n.coachNotNow),
                ),
                FilledButton.tonal(
                  onPressed: onUse,
                  child: Text(
                    l10n.coachUse,
                    // Says what it fills, not just "Use".
                    semanticsLabel: useSemantics,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeloadOffer extends StatelessWidget {
  const _DeloadOffer({
    required this.title,
    required this.body,
    required this.onStart,
    required this.onDecline,
  });

  final String title;
  final String body;
  final VoidCallback onStart;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final fg = scheme.onTertiaryContainer;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.pause_circle_outline, size: 18, color: fg),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(color: fg),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(color: fg),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.xs,
              children: [
                TextButton(
                  onPressed: onDecline,
                  style: TextButton.styleFrom(foregroundColor: fg),
                  child: Text(l10n.coachNotNow),
                ),
                TextButton(
                  onPressed: onStart,
                  style: TextButton.styleFrom(foregroundColor: fg),
                  child: Text(l10n.coachStartDeload),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
