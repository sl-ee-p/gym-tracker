import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/exercise.dart';
import '../providers/workout_provider.dart';
import '../providers/exercise_provider.dart';
import '../widgets/exercise_sets_card.dart';
import '../widgets/set_input_form.dart';
import '../widgets/rest_timer_widget.dart';
import '../dialogs/exercise_form_dialog.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  bool _showRestTimer = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout'),
        actions: [
          Consumer<WorkoutProvider>(
            builder: (context, workoutProvider, child) {
              if (workoutProvider.hasActiveWorkout) {
                return PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'complete') {
                      await _completeWorkout();
                    } else if (value == 'cancel') {
                      await _cancelWorkout();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'complete',
                      child: Text('Complete Workout'),
                    ),
                    const PopupMenuItem(
                      value: 'cancel',
                      child: Text('Cancel Workout'),
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<WorkoutProvider>(
        builder: (context, workoutProvider, child) {
          if (!workoutProvider.hasActiveWorkout) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.fitness_center,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Active Workout',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a new workout to begin tracking your exercises',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await workoutProvider.startWorkout(
                        workoutName: 'My Workout',
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Start Workout'),
                  ),
                ],
              ),
            );
          }

          final activeWorkout = workoutProvider.activeWorkout!;
          final currentWorkoutExercises = workoutProvider.getCurrentWorkoutExercises();
          
          return Stack(
            children: [
              Column(
                children: [
                  // Workout Header
                  Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            activeWorkout.name ?? 'My Workout',
                            style: Theme.of(context).textTheme.headlineSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton.filledTonal(
                            onPressed: _showAddExerciseDialog,
                            tooltip: 'Add exercise',
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.add, size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.timer,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Consumer<WorkoutProvider>(
                          builder: (context, provider, _) {
                            final duration = provider.currentWorkoutDuration;
                            return Text(
                              duration != null ? _formatDuration(duration) : '0m',
                              style: Theme.of(context).textTheme.bodyMedium,
                            );
                          },
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.fitness_center,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${currentWorkoutExercises.length} exercises',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.repeat,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${workoutProvider.currentSets.length} sets',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Exercise List
              Expanded(
                child: currentWorkoutExercises.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_circle_outline,
                              size: 48,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Add your first exercise',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap the + button to get started',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _showAddExerciseDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('Add First Exercise'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: currentWorkoutExercises.length,
                        itemBuilder: (context, index) {
                          final exerciseId = currentWorkoutExercises[index];
                          return Consumer<ExerciseProvider>(
                            builder: (context, exerciseProvider, child) {
                              final exercise = exerciseProvider.getExerciseById(exerciseId);
                              if (exercise == null) return const SizedBox.shrink();
                              
                              final sets = workoutProvider.getSetsForExercise(exerciseId);
                              
                              return Column(
                                children: [
                                  // Exercise Sets Card
                                  ExerciseSetsCard(
                                    exercise: exercise,
                                    sets: sets,
                                    isActiveWorkout: true,
                                    onDeleteSet: (set) async {
                                      await workoutProvider.deleteSet(set.id!);
                                    },
                                  ),
                                  
                                  const SizedBox(height: 16),
                                  
                                  // Set Input Form
                                  SetInputForm(
                                    exercise: exercise,
                                    previousWeight: workoutProvider.getLastSetForExercise(exerciseId)?.weight,
                                    previousReps: workoutProvider.getLastSetForExercise(exerciseId)?.reps,
                                    previousDuration: workoutProvider.getLastSetForExercise(exerciseId)?.duration,
                                    onSetAdded: (weight, reps, duration, notes) async {
                                      await workoutProvider.addSet(
                                        exerciseId: exerciseId,
                                        weight: weight,
                                        reps: reps,
                                        duration: duration,
                                        notes: notes,
                                      );
                                    },
                                    onRestTimerRequested: ([int? restTime]) {
                                      setState(() {
                                        _showRestTimer = true;
                                      });
                                    },
                                  ),
                                  
                                  const SizedBox(height: 24),
                                ],
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
          // Rest Timer Overlay
          if (_showRestTimer)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: RestTimerWidget(
                    onTimerComplete: () {
                      setState(() {
                        _showRestTimer = false;
                      });
                    },
                    onDismiss: () {
                      setState(() {
                        _showRestTimer = false;
                      });
                    },
                  ),
                ),
              ),
            ),
          ],
        );
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  Future<void> _completeWorkout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Workout'),
        content: const Text('Are you sure you want to complete this workout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<WorkoutProvider>().completeWorkout();
    }
  }

  Future<void> _cancelWorkout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Workout'),
        content: const Text('Are you sure you want to cancel this workout? All progress will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Workout'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Cancel Workout'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<WorkoutProvider>().cancelWorkout();
    }
  }

  Future<void> _showAddExerciseDialog() async {
    final workoutProvider = context.read<WorkoutProvider>();
    final currentExerciseIds = workoutProvider.getCurrentWorkoutExercises().toSet();

    final selectedExercise = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        String searchQuery = '';

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> createExerciseFromSearch() async {
              final requestedName = searchQuery.trim();
              final result = await showDialog<bool>(
                context: context,
                builder: (context) => ExerciseFormDialog(
                  initialName: requestedName.isEmpty ? null : requestedName,
                ),
              );

              if (result != true || !context.mounted) {
                return;
              }

              final updatedExercises = context
                  .read<ExerciseProvider>()
                  .exercises
                  .where((exercise) =>
                      exercise.id != null &&
                      !currentExerciseIds.contains(exercise.id))
                  .toList();

              if (requestedName.isNotEmpty) {
                final createdMatch = updatedExercises
                    .where(
                      (exercise) =>
                          exercise.name.trim().toLowerCase() ==
                          requestedName.toLowerCase(),
                    )
                    .toList()
                  ..sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));

                if (createdMatch.isNotEmpty) {
                  if (context.mounted) {
                    Navigator.of(context).pop(createdMatch.first);
                  }
                  return;
                }
              }

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Exercise created. Tap it below to add it.'),
                  ),
                );
              }
            }

            return Consumer<ExerciseProvider>(
              builder: (context, exerciseProvider, child) {
                final availableExercises = exerciseProvider.exercises
                    .where((exercise) =>
                        exercise.id != null &&
                        !currentExerciseIds.contains(exercise.id))
                    .toList()
                  ..sort((a, b) => a.name.compareTo(b.name));

                final filteredExercises = availableExercises
                    .where((exercise) => exercise.name
                        .toLowerCase()
                        .contains(searchQuery.toLowerCase()))
                    .toList();

                final canCreateNamed = searchQuery.trim().isNotEmpty;

                return SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 8,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                    ),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.72,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Exercise',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'Search exercises',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                onPressed: createExerciseFromSearch,
                                tooltip: canCreateNamed
                                    ? 'Create "${searchQuery.trim()}"'
                                    : 'Create new exercise',
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ),
                            onChanged: (value) {
                              setModalState(() {
                                searchQuery = value;
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: createExerciseFromSearch,
                              icon: const Icon(Icons.add),
                              label: Text(
                                canCreateNamed
                                    ? 'Create "${searchQuery.trim()}"'
                                    : 'Create new exercise',
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: availableExercises.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'No exercises available yet',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        ElevatedButton.icon(
                                          onPressed: createExerciseFromSearch,
                                          icon: const Icon(Icons.add),
                                          label: const Text('Create first exercise'),
                                        ),
                                      ],
                                    ),
                                  )
                                : filteredExercises.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'No exercises match your search',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                            const SizedBox(height: 12),
                                            OutlinedButton.icon(
                                              onPressed: createExerciseFromSearch,
                                              icon: const Icon(Icons.add),
                                              label: Text(
                                                canCreateNamed
                                                    ? 'Create "${searchQuery.trim()}"'
                                                    : 'Create new exercise',
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.separated(
                                        itemCount: filteredExercises.length,
                                        separatorBuilder: (_, __) => const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                          final exercise = filteredExercises[index];
                                          return ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: const CircleAvatar(
                                              child: Icon(Icons.fitness_center, size: 18),
                                            ),
                                            title: Text(exercise.name),
                                            subtitle: exercise.muscleGroups.isNotEmpty
                                                ? Text(
                                                    exercise.muscleGroups
                                                        .take(2)
                                                        .join(' • '),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  )
                                                : null,
                                            trailing:
                                                const Icon(Icons.add_circle_outline),
                                            onTap: () => Navigator.of(context).pop(exercise),
                                          );
                                        },
                                      ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    if (selectedExercise != null && mounted) {
      workoutProvider.addExerciseToWorkout(selectedExercise.id!);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${selectedExercise.name} added to workout'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }


}