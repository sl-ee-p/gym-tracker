import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dialogs/target_weight_dialog.dart';
import '../models/weight_goal.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_spacing.dart';
import '../utils/weight_format.dart';

/// Progress towards the body-weight goal: a bar from the starting weight to
/// the target, with the distance left. Used on the Body Weight tab and as a
/// Home block.
///
/// With no goal set, [showWhenEmpty] decides between an invitation to set
/// one (the Body Weight tab) and nothing at all (the Home block — an empty
/// card on the dashboard would just be noise).
class WeightGoalCard extends StatelessWidget {
  const WeightGoalCard({super.key, this.showWhenEmpty = true});

  final bool showWhenEmpty;

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final progress = userProvider.weightGoalProgress;
    final unit = userProvider.weightUnit;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    if (progress == null) {
      if (!showWhenEmpty) return const SizedBox.shrink();
      return Card(
        child: ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: const Text('No weight goal'),
          subtitle: const Text('Set a target to track progress towards it'),
          trailing: TextButton(
            onPressed: () => showTargetWeightDialog(context),
            child: const Text('Set a target'),
          ),
        ),
      );
    }

    final start = userProvider.userProfile?.targetWeightStart;
    final current = userProvider.currentWeight;
    final verb =
        progress.direction == WeightGoalDirection.lose ? 'to lose' : 'to gain';
    final status = progress.reached
        ? 'Goal reached'
        : (progress.remainingKg == null
            ? 'Log a weight to see progress'
            : '${formatWeight(progress.remainingKg!, unit: unit)} $verb');

    return Card(
      child: InkWell(
        onTap: () => showTargetWeightDialog(context),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    progress.reached ? Icons.check_circle : Icons.flag_outlined,
                    size: 20,
                    color: progress.reached
                        ? context.semanticColors.success
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('Weight goal',
                        style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    formatWeight(progress.targetKg, unit: unit),
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (progress.fraction != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: LinearProgressIndicator(
                    value: progress.fraction,
                    minHeight: 8,
                    color: progress.reached
                        ? context.semanticColors.success
                        : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(status, style: theme.textTheme.bodyMedium),
              if (start != null && current != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${formatWeight(start, unit: unit)} → '
                  '${formatWeight(current, unit: unit)} → '
                  '${formatWeight(progress.targetKg, unit: unit)}',
                  style: muted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
