import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/progress_provider.dart';
import '../providers/user_provider.dart';
import '../utils/app_spacing.dart';
import '../widgets/workout_heatmap.dart';
import '../widgets/workout_heatmap_card.dart';
import '../widgets/system_nav_bar_spacer.dart';

/// The full-year view of the same data the dashboard card shows.
///
/// Titled "Training Consistency" rather than "Workout Streak": the two streak
/// counters this screen led with are gone, replaced by the weekly goal and the
/// achievements feed. See [Achievement] for the reasoning.
class WorkoutHeatmapScreen extends StatefulWidget {
  const WorkoutHeatmapScreen({super.key});

  @override
  State<WorkoutHeatmapScreen> createState() => _WorkoutHeatmapScreenState();
}

class _WorkoutHeatmapScreenState extends State<WorkoutHeatmapScreen> {
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
    return Scaffold(
      bottomNavigationBar: const SystemNavBarSpacer(),
      appBar: AppBar(title: const Text('Training Consistency')),
      body: Consumer2<ProgressProvider, UserProvider>(
        builder: (context, progressProvider, userProvider, child) {
          final achievements = progressProvider.achievements;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WeeklyGoalSummary(
                  completed: progressProvider.workoutsThisWeek,
                  goal: userProvider.weeklyWorkoutGoal,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Last 12 months',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  // reverse: true so the view opens on the most recent weeks
                  // rather than a year ago.
                  reverse: true,
                  child: WorkoutHeatmap(
                    workoutDays: progressProvider.workoutDates.toSet(),
                    weeksToShow: 52,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Recent achievements',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.md),
                if (achievements.isEmpty)
                  Text(
                    'Beat a previous best and it will show up here.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )
                else
                  for (final achievement in achievements)
                    AchievementRow(
                      achievement: achievement,
                      weightUnit: userProvider.weightUnit,
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}
