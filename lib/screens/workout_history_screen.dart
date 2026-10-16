import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/workout_session.dart';
import '../providers/user_provider.dart';
import '../providers/workout_provider.dart';
import '../utils/weight_format.dart';
import 'workout_detail_screen.dart';
import '../utils/app_date.dart';

class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen> {

  /// The display unit for every weight this screen renders. Stored weights
  /// are always kg; formatWeight converts before formatting.
  String get weightUnit => context.watch<UserProvider>().weightUnit;

  @override
  void initState() {
    super.initState();
    // Load workout history when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WorkoutProvider>().loadWorkoutHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<WorkoutProvider>().loadWorkoutHistory();
            },
          ),
        ],
      ),
      body: Consumer<WorkoutProvider>(
        builder: (context, workoutProvider, child) {
          if (workoutProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final workouts = workoutProvider.workoutHistory
              .where((workout) => workout.isCompleted)
              .toList();

          if (workouts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Workouts Yet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete your first workout to see it here',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => workoutProvider.loadWorkoutHistory(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: workouts.length,
              itemBuilder: (context, index) {
                final workout = workouts[index];
                return _buildWorkoutCard(context, workout, workoutProvider);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildWorkoutCard(BuildContext context, WorkoutSession workout, WorkoutProvider workoutProvider) {
    final stats = _getWorkoutStats(workout, workoutProvider);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          workout.name ?? 'Workout',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            
            // Date
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDate(workout.date),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            
            const SizedBox(height: 4),
            
            // Stats Row
            Row(
              children: [
                // Duration
                if (workout.duration != null) ...[
                  Icon(
                    Icons.timer,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(workout.duration!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 16),
                ],
                
                // Exercises
                Icon(
                  Icons.fitness_center,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '${stats['exercises']} exercise${stats['exercises'] != 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                
                const SizedBox(width: 16),
                
                // Sets
                Icon(
                  Icons.repeat,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '${stats['sets']} set${stats['sets'] != 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            
            // Volume (if available)
            if (stats['volume'] > 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.scale,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${formatWeight(stats['volume'] as double, unit: weightUnit)} total',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.replay),
              tooltip: (stats['exercises'] as int) > 0
                  ? 'Repeat workout'
                  : 'No exercises to repeat',
              onPressed: (stats['exercises'] as int) > 0
                  ? () => repeatPastWorkout(context, workout)
                  : null,
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _navigateToWorkoutDetail(workout),
      ),
    );
  }

  Map<String, dynamic> _getWorkoutStats(WorkoutSession workout, WorkoutProvider workoutProvider) {
    if (workout.id == null) {
      return {'exercises': 0, 'sets': 0, 'volume': 0.0};
    }
    
    final totalSets = workoutProvider.getTotalSetsForWorkout(workout.id!);
    final totalVolume = workoutProvider.getTotalVolumeForWorkout(workout.id!);
    final totalExercises = workoutProvider.getUniqueExerciseCountForWorkout(workout.id!);
    
    return {
      'exercises': totalExercises,
      'sets': totalSets,
      'volume': totalVolume,
    };
  }
  
  void _navigateToWorkoutDetail(WorkoutSession workout) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WorkoutDetailScreen(workout: workout),
      ),
    );
  }

  String _formatDate(DateTime date) {
    // daysBetween, not today.difference(entryDate).inDays: two local
    // midnights are 23 or 25 hours apart across a DST transition, so the
    // truncating division silently reported "Yesterday" for today.
    final difference = daysBetween(date, DateTime.now());

    if (difference == 0) {
      return 'Today ${_formatTime(date)}';
    } else if (difference == 1) {
      return 'Yesterday ${_formatTime(date)}';
    } else if (difference < 7) {
      final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${weekdays[date.weekday - 1]} ${_formatTime(date)}';
    } else {
      return '${date.day}/${date.month}/${date.year} ${_formatTime(date)}';
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