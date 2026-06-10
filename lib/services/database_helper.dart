import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/exercise_category.dart';
import '../models/exercise.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'gym_tracker.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createTables,
      onOpen: (db) async {
        await _seedDefaultData(db);
      },
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // User Profile table
    await db.execute('''
      CREATE TABLE user_profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        createdDate TEXT NOT NULL,
        currentWeight REAL,
        weightUnit TEXT NOT NULL DEFAULT 'kg'
      )
    ''');

    // Exercise Categories table
    await db.execute('''
      CREATE TABLE exercise_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        colorValue INTEGER NOT NULL
      )
    ''');

    // Exercises table
    await db.execute('''
      CREATE TABLE exercises (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        categoryId INTEGER NOT NULL,
        instructions TEXT,
        muscleGroups TEXT,
        isWeightBased INTEGER NOT NULL DEFAULT 1,
        isTimeBased INTEGER NOT NULL DEFAULT 0,
        isRepsBased INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (categoryId) REFERENCES exercise_categories (id)
      )
    ''');

    // Workout Sessions table
    await db.execute('''
      CREATE TABLE workout_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        name TEXT,
        categoryId INTEGER,
        notes TEXT,
        duration INTEGER,
        isCompleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (categoryId) REFERENCES exercise_categories (id)
      )
    ''');

    // Exercise Sets table
    await db.execute('''
      CREATE TABLE exercise_sets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workoutSessionId INTEGER NOT NULL,
        exerciseId INTEGER NOT NULL,
        setNumber INTEGER NOT NULL,
        weight REAL,
        reps INTEGER,
        duration INTEGER,
        notes TEXT,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (workoutSessionId) REFERENCES workout_sessions (id) ON DELETE CASCADE,
        FOREIGN KEY (exerciseId) REFERENCES exercises (id)
      )
    ''');

    // Weight Entries table
    await db.execute('''
      CREATE TABLE weight_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        weight REAL NOT NULL,
        date TEXT NOT NULL,
        notes TEXT
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_exercise_sets_workout ON exercise_sets (workoutSessionId)');
    await db.execute('CREATE INDEX idx_exercise_sets_exercise ON exercise_sets (exerciseId)');
    await db.execute('CREATE INDEX idx_weight_entries_date ON weight_entries (date)');
    await db.execute('CREATE INDEX idx_workout_sessions_date ON workout_sessions (date)');
  }

  Future<void> _seedDefaultData(DatabaseExecutor db) async {
    // Check if data already exists
    final categoryCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM exercise_categories')
    ) ?? 0;

    if (categoryCount == 0) {
      // Insert default categories
      final categories = ExerciseCategory.getDefaultCategories();
      for (final category in categories) {
        await db.insert('exercise_categories', category.toMap());
      }

      // Insert default exercises
      final exercises = Exercise.getDefaultExercises();
      for (final exercise in exercises) {
        await db.insert('exercises', exercise.toMap());
      }
    }
  }

  Future<Map<String, dynamic>> exportAllTables() async {
    final db = await database;
    const tables = [
      'user_profiles',
      'exercise_categories',
      'exercises',
      'workout_sessions',
      'exercise_sets',
      'weight_entries',
    ];

    final tableData = <String, dynamic>{};
    for (final table in tables) {
      final rows = await db.query(table);
      tableData[table] = rows;
    }

    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'schemaVersion': 1,
      'format': 'gym-tracker-json-export-v1',
      'tables': tableData,
    };
  }

  Future<String> exportAllTablesAsJson() async {
    final exportData = await exportAllTables();
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  Future<void> clearAllData({bool reseedDefaults = true}) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('exercise_sets');
      await txn.delete('workout_sessions');
      await txn.delete('weight_entries');
      await txn.delete('user_profiles');
      await txn.delete('exercises');
      await txn.delete('exercise_categories');

      if (reseedDefaults) {
        await _seedDefaultData(txn);
      }
    });
  }

  // Generic CRUD operations
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(table, data);
  }

  Future<List<Map<String, dynamic>>> query(String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final db = await database;
    return await db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
  }

  Future<int> update(String table, Map<String, dynamic> data, {
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    final db = await database;
    return await db.update(table, data, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(String table, {
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    final db = await database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<dynamic>? arguments]) async {
    final db = await database;
    return await db.rawQuery(sql, arguments);
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}