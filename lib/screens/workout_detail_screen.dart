import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/workout_session.dart';
import '../models/exercise_set.dart';
import '../providers/workout_provider.dart';
import '../providers/exercise_provider.dart';
import '../widgets/exercise_sets_card.dart';

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
      appBar: AppBar(
        title: Text(widget.workout.name ?? 'Workout Details'),
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
                      '${stats['volume'].toStringAsFixed(1)} kg',
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
              isActiveWorkout: false, // This is a past workout, no editing
            ),
          );
        },
      );
    }).toList();
  }

  Map<String, dynamic> _calculateWorkoutStats() {
    final exerciseIds = <int>{};
    double totalVolume = 0;
    
    for (final set in _workoutSets) {
      exerciseIds.add(set.exerciseId);
      if (set.weight != null && set.reps != null) {
        totalVolume += set.weight! * set.reps!;
      }
    }
    
    return {
      'exercises': exerciseIds.length,
      'sets': _workoutSets.length,
      'volume': totalVolume,
    };
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Today, ${_formatTime(date)}';
    } else if (difference.inDays == 1) {
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