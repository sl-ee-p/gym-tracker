import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../dialogs/edit_set_dialog.dart';
import '../models/exercise.dart';
import '../models/workout_session.dart';
import '../models/exercise_set.dart';
import '../providers/workout_provider.dart';
import '../providers/exercise_provider.dart';
import '../providers/progress_provider.dart';
import '../providers/user_provider.dart';
import '../utils/weight_format.dart';
import '../widgets/exercise_sets_card.dart';
import 'workout_screen.dart';
import '../utils/app_date.dart';
import '../widgets/system_nav_bar_spacer.dart';

class WorkoutDetailScreen extends StatefulWidget {
  final WorkoutSession workout;
  
  const WorkoutDetailScreen({
    super.key,
    required this.workout,
  });

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {

  /// The display unit for every weight this screen renders. Stored weights
  /// are always kg; formatWeight converts before formatting.
  String get weightUnit => context.watch<UserProvider>().weightUnit;

  List<ExerciseSet> _workoutSets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkoutDetails();
  }

  Future<void> _loadWorkoutDetails() async {
    if (widget.workout.id == null) return;
    
    try {
      final workoutProvider = context.read<WorkoutProvider>();
      final sets = await workoutProvider.getWorkoutSets(widget.workout.id!);
      
      setState(() {
        _workoutSets = sets;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading workout details: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const SystemNavBarSpacer(),
      appBar: AppBar(
        title: Text(widget.workout.name ?? 'Workout Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.replay),
            tooltip: _workoutSets.isEmpty ? 'No exercises to repeat' : 'Repeat workout',
            onPressed: _isLoading || _workoutSets.isEmpty
                ? null
                : () => repeatPastWorkout(context, widget.workout),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Workout Header Card
                  _buildWorkoutHeaderCard(),
                  
                  const SizedBox(height: 16),
                  
                  // Exercises
                  if (_workoutSets.isNotEmpty) ...[
                    Text(
                      'Exercises',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    
                    ..._buildExerciseGroups(),
                  ] else ...[
                    Center(
                      child: Column(
                        children: [
                          const SizedBox(height: 40),
                          Icon(
                            Icons.fitness_center_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No exercises recorded',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
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

  Widget _buildWorkoutHeaderCard() {
    final stats = _calculateWorkoutStats();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date and Duration
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Date',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDate(widget.workout.date),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                if (widget.workout.duration != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Duration',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDuration(widget.workout.duration!),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Stats Grid
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Exercises',
                    stats['exercises'].toString(),
                    Icons.fitness_center,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Sets',
                    stats['sets'].toString(),
                    Icons.repeat,
                  ),
                ),
                if (stats['volume'] > 0)
                  Expanded(
                    child: _buildStatItem(
                      'Volume',
                      formatWeight(stats['volume'] as double, unit: weightUnit),
                      Icons.scale,
                    ),
                  ),
              ],
            ),
            
            // Notes (if any)
            if (widget.workout.notes != null && widget.workout.notes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Notes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                widget.workout.notes!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildExerciseGroups() {
    // Group sets by exercise
    final exerciseGroups = <int, List<ExerciseSet>>{};
    for (final set in _workoutSets) {
      exerciseGroups.putIfAbsent(set.exerciseId, () => []).add(set);
    }
    
    return exerciseGroups.entries.map((entry) {
      final exerciseId = entry.key;
      final sets = entry.value;
      
      return Consumer<ExerciseProvider>(
        builder: (context, exerciseProvider, child) {
          final exercise = exerciseProvider.getExerciseById(exerciseId);
          if (exercise == null) {
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Unknown Exercise (ID: $exerciseId)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            );
          }
          
          // Sort sets by set number
          sets.sort((a, b) => a.setNumber.compareTo(b.setNumber));
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ExerciseSetsCard(
              exercise: exercise,
              sets: sets,
              // A past workout: sets can be corrected, but not added,
              // deleted or regrouped.
              isActiveWorkout: false,
              onEditSet: (set) => _editSet(exercise, set),
            ),
          );
        },
      );
    }).toList();
  }

  Future<void> _editSet(Exercise exercise, ExerciseSet set) async {
    final edited =
        await showEditSetDialog(context, exercise: exercise, set: set);
    if (edited == null || !mounted) return;

    final progressProvider = context.read<ProgressProvider>();
    try {
      await context.read<WorkoutProvider>().updateSet(edited);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the set: $e')),
      );
      return;
    }

    // This screen holds its own copy of the sets, and an edit can move the
    // record badges on other sets too — reload rather than patch.
    await _loadWorkoutDetails();
    // A past set feeds every chart, total and the achievements feed.
    await progressProvider.loadAllProgressData();
  }

  Map<String, dynamic> _calculateWorkoutStats() {
    final exerciseIds = <int>{};
    double totalVolume = 0;
    
    for (final set in _workoutSets) {
      exerciseIds.add(set.exerciseId);
      // Warm-ups excluded, as in every other volume figure — otherwise this
      // header disagreed with the history list and the PDF for one workout.
      if (!set.isWarmup) totalVolume += set.volume ?? 0;
    }
    
    return {
      'exercises': exerciseIds.length,
      'sets': _workoutSets.length,
      'volume': totalVolume,
    };
  }

  String _formatDate(DateTime date) {
    // daysBetween, not today.difference(entryDate).inDays: two local
    // midnights are 23 or 25 hours apart across a DST transition, so the
    // truncating division silently reported "Yesterday" for today.
    final difference = daysBetween(date, DateTime.now());

    if (difference == 0) {
      return 'Today, ${_formatTime(date)}';
    } else if (difference == 1) {
      return 'Yesterday, ${_formatTime(date)}';
    } else {
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${date.day} ${months[date.month - 1]} ${date.year}, ${_formatTime(date)}';
    }
  }
  
  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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
}

/// Starts a new workout pre-filled with [sourceWorkout]'s exercises. Blocks
/// (rather than discarding) if a different workout is already active — an
/// in-progress workout with already-logged sets must never be silently
/// destroyed by an unrelated "repeat this old workout" action — and offers
/// a non-destructive shortcut to the active workout instead.
Future<void> repeatPastWorkout(
  BuildContext context,
  WorkoutSession sourceWorkout,
) async {
  if (sourceWorkout.id == null) return;

  final workoutProvider = context.read<WorkoutProvider>();

  if (workoutProvider.hasActiveWorkout) {
    final activeWorkout = workoutProvider.activeWorkout!;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Workout Already in Progress'),
        content: Text(
          'You already have "${activeWorkout.name ?? 'a workout'}" in '
          'progress. Finish or cancel it before starting a repeat of this '
          'workout.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WorkoutScreen()),
              );
            },
            child: const Text('Go to Active Workout'),
          ),
        ],
      ),
    );
    return;
  }

  // Confirm before duplicating. duplicateWorkout -> startWorkout inserts a
  // real workout_sessions row immediately, so a mis-tap on the replay icon
  // silently created a persisted in-progress workout — which then blocked
  // every other repeat and template action until it was found and cancelled.
  final exerciseNames =
      await _exerciseNamesForWorkout(context, sourceWorkout.id!);
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Repeat Workout'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start a new workout with the same exercises as '
            '"${sourceWorkout.name ?? 'this workout'}"?',
          ),
          if (exerciseNames.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              exerciseNames.join(' · '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Sets are not copied — you start from an empty log.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Start Workout'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    await workoutProvider.duplicateWorkout(sourceWorkout.id!);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not repeat workout: $e')),
      );
    }
    return;
  }

  if (context.mounted) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WorkoutScreen()),
    );
  }
}
/// Names of the distinct exercises in [workoutId], in the order
/// [WorkoutProvider.duplicateWorkout] will add them, for the repeat
/// confirmation dialog. Returns an empty list if anything goes wrong — the
/// dialog degrades to its headline question rather than failing.
Future<List<String>> _exerciseNamesForWorkout(
  BuildContext context,
  int workoutId,
) async {
  try {
    final workoutProvider = context.read<WorkoutProvider>();
    final exerciseProvider = context.read<ExerciseProvider>();
    final sets = await workoutProvider.getWorkoutSets(workoutId);
    // Same ordering duplicateWorkout uses: getWorkoutSets returns
    // "exerciseId, setNumber" order, which is not the order exercises were
    // actually performed in, and the dialog should list what will happen.
    final ordered = [...sets]..sort((a, b) {
        final byTime = a.timestamp.compareTo(b.timestamp);
        return byTime != 0 ? byTime : (a.id ?? 0).compareTo(b.id ?? 0);
      });
    final seen = <int>{};
    return [
      for (final set in ordered)
        if (seen.add(set.exerciseId))
          exerciseProvider.getExerciseById(set.exerciseId)?.name ??
              '(deleted exercise)',
    ];
  } catch (e) {
    debugPrint('Could not list exercises for repeat confirmation: $e');
    return const [];
  }
}
