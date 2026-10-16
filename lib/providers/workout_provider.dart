import 'package:flutter/material.dart';
import '../models/workout_session.dart';
import '../models/exercise_set.dart';
import '../models/workout_template.dart';
import '../services/workout_repository.dart';
import '../services/exercise_repository.dart';
import '../services/workout_template_repository.dart';

class WorkoutProvider extends ChangeNotifier {
  final WorkoutRepository _repository = WorkoutRepository();
  final ExerciseRepository _exerciseRepository = ExerciseRepository();
  final WorkoutTemplateRepository _templateRepository = WorkoutTemplateRepository();

  // Active workout state
  WorkoutSession? _activeWorkout;
  List<ExerciseSet> _currentSets = [];
  List<int> _currentWorkoutExercises = []; // Track exercises in current workout
  DateTime? _workoutStartTime;

  /// exerciseId -> groupId (the anchor exerciseId of that superset/circuit).
  /// An exercise absent from this map is standalone. Mirrors this workout's
  /// `workout_exercise_groups` rows.
  final Map<int, int> _exerciseGroupIds = {};

  /// exerciseId -> groupOrder: this exercise's 0-based position within its
  /// group. Only meaningful for exercises present in [_exerciseGroupIds].
  final Map<int, int> _exerciseGroupOrders = {};

  // Which exercise the set-input form targets. Lives here rather than in
  // WorkoutScreen's State so it survives the AnimatedSwitcher unmounting the
  // Workout tab on every nav-bar switch — see selectExercise().
  int? _selectedExerciseId;
  
  // Workout history
  List<WorkoutSession> _workoutHistory = [];
  final Map<int, List<ExerciseSet>> _workoutSets = {};

  // Workout templates
  List<WorkoutTemplate> _templates = [];

  bool _isLoading = false;

  // Getters
  WorkoutSession? get activeWorkout => _activeWorkout;
  List<ExerciseSet> get currentSets => _currentSets;
  DateTime? get workoutStartTime => _workoutStartTime;
  List<WorkoutSession> get workoutHistory => _workoutHistory;
  List<WorkoutTemplate> get templates => _templates;
  bool get isLoading => _isLoading;
  bool get hasActiveWorkout => _activeWorkout != null;
  int? get selectedExerciseId => _selectedExerciseId;
  
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

      // Load sets for all workouts in one query instead of one per workout.
      final workoutIds =
          _workoutHistory.map((workout) => workout.id).whereType<int>().toList();
      final sets = await _repository.getSetsByWorkouts(workoutIds);
      final setsByWorkout = <int, List<ExerciseSet>>{};
      for (final set in sets) {
        setsByWorkout.putIfAbsent(set.workoutSessionId, () => []).add(set);
      }
      for (final workoutId in workoutIds) {
        _workoutSets[workoutId] = setsByWorkout[workoutId] ?? [];
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
      _exerciseGroupIds.clear();
      _exerciseGroupOrders.clear();

      if (_activeWorkout != null) {
        _currentSets = await _repository.getSetsByWorkout(_activeWorkout!.id!);
        _workoutStartTime = _activeWorkout!.date;

        // Rebuild exercise list from sets, in the order each exercise was
        // first added to this workout — not getSetsByWorkout's storage order.
        _currentWorkoutExercises = _orderedExerciseIds(_currentSets);

        final groups =
            await _repository.getWorkoutExerciseGroups(_activeWorkout!.id!);
        for (final group in groups) {
          _exerciseGroupIds[group.exerciseId] = group.groupId;
          _exerciseGroupOrders[group.exerciseId] = group.groupOrder;
        }

        // A grouped exercise with zero logged sets has no footprint in
        // _orderedExerciseIds above, so without this it would silently
        // vanish on reload — it never had a set to be rebuilt from. Splice
        // any such missing member in next to whichever sibling(s) already
        // made it into the list; standalone zero-set exercises are
        // deliberately left with today's existing (unfixed) behavior.
        for (final groupId in _exerciseGroupIds.values.toSet()) {
          final members = _exerciseGroupIds.entries
              .where((entry) => entry.value == groupId)
              .map((entry) => entry.key);
          final hasMissingMember =
              members.any((id) => !_currentWorkoutExercises.contains(id));
          if (hasMissingMember) _makeGroupContiguous(groupId);
        }
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
      _exerciseGroupIds.clear();
      _exerciseGroupOrders.clear();
      _selectedExerciseId = null;

      notifyListeners();
    } catch (e) {
      debugPrint('Error starting workout: $e');
      rethrow;
    }
  }

  /// Starts a new workout pre-populated with the same name/category and the
  /// same distinct exercises — in first-appearance order, not arbitrary set
  /// order — as a previously logged workout. No sets are copied; only the
  /// exercise list is seeded, and the user logs fresh sets against it.
  ///
  /// Exercises that were deleted from the exercise library since the source
  /// workout was logged are silently skipped, so the new workout never
  /// contains an exercise id that can't be resolved.
  ///
  /// Throws if a workout is already active or [sourceWorkoutSessionId]
  /// can't be found.
  Future<void> duplicateWorkout(int sourceWorkoutSessionId) async {
    if (_activeWorkout != null) {
      throw Exception('A workout is already active');
    }

    final sourceWorkout = await _repository.getWorkoutById(sourceWorkoutSessionId);
    if (sourceWorkout == null) {
      throw Exception('Source workout not found');
    }

    final sourceSets = await _repository.getSetsByWorkout(sourceWorkoutSessionId);
    final orderedExerciseIds = _orderedExerciseIds(sourceSets);

    // Drop exercises no longer in the library: exercise deletion is a hard,
    // unconditional delete with no cascade from exercises -> exercise_sets,
    // so a source workout can reference an exercise id that no longer
    // exists.
    final existingExercises = await _exerciseRepository.getAllExercises();
    final existingIds = existingExercises.map((e) => e.id).whereType<int>().toSet();
    final validExerciseIds = orderedExerciseIds.where(existingIds.contains).toList();

    await startWorkout(
      workoutName: sourceWorkout.name,
      categoryId: sourceWorkout.categoryId,
    );

    for (final exerciseId in validExerciseIds) {
      await addExerciseToWorkout(exerciseId);
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

      // The automatic backup used to run here, awaited, on the critical path:
      // a slow MediaStore write stalled finishing a workout, and its failures
      // were invisible. It now runs from WorkoutScreen after this returns,
      // where the user's autoBackupEnabled setting can be honoured and the
      // result recorded — see BackupService.

      // Reset active workout state
      _activeWorkout = null;
      _workoutStartTime = null;
      _currentSets = [];
      _currentWorkoutExercises = [];
      _exerciseGroupIds.clear();
      _exerciseGroupOrders.clear();
      _selectedExerciseId = null;

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
      _exerciseGroupIds.clear();
      _exerciseGroupOrders.clear();
      _selectedExerciseId = null;

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
  /// Logs a set and returns it, including the id and the resolved
  /// `isPersonalRecord` flag assigned at insert time.
  Future<ExerciseSet> addSet({
    required int exerciseId,
    double? weight,
    int? reps,
    Duration? duration,
    String? notes,
    bool isWarmup = false,
    int? partialReps,
    double? rpe,
  }) async {
    try {
      if (_activeWorkout == null) {
        throw Exception('No active workout');
      }

      // Checked *before* inserting — against history only, never against the
      // set being added right now. isRepPersonalRecord excludes warm-ups for
      // us, and deliberately includes the workout in progress: the second
      // heavy set of a session must beat the first, not just the last
      // completed workout.
      //
      // A warm-up set is never itself flagged as a PR, even if it happens to
      // beat everything before it — it's not a true effort max.
      //
      // Persisted on the row rather than held in screen state: the "New best"
      // marker has to survive leaving the workout, and it doubles as the
      // source for PR history and the achievements feed.
      final isRecord = weight != null &&
          reps != null &&
          !isWarmup &&
          await _repository.isRepPersonalRecord(
            exerciseId,
            weight: weight,
            reps: reps,
          );

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
        isWarmup: isWarmup,
        isPersonalRecord: isRecord,
        timestamp: DateTime.now(),
        // 0 partials is "none", stored as null like every other absent value.
        partialReps: partialReps != null && partialReps > 0 ? partialReps : null,
        rpe: rpe,
      );

      final id = await _repository.insertSet(set);
      final newSet = set.copyWith(id: id);
      _currentSets.add(newSet);

      // Ensure exercise is in the workout exercises list
      if (!_currentWorkoutExercises.contains(exerciseId)) {
        _currentWorkoutExercises.add(exerciseId);
      }

      notifyListeners();
      return newSet;
    } catch (e) {
      debugPrint('Error adding set: $e');
      rethrow;
    }
  }

  /// Saves an edited set — in the active workout or any past one — and
  /// returns it with its re-resolved `isPersonalRecord` flag.
  ///
  /// Records are recomputed for the whole exercise, not just this set:
  /// raising a set's weight can make it a record *and* demote every later
  /// set it now matches, and lowering one can do the reverse.
  Future<ExerciseSet> updateSet(ExerciseSet set) async {
    try {
      await _repository.updateSet(set);
      final recordIds =
          await _repository.recalculatePersonalRecords(set.exerciseId);
      final updated = set.copyWith(
        isPersonalRecord: set.id != null && recordIds.contains(set.id),
      );

      final index = _currentSets.indexWhere((s) => s.id == set.id);
      if (index != -1) _currentSets[index] = updated;
      _applyRecordFlags(set.exerciseId, recordIds);

      // A past workout's cached sets feed the history list's volume and set
      // counts, so they go stale too.
      final cached = _workoutSets[set.workoutSessionId];
      if (cached != null) {
        final cachedIndex = cached.indexWhere((s) => s.id == set.id);
        if (cachedIndex != -1) cached[cachedIndex] = updated;
      }

      notifyListeners();
      return updated;
    } catch (e) {
      debugPrint('Error updating set: $e');
      rethrow;
    }
  }

  /// Brings every in-memory copy of [exerciseId]'s sets in line with the
  /// freshly recalculated [recordIds], so badges repaint without a reload.
  void _applyRecordFlags(int exerciseId, Set<int> recordIds) {
    for (var i = 0; i < _currentSets.length; i++) {
      final set = _currentSets[i];
      if (set.exerciseId != exerciseId) continue;
      final isRecord = set.id != null && recordIds.contains(set.id);
      if (set.isPersonalRecord != isRecord) {
        _currentSets[i] = set.copyWith(isPersonalRecord: isRecord);
      }
    }
    for (final sets in _workoutSets.values) {
      for (var i = 0; i < sets.length; i++) {
        final set = sets[i];
        if (set.exerciseId != exerciseId) continue;
        final isRecord = set.id != null && recordIds.contains(set.id);
        if (set.isPersonalRecord != isRecord) {
          sets[i] = set.copyWith(isPersonalRecord: isRecord);
        }
      }
    }
  }

  Future<void> deleteSet(int setId) async {
    try {
      final deleted = _currentSets.where((set) => set.id == setId).firstOrNull;
      await _repository.deleteSet(setId);
      _currentSets.removeWhere((set) => set.id == setId);

      // Personal records depend on everything logged earlier, so removing a
      // set can promote or demote every later set of that exercise —
      // including un-marking one that is no longer a record because the set
      // that beat it is gone. Recompute rather than leaving stale flags.
      if (deleted != null) {
        final recordIds =
            await _repository.recalculatePersonalRecords(deleted.exerciseId);
        _applyRecordFlags(deleted.exerciseId, recordIds);
      }
      
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

  /// Distinct exercise ids from [sets], in first-appearance order (by
  /// timestamp, then id as a tiebreaker) — getSetsByWorkout orders by
  /// "exerciseId, setNumber", which is not appearance order, so this needs
  /// its own sort.
  List<int> _orderedExerciseIds(List<ExerciseSet> sets) {
    final orderedSets = [...sets]..sort((a, b) {
        final byTime = a.timestamp.compareTo(b.timestamp);
        return byTime != 0 ? byTime : (a.id ?? 0).compareTo(b.id ?? 0);
      });

    final seen = <int>{};
    return [
      for (final set in orderedSets)
        if (seen.add(set.exerciseId)) set.exerciseId,
    ];
  }

  // Add exercise to current workout
  /// Adds [exerciseId] to the current workout's exercise list.
  ///
  /// When [groupId] and [groupOrder] are both given, this also records that
  /// [exerciseId] belongs to that superset/circuit group — persisted via
  /// [WorkoutRepository.upsertWorkoutExerciseGroup] — and updates the
  /// in-memory group maps. Every existing call site passes neither, which
  /// keeps this exactly the in-memory-only, no-DB-write operation it always
  /// was for a standalone exercise.
  Future<void> addExerciseToWorkout(
    int exerciseId, {
    int? groupId,
    int? groupOrder,
  }) async {
    final added = !_currentWorkoutExercises.contains(exerciseId);
    if (added) {
      _currentWorkoutExercises.add(exerciseId);
    }

    if (groupId != null && groupOrder != null) {
      final workoutId = _activeWorkout?.id;
      if (workoutId != null) {
        await _repository.upsertWorkoutExerciseGroup(
          workoutSessionId: workoutId,
          exerciseId: exerciseId,
          groupId: groupId,
          groupOrder: groupOrder,
        );
      }
      _exerciseGroupIds[exerciseId] = groupId;
      _exerciseGroupOrders[exerciseId] = groupOrder;
      notifyListeners();
    } else if (added) {
      notifyListeners();
    }
  }

  // Which exercise the set-input form currently targets.
  void selectExercise(int exerciseId) {
    if (_selectedExerciseId == exerciseId) return;
    _selectedExerciseId = exerciseId;
    notifyListeners();
  }

  // Remove exercise from current workout (if no sets exist)
  /// Removes [exerciseId] from the current workout, if it has no sets yet
  /// (mirrors the previous no-op guard exactly). If it was grouped, its
  /// group membership is dissolved first via [ungroupExercise], so no stale
  /// `workout_exercise_groups` row outlives the exercise it referenced.
  Future<void> removeExerciseFromWorkout(int exerciseId) async {
    final hasSets = _currentSets.any((set) => set.exerciseId == exerciseId);
    if (hasSets) return;

    if (_exerciseGroupIds.containsKey(exerciseId)) {
      await ungroupExercise(exerciseId);
    }
    _currentWorkoutExercises.remove(exerciseId);
    notifyListeners();
  }

  /// Groups [exerciseIds] (2 or more) into one superset/circuit, in the
  /// given order. The first id becomes the group's anchor — its own
  /// exerciseId doubles as the group's id, per this feature's design.
  ///
  /// Re-splices [_currentWorkoutExercises] so the group's members become
  /// contiguous, so grouping doesn't visually jump a card to the end of the
  /// list — see [_makeGroupContiguous].
  Future<void> groupExercises(List<int> exerciseIds) async {
    if (exerciseIds.length < 2) {
      throw ArgumentError('A group needs at least 2 exercises');
    }

    final anchor = exerciseIds.first;
    for (var i = 0; i < exerciseIds.length; i++) {
      await addExerciseToWorkout(exerciseIds[i], groupId: anchor, groupOrder: i);
    }

    _makeGroupContiguous(anchor);
    notifyListeners();
  }

  /// Removes [exerciseId] from its superset/circuit group, if it is in one.
  /// A group left with exactly one remaining member is not meaningful as a
  /// group, so that last member is recursively ungrouped too.
  Future<void> ungroupExercise(int exerciseId) async {
    final groupId = _exerciseGroupIds[exerciseId];
    if (groupId == null) return;

    _exerciseGroupIds.remove(exerciseId);
    _exerciseGroupOrders.remove(exerciseId);

    final workoutId = _activeWorkout?.id;
    if (workoutId != null) {
      await _repository.deleteWorkoutExerciseGroup(workoutId, exerciseId);
    }

    final remainingMembers = _exerciseGroupIds.entries
        .where((entry) => entry.value == groupId)
        .map((entry) => entry.key)
        .toList();
    if (remainingMembers.length == 1) {
      await ungroupExercise(remainingMembers.single);
    }

    notifyListeners();
  }

  /// The sorted-by-groupOrder member list of [exerciseId]'s superset/circuit
  /// group, or `null` if it is standalone.
  List<int>? groupMembersFor(int exerciseId) {
    final groupId = _exerciseGroupIds[exerciseId];
    if (groupId == null) return null;

    return _exerciseGroupIds.entries
        .where((entry) => entry.value == groupId)
        .map((entry) => entry.key)
        .toList()
      ..sort((a, b) =>
          (_exerciseGroupOrders[a] ?? 0).compareTo(_exerciseGroupOrders[b] ?? 0));
  }

  /// `true` for a standalone exercise, or for the last member (by
  /// groupOrder) of its group. This is the static rule the rest-timer
  /// auto-adjust is built on: only an exercise for which this is `false`
  /// offers the shortened "Quick Rest" instead of the normal timer.
  bool isLastInGroup(int exerciseId) {
    final members = groupMembersFor(exerciseId);
    if (members == null) return true;
    return members.isNotEmpty && members.last == exerciseId;
  }

  /// Partitions the current workout's exercises into display rows:
  /// `[exerciseId]` for a standalone exercise, or the group's full ordered
  /// member list the first time one of its members is reached while
  /// scanning [_currentWorkoutExercises] — so a group is never emitted as
  /// more than one row.
  List<List<int>> groupedWorkoutRows() {
    final rows = <List<int>>[];
    final emittedGroups = <int>{};

    for (final exerciseId in _currentWorkoutExercises) {
      final groupId = _exerciseGroupIds[exerciseId];
      if (groupId == null) {
        rows.add([exerciseId]);
        continue;
      }
      if (!emittedGroups.add(groupId)) continue;
      rows.add(groupMembersFor(exerciseId) ?? [exerciseId]);
    }

    return rows;
  }

  /// Makes every member of [groupId] contiguous within
  /// [_currentWorkoutExercises], in stored groupOrder, at the position of
  /// whichever member is currently placed earliest (or appended at the end
  /// if none are placed yet). A member not yet present at all is inserted
  /// too — this is what lets a zero-set grouped exercise be recovered on
  /// [loadActiveWorkout] instead of vanishing.
  void _makeGroupContiguous(int groupId) {
    final members = _exerciseGroupIds.entries
        .where((entry) => entry.value == groupId)
        .map((entry) => entry.key)
        .toList()
      ..sort((a, b) =>
          (_exerciseGroupOrders[a] ?? 0).compareTo(_exerciseGroupOrders[b] ?? 0));

    if (members.length < 2) return;

    final placedIndexes = members
        .map(_currentWorkoutExercises.indexOf)
        .where((index) => index != -1)
        .toList();
    final insertAt = placedIndexes.isEmpty
        ? _currentWorkoutExercises.length
        : placedIndexes.reduce((a, b) => a < b ? a : b);

    _currentWorkoutExercises.removeWhere(members.contains);
    final safeInsertAt = insertAt > _currentWorkoutExercises.length
        ? _currentWorkoutExercises.length
        : insertAt;
    _currentWorkoutExercises.insertAll(safeInsertAt, members);
  }

  // Statistics
  double getTotalVolumeForWorkout(int workoutId) {
    final sets = _workoutSets[workoutId] ?? [];
    return sets
        .where((set) => !set.isWarmup)
        .fold(0.0, (total, set) => total + (set.volume ?? 0));
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
    final totalVolume = _currentSets
        .where((set) => !set.isWarmup)
        .fold(0.0, (sum, set) => sum + (set.volume ?? 0));
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
      loadTemplates(),
    ]);
  }

  // Workout templates
  Future<void> loadTemplates() async {
    try {
      _templates = await _templateRepository.getAllTemplates();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading templates: $e');
    }
  }

  Future<void> createTemplate({
    required String name,
    int? categoryId,
    String? notes,
    required List<int> exerciseIds,
    List<int?>? exerciseGroupIds,
  }) async {
    try {
      final template = WorkoutTemplate(
        name: name,
        categoryId: categoryId,
        notes: notes,
        exerciseIds: exerciseIds,
        // WorkoutTemplate itself defaults to an all-null list the same
        // length as exerciseIds when this is omitted.
        exerciseGroupIds: exerciseGroupIds,
        createdDate: DateTime.now(),
      );
      final id = await _templateRepository.insertTemplate(template);
      _templates.insert(0, template.copyWith(id: id));
      notifyListeners();
    } catch (e) {
      debugPrint('Error creating template: $e');
      rethrow;
    }
  }

  Future<void> deleteTemplate(int templateId) async {
    try {
      await _templateRepository.deleteTemplate(templateId);
      _templates.removeWhere((t) => t.id == templateId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting template: $e');
    }
  }

  /// Modeled directly on [duplicateWorkout], seeding from a [WorkoutTemplate]
  /// instead of a past logged [WorkoutSession]. Same dangling-exercise-id
  /// defense: filters out ids no longer in the exercise library.
  Future<void> startWorkoutFromTemplate(int templateId) async {
    if (_activeWorkout != null) {
      throw Exception('A workout is already active');
    }
    final template = await _templateRepository.getTemplateById(templateId);
    if (template == null) {
      throw Exception('Template not found');
    }
    final existingExercises = await _exerciseRepository.getAllExercises();
    final existingIds = existingExercises.map((e) => e.id).whereType<int>().toSet();
    final validExerciseIds = template.exerciseIds.where(existingIds.contains).toList();

    await startWorkout(workoutName: template.name, categoryId: template.categoryId);
    for (final exerciseId in validExerciseIds) {
      await addExerciseToWorkout(exerciseId);
    }

    // Carry the template's supersets/circuits over, dropping any member
    // that didn't survive the same "still in the exercise library" filter
    // above — a group left with fewer than 2 valid members goes standalone.
    for (final group in template.exerciseGroups) {
      final validGroup = group.where(existingIds.contains).toList();
      if (validGroup.length < 2) continue;
      await groupExercises(validGroup);
    }
  }
}