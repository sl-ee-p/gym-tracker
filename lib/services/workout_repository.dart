import '../models/workout_session.dart';
import '../models/exercise_set.dart';
import '../models/exercise.dart';
import '../models/workout_exercise_group.dart';
import '../utils/personal_records.dart';
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

  /// Deletes the workout and every set logged against it.
  ///
  /// The sets go explicitly rather than through the `ON DELETE CASCADE` the
  /// schema declares on `exercise_sets.workoutSessionId`. That cascade has
  /// never fired: SQLite enforces foreign keys per connection and only when
  /// `PRAGMA foreign_keys` is ON, which this app deliberately never sets —
  /// `exercise_sets.exerciseId` references `exercises` with no ON DELETE
  /// clause, so enforcement would make `deleteExercise` (an intentional hard
  /// delete) start throwing. Until this, cancelling a workout orphaned its
  /// sets forever: invisible to every screen, but still counted by the
  /// Progress screen's all-time max weight.
  Future<int> deleteWorkout(int id) async {
    final affectedExerciseIds = (await _dbHelper.rawQuery(
      'SELECT DISTINCT exerciseId FROM exercise_sets WHERE workoutSessionId = ?',
      [id],
    ))
        .map((row) => (row['exerciseId'] as num).toInt())
        .toList();

    final deleted = await _dbHelper.transaction<int>((txn) async {
      await txn.delete(
        'exercise_sets',
        where: 'workoutSessionId = ?',
        whereArgs: [id],
      );
      // Same reasoning as exercise_sets above: no cascade ever fires, so a
      // deleted/cancelled workout would otherwise leave its group rows
      // behind forever.
      await txn.delete(
        'workout_exercise_groups',
        where: 'workoutSessionId = ?',
        whereArgs: [id],
      );
      return txn.delete('workout_sessions', where: 'id = ?', whereArgs: [id]);
    });

    // Same reason deleteSet recomputes: isPersonalRecord is a running maximum
    // over history, so removing sets can promote later ones. Runs after the
    // commit, not inside it — recalculatePersonalRecords goes through
    // _dbHelper's own connection and would deadlock against the open
    // transaction.
    for (final exerciseId in affectedExerciseIds) {
      await recalculatePersonalRecords(exerciseId);
    }

    return deleted;
  }

  /// This workout's superset/circuit groupings, ordered so members of the
  /// same group are contiguous and in [WorkoutExerciseGroup.groupOrder].
  Future<List<WorkoutExerciseGroup>> getWorkoutExerciseGroups(
      int workoutId) async {
    final maps = await _dbHelper.query(
      'workout_exercise_groups',
      where: 'workoutSessionId = ?',
      whereArgs: [workoutId],
      orderBy: 'groupId, groupOrder',
    );
    return maps.map((map) => WorkoutExerciseGroup.fromMap(map)).toList();
  }

  /// Adds or moves [exerciseId] into group [groupId] at [groupOrder].
  ///
  /// The unique index on (workoutSessionId, exerciseId) means an exercise
  /// can only ever be in one group per workout, so moving it — including
  /// into a different group — is delete-then-insert inside one transaction
  /// rather than a plain insert.
  Future<void> upsertWorkoutExerciseGroup({
    required int workoutSessionId,
    required int exerciseId,
    required int groupId,
    required int groupOrder,
  }) async {
    await _dbHelper.transaction<void>((txn) async {
      await txn.delete(
        'workout_exercise_groups',
        where: 'workoutSessionId = ? AND exerciseId = ?',
        whereArgs: [workoutSessionId, exerciseId],
      );
      await txn.insert('workout_exercise_groups', {
        'workoutSessionId': workoutSessionId,
        'exerciseId': exerciseId,
        'groupId': groupId,
        'groupOrder': groupOrder,
      });
    });
  }

  /// Removes [exerciseId]'s group membership for [workoutSessionId], if any.
  Future<void> deleteWorkoutExerciseGroup(
      int workoutSessionId, int exerciseId) async {
    await _dbHelper.delete(
      'workout_exercise_groups',
      where: 'workoutSessionId = ? AND exerciseId = ?',
      whereArgs: [workoutSessionId, exerciseId],
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

  /// Fetches sets for multiple workouts in one query (grouped by
  /// [ExerciseSet.workoutSessionId] on the caller's side) instead of one
  /// query per workout.
  Future<List<ExerciseSet>> getSetsByWorkouts(List<int> workoutIds) async {
    if (workoutIds.isEmpty) return [];
    final placeholders = List.filled(workoutIds.length, '?').join(',');
    final maps = await _dbHelper.query(
      'exercise_sets',
      where: 'workoutSessionId IN ($placeholders)',
      whereArgs: workoutIds,
      orderBy: 'workoutSessionId, exerciseId, setNumber',
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

  /// Recomputes `isPersonalRecord` for every set of [exerciseId] and returns
  /// the ids that are now flagged.
  ///
  /// Needed because the flag depends on everything logged before a set:
  /// deleting or editing a set (or the record itself) can change every later
  /// set's answer. Replays [findRepRecords], the same rule addSet applies
  /// live — warm-ups and sets missing weight/reps never count, and an
  /// exercise's first set has nothing to beat.
  Future<Set<int>> recalculatePersonalRecords(int exerciseId) async {
    final rows = await _dbHelper.rawQuery(
      // Joined only to skip sets whose workout no longer exists; deliberately
      // no isCompleted filter, since this runs mid-workout from deleteSet and
      // must see the same history isRepPersonalRecord does.
      'SELECT es.id, es.weight, es.reps FROM exercise_sets es '
      'INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id '
      'WHERE es.exerciseId = ? AND es.isWarmup = 0 '
      'AND es.weight IS NOT NULL AND es.reps IS NOT NULL '
      // id breaks ties so two sets sharing a timestamp replay deterministically.
      'ORDER BY es.timestamp ASC, es.id ASC',
      [exerciseId],
    );

    final recordIds = findRepRecords(rows.map((row) => (
          id: (row['id'] as num).toInt(),
          weight: (row['weight'] as num).toDouble(),
          reps: (row['reps'] as num).toInt(),
        )));

    // Blanket updates rather than one per set: an exercise with hundreds of
    // logged sets would otherwise mean hundreds of round trips. Chunked,
    // because rep records are common enough that a long history can pass
    // SQLite's bound-variable limit.
    await _dbHelper.rawUpdate(
      'UPDATE exercise_sets SET isPersonalRecord = 0 WHERE exerciseId = ?',
      [exerciseId],
    );
    final ids = recordIds.toList();
    const chunkSize = 500;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk =
          ids.sublist(i, i + chunkSize > ids.length ? ids.length : i + chunkSize);
      final placeholders = List.filled(chunk.length, '?').join(',');
      await _dbHelper.rawUpdate(
        'UPDATE exercise_sets SET isPersonalRecord = 1 WHERE id IN ($placeholders)',
        chunk,
      );
    }
    return recordIds;
  }

  /// [recalculatePersonalRecords] for every exercise that has a set — for
  /// after a backup restore, whose flags may come from an older rule.
  Future<void> recalculateAllPersonalRecords() async {
    final rows = await _dbHelper
        .rawQuery('SELECT DISTINCT exerciseId FROM exercise_sets');
    for (final row in rows) {
      await recalculatePersonalRecords((row['exerciseId'] as num).toInt());
    }
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
          'totalVolume': setList
              .where((set) => !set.isWarmup)
              .fold(0.0, (sum, set) => sum + (set.volume ?? 0)),
        });
      }
    }

    return {
      'workout': workout,
      'exercises': exercises,
      'totalExercises': exercises.length,
      'totalSets': sets.length,
      'totalVolume': sets
          .where((set) => !set.isWarmup)
          .fold(0.0, (sum, set) => sum + (set.volume ?? 0)),
    };
  }

  // Get progress data for an exercise (for charts)
  Future<List<Map<String, dynamic>>> getExerciseProgressData(
    int exerciseId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // isCompleted = 1 matches getWorkoutDates and getWorkoutStatistics. Without
    // it the workout currently in progress plotted as a chart point that moved
    // as you logged sets, and an abandoned session stayed on the chart forever.
    String whereClause = 'es.exerciseId = ? AND ws.isCompleted = 1';
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
        ws.id as workoutId,
        ws.date as workoutDate,
        ws.name as workoutName
      FROM exercise_sets es
      INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id
      WHERE $whereClause
      ORDER BY ws.date ASC, es.setNumber ASC
    ''', whereArgs);
  }

  /// Completed workouts in the half-open range [start, end).
  Future<int> countCompletedWorkouts({DateTime? start, DateTime? end}) async {
    final clauses = <String>['isCompleted = 1'];
    final args = <dynamic>[];
    if (start != null) {
      clauses.add('date >= ?');
      args.add(start.toIso8601String());
    }
    if (end != null) {
      clauses.add('date < ?');
      args.add(end.toIso8601String());
    }
    final rows = await _dbHelper.rawQuery(
      'SELECT COUNT(*) as count FROM workout_sessions WHERE ${clauses.join(' AND ')}',
      args,
    );
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  /// The most recent personal-record sets, newest first.
  ///
  /// Reads the persisted isPersonalRecord flag rather than recomputing maxima,
  /// so this reflects what was a record *when it was logged* — the same thing
  /// the "New best" badge shows on the set itself.
  Future<List<Map<String, dynamic>>> getRecentPersonalRecords({
    int limit = 5,
  }) async {
    // LEFT JOIN so a record logged against a since-deleted exercise still
    // appears, matching how the CSV export treats the same situation.
    return await _dbHelper.rawQuery('''
      SELECT e.name as exerciseName, es.weight, es.reps, es.timestamp
      FROM exercise_sets es
      INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id
      LEFT JOIN exercises e ON es.exerciseId = e.id
      WHERE es.isPersonalRecord = 1 AND ws.isCompleted = 1
      ORDER BY es.timestamp DESC
      LIMIT ?
    ''', [limit]);
  }

  /// The date of the [n]th completed workout (1-based), for dating a
  /// "100th workout" milestone. Null if there aren't that many yet.
  Future<DateTime?> getNthWorkoutDate(int n) async {
    if (n < 1) return null;
    final rows = await _dbHelper.rawQuery(
      'SELECT date FROM workout_sessions WHERE isCompleted = 1 '
      'ORDER BY date ASC LIMIT 1 OFFSET ?',
      [n - 1],
    );
    if (rows.isEmpty) return null;
    return DateTime.parse(rows.first['date'] as String);
  }

  /// The exercise with the most recent logged set in a completed workout, or
  /// null if nothing has been logged yet.
  ///
  /// The Progress tab used to default to `exercises.first`, which is whichever
  /// exercise the seed data inserted first — almost never one the user has
  /// trained, so the chart opened on a permanent "No Progress Data" state and
  /// read as broken.
  Future<int?> getMostRecentlyTrainedExerciseId() async {
    final rows = await _dbHelper.rawQuery('''
      SELECT es.exerciseId
      FROM exercise_sets es
      INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id
      WHERE ws.isCompleted = 1
      ORDER BY es.timestamp DESC
      LIMIT 1
    ''');
    if (rows.isEmpty) return null;
    return (rows.first['exerciseId'] as num?)?.toInt();
  }

  /// All-time bests for an exercise, as the Progress screen displays them.
  ///
  /// Deliberately the same population ProgressProvider aggregates for the
  /// chart: completed workouts only, no warm-ups, and any set carrying a
  /// weight — reps may be null. Both halves of that matter:
  ///
  /// * The join excludes the workout currently in progress, so "all-time"
  ///   can't quote a weight the chart beside it doesn't show yet. (It also
  ///   excluded orphaned sets, back when those existed.)
  /// * Requiring `reps IS NOT NULL`, as this used to, let a weighted set with
  ///   no reps raise the chart's visible max but not this one — so all-time
  ///   read *lower* than the visible max, which is impossible, and the caption
  ///   silently vanished.
  ///
  /// This is the display definition only. Personal-record detection uses
  /// [isRepPersonalRecord], which answers a different question.
  Future<Map<String, dynamic>?> getExercisePersonalRecords(int exerciseId) async {
    final results = await _dbHelper.rawQuery('''
      SELECT
        MAX(es.weight) as maxWeight,
        MAX(es.reps) as maxReps,
        MAX(es.weight * es.reps) as maxVolume
      FROM exercise_sets es
      INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id
      WHERE es.exerciseId = ?
        AND ws.isCompleted = 1
        AND es.isWarmup = 0
        AND es.weight IS NOT NULL
    ''', [exerciseId]);

    if (results.isEmpty) return null;
    return results.first;
  }

  /// Whether a new [weight] × [reps] set of [exerciseId] would be a personal
  /// record against everything already logged — see [findRepRecords]. Call
  /// it *before* inserting the set, so the set can't match itself.
  ///
  /// Unlike [getExercisePersonalRecords] this does *not* filter on
  /// `isCompleted`, and must not: a set has to beat the ones logged minutes
  /// earlier in the same unfinished session, or every set of a session that
  /// beats the old best would be flagged a new best. The join is only here to
  /// exclude sets whose workout no longer exists.
  Future<bool> isRepPersonalRecord(
    int exerciseId, {
    required double weight,
    required int reps,
  }) async {
    final rows = await _dbHelper.rawQuery('''
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN es.weight >= ? AND es.reps >= ? THEN 1 ELSE 0 END)
          as matching
      FROM exercise_sets es
      INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id
      WHERE es.exerciseId = ?
        AND es.isWarmup = 0
        AND es.weight IS NOT NULL
        AND es.reps IS NOT NULL
    ''', [weight, reps, exerciseId]);

    final total = (rows.first['total'] as num?)?.toInt() ?? 0;
    final matching = (rows.first['matching'] as num?)?.toInt() ?? 0;
    // No history at all: the first set has nothing to beat.
    return total > 0 && matching == 0;
  }

  /// Every non-warm-up set of [exerciseId] with weight and reps, from
  /// completed workouts — the input to [computeRepMaxes]. Completed only,
  /// like [getExercisePersonalRecords], so the table beside the chart can't
  /// quote a set the chart doesn't show yet.
  Future<List<({double weight, int reps, DateTime date})>> getRepMaxSets(
      int exerciseId) async {
    final rows = await _dbHelper.rawQuery('''
      SELECT es.weight, es.reps, es.timestamp
      FROM exercise_sets es
      INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id
      WHERE es.exerciseId = ?
        AND ws.isCompleted = 1
        AND es.isWarmup = 0
        AND es.weight IS NOT NULL
        AND es.reps IS NOT NULL
    ''', [exerciseId]);

    return [
      for (final row in rows)
        (
          weight: (row['weight'] as num).toDouble(),
          reps: (row['reps'] as num).toInt(),
          date: DateTime.parse(row['timestamp'] as String),
        ),
    ];
  }

  /// Distinct calendar dates (time discarded) with a completed workout.
  /// Truncation happens in Dart, not SQL, for correctness independent of
  /// SQLite date-string parsing quirks — fine for a single-user log.
  Future<List<DateTime>> getWorkoutDates({DateTime? start, DateTime? end}) async {
    String whereClause = 'isCompleted = 1';
    final whereArgs = <dynamic>[];
    if (start != null) {
      whereClause += ' AND date >= ?';
      whereArgs.add(DateTime(start.year, start.month, start.day).toIso8601String());
    }
    if (end != null) {
      final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
      whereClause += ' AND date <= ?';
      whereArgs.add(endOfDay.toIso8601String());
    }
    final maps = await _dbHelper.rawQuery('SELECT DISTINCT date FROM workout_sessions WHERE $whereClause', whereArgs);
    final dates = maps.map((row) => DateTime.parse(row['date'] as String))
        .map((dt) => DateTime(dt.year, dt.month, dt.day)).toSet().toList()..sort();
    return dates;
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