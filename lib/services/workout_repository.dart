import '../models/workout_session.dart';
import '../models/exercise_set.dart';
import '../models/exercise.dart';
import 'database_helper.dart';

class WorkoutRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Workout Sessions
  Future<List<WorkoutSession>> getAllWorkouts({int? limit}) async {
    final maps = await _dbHelper.query(
      'workout_sessions',
      orderBy: 'date DESC',
      limit: limit,
    );
    return maps.map((map) => WorkoutSession.fromMap(map)).toList();
  }

  Future<List<WorkoutSession>> getWorkoutsByDateRange(DateTime start, DateTime end) async {
    final maps = await _dbHelper.query(
      'workout_sessions',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date DESC',
    );
    return maps.map((map) => WorkoutSession.fromMap(map)).toList();
  }

  Future<WorkoutSession?> getWorkoutById(int id) async {
    final maps = await _dbHelper.query(
      'workout_sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return WorkoutSession.fromMap(maps.first);
  }

  Future<WorkoutSession?> getActiveWorkout() async {
    final maps = await _dbHelper.query(
      'workout_sessions',
      where: 'isCompleted = ?',
      whereArgs: [0],
      orderBy: 'date DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return WorkoutSession.fromMap(maps.first);
  }

  Future<int> insertWorkout(WorkoutSession workout) async {
    return await _dbHelper.insert('workout_sessions', workout.toMap());
  }

  Future<int> updateWorkout(WorkoutSession workout) async {
    return await _dbHelper.update(
      'workout_sessions',
      workout.toMap(),
      where: 'id = ?',
      whereArgs: [workout.id],
    );
  }

  Future<int> deleteWorkout(int id) async {
    // This will cascade delete all exercise sets due to foreign key constraint
    return await _dbHelper.delete(
      'workout_sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> completeWorkout(int workoutId, {Duration? duration}) async {
    final updateData = <String, dynamic>{
      'isCompleted': 1,
    };
    if (duration != null) {
      updateData['duration'] = duration.inMinutes;
    }
    
    return await _dbHelper.update(
      'workout_sessions',
      updateData,
      where: 'id = ?',
      whereArgs: [workoutId],
    );
  }

  // Exercise Sets
  Future<List<ExerciseSet>> getSetsByWorkout(int workoutId) async {
    final maps = await _dbHelper.query(
      'exercise_sets',
      where: 'workoutSessionId = ?',
      whereArgs: [workoutId],
      orderBy: 'exerciseId, setNumber',
    );
    return maps.map((map) => ExerciseSet.fromMap(map)).toList();
  }

  Future<List<ExerciseSet>> getSetsByExercise(int exerciseId, {int? limit}) async {
    final maps = await _dbHelper.query(
      'exercise_sets',
      where: 'exerciseId = ?',
      whereArgs: [exerciseId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map((map) => ExerciseSet.fromMap(map)).toList();
  }

  Future<ExerciseSet?> getSetById(int id) async {
    final maps = await _dbHelper.query(
      'exercise_sets',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return ExerciseSet.fromMap(maps.first);
  }

  Future<int> insertSet(ExerciseSet set) async {
    return await _dbHelper.insert('exercise_sets', set.toMap());
  }

  Future<int> updateSet(ExerciseSet set) async {
    return await _dbHelper.update(
      'exercise_sets',
      set.toMap(),
      where: 'id = ?',
      whereArgs: [set.id],
    );
  }

  Future<int> deleteSet(int id) async {
    return await _dbHelper.delete(
      'exercise_sets',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Get workout summary with exercises and sets
  Future<Map<String, dynamic>> getWorkoutSummary(int workoutId) async {
    final workout = await getWorkoutById(workoutId);
    if (workout == null) return {};

    final sets = await getSetsByWorkout(workoutId);
    
    // Group sets by exercise
    final Map<int, List<ExerciseSet>> exerciseSets = {};
    for (final set in sets) {
      exerciseSets.putIfAbsent(set.exerciseId, () => []).add(set);
    }

    // Get exercise details
    final List<Map<String, dynamic>> exercises = [];
    for (final exerciseId in exerciseSets.keys) {
      final exerciseData = await _dbHelper.query(
        'exercises',
        where: 'id = ?',
        whereArgs: [exerciseId],
      );
      
      if (exerciseData.isNotEmpty) {
        final exercise = Exercise.fromMap(exerciseData.first);
        final setList = exerciseSets[exerciseId]!;
        
        exercises.add({
          'exercise': exercise,
          'sets': setList,
          'totalSets': setList.length,
          'totalVolume': setList.fold(0.0, (sum, set) => sum + (set.volume ?? 0)),
        });
      }
    }

    return {
      'workout': workout,
      'exercises': exercises,
      'totalExercises': exercises.length,
      'totalSets': sets.length,
      'totalVolume': sets.fold(0.0, (sum, set) => sum + (set.volume ?? 0)),
    };
  }

  // Get progress data for an exercise (for charts)
  Future<List<Map<String, dynamic>>> getExerciseProgressData(
    int exerciseId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    String whereClause = 'es.exerciseId = ?';
    List<dynamic> whereArgs = [exerciseId];

    if (startDate != null) {
      whereClause += ' AND ws.date >= ?';
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      whereClause += ' AND ws.date <= ?';
      whereArgs.add(endDate.toIso8601String());
    }

    return await _dbHelper.rawQuery('''
      SELECT 
        es.*,
        ws.date as workoutDate,
        ws.name as workoutName
      FROM exercise_sets es
      INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id
      WHERE $whereClause
      ORDER BY ws.date ASC, es.setNumber ASC
    ''', whereArgs);
  }

  // Get personal records for an exercise
  Future<Map<String, dynamic>?> getExercisePersonalRecords(int exerciseId) async {
    final results = await _dbHelper.rawQuery('''
      SELECT 
        MAX(weight) as maxWeight,
        MAX(reps) as maxReps,
        MAX(weight * reps) as maxVolume
      FROM exercise_sets
      WHERE exerciseId = ? AND weight IS NOT NULL AND reps IS NOT NULL
    ''', [exerciseId]);

    if (results.isEmpty) return null;
    return results.first;
  }

  // Get workout statistics
  Future<Map<String, dynamic>> getWorkoutStatistics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (startDate != null) {
      whereClause += ' AND date >= ?';
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      whereClause += ' AND date <= ?';
      whereArgs.add(endDate.toIso8601String());
    }

    final results = await _dbHelper.rawQuery('''
      SELECT 
        COUNT(*) as totalWorkouts,
        AVG(duration) as avgDuration,
        SUM(duration) as totalDuration
      FROM workout_sessions
      WHERE $whereClause AND isCompleted = 1
    ''', whereArgs);

    return results.isNotEmpty ? results.first : {};
  }
}