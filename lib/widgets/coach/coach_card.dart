import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../coach/coach_models.dart';
import '../../l10n/app_localizations.dart';
import '../../models/exercise.dart';
import '../../providers/coach_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/numeric_text_styles.dart';
import '../../utils/app_spacing.dart';
import '../../utils/weight_format.dart';
import 'coach_sparkline.dart';
import 'coach_text.dart';
import 'coach_why_sheet.dart';

/// The coach's summary for one exercise on the Exercise details screen:
/// status, 1RM (or best set) with its 4-week change, a sparkline, and the
/// next-session suggestion with a short reason. See docs/COACH.md.
class CoachCard extends StatelessWidget {
  const CoachCard({super.key, required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final report = context.watch<CoachProvider>().reportFor(exercise);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: report == null
              ? const _LoadingBody()
              : _CoachBody(report: report, exercise: exercise),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.status});

  final CoachStatus? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Icon(Icons.auto_graph, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(l10n.coachTitle, style: theme.textTheme.titleMedium),
        ),
        if (status != null &&
            status != CoachStatus.noData &&
            status != CoachStatus.unsupported)
          CoachStatusChip(status: status!),
      ],
    );
  }
}

/// Small pill with the coach's status, coloured by how good the news is.
class CoachStatusChip extends StatelessWidget {
  const CoachStatusChip({super.key, required this.status});

  final CoachStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final success = context.semanticColors.success;
    final (bg, fg) = switch (status) {
      CoachStatus.progressing => (success.withValues(alpha: 0.16), success),
      CoachStatus.stalled || CoachStatus.deloading => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Text(
        CoachText.of(context, 'kg').status(status),
        style: theme.textTheme.labelMedium?.copyWith(color: fg),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget block(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header(),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                block(90, 12),
                const SizedBox(height: AppSpacing.sm),
                block(120, 28),
              ],
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: block(double.infinity, 56)),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        block(double.infinity, 76),
      ],
    );
  }
}

class _CoachBody extends StatelessWidget {
  const _CoachBody({required this.report, required this.exercise});

  final CoachReport report;
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final text = CoachText(l10n, report.unit);

    if (report.status == CoachStatus.unsupported ||
        report.status == CoachStatus.noData) {
      final unsupported = report.status == CoachStatus.unsupported;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Header(),
          const SizedBox(height: AppSpacing.md),
          if (!unsupported)
            Text(l10n.coachEmptyTitle, style: theme.textTheme.titleSmall),
          if (!unsupported) const SizedBox(height: AppSpacing.xs),
          Text(
            unsupported ? l10n.coachUnsupported : l10n.coachEmptyBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final s = report.suggestion!;
    final baseline = report.status == CoachStatus.baseline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(status: report.status),
        const SizedBox(height: AppSpacing.lg),
        if (baseline)
          _BaselineProgress(count: report.exposures)
        else
          _Headline(report: report, text: text),
        if (report.deload != null ||
            report.status == CoachStatus.deloading) ...[
          const SizedBox(height: AppSpacing.md),
          _DeloadBanner(report: report, text: text),
        ],
        const SizedBox(height: AppSpacing.md),
        _NextSession(suggestion: s, text: text),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                report.range.learned
                    ? l10n.coachRepRangeLearned(
                        report.range.lo,
                        report.range.hi,
                      )
                    : l10n.coachRepRangeDefault(
                        report.range.lo,
                        report.range.hi,
                      ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () => showCoachWhySheet(
                context,
                report: report,
                plateLoaded: exercise.usesPlateCalculator,
              ),
              child: Text(l10n.coachWhy),
            ),
          ],
        ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.report, required this.text});

  final CoachReport report;
  final CoachText text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = text.l10n;
    final unit = report.unit;
    final top = report.lastTopSet;
    final String label;
    final String value;
    if (report.showsOneRepMax && report.latestValueKg != null) {
      label = l10n.coachEstimatedOneRepMax;
      value = formatWeight(report.latestValueKg!, unit: unit);
    } else {
      label = l10n.coachLastTopSet;
      value = top == null
          ? '–'
          : l10n.coachWeightTimesReps(
              formatWeight(top.weightKg, unit: unit),
              '${top.reps}',
            );
    }

    final change = report.changePercent;
    final rounded = change == null ? 0 : (change * 100).round();
    final success = context.semanticColors.success;
    final (color, icon, changeText) = change == null || rounded == 0
        ? (scheme.onSurfaceVariant, Icons.remove, l10n.coachChangeFlat)
        : rounded > 0
        ? (success, Icons.arrow_upward, l10n.coachChangeUp('$rounded'))
        : (
            scheme.error,
            Icons.arrow_downward,
            l10n.coachChangeDown('${rounded.abs()}'),
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: NumericTextStyles.title()),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      changeText,
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          flex: 4,
          child: SizedBox(
            height: 64,
            child: CoachSparkline(points: report.trend, unit: unit),
          ),
        ),
      ],
    );
  }
}

class _BaselineProgress extends StatelessWidget {
  const _BaselineProgress({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    const target = 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.coachBaselineTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (var i = 0; i < target; i++) ...[
              Container(
                width: 28,
                height: 6,
                decoration: BoxDecoration(
                  color: i < count
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.coachBaselineBody(count, target),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DeloadBanner extends StatelessWidget {
  const _DeloadBanner({required this.report, required this.text});

  final CoachReport report;
  final CoachText text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = report.deload;
    final title = d != null
        ? text.banner(report)!
        : text.l10n.coachStatusDeloading;
    final body = d != null
        ? text.deload(d)
        : text.headlineReason(report.suggestion!) ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.battery_charging_full,
            size: 20,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onTertiaryContainer,
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

class _NextSession extends StatelessWidget {
  const _NextSession({required this.suggestion, required this.text});

  final CoachSuggestion suggestion;
  final CoachText text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = text.l10n;
    final reason = text.headlineReason(suggestion);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.coachNextSession,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            text.suggestion(suggestion),
            style: NumericTextStyles.title(color: scheme.primary),
          ),
          if (suggestion.secondSetReps != null)
            Text(
              l10n.coachSecondSet(suggestion.secondSetReps!),
              style: theme.textTheme.bodyMedium,
            ),
          if (reason != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(reason, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
