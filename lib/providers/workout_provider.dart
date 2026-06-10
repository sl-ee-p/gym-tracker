import 'package:flutter/material.dart';
import '../models/workout_session.dart';
import '../models/exercise_set.dart';
import '../services/workout_repository.dart';

class WorkoutProvider extends ChangeNotifier {
  final WorkoutRepository _repository = WorkoutRepository();
  
  // Active workout state
  WorkoutSession? _activeWorkout;
  List<ExerciseSet> _currentSets = [];
  List<int> _currentWorkoutExercises = []; // Track exercises in current workout
  DateTime? _workoutStartTime;
  
  // Workout history
  List<WorkoutSession> _workoutHistory = [];
  final Map<int, List<ExerciseSet>> _workoutSets = {};
  
  bool _isLoading = false;
  
  // Getters
  WorkoutSession? get activeWorkout => _activeWorkout;
  List<ExerciseSet> get currentSets => _currentSets;
  DateTime? get workoutStartTime => _workoutStartTime;
  List<WorkoutSession> get workoutHistory => _workoutHistory;
  bool get isLoading => _isLoading;
  bool get hasActiveWorkout => _activeWorkout != null;
  
  Duration? get currentWorkoutDuration {
    if (_workoutStartTime == null) return null;
    return DateTime.now().difference(_workoutStartTime!);
  }

  // Load data
  Future<void> loadWorkoutHistory({int? limit}) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _workoutHistory = await _repository.getAllWorkouts(limit: limit);
      
      // Load sets for each workout
      for (final workout in _workoutHistory) {
        if (workout.id != null) {
          final sets = await _repository.getSetsByWorkout(workout.id!);
          _workoutSets[workout.id!] = sets;
        }
      }
    } catch (e) {
      debugPrint('Error loading workout history: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadActiveWorkout() async {
    try {
      _activeWorkout = await _repository.getActiveWorkout();
      
      if (_activeWorkout != null) {
        _currentSets = await _repository.getSetsByWorkout(_activeWorkout!.id!);
        _workoutStartTime = _activeWorkout!.date;
        
        // Rebuild exercise list from sets
        final exerciseIds = <int>{};
        for (final set in _currentSets) {
          exerciseIds.add(set.exerciseId);
        }
        _currentWorkoutExercises = exerciseIds.toList();
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading active workout: $e');
    }
  }

  // Workout management
  Future<void> startWorkout({
    String? workoutName,
    int? categoryId,
  }) async {
    try {
      if (_activeWorkout != null) {
        throw Exception('A workout is already active');
      }

      final workout = WorkoutSession(
        date: DateTime.now(),
        name: workoutName,
        categoryId: categoryId,
        isCompleted: false,
      );

      final id = await _repository.insertWorkout(workout);
      _activeWorkout = workout.copyWith(id: id);
      _workoutStartTime = DateTime.now();
      _currentSets = [];
      _currentWorkoutExercises = [];
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error starting workout: $e');
      rethrow;
    }
  }

  Future<void> completeWorkout({String? notes}) async {
    try {
      if (_activeWorkout == null) return;

      final duration = _workoutStartTime != null 
          ? DateTime.now().difference(_workoutStartTime!)
          : null;

      // Update workout with completion status
      final completedWorkout = _activeWorkout!.copyWith(
        isCompleted: true,
        duration: duration,
        notes: notes,
      );

      await _repository.updateWorkout(completedWorkout);
      
      // Reset active workout state
      _activeWorkout = null;
      _workoutStartTime = null;
      _currentSets = [];
      _currentWorkoutExercises = [];
      
      // Reload workout history to include the completed workout
      await loadWorkoutHistory();
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error completing workout: $e');
    }
  }

  Future<void> cancelWorkout() async {
    try {
      if (_activeWorkout == null) return;

      // Delete the workout and all its sets
      await _repository.deleteWorkout(_activeWorkout!.id!);
      
      // Reset state
      _activeWorkout = null;
      _workoutStartTime = null;
      _currentSets = [];
      _currentWorkoutExercises = [];
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error canceling workout: $e');
    }
  }

  Future<void> updateWorkout(WorkoutSession workout) async {
    try {
      await _repository.updateWorkout(workout);
      
      if (_activeWorkout?.id == workout.id) {
        _activeWorkout = workout;
      }
      
      // Update in history as well
      final index = _workoutHistory.indexWhere((w) => w.id == workout.id);
      if (index != -1) {
        _workoutHistory[index] = workout;
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating workout: $e');
    }
  }

  // Exercise set management
  Future<void> addSet({
    required int exerciseId,
    double? weight,
    int? reps,
    Duration? duration,
    String? notes,
  }) async {
    try {
      if (_activeWorkout == null) {
        throw Exception('No active workout');
      }

      // Calculate set number
      final existingSets = _currentSets
          .where((set) => set.exerciseId == exerciseId)
          .toList();
      final setNumber = existingSets.length + 1;

      final set = ExerciseSet(
        workoutSessionId: _activeWorkout!.id!,
        exerciseId: exerciseId,
        setNumber: setNumber,
        weight: weight,
        reps: reps,
        duration: duration,
        notes: notes,
        timestamp: DateTime.now(),
      );

      final id = await _repository.insertSet(set);
      final newSet = set.copyWith(id: id);
      _currentSets.add(newSet);
      
      // Ensure exercise is in the workout exercises list
      if (!_currentWorkoutExercises.contains(exerciseId)) {
        _currentWorkoutExercises.add(exerciseId);
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding set: $e');
      rethrow;
    }
  }

  Future<void> updateSet(ExerciseSet set) async {
    try {
      await _repository.updateSet(set);
      
      final index = _currentSets.indexWhere((s) => s.id == set.id);
      if (index != -1) {
        _currentSets[index] = set;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating set: $e');
    }
  }

  Future<void> deleteSet(int setId) async {
    try {
      await _repository.deleteSet(setId);
      _currentSets.removeWhere((set) => set.id == setId);
      
      // Renumber remaining sets for each exercise
      final groupedSets = <int, List<ExerciseSet>>{};
      for (final set in _currentSets) {
        groupedSets.putIfAbsent(set.exerciseId, () => []).add(set);
      }

      for (final exerciseId in groupedSets.keys) {
        final sets = groupedSets[exerciseId]!;
        sets.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        
        for (int i = 0; i < sets.length; i++) {
          if (sets[i].setNumber != i + 1) {
            final updatedSet = sets[i].copyWith(setNumber: i + 1);
            await _repository.updateSet(updatedSet);
            _currentSets[_currentSets.indexWhere((s) => s.id == sets[i].id)] = updatedSet;
          }
        }
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting set: $e');
    }
  }

  // Get sets for specific exercise in current workout
  List<ExerciseSet> getSetsForExercise(int exerciseId) {
    return _currentSets
        .where((set) => set.exerciseId == exerciseId)
        .toList()
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
  }

  // Get unique exercises in current workout
  List<int> getCurrentWorkoutExercises() {
    return List.from(_currentWorkoutExercises);
  }

  // Add exercise to current workout
  void addExerciseToWorkout(int exerciseId) {
    if (!_currentWorkoutExercises.contains(exerciseId)) {
      _currentWorkoutExercises.add(exerciseId);
      notifyListeners();
    }
  }

  // Remove exercise from current workout (if no sets exist)
  void removeExerciseFromWorkout(int exerciseId) {
    final hasSets = _currentSets.any((set) => set.exerciseId == exerciseId);
    if (!hasSets) {
      _currentWorkoutExercises.remove(exerciseId);
      notifyListeners();
    }
  }

  // Statistics
  double getTotalVolumeForWorkout(int workoutId) {
    final sets = _workoutSets[workoutId] ?? [];
    return sets.fold(0.0, (total, set) => total + (set.volume ?? 0));
  }

  int getTotalSetsForWorkout(int workoutId) {
    return _workoutSets[workoutId]?.length ?? 0;
  }

  int getUniqueExerciseCountForWorkout(int workoutId) {
    final sets = _workoutSets[workoutId] ?? [];
    return sets.map((set) => set.exerciseId).toSet().length;
  }

  Map<String, dynamic> getCurrentWorkoutStats() {
    final totalSets = _currentSets.length;
    final totalVolume = _currentSets.fold(0.0, (sum, set) => sum + (set.volume ?? 0));
    final uniqueExercises = getCurrentWorkoutExercises().length;
    
    return {
      'totalSets': totalSets,
      'totalVolume': totalVolume,
      'uniqueExercises': uniqueExercises,
      'duration': currentWorkoutDuration,
    };
  }

  // Get last set for an exercise (for reference in next set)
  ExerciseSet? getLastSetForExercise(int exerciseId) {
    final exerciseSets = getSetsForExercise(exerciseId);
    return exerciseSets.isEmpty ? null : exerciseSets.last;
  }

  // Get all sets for a specific workout (for workout detail screen)
  Future<List<ExerciseSet>> getWorkoutSets(int workoutId) async {
    try {
      return await _repository.getSetsByWorkout(workoutId);
    } catch (e) {
      debugPrint('Error getting workout sets: $e');
      return [];
    }
  }

  Future<void> initialize() async {
    await Future.wait([
      loadActiveWorkout(),
      loadWorkoutHistory(limit: 20),
    ]);
  }
}