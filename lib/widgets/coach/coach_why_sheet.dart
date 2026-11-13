import 'package:flutter/material.dart';

import '../../coach/coach_models.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/numeric_text_styles.dart';
import '../../utils/app_spacing.dart';
import 'coach_sparkline.dart';
import 'coach_text.dart';

/// "Why this suggestion": every reason the engine gave, the trend with its
/// axis, and where the rep range and weight step come from.
Future<void> showCoachWhySheet(
  BuildContext context, {
  required CoachReport report,
  required bool plateLoaded,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) =>
        CoachWhySheet(report: report, plateLoaded: plateLoaded),
  );
}

class CoachWhySheet extends StatelessWidget {
  const CoachWhySheet({
    super.key,
    required this.report,
    required this.plateLoaded,
  });

  final CoachReport report;
  final bool plateLoaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final text = CoachText(l10n, report.unit);
    final s = report.suggestion;
    final reasons = [
      ...?s?.reasons.where((r) => !CoachText.isFeedback(r)),
      if (report.deload != null) report.deload!.trigger,
    ];
    final feedbackReasons = [...?s?.reasons.where(CoachText.isFeedback)];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.coachWhyTitle, style: theme.textTheme.titleLarge),
            if (s != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                text.suggestion(s),
                style: NumericTextStyles.title(color: scheme.primary),
              ),
              if (s.secondSetReps != null)
                Text(
                  l10n.coachSecondSet(s.secondSetReps!),
                  style: theme.textTheme.bodyMedium,
                ),
            ],
            const SizedBox(height: AppSpacing.lg),
            for (final r in reasons) _ReasonLine(r, text: text),
            if (s != null) ...[
              Text(l10n.coachLearnedTitle, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              for (final r in feedbackReasons) _ReasonLine(r, text: text),
              Text(
                text.learned(report),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (report.deload != null) ...[
              Text(
                text.deload(report.deload!),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (report.trend.length >= 2) ...[
              Text(
                report.showsOneRepMax
                    ? l10n.coachTrendOneRepMax(report.trend.length)
                    : l10n.coachTrendIndex(report.trend.length),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 160,
                child: CoachSparkline(
                  points: report.trend,
                  unit: report.unit,
                  compact: false,
                  showValues: report.showsOneRepMax,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.coachTrendAverage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            _FactLine(
              icon: Icons.straighten,
              text: report.range.learned
                  ? l10n.coachRepRangeLearned(report.range.lo, report.range.hi)
                  : l10n.coachRepRangeDefault(report.range.lo, report.range.hi),
            ),
            const SizedBox(height: AppSpacing.sm),
            _FactLine(
              icon: Icons.fitness_center,
              text: plateLoaded
                  ? l10n.coachWeightStepPlates(text.weight(report.step))
                  : l10n.coachWeightStepLearned(text.weight(report.step)),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(CoachReasonCode code) => switch (code) {
    CoachReasonCode.hitTopOfRange => Icons.trending_up,
    CoachReasonCode.climbingReps ||
    CoachReasonCode.secondSetShort ||
    CoachReasonCode.bigStepRepsFirst => Icons.add_circle_outline,
    CoachReasonCode.belowRange ||
    CoachReasonCode.missedTwice ||
    CoachReasonCode.missedEaseOff => Icons.south_east,
    CoachReasonCode.stalled ||
    CoachReasonCode.regressed => Icons.pause_circle_outline,
    CoachReasonCode.deloadContinue ||
    CoachReasonCode.deloadDone => Icons.battery_charging_full,
    CoachReasonCode.welcomeBack => Icons.waving_hand_outlined,
    CoachReasonCode.lightSessionIgnored => Icons.filter_alt_outlined,
    CoachReasonCode.baselineSessions => Icons.flag_outlined,
    CoachReasonCode.feedbackAdjusted ||
    CoachReasonCode.lastRating => Icons.tune,
  };
}

class _ReasonLine extends StatelessWidget {
  const _ReasonLine(this.reason, {required this.text});

  final CoachReason reason;
  final CoachText text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              CoachWhySheet._iconFor(reason.code),
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(text.reason(reason), style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _FactLine extends StatelessWidget {
  const _FactLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
