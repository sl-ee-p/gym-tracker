import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/exercise_provider.dart';
import '../utils/app_spacing.dart';
import '../utils/muscle_region_mapping.dart';
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/muscle_map_section.dart';

/// Browse the muscle map by exercise: pick a movement, see what it works.
///
/// The counterpart to opening the diagram from one exercise's details screen —
/// same [MuscleMapSection] underneath, so the two can't disagree about what an
/// exercise highlights.
class MuscleMapScreen extends StatefulWidget {
  const MuscleMapScreen({super.key});

  @override
  State<MuscleMapScreen> createState() => _MuscleMapScreenState();
}

class _MuscleMapScreenState extends State<MuscleMapScreen> {
  /// The id rather than the [Exercise], so an edit made elsewhere while this
  /// screen is open is picked up on the next build instead of going stale.
  int? _exerciseId;

  Future<void> _pickExercise() async {
    // Reuses the app-wide picker (typo-tolerant search, category chips)
    // rather than growing a second exercise list here.
    final picked = await showExercisePickerSheet(
      context,
      title: 'Choose Exercise',
    );
    if (picked == null || !mounted) return;
    setState(() => _exerciseId = picked.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Muscle Map')),
      body: Consumer<ExerciseProvider>(
        builder: (context, exerciseProvider, child) {
          final id = _exerciseId;
          final exercise = id == null ? null : exerciseProvider.getExerciseById(id);

          // Covers both "nothing picked yet" and "the picked exercise has since
          // been deleted", which want the same prompt.
          if (exercise == null) return _EmptyState(onPick: _pickExercise);

          final theme = Theme.of(context);

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exercise.name, style: theme.textTheme.titleLarge),
                        if (exercise.muscleGroups.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            exercise.muscleGroups.join(', '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: _pickExercise,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Change'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              MuscleMapSection(
                exercise: exercise,
                activeMuscles: musclesForExercise(exercise),
                undrawableGroups: undrawableMuscleGroups(exercise),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPick;

  const _EmptyState({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.accessibility_new,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('See what an exercise works', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Pick an exercise to highlight it on the muscle map.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.search),
              label: const Text('Choose Exercise'),
            ),
          ],
        ),
      ),
    );
  }
}
