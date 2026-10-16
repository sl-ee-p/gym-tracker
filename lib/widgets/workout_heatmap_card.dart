import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/achievement.dart';
import '../providers/progress_provider.dart';
import '../providers/user_provider.dart';
import '../screens/workout_heatmap_screen.dart';
import '../theme/app_theme.dart';
import '../utils/app_date.dart';
import '../utils/app_spacing.dart';
import '../utils/weight_format.dart';
import 'workout_heatmap.dart';

/// The dashboard's training-consistency card: a weekly goal ring, the day
/// grid, and recent achievements.
///
/// It used to lead with "Current streak" and "Longest streak". Both are gone
/// on purpose — see [Achievement]. A weekly target fits how strength training
/// actually works (rest days are part of the plan, and the unit that matters
/// is the week), and it resets on Monday rather than punishing one missed day
/// by wiping out months of work.
class WorkoutHeatmapCard extends StatefulWidget {
  const WorkoutHeatmapCard({super.key});

  @override
  State<WorkoutHeatmapCard> createState() => _WorkoutHeatmapCardState();
}

class _WorkoutHeatmapCardState extends State<WorkoutHeatmapCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProgressProvider>().loadHeatmapData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WorkoutHeatmapScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Consumer2<ProgressProvider, UserProvider>(
            builder: (context, progressProvider, userProvider, child) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WeeklyGoalSummary(
                    completed: progressProvider.workoutsThisWeek,
                    goal: userProvider.weeklyWorkoutGoal,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: WorkoutHeatmap(
                      workoutDays: progressProvider.workoutDates.toSet(),
                      weeksToShow: 12,
                    ),
                  ),
                  if (progressProvider.achievements.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.md),
                    for (final achievement in progressProvider.achievements)
                      AchievementRow(
                        achievement: achievement,
                        weightUnit: userProvider.weightUnit,
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// "3 of 4 this week" with a progress ring.
///
/// The ring fills but never overflows past full, and passing the goal is
/// acknowledged rather than turned into a new bar to clear — the point is to
/// show up, not to chase an ever-rising number.
class WeeklyGoalSummary extends StatelessWidget {
  const WeeklyGoalSummary({
    super.key,
    required this.completed,
    required this.goal,
  });

  final int completed;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = context.semanticColors.success;
    final safeGoal = goal <= 0 ? 1 : goal;
    final progress = (completed / safeGoal).clamp(0.0, 1.0);
    final metGoal = completed >= safeGoal;

    return Row(
      children: [
        SizedBox(
          width: 52,
          height: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // A determinate indicator rather than a custom painter: this is
              // a plain fraction, and the theme already styles it correctly.
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 5,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    metGoal ? success : theme.colorScheme.primary,
                  ),
                ),
              ),
              if (metGoal)
                Icon(Icons.check, size: 22, color: success)
              else
                Text(
                  '$completed',
                  style: theme.textTheme.titleMedium,
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This week', style: theme.textTheme.labelMedium),
              const SizedBox(height: 2),
              Text(
                '$completed of $safeGoal workout${safeGoal == 1 ? '' : 's'}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                metGoal
                    ? 'Goal reached — anything else is a bonus.'
                    : 'Resets Monday · ${_daysLeftLabel()}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: metGoal ? success : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _daysLeftLabel() {
    final now = DateTime.now();
    // Including today: on a Sunday there is still one day left, not zero.
    final daysLeft = 7 - (daysBetween(startOfWeek(now), now));
    return '$daysLeft day${daysLeft == 1 ? '' : 's'} left';
  }
}

/// One line of the achievements feed.
class AchievementRow extends StatelessWidget {
  const AchievementRow({
    super.key,
    required this.achievement,
    required this.weightUnit,
  });

  final Achievement achievement;
  final String weightUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRecord = achievement.kind == AchievementKind.personalRecord;
    final color =
        isRecord ? context.semanticColors.success : theme.colorScheme.secondary;

    // Records arrive as raw kg + reps; converting and labelling them is a
    // display concern and belongs here. Unit goes with the weight, reps last:
    // "100 kg × 8".
    final detail = isRecord ? _describeRecord() : achievement.detail;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            isRecord ? Icons.trending_up : Icons.military_tech_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: theme.textTheme.bodySmall,
                children: [
                  TextSpan(
                    text: isRecord ? 'New best · ' : 'Milestone · ',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: achievement.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (detail.isNotEmpty) TextSpan(text: '  $detail'),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _relativeDate(achievement.date),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _describeRecord() {
    final weightKg = achievement.weightKg;
    if (weightKg == null) return '';
    final weight = formatWeight(weightKg, unit: weightUnit);
    final reps = achievement.reps;
    return reps == null ? weight : '$weight × $reps';
  }

  String _relativeDate(DateTime date) {
    final days = daysBetween(date, DateTime.now());
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '${days}d ago';
    if (days < 35) return '${(days / 7).floor()}w ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
