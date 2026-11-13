import 'dart:async';

import 'package:flutter/foundation.dart';

import '../coach/coach_models.dart';
import '../models/exercise.dart';
import '../services/coach_service.dart';

/// Caches one [CoachReport] per exercise and holds the coach's in-memory
/// choices for the workout in progress ("Not now", "Start deload").
///
/// Reports go stale whenever [WorkoutProvider] notifies (wired with a proxy
/// provider in main.dart). A stale report keeps being shown while the fresh
/// one loads, so the card never flashes back to its loading state.
class CoachProvider extends ChangeNotifier {
  CoachProvider({CoachService? service}) : _service = service ?? CoachService();

  final CoachService _service;
  final Map<String, CoachReport> _reports = {};
  final Map<String, int> _loadedGeneration = {};
  final Set<String> _loading = {};
  final Map<String, Exercise> _exercises = {};
  int _generation = 0;
  String _unit = 'kg';
  double _defaultBarWeightKg = 20;
  bool _enabled = true;
  bool _disposed = false;

  /// The Settings switch. When off, nothing is loaded and the card and the
  /// workout row show nothing; stored feedback is kept for when it's back.
  bool get enabled => _enabled;

  /// Workout id → exercise ids the user dismissed for that workout.
  final Map<int?, Set<int>> _dismissed = {};

  /// Workout id → exercise ids where the user started the suggested deload.
  final Map<int?, Set<int>> _deloadStarted = {};

  /// Workout id → exercise ids where the user declined the deload banner.
  final Map<int?, Set<int>> _deloadDeclined = {};

  /// (workout, exercise) → saved rating; a null value means "looked up,
  /// none yet". Ratings are stored, unlike the choices above.
  final Map<(int, int), CoachRating?> _ratings = {};
  final Set<(int, int)> _ratingsLoading = {};

  /// Ratings the user reopened with "Change".
  final Set<(int, int)> _changingRating = {};

  /// Called by the proxy provider when workouts or profile settings change.
  void update({
    required String unit,
    required double defaultBarWeightKg,
    bool enabled = true,
  }) {
    final settingsChanged =
        unit != _unit || defaultBarWeightKg != _defaultBarWeightKg;
    _unit = unit;
    _defaultBarWeightKg = defaultBarWeightKg;
    _enabled = enabled;
    if (settingsChanged) _reports.clear();
    _generation++;
    if (!enabled) return;
    // Reload what is on screen after the current build, never during it.
    final keys = _exercises.keys.toList();
    scheduleMicrotask(() {
      for (final key in keys) {
        final exercise = _exercises[key];
        if (exercise != null) _load(key, exercise);
      }
    });
  }

  /// The latest report for [exercise], possibly stale, or null while the
  /// first one loads. Starts a load when needed.
  CoachReport? reportFor(Exercise exercise) {
    if (!_enabled) return null;
    final key = _key(exercise);
    _exercises[key] = exercise;
    if (_loadedGeneration[key] != _generation && !_loading.contains(key)) {
      scheduleMicrotask(() => _load(key, exercise));
    }
    return _reports[key];
  }

  Future<void> _load(String key, Exercise exercise) async {
    if (_loading.contains(key) || _disposed) return;
    _loading.add(key);
    final generation = _generation;
    try {
      final report = await _service.reportFor(
        exercise,
        unit: _unit,
        defaultBarWeightKg: _defaultBarWeightKg,
      );
      if (_disposed) return;
      _reports[key] = report;
      _loadedGeneration[key] = generation;
      notifyListeners();
    } catch (e) {
      debugPrint('Coach: could not analyse ${exercise.name}: $e');
    } finally {
      _loading.remove(key);
    }
  }

  // The key covers everything about the exercise that changes the maths, so
  // editing it (e.g. switching on the plate calculator) gives a fresh report.
  String _key(Exercise e) =>
      '${e.id}|${e.isWeightBased}|${e.isRepsBased}|${e.isTimeBased}'
      '|${e.usesPlateCalculator}|${e.barWeightKg}';

  bool isDismissed(int? workoutId, int exerciseId) =>
      _dismissed[workoutId]?.contains(exerciseId) ?? false;

  void dismiss(int? workoutId, int exerciseId) {
    (_dismissed[workoutId] ??= {}).add(exerciseId);
    notifyListeners();
  }

  bool isDeloadStarted(int? workoutId, int exerciseId) =>
      _deloadStarted[workoutId]?.contains(exerciseId) ?? false;

  void startDeload(int? workoutId, int exerciseId) {
    (_deloadStarted[workoutId] ??= {}).add(exerciseId);
    notifyListeners();
  }

  bool isDeloadDeclined(int? workoutId, int exerciseId) =>
      _deloadDeclined[workoutId]?.contains(exerciseId) ?? false;

  void declineDeload(int? workoutId, int exerciseId) {
    (_deloadDeclined[workoutId] ??= {}).add(exerciseId);
    notifyListeners();
  }

  /// The saved rating for [exerciseId] in [workoutId], or null. Looks it
  /// up the first time, so a rebuilt screen still shows the answer.
  CoachRating? ratingFor(int workoutId, int exerciseId) {
    final key = (workoutId, exerciseId);
    if (!_ratings.containsKey(key) && !_ratingsLoading.contains(key)) {
      _ratingsLoading.add(key);
      scheduleMicrotask(() async {
        try {
          final rating = await _service.ratingFor(workoutId, exerciseId);
          if (_disposed) return;
          // A tap that landed while this loaded wins.
          if (!_ratings.containsKey(key)) {
            _ratings[key] = rating;
            notifyListeners();
          }
        } catch (e) {
          debugPrint('Coach: could not read a rating: $e');
        } finally {
          _ratingsLoading.remove(key);
        }
      });
    }
    return _ratings[key];
  }

  /// Saves how [suggestion] felt. It reaches the engine once the workout is
  /// completed, which refreshes every report anyway.
  Future<void> rate(
    int workoutId,
    int exerciseId,
    CoachSuggestion suggestion,
    CoachRating rating,
  ) async {
    final key = (workoutId, exerciseId);
    _ratings[key] = rating;
    _changingRating.remove(key);
    notifyListeners();
    try {
      await _service.rate(
        workoutId: workoutId,
        exerciseId: exerciseId,
        feedback: CoachFeedback(
          date: DateTime.now(),
          action: suggestion.action,
          weightKg: suggestion.weightKg,
          repsMin: suggestion.repsMin,
          repsMax: suggestion.repsMax,
          rating: rating,
        ),
      );
    } catch (e) {
      debugPrint('Coach: could not save a rating: $e');
    }
  }

  bool isChangingRating(int workoutId, int exerciseId) =>
      _changingRating.contains((workoutId, exerciseId));

  void changeRating(int workoutId, int exerciseId) {
    _changingRating.add((workoutId, exerciseId));
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
