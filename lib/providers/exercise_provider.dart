import 'package:flutter/material.dart';
import '../models/exercise.dart';
import '../models/exercise_category.dart';
import '../services/exercise_repository.dart';

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

  Future<void> addCategory(ExerciseCategory category) async {
    try {
      final id = await _repository.insertCategory(category);
      final newCategory = category.copyWith(id: id);
      _categories.add(newCategory);
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding category: $e');
    }
  }

  Future<void> updateCategory(ExerciseCategory category) async {
    try {
      await _repository.updateCategory(category);
      final index = _categories.indexWhere((cat) => cat.id == category.id);
      if (index != -1) {
        _categories[index] = category;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating category: $e');
    }
  }

  Future<void> deleteCategory(int id) async {
    try {
      await _repository.deleteCategory(id);
      _categories.removeWhere((cat) => cat.id == id);
      
      // Also remove exercises in this category
      _exercises.removeWhere((exercise) => exercise.categoryId == id);
      _applyFilters();
      
      // Clear category filter if it was selected
      if (_selectedCategoryId == id) {
        _selectedCategoryId = null;
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting category: $e');
    }
  }

  // Exercise operations
  Exercise? getExerciseById(int id) {
    try {
      return _exercises.firstWhere((exercise) => exercise.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> addExercise(Exercise exercise) async {
    try {
      final id = await _repository.insertExercise(exercise);
      final newExercise = exercise.copyWith(id: id);
      _exercises.add(newExercise);
      _applyFilters();
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding exercise: $e');
    }
  }

  Future<void> updateExercise(Exercise exercise) async {
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
    _filteredExercises = _exercises.where((exercise) {
      // Category filter
      if (_selectedCategoryId != null && exercise.categoryId != _selectedCategoryId) {
        return false;
      }
      
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final nameMatch = exercise.name.toLowerCase().contains(_searchQuery);
        final muscleMatch = exercise.muscleGroups
            .any((muscle) => muscle.toLowerCase().contains(_searchQuery));
        if (!nameMatch && !muscleMatch) {
          return false;
        }
      }
      
      return true;
    }).toList();

    // Sort by name
    _filteredExercises.sort((a, b) => a.name.compareTo(b.name));
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

  // Search exercises
  Future<List<Exercise>> searchExercises(String query) async {
    try {
      return await _repository.searchExercises(query);
    } catch (e) {
      debugPrint('Error searching exercises: $e');
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