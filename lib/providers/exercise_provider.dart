import 'package:flutter/material.dart';
import '../models/exercise.dart';
import '../models/exercise_category.dart';
import '../services/exercise_repository.dart';
import '../utils/exercise_search.dart';

class ExerciseProvider extends ChangeNotifier {
  final ExerciseRepository _repository = ExerciseRepository();
  
  List<Exercise> _exercises = [];
  List<ExerciseCategory> _categories = [];
  List<Exercise> _filteredExercises = [];
  
  int? _selectedCategoryId;
  String _searchQuery = '';
  bool _isLoading = false;
  
  // Getters
  List<Exercise> get exercises => _exercises;
  List<ExerciseCategory> get categories => _categories;
  List<Exercise> get filteredExercises => _filteredExercises;
  int? get selectedCategoryId => _selectedCategoryId;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;

  // Load data
  Future<void> loadCategories() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _categories = await _repository.getAllCategories();
    } catch (e) {
      debugPrint('Error loading categories: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadExercises({int? categoryId}) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _exercises = await _repository.getAllExercises(categoryId: categoryId);
      _applyFilters();
    } catch (e) {
      debugPrint('Error loading exercises: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAllData() async {
    await Future.wait([
      loadCategories(),
      loadExercises(),
    ]);
  }

  // Category operations
  ExerciseCategory? getCategoryById(int id) {
    try {
      return _categories.firstWhere((cat) => cat.id == id);
    } catch (e) {
      return null;
    }
  }

  // The three category mutations below rethrow rather than swallowing.
  // They are driven directly by a user action with a visible outcome — a
  // duplicate name hits the UNIQUE constraint, and deleteCategory refuses
  // outright while exercises still reference the category — and silently
  // logging those left the screen looking like nothing happened.

  Future<void> addCategory(ExerciseCategory category) async {
    try {
      final id = await _repository.insertCategory(category);
      final newCategory = category.copyWith(id: id);
      _categories.add(newCategory);
      _sortCategories();
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding category: $e');
      rethrow;
    }
  }

  Future<void> updateCategory(ExerciseCategory category) async {
    try {
      await _repository.updateCategory(category);
      final index = _categories.indexWhere((cat) => cat.id == category.id);
      if (index != -1) {
        _categories[index] = category;
        _sortCategories();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating category: $e');
      rethrow;
    }
  }

  Future<void> deleteCategory(int id) async {
    try {
      await _repository.deleteCategory(id);
      _categories.removeWhere((cat) => cat.id == id);

      // Clear category filter if it was selected
      if (_selectedCategoryId == id) {
        _selectedCategoryId = null;
        _applyFilters();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting category: $e');
      rethrow;
    }
  }

  /// How many exercises are in [categoryId], for the delete confirmation.
  Future<int> countExercisesInCategory(int categoryId) =>
      _repository.countExercisesInCategory(categoryId);

  /// Moves every exercise out of [fromCategoryId] into [toCategoryId] and
  /// refreshes the in-memory list so filters and the library reflect it.
  Future<void> reassignExercises(int fromCategoryId, int toCategoryId) async {
    try {
      await _repository.reassignExercises(fromCategoryId, toCategoryId);
      await loadExercises();
    } catch (e) {
      debugPrint('Error reassigning exercises: $e');
      rethrow;
    }
  }

  /// Keeps the in-memory list in the same order the repository returns
  /// (by name), so a renamed or newly added category doesn't jump to the end.
  void _sortCategories() {
    _categories.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  // Exercise operations
  Exercise? getExerciseById(int id) {
    try {
      return _exercises.firstWhere((exercise) => exercise.id == id);
    } catch (e) {
      return null;
    }
  }

  /// The exercise already using [name], ignoring [excludingId] (the row being
  /// renamed). Null when the name is free.
  ///
  /// Static and list-taking so it is testable without a database, matching
  /// [sortFavoritesFirst] below.
  static Exercise? findDuplicateName(
    List<Exercise> exercises,
    String name, {
    int? excludingId,
  }) {
    final key = Exercise.normalizeName(name);
    for (final exercise in exercises) {
      if (excludingId != null && exercise.id == excludingId) continue;
      if (Exercise.normalizeName(exercise.name) == key) return exercise;
    }
    return null;
  }

  /// [findDuplicateName] against the loaded library, which is always the whole
  /// library: loadExercises is only ever called without a categoryId, since
  /// category filtering happens in [_applyFilters].
  Exercise? findByName(String name, {int? excludingId}) =>
      findDuplicateName(_exercises, name, excludingId: excludingId);

  // Both mutations below rethrow, for the same reason the category mutations
  // above do: they are driven by a user action with a visible outcome. The
  // form dialog used to pop with "Exercise added successfully" while the row
  // silently didn't exist.

  Future<void> addExercise(Exercise exercise) async {
    final clash = findByName(exercise.name);
    if (clash != null) throw DuplicateExerciseNameException(clash.name);

    try {
      final id = await _repository.insertExercise(exercise);
      final newExercise = exercise.copyWith(id: id);
      _exercises.add(newExercise);
      _applyFilters();
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding exercise: $e');
      rethrow;
    }
  }

  Future<void> updateExercise(Exercise exercise) async {
    final clash = findByName(exercise.name, excludingId: exercise.id);
    if (clash != null) throw DuplicateExerciseNameException(clash.name);

    try {
      await _repository.updateExercise(exercise);
      final index = _exercises.indexWhere((ex) => ex.id == exercise.id);
      if (index != -1) {
        _exercises[index] = exercise;
        _applyFilters();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating exercise: $e');
      rethrow;
    }
  }

  Future<void> deleteExercise(int id) async {
    try {
      await _repository.deleteExercise(id);
      _exercises.removeWhere((exercise) => exercise.id == id);
      _applyFilters();
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting exercise: $e');
    }
  }

  Future<void> setFavorite(int exerciseId, bool isFavorite) async {
    try {
      await _repository.setFavorite(exerciseId, isFavorite);
      final index = _exercises.indexWhere((ex) => ex.id == exerciseId);
      if (index != -1) {
        _exercises[index] = _exercises[index].copyWith(isFavorite: isFavorite);
        _applyFilters();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error setting favorite: $e');
    }
  }

  /// A stable two-bucket partition (favorites first) applied on top of
  /// [ExerciseSearch]'s ranking, exposed as a static helper so both
  /// [_applyFilters] and [ExercisePickerSheet] (which calls
  /// [ExerciseSearch.search] directly, bypassing [filteredExercises]) share
  /// identical behavior.
  static List<Exercise> sortFavoritesFirst(List<Exercise> rankedExercises) {
    final favorites = <Exercise>[];
    final others = <Exercise>[];
    for (final exercise in rankedExercises) {
      (exercise.isFavorite ? favorites : others).add(exercise);
    }
    return [...favorites, ...others];
  }

  // Filtering
  void setSelectedCategory(int? categoryId) {
    _selectedCategoryId = categoryId;
    _applyFilters();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query.toLowerCase();
    _applyFilters();
    notifyListeners();
  }

  void clearFilters() {
    _selectedCategoryId = null;
    _searchQuery = '';
    _applyFilters();
    notifyListeners();
  }

  void _applyFilters() {
    final categoryFiltered = _selectedCategoryId == null
        ? _exercises
        : _exercises
            .where((exercise) => exercise.categoryId == _selectedCategoryId)
            .toList();

    _filteredExercises = sortFavoritesFirst(ExerciseSearch.search(_searchQuery, categoryFiltered));
  }

  // Popular exercises
  Future<List<Exercise>> getPopularExercises({int limit = 10}) async {
    try {
      return await _repository.getPopularExercises(limit: limit);
    } catch (e) {
      debugPrint('Error loading popular exercises: $e');
      return [];
    }
  }

  // Get exercises by category
  List<Exercise> getExercisesByCategory(int categoryId) {
    return _exercises.where((exercise) => exercise.categoryId == categoryId).toList();
  }

  Future<void> initialize() async {
    await loadAllData();
  }
}