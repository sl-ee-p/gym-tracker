import 'dart:math' as math;

import '../coach/coach_models.dart';
import '../coach/progression_engine.dart';
import '../models/exercise.dart';
import 'workout_repository.dart';

/// Feeds an exercise's logged history to the pure [ProgressionEngine].
///
/// Only completed workouts count (that is what [WorkoutRepository.
/// getExerciseProgressData] returns), so the workout in progress never moves
/// its own suggestion. Warm-ups are dropped here; fragments, light sessions
/// and the rest are the engine's business. See docs/COACH.md.
class CoachService {
  CoachService({
    WorkoutRepository? repository,
    this.engine = const ProgressionEngine(),
  }) : _repository = repository ?? WorkoutRepository();

  final WorkoutRepository _repository;
  final ProgressionEngine engine;

  /// True for exercises the coach can steer: weight × reps, not timed.
  static bool supports(Exercise exercise) =>
      exercise.isWeightBased && exercise.isRepsBased && !exercise.isTimeBased;

  Future<CoachReport> reportFor(
    Exercise exercise, {
    required String unit,
    required double defaultBarWeightKg,
    DateTime? now,
  }) async {
    if (!supports(exercise) || exercise.id == null) {
      return CoachReport(
        status: CoachStatus.unsupported,
        range: engine.config.defaultRange,
        step: unit == 'lbs' ? 5 : 2.5,
        unit: unit,
        exposures: 0,
      );
    }
    final rows = await _repository.getExerciseProgressData(exercise.id!);
    final feedback = await _repository.getCoachFeedback(exercise.id!);
    final others = await _repository.getRecentCoachRatings(
      excludeExerciseId: exercise.id!,
    );
    return engine.analyze(
      exposuresFromRows(rows),
      now: now ?? DateTime.now(),
      unit: unit,
      equipment: exercise.usesPlateCalculator
          ? CoachEquipment.plates(
              barWeightKg: exercise.barWeightKg ?? defaultBarWeightKg,
            )
          : const CoachEquipment.stack(),
      feedback: feedback,
      prior: priorFrom(others, engine.config),
    );
  }

  /// Half of what the lifter's ratings on other exercises would make the
  /// calibration: a new exercise leans the way the others do, gently.
  static double priorFrom(List<int> ratings, CoachConfig config) {
    if (ratings.isEmpty) return 0;
    final mean = ratings.reduce((a, b) => a + b) / ratings.length;
    final confidence = math.min(1.0, ratings.length / config.feedbackFullCount);
    return 0.5 * 2 * mean * confidence;
  }

  /// The lifter's rating of [exerciseId] in [workoutId], if any.
  Future<CoachRating?> ratingFor(int workoutId, int exerciseId) =>
      _repository.getCoachRating(workoutId, exerciseId);

  /// Saves (or replaces) a rating. It counts once the workout is completed.
  Future<void> rate({
    required int workoutId,
    required int exerciseId,
    required CoachFeedback feedback,
  }) => _repository.upsertCoachFeedback(
    workoutSessionId: workoutId,
    exerciseId: exerciseId,
    feedback: feedback,
  );

  /// Groups progress rows (ordered by workout date, then set number) into
  /// one exposure per workout, without warm-ups.
  static List<CoachExposure> exposuresFromRows(
    List<Map<String, dynamic>> rows,
  ) {
    final byWorkout = <int, List<CoachSet>>{};
    final dates = <int, DateTime>{};
    for (final row in rows) {
      if (row['isWarmup'] == 1) continue;
      final workoutId = row['workoutId'] as int;
      dates[workoutId] ??= DateTime.parse(row['workoutDate'] as String);
      byWorkout
          .putIfAbsent(workoutId, () => [])
          .add(
            CoachSet(
              weightKg: (row['weight'] as num?)?.toDouble() ?? 0,
              reps: (row['reps'] as num?)?.toInt() ?? 0,
            ),
          );
    }
    return [
      for (final entry in byWorkout.entries)
        CoachExposure(date: dates[entry.key]!, sets: entry.value),
    ];
  }
}
