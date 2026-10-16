import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/exercise.dart';
import '../models/exercise_set.dart';
import '../providers/user_provider.dart';
import '../screens/progress_screen.dart';
import '../theme/app_theme.dart';
import '../theme/numeric_text_styles.dart';
import '../utils/app_spacing.dart';
import '../utils/weight_format.dart';
import 'app_overflow_menu.dart';

class ExerciseSetsCard extends StatelessWidget {
  final Exercise exercise;
  final List<ExerciseSet> sets;
  final Function(ExerciseSet)? onDeleteSet;
  final Function(ExerciseSet)? onEditSet;
  final VoidCallback? onRemoveExercise;
  final bool isActiveWorkout;
  final bool isSelected;
  final VoidCallback? onTap;

  /// This exercise's 1-based position within its superset/circuit group,
  /// paired with [groupSize] to render the "Superset N/size" chip. `null`
  /// (the default) means standalone — no chip, no "Remove from superset"
  /// menu item.
  final int? groupPosition;

  /// The total number of exercises in this group. `null` for a standalone
  /// exercise.
  final int? groupSize;

  /// "Group with…" in the overflow menu — always offered when
  /// [isActiveWorkout], whether or not this exercise is already grouped.
  final VoidCallback? onGroupWith;

  /// "Remove from superset" in the overflow menu — only offered when
  /// [groupSize] is non-null.
  final VoidCallback? onUngroup;

  /// "Add warm-up sets" in the overflow menu — only offered for exercises
  /// logged by weight and reps, the only ones a ramp makes sense for.
  final VoidCallback? onGenerateWarmups;

  // Personal-record marking used to arrive here as a Set<int> of "sets this
  // screen just logged". It is now read off ExerciseSet.isPersonalRecord, so
  // the badge is identical in the live workout and in history, and survives
  // the screen being disposed.

  const ExerciseSetsCard({
    super.key,
    required this.exercise,
    required this.sets,
    this.onDeleteSet,
    this.onEditSet,
    this.onRemoveExercise,
    this.isActiveWorkout = false,
    this.isSelected = false,
    this.onTap,
    this.groupPosition,
    this.groupSize,
    this.onGroupWith,
    this.onUngroup,
    this.onGenerateWarmups,
  });

  @override
  Widget build(BuildContext context) {
    final weightUnit = context.watch<UserProvider>().weightUnit;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: isSelected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (exercise.muscleGroups.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          exercise.muscleGroups.join(', '),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (groupSize != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Superset $groupPosition/$groupSize',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                if (sets.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${sets.length} set${sets.length != 1 ? 's' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                if (isActiveWorkout) ...[
                  if (sets.isNotEmpty) const SizedBox(width: 4),
                  AppOverflowMenu(
                    tooltip: 'Exercise options',
                    items: [
                      AppMenuItem(
                        label: 'See stats',
                        icon: Icons.trending_up,
                        onSelected: () => _openStats(context),
                      ),
                      if (onGenerateWarmups != null &&
                          exercise.isWeightBased &&
                          exercise.isRepsBased)
                        AppMenuItem(
                          label: 'Add warm-up sets',
                          icon: Icons.whatshot_outlined,
                          onSelected: onGenerateWarmups!,
                        ),
                      if (onGroupWith != null)
                        AppMenuItem(
                          label: 'Group with…',
                          icon: Icons.link,
                          onSelected: onGroupWith!,
                        ),
                      if (groupSize != null && onUngroup != null)
                        AppMenuItem(
                          label: 'Remove from superset',
                          icon: Icons.link_off,
                          isDestructive: true,
                          onSelected: onUngroup!,
                        ),
                      // Only ever offered when sets.isEmpty — mirrors
                      // WorkoutProvider.removeExerciseFromWorkout's own no-op
                      // guard, so this action is never offered where it would
                      // silently do nothing.
                      if (sets.isEmpty && onRemoveExercise != null)
                        AppMenuItem(
                          label: 'Remove from workout',
                          icon: Icons.remove_circle_outline,
                          isDestructive: true,
                          onSelected: () => _confirmRemoveExercise(context),
                        ),
                    ],
                  ),
                ],
              ],
            ),

            if (sets.isNotEmpty) ...[
              const SizedBox(height: 16),
              
              // Sets Table Header
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 30, child: Text('Set', style: TextStyle(fontWeight: FontWeight.w600))),
                    if (exercise.isWeightBased) ...[
                      const SizedBox(width: 16),
                      const SizedBox(width: 60, child: Text('Weight', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600))),
                    ],
                    if (exercise.isRepsBased) ...[
                      const SizedBox(width: 16),
                      const SizedBox(width: 50, child: Text('Reps', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600))),
                    ],
                    if (exercise.isTimeBased) ...[
                      const SizedBox(width: 16),
                      const SizedBox(width: 70, child: Text('Duration', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600))),
                    ],
                    const Spacer(),
                    if (_hasSetActions) const SizedBox(width: 40), // Space for actions
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Sets List — each row settles in with a brief fade/scale on
              // first appearance (keyed by set id, so existing rows that
              // rebuild for an unrelated reason don't re-animate). Explicitly
              // not: a bounce/elastic overshoot or any celebratory flourish —
              // just enough to read as "this one just dropped in."
              ...sets.map((set) => TweenAnimationBuilder<double>(
                    key: ValueKey(set.id),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    builder: (context, t, child) => Opacity(
                      opacity: t,
                      child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
                    ),
                    child: _buildSetRow(context, set, weightUnit),
                  )),
            ] else ...[
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.fitness_center_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No sets recorded yet',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildSetRow(BuildContext context, ExerciseSet set, String weightUnit) {
    final colorScheme = Theme.of(context).colorScheme;
    // A Border object (not shorthand Border.all) so the warm-up accent below
    // can override just the left side without restructuring this decoration.
    final rowBorderSide = BorderSide(color: colorScheme.outlineVariant);
    // Warm-ups are excluded from volume, PRs and every progress aggregate, so
    // they need to read as a different kind of row at a glance — otherwise a
    // logged warm-up looks like a working set you failed to beat.
    final warmupSide = BorderSide(color: colorScheme.tertiary, width: 3);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: set.isWarmup
            ? colorScheme.surfaceContainerLowest
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          top: rowBorderSide,
          bottom: rowBorderSide,
          left: set.isWarmup ? warmupSide : rowBorderSide,
          right: rowBorderSide,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Set number, or a W for warm-ups — they still occupy a set
              // number in the data, but showing it invites reading them as
              // working sets.
              SizedBox(
                width: 30,
                child: Text(
                  set.isWarmup ? 'W' : '${set.setNumber}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: set.isWarmup ? colorScheme.tertiary : null,
                  ),
                ),
              ),

              // Weight
              if (exercise.isWeightBased) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: 68,
                  child: Text(
                    set.weight != null
                        ? formatWeight(set.weight!, unit: weightUnit)
                        : '-',
                    textAlign: TextAlign.center,
                    style: NumericTextStyles.body(color: colorScheme.onSurface),
                  ),
                ),
              ],

              // Reps
              if (exercise.isRepsBased) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: 50,
                  // Partials ride along as a smaller, muted "+3" — visibly
                  // extra, not part of the rep count. scaleDown keeps
                  // "12 +10" inside the fixed column instead of overflowing.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text.rich(
                      TextSpan(
                        text: set.reps?.toString() ?? '-',
                        children: [
                          if (set.hasPartialReps)
                            TextSpan(
                              text: ' +${set.partialReps}',
                              style: NumericTextStyles.body(
                                color: colorScheme.onSurfaceVariant,
                              ).copyWith(fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: NumericTextStyles.body(color: colorScheme.onSurface),
                    ),
                  ),
                ),
              ],

              // Duration
              if (exercise.isTimeBased) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: 70,
                  child: Text(
                    set.duration != null ? _formatDuration(set.duration!) : '-',
                    textAlign: TextAlign.center,
                    style: NumericTextStyles.body(color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ],

              const Spacer(),

              // Actions — whenever the caller wired any. A past workout
              // passes Edit only; the live one passes Edit and Delete.
              if (_hasSetActions) ...[
                AppOverflowMenu(
                  tooltip: 'Set options',
                  iconSize: 18,
                  items: [
                    if (onEditSet != null)
                      AppMenuItem(
                        label: 'Edit',
                        icon: Icons.edit,
                        onSelected: () => onEditSet?.call(set),
                      ),
                    if (onDeleteSet != null)
                      AppMenuItem(
                        label: 'Delete',
                        icon: Icons.delete,
                        isDestructive: true,
                        onSelected: () => _confirmDeleteSet(context, set),
                      ),
                  ],
                ),
              ],
            ],
          ),

          // Notes — shown on their own full-width line so they are fully
          // readable instead of being truncated.
          if (set.notes != null && set.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.sticky_note_2_outlined,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    set.notes!.trim(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (set.isWarmup || set.isPersonalRecord || set.rpe != null) ...[
            const SizedBox(height: 4),
            // Wrap, not Row: three tags can outgrow a narrow card.
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 2,
              children: [
                if (set.isWarmup)
                  _Tag(
                    icon: Icons.whatshot_outlined,
                    label: 'Warm-up',
                    color: colorScheme.tertiary,
                  ),
                // Neutral colour: effort is information, not an achievement.
                if (set.rpe != null)
                  _Tag(
                    icon: Icons.speed,
                    label: 'RPE ${formatRpe(set.rpe!)}',
                    color: colorScheme.onSurfaceVariant,
                  ),
                // "New best" reads as a fact, not a cheer. Deliberately not
                // using: a trophy icon, a gold/orange "achievement" color, an
                // exclamation mark, or a scale-in animation.
                //
                // Read straight off the persisted set, so it survives leaving
                // and re-entering the workout and shows up in history too —
                // it used to live in a Set<int> on WorkoutScreen's State,
                // which every nav-tab switch threw away.
                if (set.isPersonalRecord)
                  _Tag(
                    icon: Icons.trending_up,
                    label: 'New best',
                    color: context.semanticColors.success,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool get _hasSetActions => onEditSet != null || onDeleteSet != null;

  void _confirmDeleteSet(BuildContext context, ExerciseSet set) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Set'),
        content: Text('Are you sure you want to delete set ${set.setNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        onDeleteSet?.call(set);
      }
    });
  }

  void _openStats(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProgressScreen(initialExerciseId: exercise.id),
      ),
    );
  }

  void _confirmRemoveExercise(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Exercise'),
        content: Text('Remove ${exercise.name} from this workout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        onRemoveExercise?.call();
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    
    if (minutes > 0) {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${seconds}s';
    }
  }
}
/// A small icon+label marker used for the per-set warm-up and personal-record
/// annotations. Kept flat and quiet — no pill background, no border — so a row
/// carrying both still reads as one line of metadata rather than two chips.
class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
