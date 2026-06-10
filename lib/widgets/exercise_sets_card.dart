import 'package:flutter/material.dart';
import '../models/exercise.dart';
import '../models/exercise_set.dart';

class ExerciseSetsCard extends StatelessWidget {
  final Exercise exercise;
  final List<ExerciseSet> sets;
  final Function(ExerciseSet)? onDeleteSet;
  final Function(ExerciseSet)? onEditSet;
  final bool isActiveWorkout;

  const ExerciseSetsCard({
    super.key,
    required this.exercise,
    required this.sets,
    this.onDeleteSet,
    this.onEditSet,
    this.isActiveWorkout = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
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
                            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
                    const Expanded(child: Text('Notes', style: TextStyle(fontWeight: FontWeight.w600))),
                    if (isActiveWorkout) const SizedBox(width: 40), // Space for actions
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Sets List
              ...sets.map((set) => _buildSetRow(context, set)),
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
    );
  }

  Widget _buildSetRow(BuildContext context, ExerciseSet set) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          // Set Number
          SizedBox(
            width: 30,
            child: Text(
              '${set.setNumber}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // Weight
          if (exercise.isWeightBased) ...[
            const SizedBox(width: 16),
            SizedBox(
              width: 60,
              child: Text(
                set.weight != null ? '${set.weight!.toStringAsFixed(1)} kg' : '-',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],

          // Reps
          if (exercise.isRepsBased) ...[
            const SizedBox(width: 16),
            SizedBox(
              width: 50,
              child: Text(
                set.reps?.toString() ?? '-',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
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
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],

          // Notes
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              set.notes ?? '',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.8),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Actions (for active workout only)
          if (isActiveWorkout) ...[
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
              padding: EdgeInsets.zero,
              itemBuilder: (context) => [
                if (onEditSet != null)
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 16),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                if (onDeleteSet != null)
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEditSet?.call(set);
                    break;
                  case 'delete':
                    _confirmDeleteSet(context, set);
                    break;
                }
              },
            ),
          ],
        ],
      ),
    );
  }

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
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    
    if (minutes > 0) {
      return '${minutes}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${seconds}s';
    }
  }
}