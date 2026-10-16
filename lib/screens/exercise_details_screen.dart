import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dialogs/exercise_form_dialog.dart';
import '../models/exercise.dart';
import '../providers/exercise_provider.dart';
import '../utils/app_spacing.dart';
import '../utils/muscle_region_mapping.dart';
import '../widgets/muscle_map_section.dart';

/// Everything known about one exercise, including the muscle map.
///
/// A full screen rather than the `AlertDialog` this replaced: an anatomical
/// figure plus its front/back toggle does not fit in a dialog alongside the
/// instructions and type chips, and every other "details of one thing" surface
/// in the app (see [WorkoutDetailScreen]) is already a screen.
///
/// Takes an id, not an [Exercise], and reads the row live from
/// [ExerciseProvider]: editing the muscle groups from the app-bar action has to
/// repaint the diagram underneath without a round trip through the caller.
class ExerciseDetailsScreen extends StatelessWidget {
  final int exerciseId;

  const ExerciseDetailsScreen({super.key, required this.exerciseId});

  Future<void> _editExercise(BuildContext context, Exercise exercise) async {
    await showDialog<bool>(
      context: context,
      builder: (context) => ExerciseFormDialog(exercise: exercise),
    );
    // No setState and no result handling: this screen watches the provider, so
    // a successful save has already repainted it.
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ExerciseProvider>(
      builder: (context, exerciseProvider, child) {
        final exercise = exerciseProvider.getExerciseById(exerciseId);

        // Deleting the exercise from another surface while this screen is on
        // the stack is reachable, so it gets a real empty state rather than a
        // null-assertion crash.
        if (exercise == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Exercise')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.do_not_disturb_on_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'This exercise was deleted',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final theme = Theme.of(context);
        final activeMuscles = musclesForExercise(exercise);
        final undrawable = undrawableMuscleGroups(exercise);

        return Scaffold(
          appBar: AppBar(
            title: Text(exercise.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit exercise',
                onPressed: () => _editExercise(context, exercise),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (exercise.instructions?.trim().isNotEmpty ?? false) ...[
                _SectionHeader('Instructions'),
                const SizedBox(height: AppSpacing.sm),
                Text(exercise.instructions!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.lg),
              ],

              if (exercise.muscleGroups.isNotEmpty) ...[
                _SectionHeader('Muscle Groups'),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  exercise.muscleGroups.join(', '),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              _SectionHeader('Exercise Type'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (exercise.isWeightBased) const Chip(label: Text('Weight-based')),
                  if (exercise.isRepsBased) const Chip(label: Text('Reps-based')),
                  if (exercise.isTimeBased) const Chip(label: Text('Time-based')),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              _SectionHeader('Muscle Map'),
              const SizedBox(height: AppSpacing.sm),
              MuscleMapSection(
                exercise: exercise,
                activeMuscles: activeMuscles,
                undrawableGroups: undrawable,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}
