import 'package:flutter/material.dart';
import 'package:flutter_body_atlas/flutter_body_atlas.dart';

import '../models/exercise.dart';
import '../utils/app_spacing.dart';
import '../utils/muscle_region_mapping.dart';
import 'muscle_diagram.dart';

/// The diagram plus the two bits of copy that only make sense next to it: what
/// the highlight colour means, and which typed muscle groups aren't drawn.
///
/// Shared by [ExerciseDetailsScreen] and the standalone Muscle Map screen, so
/// an unmatched muscle string is explained identically in both places.
class MuscleMapSection extends StatelessWidget {
  final Exercise exercise;
  final Set<Muscle> activeMuscles;
  final List<String> undrawableGroups;

  const MuscleMapSection({
    super.key,
    required this.exercise,
    required this.activeMuscles,
    required this.undrawableGroups,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (activeMuscles.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              exercise.muscleGroups.isEmpty
                  ? 'No muscle groups recorded for this exercise yet — add some '
                      'with Edit to see them highlighted.'
                  : 'None of this exercise\'s muscle groups can be shown on the '
                      'diagram.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Muscles worked',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

        MuscleDiagram(
          activeMuscles: activeMuscles,
          initialView: preferredViewForExercise(exercise),
        ),

        if (undrawableGroups.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Not shown on the diagram: ${undrawableGroups.join(', ')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
