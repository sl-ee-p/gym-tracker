import '../models/exercise.dart';
import '../models/exercise_category.dart';
import 'database_helper.dart';

class ExerciseRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Exercise Categories
  Future<List<ExerciseCategory>> getAllCategories() async {
    final maps = await _dbHelper.query('exercise_categories', orderBy: 'name');
    return maps.map((map) => ExerciseCategory.fromMap(map)).toList();
  }

  Future<ExerciseCategory?> getCategoryById(int id) async {
    final maps = await _dbHelper.query(
      'exercise_categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return ExerciseCategory.fromMap(maps.first);
  }

  Future<int> insertCategory(ExerciseCategory category) async {
    return await _dbHelper.insert('exercise_categories', category.toMap());
  }

  Future<int> updateCategory(ExerciseCategory category) async {
    return await _dbHelper.update(
      'exercise_categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<int> deleteCategory(int id) async {
    return await _dbHelper.delete(
      'exercise_categories',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Exercises
  Future<List<Exercise>> getAllExercises({int? categoryId}) async {
    final maps = await _dbHelper.query(
      'exercises',
      where: categoryId != null ? 'categoryId = ?' : null,
      whereArgs: categoryId != null ? [categoryId] : null,
      orderBy: 'name',
    );
    return maps.map((map) => Exercise.fromMap(map)).toList();
  }

  Future<Exercise?> getExerciseById(int id) async {
    final maps = await _dbHelper.query(
      'exercises',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Exercise.fromMap(maps.first);
  }

  Future<List<Exercise>> searchExercises(String query) async {
    final maps = await _dbHelper.query(
      'exercises',
      where: 'name LIKE ? OR muscleGroups LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'name',
    );
    return maps.map((map) => Exercise.fromMap(map)).toList();
  }

  Future<int> insertExercise(Exercise exercise) async {
    return await _dbHelper.insert('exercises', exercise.toMap());
  }

  Future<int> updateExercise(Exercise exercise) async {
    return await _dbHelper.update(
      'exercises',
      exercise.toMap(),
      where: 'id = ?',
      whereArgs: [exercise.id],
    );
  }

  Future<int> deleteExercise(int id) async {
    return await _dbHelper.delete(
      'exercises',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Get exercises with category information
  Future<List<Map<String, dynamic>>> getExercisesWithCategory({int? categoryId}) async {
    final whereClause = categoryId != null 
        ? 'WHERE e.categoryId = ?'
        : '';
    final whereArgs = categoryId != null ? [categoryId] : <dynamic>[];

    return await _dbHelper.rawQuery('''
      SELECT 
        e.*,
        c.name as categoryName,
        c.colorValue as categoryColor
      FROM exercises e
      LEFT JOIN exercise_categories c ON e.categoryId = c.id
      $whereClause
      ORDER BY e.name
    ''', whereArgs);
  }

  // Get popular exercises based on usage in workouts
  Future<List<Exercise>> getPopularExercises({int limit = 10}) async {
    final maps = await _dbHelper.rawQuery('''
      SELECT e.*, COUNT(es.exerciseId) as usage_count
      FROM exercises e
      LEFT JOIN exercise_sets es ON e.id = es.exerciseId
      GROUP BY e.id
      ORDER BY usage_count DESC, e.name
      LIMIT ?
    ''', [limit]);
    
    return maps.map((map) => Exercise.fromMap(map)).toList();
  }
}