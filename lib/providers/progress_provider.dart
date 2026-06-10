import 'package:flutter/material.dart';
import '../services/workout_repository.dart';
import '../services/weight_repository.dart';

class ProgressProvider extends ChangeNotifier {
  final WorkoutRepository _workoutRepository = WorkoutRepository();
  final WeightRepository _weightRepository = WeightRepository();
  
  // Chart data
  List<Map<String, dynamic>> _exerciseProgressData = [];
  List<Map<String, dynamic>> _weightProgressData = [];
  Map<String, dynamic> _workoutStats = {};
  Map<String, dynamic> _weightStats = {};
  
  // Filters
  DateTime? _startDate;
  DateTime? _endDate;
  int? _selectedExerciseId;

  bool _isExerciseLoading = false;
  bool _isWeightLoading = false;
  int _statsLoadingCount = 0;
  
  // Getters
  List<Map<String, dynamic>> get exerciseProgressData => _exerciseProgressData;
  List<Map<String, dynamic>> get weightProgressData => _weightProgressData;
  Map<String, dynamic> get workoutStats => _workoutStats;
  Map<String, dynamic> get weightStats => _weightStats;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  int? get selectedExerciseId => _selectedExerciseId;
  bool get isExerciseLoading => _isExerciseLoading;
  bool get isWeightLoading => _isWeightLoading;
  bool get isStatsLoading => _statsLoadingCount > 0;
  bool get isLoading => isExerciseLoading || isWeightLoading || isStatsLoading;

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

        for (final set in sets) {
          final weight = (set['weight'] as double?) ?? 0;
          final reps = (set['reps'] as int?) ?? 0;
          
          if (weight > maxWeight) {
            maxWeight = weight;
          }
          
          totalVolume += weight * reps;
          totalReps += reps;
        }

        _exerciseProgressData.add({
          'date': DateTime.parse(dateKey),
          'maxWeight': maxWeight,
          'totalVolume': totalVolume,
          'totalReps': totalReps,
          'totalSets': totalSets,
          'avgWeight': totalReps > 0 ? totalVolume / totalReps : 0,
        });
      });

      // Sort by date
      _exerciseProgressData.sort((a, b) => 
          (a['date'] as DateTime).compareTo(b['date'] as DateTime));
      
    } catch (e) {
      debugPrint('Error loading exercise progress: $e');
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
    notifyListeners();
    
    try {
      final entries = await _weightRepository.getWeightEntriesByDateRange(
        startDate ?? _startDate ?? DateTime.now().subtract(const Duration(days: 365)),
        endDate ?? _endDate ?? DateTime.now(),
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
    ]);
  }

  Future<void> initialize() async {
    // Set default to last 3 months
    setLast90Days();
    await loadAllProgressData();
  }
}