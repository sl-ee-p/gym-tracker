import 'package:flutter/material.dart';
import '../models/achievement.dart';
import '../models/analytics.dart';
import '../models/progress_date_range.dart';
import '../models/workout_session.dart';
import '../services/workout_repository.dart';
import '../services/weight_repository.dart';
import '../utils/app_date.dart';
import '../utils/personal_records.dart';

class ProgressProvider extends ChangeNotifier {
  final WorkoutRepository _workoutRepository = WorkoutRepository();
  final WeightRepository _weightRepository = WeightRepository();
  
  // Chart data
  List<Map<String, dynamic>> _exerciseProgressData = [];
  List<Map<String, dynamic>> _weightProgressData = [];
  Map<String, dynamic> _workoutStats = {};
  Map<String, dynamic> _weightStats = {};

  // Streak / frequency heatmap data — deliberately independent of the
  // date-range filter below: always a fixed trailing window, not coupled
  // to whatever range the Progress tabs have selected.
  List<DateTime> _workoutDates = [];

  /// Replaces the old streak counters. See [Achievement] for why.
  int _workoutsThisWeek = 0;
  List<Achievement> _achievements = const [];
  
  // Filters
  DateTime? _startDate;
  DateTime? _endDate;
  int? _selectedExerciseId;

  bool _isExerciseLoading = false;
  bool _isWeightLoading = false;
  int _statsLoadingCount = 0;

  // A failed query used to be indistinguishable from "no data": both loaders
  // caught, debugPrint'ed and left the list empty, so the UI showed its
  // friendly "No Progress Data" state for what was actually a broken read.
  String? _exerciseError;
  String? _weightError;
  
  // Getters
  List<Map<String, dynamic>> get exerciseProgressData => _exerciseProgressData;
  List<Map<String, dynamic>> get weightProgressData => _weightProgressData;
  Map<String, dynamic> get workoutStats => _workoutStats;
  Map<String, dynamic> get weightStats => _weightStats;
  List<DateTime> get workoutDates => _workoutDates;
  int get workoutsThisWeek => _workoutsThisWeek;
  List<Achievement> get achievements => _achievements;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  int? get selectedExerciseId => _selectedExerciseId;
  bool get isExerciseLoading => _isExerciseLoading;
  bool get isWeightLoading => _isWeightLoading;
  bool get isStatsLoading => _statsLoadingCount > 0;
  bool get isLoading => isExerciseLoading || isWeightLoading || isStatsLoading;
  String? get exerciseError => _exerciseError;
  String? get weightError => _weightError;

  // Date range management
  void setDateRange(DateTime? start, DateTime? end) {
    _startDate = start;
    _endDate = end;
    notifyListeners();
  }

  void setSelectedExercise(int? exerciseId) {
    _selectedExerciseId = exerciseId;
    notifyListeners();
  }

  // Load exercise progress data
  Future<void> loadExerciseProgress(int exerciseId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _isExerciseLoading = true;
    _selectedExerciseId = exerciseId;
    _exerciseError = null;
    notifyListeners();
    
    try {
      final rawData = await _workoutRepository.getExerciseProgressData(
        exerciseId,
        startDate: startDate ?? _startDate,
        endDate: endDate ?? _endDate,
      );

      // Process data for charts - group by workout date and calculate max weight/volume
      final Map<String, List<Map<String, dynamic>>> groupedData = {};
      
      for (final entry in rawData) {
        final date = entry['workoutDate'] as String;
        final dateKey = DateTime.parse(date).toIso8601String().split('T')[0]; // Date only
        
        groupedData.putIfAbsent(dateKey, () => []).add(entry);
      }

      _exerciseProgressData = [];
      
      groupedData.forEach((dateKey, sets) {
        double maxWeight = 0;
        double totalVolume = 0;
        int totalReps = 0;
        int totalSets = sets.length;
        String? maxWeightNote;

        // Tracks whether any non-warm-up set that day actually carried a
        // weight. A bodyweight or time-based exercise has weight NULL on
        // every set, and coercing those to 0 charted a flat line along the
        // axis that looked like real data. Days with no weighted set are
        // dropped below instead.
        var hasWeightedSet = false;
        // Best Epley estimate of the day. Null when no set qualifies — a
        // 20-rep set has no meaningful 1RM estimate, see estimateOneRepMax.
        double? maxEstimated1RM;

        for (final set in sets) {
          final isWarmup = set['isWarmup'] == 1;
          final weight = (set['weight'] as num?)?.toDouble();
          final reps = (set['reps'] as int?) ?? 0;
          final note = (set['notes'] as String?)?.trim();

          if (isWarmup) continue;
          if (weight == null) continue;

          hasWeightedSet = true;
          if (weight > maxWeight) {
            maxWeight = weight;
            maxWeightNote = (note != null && note.isNotEmpty) ? note : null;
          }
          totalVolume += weight * reps;
          totalReps += reps;

          final estimate = estimateOneRepMax(weight, reps);
          if (estimate != null &&
              (maxEstimated1RM == null || estimate > maxEstimated1RM)) {
            maxEstimated1RM = estimate;
          }
        }

        if (!hasWeightedSet) return;

        // Collect every note recorded that day so they remain readable from
        // the chart even when they belong to a non-max-weight set.
        final allNotes = sets
            .map((set) => (set['notes'] as String?)?.trim())
            .where((note) => note != null && note.isNotEmpty)
            .cast<String>()
            .toList();

        _exerciseProgressData.add({
          'date': DateTime.parse(dateKey),
          // The session behind this point, so the Recent Sessions list can
          // open it. A day with two workouts collapses into one point; the
          // last one logged is the one this opens.
          'workoutId': (sets.last['workoutId'] as num?)?.toInt(),
          'maxWeight': maxWeight,
          'estimated1RM': maxEstimated1RM,
          'totalVolume': totalVolume,
          'totalReps': totalReps,
          'totalSets': totalSets,
          'avgWeight': totalReps > 0 ? totalVolume / totalReps : 0,
          'note': maxWeightNote,
          'notes': allNotes,
        });
      });

      // Sort by date
      _exerciseProgressData.sort((a, b) => 
          (a['date'] as DateTime).compareTo(b['date'] as DateTime));
      
    } catch (e) {
      debugPrint('Error loading exercise progress: $e');
      _exerciseProgressData = [];
      _exerciseError = 'Could not load progress for this exercise.';
    } finally {
      _isExerciseLoading = false;
      notifyListeners();
    }
  }

  // Load weight progress data
  Future<void> loadWeightProgress({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _isWeightLoading = true;
    _weightError = null;
    notifyListeners();
    
    try {
      // No 365-day fallback. clearDateRange() nulls both dates to mean "all
      // time", and substituting a year here quietly capped it — so "All Time"
      // hid older entries on this tab while the exercise tab, which has no
      // such fallback, showed everything.
      final entries = await _weightRepository.getWeightEntriesByDateRange(
        startDate ?? _startDate,
        endDate ?? _endDate,
      );

      _weightProgressData = entries.map((entry) => {
        'date': entry.date,
        'weight': entry.weight,
        'notes': entry.notes,
      }).toList();
      
      // Sort by date (should already be sorted, but just in case)
      _weightProgressData.sort((a, b) => 
          (a['date'] as DateTime).compareTo(b['date'] as DateTime));
      
    } catch (e) {
      debugPrint('Error loading weight progress: $e');
      _weightProgressData = [];
      _weightError = 'Could not load body weight history.';
    } finally {
      _isWeightLoading = false;
      notifyListeners();
    }
  }

  // Load workout statistics
  Future<void> loadWorkoutStatistics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _statsLoadingCount++;
    notifyListeners();

    try {
      _workoutStats = await _workoutRepository.getWorkoutStatistics(
        startDate: startDate ?? _startDate,
        endDate: endDate ?? _endDate,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading workout statistics: $e');
    } finally {
      _statsLoadingCount = (_statsLoadingCount - 1).clamp(0, 999999).toInt();
      notifyListeners();
    }
  }

  // Load weight statistics
  Future<void> loadWeightStatistics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _statsLoadingCount++;
    notifyListeners();

    try {
      _weightStats = await _weightRepository.getWeightStatistics(
        startDate: startDate ?? _startDate,
        endDate: endDate ?? _endDate,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading weight statistics: $e');
    } finally {
      _statsLoadingCount = (_statsLoadingCount - 1).clamp(0, 999999).toInt();
      notifyListeners();
    }
  }

  // Load workout dates for the streak / frequency heatmap
  Future<void> loadWorkoutDates({DateTime? start, DateTime? end}) async {
    try {
      _workoutDates = await _workoutRepository.getWorkoutDates(start: start, end: end);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading workout dates: $e');
    }
  }

  /// Completed workouts since Monday of the current week, for the goal ring.
  Future<void> loadThisWeekWorkoutCount() async {
    try {
      final weekStart = startOfWeek(DateTime.now());
      _workoutsThisWeek = await _workoutRepository.countCompletedWorkouts(
        start: weekStart,
        end: addDays(weekStart, 7),
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error counting this week\'s workouts: $e');
    }
  }

  /// Recent personal records plus the most recent workout-count milestone,
  /// newest first.
  Future<void> loadAchievements({int limit = 3}) async {
    try {
      final records =
          await _workoutRepository.getRecentPersonalRecords(limit: limit);
      final achievements = <Achievement>[
        for (final row in records)
          Achievement(
            kind: AchievementKind.personalRecord,
            title: (row['exerciseName'] as String?) ?? '(deleted exercise)',
            date: DateTime.parse(row['timestamp'] as String),
            weightKg: (row['weight'] as num?)?.toDouble(),
            reps: (row['reps'] as num?)?.toInt(),
          ),
      ];

      final milestone = await _loadLatestMilestone();
      if (milestone != null) achievements.add(milestone);

      achievements.sort((a, b) => b.date.compareTo(a.date));
      _achievements = achievements.take(limit).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading achievements: $e');
    }
  }

  /// The highest round workout total the user has passed, dated to the
  /// workout that crossed it. Null before the first milestone.
  Future<Achievement?> _loadLatestMilestone() async {
    const milestones = [10, 25, 50, 100, 150, 200, 250, 300, 400, 500, 750, 1000];
    final total = await _workoutRepository.countCompletedWorkouts();
    final passed = milestones.where((m) => m <= total);
    if (passed.isEmpty) return null;

    final latest = passed.last;
    final date = await _workoutRepository.getNthWorkoutDate(latest);
    if (date == null) return null;

    return Achievement(
      kind: AchievementKind.milestone,
      title: '$latest workouts',
      detail: 'logged since you started',
      date: date,
    );
  }

  /// The exercise's best weight at 1/3/5/8/10/12+ reps, all-time. Empty on
  /// error — the card simply doesn't show.
  Future<List<RepMax>> getRepMaxes(int exerciseId) async {
    try {
      return computeRepMaxes(await _workoutRepository.getRepMaxSets(exerciseId));
    } catch (e) {
      debugPrint('Error loading rep maxes: $e');
      return const [];
    }
  }

  // Get personal records for an exercise
  Future<Map<String, dynamic>?> getPersonalRecords(int exerciseId) async {
    try {
      return await _workoutRepository.getExercisePersonalRecords(exerciseId);
    } catch (e) {
      debugPrint('Error loading personal records: $e');
      return null;
    }
  }

  // Calculate trends
  Map<String, dynamic> calculateWeightTrend() {
    if (_weightProgressData.length < 2) {
      return {'trend': 'insufficient_data'};
    }

    final first = _weightProgressData.first;
    final last = _weightProgressData.last;
    
    final startWeight = first['weight'] as double;
    final endWeight = last['weight'] as double;
    final change = endWeight - startWeight;
    final changePercent = (change / startWeight) * 100;
    
    String trend;
    if (change > 0.5) {
      trend = 'increasing';
    } else if (change < -0.5) {
      trend = 'decreasing';
    } else {
      trend = 'stable';
    }

    return {
      'trend': trend,
      'change': change,
      'changePercent': changePercent,
      'startWeight': startWeight,
      'endWeight': endWeight,
      'startDate': first['date'],
      'endDate': last['date'],
    };
  }

  Map<String, dynamic> calculateExerciseTrend() {
    if (_exerciseProgressData.length < 2) {
      return {'trend': 'insufficient_data'};
    }

    final first = _exerciseProgressData.first;
    final last = _exerciseProgressData.last;
    
    final startMaxWeight = first['maxWeight'] as double;
    final endMaxWeight = last['maxWeight'] as double;
    final change = endMaxWeight - startMaxWeight;
    final changePercent = startMaxWeight > 0 ? (change / startMaxWeight) * 100 : 0;
    
    String trend;
    if (change > 0) {
      trend = 'increasing';
    } else if (change < 0) {
      trend = 'decreasing';
    } else {
      trend = 'stable';
    }

    return {
      'trend': trend,
      'change': change,
      'changePercent': changePercent,
      'startMaxWeight': startMaxWeight,
      'endMaxWeight': endMaxWeight,
      'startDate': first['date'],
      'endDate': last['date'],
    };
  }

  /// One workout by id, for opening a chart point's session.
  Future<WorkoutSession?> getWorkoutById(int id) async {
    try {
      return await _workoutRepository.getWorkoutById(id);
    } catch (e) {
      debugPrint('Error loading workout $id: $e');
      return null;
    }
  }

  /// The exercise the user most recently logged a set for, for defaulting the
  /// Progress tab's selector. Null when nothing has been logged.
  Future<int?> getMostRecentlyTrainedExerciseId() async {
    try {
      return await _workoutRepository.getMostRecentlyTrainedExerciseId();
    } catch (e) {
      debugPrint('Error finding most recently trained exercise: $e');
      return null;
    }
  }

  // Predefined date ranges
  void setLast30Days() {
    final start = DateTime.now().subtract(const Duration(days: 30));
    setDateRange(start, null);
  }

  void setLast90Days() {
    final start = DateTime.now().subtract(const Duration(days: 90));
    setDateRange(start, null);
  }

  void setLast6Months() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 6, now.day);
    setDateRange(start, null);
  }

  void setLastYear() {
    final now = DateTime.now();
    final start = DateTime(now.year - 1, now.month, now.day);
    setDateRange(start, null);
  }

  void clearDateRange() {
    _startDate = null;
    _endDate = null;
    notifyListeners();
  }

  // Load all progress data
  Future<void> loadAllProgressData({int? exerciseId}) async {
    await Future.wait([
      if (exerciseId != null) loadExerciseProgress(exerciseId),
      loadWeightProgress(),
      loadWorkoutStatistics(),
      loadWeightStatistics(),
      // The heatmap data used to be loaded only from the two widgets that
      // display it, and refreshed only because switching nav tabs happens to
      // remount the dashboard. Loading it here means it is correct on first
      // paint and can be refreshed explicitly after a workout completes.
      loadHeatmapData(),
    ]);
  }

  /// Everything the heatmap card shows: the day grid, this week's progress
  /// toward the goal, and the achievements feed. Always a fixed trailing
  /// window, deliberately independent of the Progress tabs' date filter.
  Future<void> loadHeatmapData() async {
    await Future.wait([
      loadWorkoutDates(start: addDays(DateTime.now(), -365)),
      loadThisWeekWorkoutCount(),
      loadAchievements(),
    ]);
  }

  /// [savedDateRange] is the [ProgressDateRange] name the user last chose, or
  /// null on a first run. Applied before anything loads so the first paint
  /// already shows the right window.
  Future<void> initialize({String? savedDateRange}) async {
    final range = ProgressDateRange.fromName(savedDateRange);
    range.applyTo(this);
    await loadAllProgressData();
  }
}