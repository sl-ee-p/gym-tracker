// Verifies the database migration scaffold in lib/services/database_helper.dart
// never loses or corrupts existing data when a DB file is reopened by the app.
//
// When a real migration is added (see the checklist above _databaseVersion in
// database_helper.dart), add a new test here following the same shape as
// 'upgrading a real legacy database preserves every row': freeze the
// *previous* version's schema as literal SQL (do not update it to match
// future _createTables edits — it must always represent what real users
// actually have on disk), seed sample rows, open it through the real
// DatabaseHelper().openDatabaseAt(path), and assert old rows survive and the
// new schema is present. Keep earlier migration tests unmodified and passing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/services/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gym_app_migration_test');
    dbPath = p.join(tempDir.path, 'gym_tracker.db');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Creates a database file with the exact schema real users' installs
  /// have today (version 1, no migrations have ever shipped). Frozen —
  /// never edit this to match future schema changes.
  Future<Database> openLegacyV1Database(String path) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE user_profiles (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              createdDate TEXT NOT NULL,
              currentWeight REAL,
              weightUnit TEXT NOT NULL DEFAULT 'kg'
            )
          ''');
          await db.execute('''
            CREATE TABLE exercise_categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              description TEXT,
              colorValue INTEGER NOT NULL
            )
          ''');
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
          await db.execute('''
            CREATE TABLE weight_entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              weight REAL NOT NULL,
              date TEXT NOT NULL,
              notes TEXT
            )
          ''');
          await db.execute(
              'CREATE INDEX idx_exercise_sets_workout ON exercise_sets (workoutSessionId)');
          await db.execute(
              'CREATE INDEX idx_exercise_sets_exercise ON exercise_sets (exerciseId)');
          await db.execute(
              'CREATE INDEX idx_weight_entries_date ON weight_entries (date)');
          await db.execute(
              'CREATE INDEX idx_workout_sessions_date ON workout_sessions (date)');
        },
      ),
    );
  }

  /// Creates a database file with the exact schema a real v3 install has on
  /// disk (v1 + the v2 and v3 migrations already applied). Frozen — never
  /// edit this to match future schema changes; it must always represent what
  /// users who last ran the v3 build actually have.
  Future<Database> openLegacyV3Database(String path) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE user_profiles (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              createdDate TEXT NOT NULL,
              currentWeight REAL,
              weightUnit TEXT NOT NULL DEFAULT 'kg',
              themeMode TEXT NOT NULL DEFAULT 'system'
            )
          ''');
          await db.execute('''
            CREATE TABLE exercise_categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              description TEXT,
              colorValue INTEGER NOT NULL
            )
          ''');
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
              isFavorite INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (categoryId) REFERENCES exercise_categories (id)
            )
          ''');
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
              isWarmup INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (workoutSessionId) REFERENCES workout_sessions (id) ON DELETE CASCADE,
              FOREIGN KEY (exerciseId) REFERENCES exercises (id)
            )
          ''');
          await db.execute('''
            CREATE TABLE weight_entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              weight REAL NOT NULL,
              date TEXT NOT NULL,
              notes TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE workout_templates (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              categoryId INTEGER,
              notes TEXT,
              exerciseIds TEXT,
              createdDate TEXT NOT NULL,
              FOREIGN KEY (categoryId) REFERENCES exercise_categories (id)
            )
          ''');
          await db.execute(
              'CREATE INDEX idx_exercise_sets_workout ON exercise_sets (workoutSessionId)');
          await db.execute(
              'CREATE INDEX idx_exercise_sets_exercise ON exercise_sets (exerciseId)');
          await db.execute(
              'CREATE INDEX idx_weight_entries_date ON weight_entries (date)');
          await db.execute(
              'CREATE INDEX idx_workout_sessions_date ON workout_sessions (date)');
          await db.execute(
              'CREATE INDEX idx_workout_templates_createdDate ON workout_templates (createdDate)');
        },
      ),
    );
  }

  /// The schema a real install running the previous release has on disk:
  /// v1 plus every shipped delta through v5. Frozen — never edit this to
  /// match future schema changes.
  Future<Database> openLegacyV5Database(String path) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE user_profiles (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              createdDate TEXT NOT NULL,
              currentWeight REAL,
              weightUnit TEXT NOT NULL DEFAULT 'kg',
              themeMode TEXT NOT NULL DEFAULT 'system',
              defaultBarWeightKg REAL NOT NULL DEFAULT 20.0,
              accentColorLight INTEGER,
              accentColorDark INTEGER,
              highlightColorLight INTEGER,
              highlightColorDark INTEGER,
              weeklyWorkoutGoal INTEGER NOT NULL DEFAULT 3,
              homeLayout TEXT,
              autoBackupEnabled INTEGER NOT NULL DEFAULT 1,
              lastBackupAt TEXT,
              progressDateRange TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE exercise_categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              description TEXT,
              colorValue INTEGER NOT NULL
            )
          ''');
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
              isFavorite INTEGER NOT NULL DEFAULT 0,
              usesPlateCalculator INTEGER NOT NULL DEFAULT 0,
              barWeightKg REAL,
              FOREIGN KEY (categoryId) REFERENCES exercise_categories (id)
            )
          ''');
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
              isWarmup INTEGER NOT NULL DEFAULT 0,
              isPersonalRecord INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (workoutSessionId) REFERENCES workout_sessions (id) ON DELETE CASCADE,
              FOREIGN KEY (exerciseId) REFERENCES exercises (id)
            )
          ''');
          await db.execute('''
            CREATE TABLE weight_entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              weight REAL NOT NULL,
              date TEXT NOT NULL,
              notes TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE workout_templates (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              categoryId INTEGER,
              notes TEXT,
              exerciseIds TEXT,
              createdDate TEXT NOT NULL,
              FOREIGN KEY (categoryId) REFERENCES exercise_categories (id)
            )
          ''');
          await db.execute(
              'CREATE INDEX idx_exercise_sets_workout ON exercise_sets (workoutSessionId)');
          await db.execute(
              'CREATE INDEX idx_exercise_sets_exercise ON exercise_sets (exerciseId)');
          await db.execute(
              'CREATE INDEX idx_weight_entries_date ON weight_entries (date)');
          await db.execute(
              'CREATE INDEX idx_workout_sessions_date ON workout_sessions (date)');
          await db.execute(
              'CREATE INDEX idx_workout_templates_createdDate ON workout_templates (createdDate)');
        },
      ),
    );
  }

  /// The schema a real install running the previous release (v6) has on
  /// disk: v1 plus every shipped delta through v6. Frozen — never edit this
  /// to match future schema changes.
  Future<Database> openLegacyV6Database(String path) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE user_profiles (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              createdDate TEXT NOT NULL,
              currentWeight REAL,
              weightUnit TEXT NOT NULL DEFAULT 'kg',
              themeMode TEXT NOT NULL DEFAULT 'system',
              defaultBarWeightKg REAL NOT NULL DEFAULT 20.0,
              accentColorLight INTEGER,
              accentColorDark INTEGER,
              highlightColorLight INTEGER,
              highlightColorDark INTEGER,
              weeklyWorkoutGoal INTEGER NOT NULL DEFAULT 3,
              homeLayout TEXT,
              autoBackupEnabled INTEGER NOT NULL DEFAULT 1,
              lastBackupAt TEXT,
              progressDateRange TEXT,
              lastProgressExerciseId INTEGER,
              restTimerSeconds INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE exercise_categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              description TEXT,
              colorValue INTEGER NOT NULL
            )
          ''');
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
              isFavorite INTEGER NOT NULL DEFAULT 0,
              usesPlateCalculator INTEGER NOT NULL DEFAULT 0,
              barWeightKg REAL,
              FOREIGN KEY (categoryId) REFERENCES exercise_categories (id)
            )
          ''');
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
              isWarmup INTEGER NOT NULL DEFAULT 0,
              isPersonalRecord INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (workoutSessionId) REFERENCES workout_sessions (id) ON DELETE CASCADE,
              FOREIGN KEY (exerciseId) REFERENCES exercises (id)
            )
          ''');
          await db.execute('''
            CREATE TABLE weight_entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              weight REAL NOT NULL,
              date TEXT NOT NULL,
              notes TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE workout_templates (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              categoryId INTEGER,
              notes TEXT,
              exerciseIds TEXT,
              createdDate TEXT NOT NULL,
              FOREIGN KEY (categoryId) REFERENCES exercise_categories (id)
            )
          ''');
          await db.execute(
              'CREATE INDEX idx_exercise_sets_workout ON exercise_sets (workoutSessionId)');
          await db.execute(
              'CREATE INDEX idx_exercise_sets_exercise ON exercise_sets (exerciseId)');
          await db.execute(
              'CREATE INDEX idx_weight_entries_date ON weight_entries (date)');
          await db.execute(
              'CREATE INDEX idx_workout_sessions_date ON workout_sessions (date)');
          await db.execute(
              'CREATE INDEX idx_workout_templates_createdDate ON workout_templates (createdDate)');
        },
      ),
    );
  }

  /// The schema a real install running the previous release (v7) has on
  /// disk: v6 plus the supersets/circuits delta. Frozen — never edit this
  /// to match future schema changes.
  Future<Database> openLegacyV7Database(String path) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE user_profiles (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              createdDate TEXT NOT NULL,
              currentWeight REAL,
              weightUnit TEXT NOT NULL DEFAULT 'kg',
              themeMode TEXT NOT NULL DEFAULT 'system',
              defaultBarWeightKg REAL NOT NULL DEFAULT 20.0,
              accentColorLight INTEGER,
              accentColorDark INTEGER,
              highlightColorLight INTEGER,
              highlightColorDark INTEGER,
              weeklyWorkoutGoal INTEGER NOT NULL DEFAULT 3,
              homeLayout TEXT,
              autoBackupEnabled INTEGER NOT NULL DEFAULT 1,
              lastBackupAt TEXT,
              progressDateRange TEXT,
              lastProgressExerciseId INTEGER,
              restTimerSeconds INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE exercise_categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              description TEXT,
              colorValue INTEGER NOT NULL
            )
          ''');
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
              isFavorite INTEGER NOT NULL DEFAULT 0,
              usesPlateCalculator INTEGER NOT NULL DEFAULT 0,
              barWeightKg REAL,
              FOREIGN KEY (categoryId) REFERENCES exercise_categories (id)
            )
          ''');
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
              isWarmup INTEGER NOT NULL DEFAULT 0,
              isPersonalRecord INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (workoutSessionId) REFERENCES workout_sessions (id) ON DELETE CASCADE,
              FOREIGN KEY (exerciseId) REFERENCES exercises (id)
            )
          ''');
          await db.execute('''
            CREATE TABLE weight_entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              weight REAL NOT NULL,
              date TEXT NOT NULL,
              notes TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE workout_templates (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              categoryId INTEGER,
              notes TEXT,
              exerciseIds TEXT,
              createdDate TEXT NOT NULL,
              exerciseGroupIds TEXT,
              FOREIGN KEY (categoryId) REFERENCES exercise_categories (id)
            )
          ''');
          await db.execute('''
            CREATE TABLE workout_exercise_groups (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              workoutSessionId INTEGER NOT NULL,
              exerciseId INTEGER NOT NULL,
              groupId INTEGER NOT NULL,
              groupOrder INTEGER NOT NULL,
              FOREIGN KEY (workoutSessionId) REFERENCES workout_sessions (id),
              FOREIGN KEY (exerciseId) REFERENCES exercises (id)
            )
          ''');
          await db.execute(
              'CREATE INDEX idx_exercise_sets_workout ON exercise_sets (workoutSessionId)');
          await db.execute(
              'CREATE INDEX idx_exercise_sets_exercise ON exercise_sets (exerciseId)');
          await db.execute(
              'CREATE INDEX idx_weight_entries_date ON weight_entries (date)');
          await db.execute(
              'CREATE INDEX idx_workout_sessions_date ON workout_sessions (date)');
          await db.execute(
              'CREATE INDEX idx_workout_templates_createdDate ON workout_templates (createdDate)');
          await db.execute(
              'CREATE INDEX idx_workout_exercise_groups_workout ON workout_exercise_groups (workoutSessionId)');
          await db.execute(
              'CREATE UNIQUE INDEX idx_workout_exercise_groups_unique ON workout_exercise_groups (workoutSessionId, exerciseId)');
        },
      ),
    );
  }

  test('upgrading a real legacy database preserves every row', () async {
    final legacyDb = await openLegacyV1Database(dbPath);

    final categoryId = await legacyDb.insert('exercise_categories', {
      'name': 'Push',
      'description': 'Chest/Shoulders/Triceps',
      'colorValue': 0xFFE57373,
    });
    final exerciseId = await legacyDb.insert('exercises', {
      'name': 'Bench Press',
      'categoryId': categoryId,
      'muscleGroups': 'Chest,Triceps',
      'isWeightBased': 1,
      'isTimeBased': 0,
      'isRepsBased': 1,
    });
    final sessionId = await legacyDb.insert('workout_sessions', {
      'date': '2026-01-01T10:00:00.000',
      'name': 'Push Day',
      'categoryId': categoryId,
      'duration': 45,
      'isCompleted': 1,
    });
    await legacyDb.insert('exercise_sets', {
      'workoutSessionId': sessionId,
      'exerciseId': exerciseId,
      'setNumber': 1,
      'weight': 80.0,
      'reps': 5,
      'timestamp': '2026-01-01T10:05:00.000',
    });
    await legacyDb.insert('weight_entries', {
      'weight': 82.5,
      'date': '2026-01-01T08:00:00.000',
    });
    await legacyDb.insert('user_profiles', {
      'name': 'Test User',
      'createdDate': '2025-01-01T00:00:00.000',
      'currentWeight': 82.5,
      'weightUnit': 'kg',
    });
    expect(await legacyDb.getVersion(), 1);
    await legacyDb.close();

    // Reopen through the real production schema logic.
    final upgraded = await DatabaseHelper().openDatabaseAt(dbPath);

    expect(await upgraded.query('exercise_categories'), hasLength(1));
    expect(await upgraded.query('exercises'), hasLength(1));
    expect(await upgraded.query('workout_sessions'), hasLength(1));
    expect(await upgraded.query('exercise_sets'), hasLength(1));
    expect(await upgraded.query('weight_entries'), hasLength(1));
    expect(await upgraded.query('user_profiles'), hasLength(1));

    final sets = await upgraded.query('exercise_sets');
    expect(sets.single['weight'], 80.0);
    expect(sets.single['reps'], 5);

    await upgraded.close();
  });

  test('fresh install (onCreate) and an upgraded legacy install converge on '
      'an identical schema', () async {
    Future<List<Map<String, Object?>>> schemaOf(Database db) async {
      final rows = await db.rawQuery(
        "SELECT type, name, sql FROM sqlite_master "
        "WHERE type IN ('table','index') AND name NOT LIKE 'sqlite_%' "
        "ORDER BY type, name",
      );
      // Normalize whitespace: the two CREATE TABLE statements being compared
      // are written at different indentation levels in source (production
      // code vs. this test's fixture), which SQLite stores verbatim in
      // sqlite_master.sql — that's a formatting difference, not a schema
      // difference, so collapse runs of whitespace before comparing. Also
      // drop whitespace adjacent to `,`/`)`: for a table with no trailing
      // table-level constraint (e.g. a FOREIGN KEY), `ALTER TABLE ADD
      // COLUMN` splices the new column definition in right where the old
      // closing paren was, which leaves a stray space before the comma
      // (from the original text's indentation) that a hand-written
      // CREATE TABLE never has.
      return rows
          .map((row) => {
                'type': row['type'],
                'name': row['name'],
                'sql': (row['sql'] as String)
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .replaceAllMapped(RegExp(r'\s+([,)])'), (m) => m[1]!)
                    .trim(),
              })
          .toList();
    }

    final freshPath = p.join(tempDir.path, 'fresh.db');
    final freshDb = await DatabaseHelper().openDatabaseAt(freshPath);
    final freshSchema = await schemaOf(freshDb);
    await freshDb.close();

    final legacyDb = await openLegacyV1Database(dbPath);
    await legacyDb.close();
    final upgradedDb = await DatabaseHelper().openDatabaseAt(dbPath);
    final upgradedSchema = await schemaOf(upgradedDb);
    await upgradedDb.close();

    expect(freshSchema, upgradedSchema);
  });

  test('upgrading a legacy v1 database to v2 adds isFavorite/isWarmup '
      'defaults and the workout_templates table without touching old rows',
      () async {
    final legacyDb = await openLegacyV1Database(dbPath);

    final categoryId = await legacyDb.insert('exercise_categories', {
      'name': 'Push',
      'description': 'Chest/Shoulders/Triceps',
      'colorValue': 0xFFE57373,
    });
    final exerciseId = await legacyDb.insert('exercises', {
      'name': 'Bench Press',
      'categoryId': categoryId,
      'muscleGroups': 'Chest,Triceps',
      'isWeightBased': 1,
      'isTimeBased': 0,
      'isRepsBased': 1,
    });
    final sessionId = await legacyDb.insert('workout_sessions', {
      'date': '2026-01-01T10:00:00.000',
      'name': 'Push Day',
      'categoryId': categoryId,
      'duration': 45,
      'isCompleted': 1,
    });
    await legacyDb.insert('exercise_sets', {
      'workoutSessionId': sessionId,
      'exerciseId': exerciseId,
      'setNumber': 1,
      'weight': 80.0,
      'reps': 5,
      'timestamp': '2026-01-01T10:05:00.000',
    });
    expect(await legacyDb.getVersion(), 1);
    await legacyDb.close();

    final upgraded = await DatabaseHelper().openDatabaseAt(dbPath);

    // Opening always migrates to the current _databaseVersion, not to 2
    // specifically — this asserts the full chain still lands correctly,
    // not that the app is pinned at v2.
    expect(await upgraded.getVersion(), 8);

    final exercises = await upgraded.query('exercises');
    expect(exercises, hasLength(1));
    expect(exercises.single['name'], 'Bench Press');
    expect(exercises.single['isFavorite'], 0);
    // Bench Press is in Exercise.barbellExerciseNames, so v4's backfill
    // switches the plate calculator on for it.
    expect(exercises.single['usesPlateCalculator'], 1);

    final sets = await upgraded.query('exercise_sets');
    expect(sets, hasLength(1));
    expect(sets.single['weight'], 80.0);
    expect(sets.single['reps'], 5);
    expect(sets.single['isWarmup'], 0);

    final templates = await upgraded.query('workout_templates');
    expect(templates, isEmpty);

    await upgraded.close();
  });

  test('upgrading a legacy v1 database to v3 adds a themeMode column '
      'defaulting to system without touching old rows', () async {
    final legacyDb = await openLegacyV1Database(dbPath);

    await legacyDb.insert('user_profiles', {
      'name': 'Test User',
      'createdDate': '2025-01-01T00:00:00.000',
      'currentWeight': 82.5,
      'weightUnit': 'kg',
    });
    expect(await legacyDb.getVersion(), 1);
    await legacyDb.close();

    final upgraded = await DatabaseHelper().openDatabaseAt(dbPath);

    expect(await upgraded.getVersion(), 8);

    final profiles = await upgraded.query('user_profiles');
    expect(profiles, hasLength(1));
    expect(profiles.single['name'], 'Test User');
    expect(profiles.single['themeMode'], 'system');

    await upgraded.close();
  });

  test('upgrading a legacy v3 database to v4 adds the new columns with their '
      'defaults without touching old rows', () async {
    final legacyDb = await openLegacyV3Database(dbPath);

    await legacyDb.insert('user_profiles', {
      'name': 'Test User',
      'createdDate': '2025-01-01T00:00:00.000',
      'currentWeight': 82.5,
      'weightUnit': 'lbs',
      'themeMode': 'dark',
    });
    final categoryId = await legacyDb.insert('exercise_categories', {
      'name': 'Push',
      'description': 'Chest/Shoulders/Triceps',
      'colorValue': 0xFFE57373,
    });
    final exerciseId = await legacyDb.insert('exercises', {
      'name': 'Bench Press',
      'categoryId': categoryId,
      'muscleGroups': 'Chest,Triceps',
      'isWeightBased': 1,
      'isTimeBased': 0,
      'isRepsBased': 1,
      'isFavorite': 1,
    });
    final machineId = await legacyDb.insert('exercises', {
      'name': 'Leg Press',
      'categoryId': categoryId,
      'muscleGroups': 'Quadriceps',
      'isWeightBased': 1,
      'isTimeBased': 0,
      'isRepsBased': 1,
      'isFavorite': 0,
    });
    final sessionId = await legacyDb.insert('workout_sessions', {
      'date': '2026-01-01T10:00:00.000',
      'name': 'Push Day',
      'categoryId': categoryId,
      'duration': 45,
      'isCompleted': 1,
    });
    await legacyDb.insert('exercise_sets', {
      'workoutSessionId': sessionId,
      'exerciseId': exerciseId,
      'setNumber': 1,
      'weight': 80.0,
      'reps': 5,
      'timestamp': '2026-01-01T10:05:00.000',
      'isWarmup': 0,
    });
    expect(await legacyDb.getVersion(), 3);
    await legacyDb.close();

    final upgraded = await DatabaseHelper().openDatabaseAt(dbPath);
    expect(await upgraded.getVersion(), 8);

    final profiles = await upgraded.query('user_profiles');
    expect(profiles, hasLength(1));
    // Pre-existing values survive untouched...
    expect(profiles.single['name'], 'Test User');
    expect(profiles.single['currentWeight'], 82.5);
    expect(profiles.single['weightUnit'], 'lbs');
    expect(profiles.single['themeMode'], 'dark');
    // ...and the new columns arrive with their defaults.
    expect(profiles.single['defaultBarWeightKg'], 20.0);
    expect(profiles.single['weeklyWorkoutGoal'], 3);
    expect(profiles.single['autoBackupEnabled'], 1);
    expect(profiles.single['accentColorLight'], isNull);
    expect(profiles.single['accentColorDark'], isNull);
    expect(profiles.single['highlightColorLight'], isNull);
    expect(profiles.single['highlightColorDark'], isNull);
    expect(profiles.single['homeLayout'], isNull);
    expect(profiles.single['lastBackupAt'], isNull);
    // v5 rides along on the same open, since a v3 install upgrades all the way.
    expect(profiles.single['progressDateRange'], isNull);

    final bench = (await upgraded
            .query('exercises', where: 'id = ?', whereArgs: [exerciseId]))
        .single;
    expect(bench['name'], 'Bench Press');
    expect(bench['isFavorite'], 1);
    expect(bench['usesPlateCalculator'], 1);
    expect(bench['barWeightKg'], isNull);

    // Leg Press is not in barbellExerciseNames, so it stays off.
    final legPress = (await upgraded
            .query('exercises', where: 'id = ?', whereArgs: [machineId]))
        .single;
    expect(legPress['usesPlateCalculator'], 0);

    final sets = await upgraded.query('exercise_sets');
    expect(sets, hasLength(1));
    expect(sets.single['weight'], 80.0);
    expect(sets.single['isWarmup'], 0);

    await upgraded.close();
  });

  test('the v4 backfill flags exactly the sets that were records when logged',
      () async {
    final legacyDb = await openLegacyV3Database(dbPath);

    final categoryId = await legacyDb.insert('exercise_categories', {
      'name': 'Push',
      'colorValue': 0xFFE57373,
    });
    final benchId = await legacyDb.insert('exercises', {
      'name': 'Bench Press',
      'categoryId': categoryId,
      'isWeightBased': 1,
      'isTimeBased': 0,
      'isRepsBased': 1,
      'isFavorite': 0,
    });
    final squatId = await legacyDb.insert('exercises', {
      'name': 'Squat',
      'categoryId': categoryId,
      'isWeightBased': 1,
      'isTimeBased': 0,
      'isRepsBased': 1,
      'isFavorite': 0,
    });
    final sessionId = await legacyDb.insert('workout_sessions', {
      'date': '2026-01-01T10:00:00.000',
      'isCompleted': 1,
    });

    Future<int> addSet(
      int exerciseId,
      String timestamp, {
      double? weight,
      int? reps = 5,
      int isWarmup = 0,
    }) {
      return legacyDb.insert('exercise_sets', {
        'workoutSessionId': sessionId,
        'exerciseId': exerciseId,
        'setNumber': 1,
        'weight': weight,
        'reps': reps,
        'timestamp': timestamp,
        'isWarmup': isWarmup,
      });
    }

    // Bench: 80 (first ever, so not a record), 85 (record), 82 (no),
    // 90 (record). Plus a heavy warm-up and a weightless set, neither of
    // which may count or poison the running max.
    final bench80 = await addSet(benchId, '2026-01-01T10:00:00.000', weight: 80);
    final benchWarmup = await addSet(benchId, '2026-01-01T10:01:00.000',
        weight: 200, isWarmup: 1);
    final bench85 = await addSet(benchId, '2026-01-01T10:02:00.000', weight: 85);
    final bench82 = await addSet(benchId, '2026-01-01T10:03:00.000', weight: 82);
    final benchNoWeight =
        await addSet(benchId, '2026-01-01T10:04:00.000', weight: null);
    final bench90 = await addSet(benchId, '2026-01-01T10:05:00.000', weight: 90);
    // A second exercise must track its own max, not inherit bench's.
    final squat100 = await addSet(squatId, '2026-01-01T11:00:00.000', weight: 100);
    final squat105 = await addSet(squatId, '2026-01-01T11:01:00.000', weight: 105);

    await legacyDb.close();

    final upgraded = await DatabaseHelper().openDatabaseAt(dbPath);

    Future<Object?> prFlagOf(int id) async {
      final row = (await upgraded
              .query('exercise_sets', where: 'id = ?', whereArgs: [id]))
          .single;
      return row['isPersonalRecord'];
    }

    expect(await prFlagOf(bench80), 0, reason: 'first ever set is not a record');
    expect(await prFlagOf(benchWarmup), 0, reason: 'warm-ups never count');
    expect(await prFlagOf(bench85), 1);
    expect(await prFlagOf(bench82), 0, reason: 'lighter than the standing max');
    expect(await prFlagOf(benchNoWeight), 0);
    expect(await prFlagOf(bench90), 1);
    expect(await prFlagOf(squat100), 0, reason: 'first squat set');
    expect(await prFlagOf(squat105), 1);

    await upgraded.close();
  });

  test(
      'upgrading a legacy v5 database to v6 adds the new profile columns and '
      'purges orphaned exercise_sets', () async {
    final legacyDb = await openLegacyV5Database(dbPath);

    await legacyDb.insert('user_profiles', {
      'name': 'Sam',
      'createdDate': DateTime(2025, 3, 1).toIso8601String(),
      'weightUnit': 'kg',
      'themeMode': 'dark',
      'defaultBarWeightKg': 20.0,
      'weeklyWorkoutGoal': 4,
      'autoBackupEnabled': 1,
      'progressDateRange': 'last30',
    });

    final workoutId = await legacyDb.insert('workout_sessions', {
      'date': DateTime(2025, 6, 1, 18).toIso8601String(),
      'name': 'Push',
      'isCompleted': 1,
    });

    Future<int> insertSet({
      required int sessionId,
      required double weight,
      required int minute,
      int setNumber = 1,
    }) {
      return legacyDb.insert('exercise_sets', {
        'workoutSessionId': sessionId,
        'exerciseId': 1,
        'setNumber': setNumber,
        'weight': weight,
        'reps': 5,
        'isWarmup': 0,
        'isPersonalRecord': 0,
        'timestamp': DateTime(2025, 6, 1, 18, minute).toIso8601String(),
      });
    }

    final keptA = await insertSet(sessionId: workoutId, weight: 80, minute: 0);
    final keptB =
        await insertSet(sessionId: workoutId, weight: 90, minute: 10, setNumber: 2);
    // The shape every cancelled workout left behind: deleteWorkout removed the
    // session row and trusted a cascade that never fired.
    await insertSet(sessionId: 4242, weight: 250, minute: 5);
    await insertSet(sessionId: 4242, weight: 260, minute: 6, setNumber: 2);

    expect(await legacyDb.getVersion(), 5);
    await legacyDb.close();

    final upgraded = await DatabaseHelper().openDatabaseAt(dbPath);
    expect(await upgraded.getVersion(), 8);

    final profile = (await upgraded.query('user_profiles')).single;
    expect(profile['name'], 'Sam');
    expect(profile['progressDateRange'], 'last30',
        reason: 'existing preferences must survive the upgrade');
    expect(profile['lastProgressExerciseId'], isNull);
    expect(profile['restTimerSeconds'], isNull);

    final remaining = await upgraded.query('exercise_sets', orderBy: 'id');
    expect(remaining.map((row) => row['id']), [keptA, keptB],
        reason: 'only the sets whose workout still exists are kept');

    await upgraded.close();
  });

  test(
      'the v6 purge re-flags a record that an orphaned set had been masking',
      () async {
    final legacyDb = await openLegacyV5Database(dbPath);

    final workoutId = await legacyDb.insert('workout_sessions', {
      'date': DateTime(2025, 6, 1, 18).toIso8601String(),
      'name': 'Pull',
      'isCompleted': 1,
    });

    Future<int> insertSet({
      required int sessionId,
      required double weight,
      required int minute,
      required int isRecord,
      int setNumber = 1,
    }) {
      return legacyDb.insert('exercise_sets', {
        'workoutSessionId': sessionId,
        'exerciseId': 7,
        'setNumber': setNumber,
        'weight': weight,
        'reps': 5,
        'isWarmup': 0,
        'isPersonalRecord': isRecord,
        'timestamp': DateTime(2025, 6, 1, 18, minute).toIso8601String(),
      });
    }

    await insertSet(sessionId: workoutId, weight: 80, minute: 0, isRecord: 0);
    // A phantom heavier than anything real, from a workout that was cancelled.
    await insertSet(sessionId: 4242, weight: 200, minute: 1, isRecord: 1);
    // Never flagged, because at the time it could not beat the phantom 200.
    final maskedRecord = await insertSet(
        sessionId: workoutId, weight: 90, minute: 2, isRecord: 0, setNumber: 2);

    await legacyDb.close();

    final upgraded = await DatabaseHelper().openDatabaseAt(dbPath);

    final row = (await upgraded
            .query('exercise_sets', where: 'id = ?', whereArgs: [maskedRecord]))
        .single;
    expect(row['isPersonalRecord'], 1,
        reason: 'removing the phantom lowers the running max, so 90 beats 80');

    await upgraded.close();
  });

  group('upgrading a legacy v6 database to v7', () {
    test(
        'adds exerciseGroupIds (null on old rows) and an empty '
        'workout_exercise_groups table without touching old rows', () async {
      final legacyDb = await openLegacyV6Database(dbPath);

      final categoryId = await legacyDb.insert('exercise_categories', {
        'name': 'Push',
        'colorValue': 0xFFE57373,
      });
      final benchId = await legacyDb.insert('exercises', {
        'name': 'Bench Press',
        'categoryId': categoryId,
        'isWeightBased': 1,
        'isTimeBased': 0,
        'isRepsBased': 1,
      });
      final squatId = await legacyDb.insert('exercises', {
        'name': 'Squat',
        'categoryId': categoryId,
        'isWeightBased': 1,
        'isTimeBased': 0,
        'isRepsBased': 1,
      });
      final sessionId = await legacyDb.insert('workout_sessions', {
        'date': DateTime(2026, 1, 1, 10).toIso8601String(),
        'name': 'Push Day',
        'categoryId': categoryId,
        'duration': 45,
        'isCompleted': 1,
      });
      final setId = await legacyDb.insert('exercise_sets', {
        'workoutSessionId': sessionId,
        'exerciseId': benchId,
        'setNumber': 1,
        'weight': 80.0,
        'reps': 5,
        'isWarmup': 0,
        'isPersonalRecord': 0,
        'timestamp': DateTime(2026, 1, 1, 10, 5).toIso8601String(),
      });
      final templateId = await legacyDb.insert('workout_templates', {
        'name': 'Push Routine',
        'exerciseIds': '$benchId,$squatId',
        'createdDate': DateTime(2025, 12, 1).toIso8601String(),
      });

      expect(await legacyDb.getVersion(), 6);
      await legacyDb.close();

      final upgraded = await DatabaseHelper().openDatabaseAt(dbPath);
      expect(await upgraded.getVersion(), 8);

      // Old rows survive untouched, and the new template column defaults to
      // null — "no groups", exactly matching what a template created before
      // this feature existed always meant.
      final templates = await upgraded.query('workout_templates');
      expect(templates, hasLength(1));
      expect(templates.single['id'], templateId);
      expect(templates.single['name'], 'Push Routine');
      expect(templates.single['exerciseIds'], '$benchId,$squatId');
      expect(templates.single['exerciseGroupIds'], isNull);

      final sets = await upgraded.query('exercise_sets');
      expect(sets, hasLength(1));
      expect(sets.single['id'], setId);
      expect(sets.single['weight'], 80.0);

      final sessions = await upgraded.query('workout_sessions');
      expect(sessions, hasLength(1));
      expect(sessions.single['id'], sessionId);

      // No workout has ever been grouped before this migration, so the new
      // table starts empty.
      final groups = await upgraded.query('workout_exercise_groups');
      expect(groups, isEmpty);

      // The table is fully usable — not just present — for a fresh insert.
      final groupRowId = await upgraded.insert('workout_exercise_groups', {
        'workoutSessionId': sessionId,
        'exerciseId': benchId,
        'groupId': benchId,
        'groupOrder': 0,
      });
      expect(groupRowId, greaterThan(0));

      await upgraded.close();
    });
  });

  group('upgrading a legacy v7 database to v8', () {
    late Database legacyDb;
    late int benchId;
    late int sessionId;

    setUp(() async {
      legacyDb = await openLegacyV7Database(dbPath);
      final categoryId = await legacyDb.insert('exercise_categories', {
        'name': 'Push',
        'colorValue': 0xFFE57373,
      });
      benchId = await legacyDb.insert('exercises', {
        'name': 'Bench Press',
        'categoryId': categoryId,
      });
      sessionId = await legacyDb.insert('workout_sessions', {
        'date': DateTime(2026, 1, 1, 10).toIso8601String(),
        'isCompleted': 1,
      });
    });

    Future<int> addSet(
      int minute, {
      required double weight,
      required int reps,
      int isRecord = 0,
      int isWarmup = 0,
    }) {
      return legacyDb.insert('exercise_sets', {
        'workoutSessionId': sessionId,
        'exerciseId': benchId,
        'setNumber': 1,
        'weight': weight,
        'reps': reps,
        'isWarmup': isWarmup,
        'isPersonalRecord': isRecord,
        'timestamp': DateTime(2026, 1, 1, 10, minute).toIso8601String(),
      });
    }

    test(
        'adds the set, profile and measurement schema with null/default '
        'values without touching old rows', () async {
      await legacyDb.insert('user_profiles', {
        'name': 'Sam',
        'createdDate': DateTime(2025, 3, 1).toIso8601String(),
        'currentWeight': 82.5,
        'weightUnit': 'lbs',
        'weeklyWorkoutGoal': 4,
        'restTimerSeconds': 120,
      });
      final setId = await addSet(0, weight: 80, reps: 5);
      await legacyDb.insert('weight_entries', {
        'weight': 82.5,
        'date': DateTime(2026, 1, 1, 8).toIso8601String(),
      });

      expect(await legacyDb.getVersion(), 7);
      await legacyDb.close();

      final upgraded = await DatabaseHelper().openDatabaseAt(dbPath);
      expect(await upgraded.getVersion(), 8);

      final profile = (await upgraded.query('user_profiles')).single;
      expect(profile['name'], 'Sam');
      expect(profile['weightUnit'], 'lbs');
      expect(profile['weeklyWorkoutGoal'], 4);
      expect(profile['restTimerSeconds'], 120);
      expect(profile['partialRepsEnabled'], 0);
      expect(profile['rpeEnabled'], 0);
      expect(profile['targetWeight'], isNull);
      expect(profile['targetWeightStart'], isNull);
      expect(profile['workoutReminderDays'], isNull);
      expect(profile['workoutReminderMinutes'], 1080);
      expect(profile['weighInReminderDays'], isNull);
      expect(profile['weighInReminderMinutes'], 450);

      final set = (await upgraded.query('exercise_sets')).single;
      expect(set['id'], setId);
      expect(set['weight'], 80.0);
      expect(set['reps'], 5);
      expect(set['partialReps'], isNull);
      expect(set['rpe'], isNull);

      expect(await upgraded.query('weight_entries'), hasLength(1));
      expect(await upgraded.query('body_measurements'), isEmpty);
      final measurementId = await upgraded.insert('body_measurements', {
        'type': 'waist',
        'value': 84.5,
        'date': DateTime(2026, 1, 2).toIso8601String(),
      });
      expect(measurementId, greaterThan(0));

      await upgraded.close();
    });

    test('recomputes personal records under the rep-PR rule', () async {
      // Under the old heaviest-weight rule only the 100×5 was a record. Under
      // the rep rule the 100×10 is too — no earlier set had both ≥ 100 kg and
      // ≥ 10 reps — while the 90×8 is beaten by the 100×10 before it.
      final first = await addSet(0, weight: 80, reps: 5);
      final heavier = await addSet(1, weight: 100, reps: 5, isRecord: 1);
      final moreReps = await addSet(2, weight: 100, reps: 10);
      final beaten = await addSet(3, weight: 90, reps: 8);
      final lighterButLonger = await addSet(4, weight: 60, reps: 15);
      final warmup = await addSet(5, weight: 200, reps: 20, isWarmup: 1);

      await legacyDb.close();
      final upgraded = await DatabaseHelper().openDatabaseAt(dbPath);

      Future<Object?> flagOf(int id) async => (await upgraded
              .query('exercise_sets', where: 'id = ?', whereArgs: [id]))
          .single['isPersonalRecord'];

      expect(await flagOf(first), 0, reason: 'first set is never a record');
      expect(await flagOf(heavier), 1);
      expect(await flagOf(moreReps), 1, reason: 'same weight, more reps');
      expect(await flagOf(beaten), 0, reason: '100×10 already beats it');
      expect(await flagOf(lighterButLonger), 1,
          reason: 'no earlier set reached 15 reps');
      expect(await flagOf(warmup), 0, reason: 'warm-ups never count');

      await upgraded.close();
    });
  });

  test('opening a newer-than-supported database file fails loudly instead '
      'of silently rewriting the version', () async {
    // Simulate a device that has a schema newer than this build knows
    // about (e.g. the user reinstalled an older build over a newer one).
    final futureDb = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 999, onCreate: (db, v) async {}),
    );
    await futureDb.close();

    expect(
      () => DatabaseHelper().openDatabaseAt(dbPath),
      throwsA(isA<StateError>()),
    );
  });
}
