import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/exercise_category.dart';
import '../models/exercise.dart';

/// What a backup file holds, for the restore confirmation.
class BackupSummary {
  const BackupSummary({
    required this.exportedAt,
    required this.schemaVersion,
    required this.workouts,
    required this.sets,
    required this.weightEntries,
    required this.measurements,
  });

  final DateTime? exportedAt;
  final int schemaVersion;
  final int workouts;
  final int sets;
  final int weightEntries;
  final int measurements;
}

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  /// Single source of truth for the schema version. Bump this — and only
  /// this — every time a migration is added below.
  ///
  /// Checklist for adding the Nth migration:
  ///  1. Bump [_databaseVersion] from N-1 to N.
  ///  2. Edit [_createTables]: bake the new column into its table's
  ///     `CREATE TABLE`, or append a new `CREATE TABLE`/`CREATE INDEX`
  ///     block — so a fresh install gets the full schema in one shot.
  ///     Never touch a table's DDL that isn't changing.
  ///  3. Add a new `Future<void> _upgradeToVN(Database db) async {...}`
  ///     containing only the delta (`ALTER TABLE ... ADD COLUMN`, or the
  ///     identical new `CREATE TABLE`/`CREATE INDEX` text used in step 2).
  ///     Never edit a previously-shipped `_upgradeToVN` function.
  ///  4. In [_onUpgrade], append `if (oldVersion < N) { await
  ///     _upgradeToVN(db); }` as a new `if`, not `else if`, below the
  ///     existing ones — a device several versions behind must run every
  ///     intermediate step, in order.
  ///  5. Update any affected model's toMap()/fromMap() and the relevant
  ///     repository.
  ///  6. Add a migration test in test/database_migration_test.dart that
  ///     freezes the *previous* version's schema as literal SQL, seeds
  ///     sample rows, runs the upgrade, and asserts old rows survive and
  ///     the new schema is present. Keep earlier migration tests
  ///     unmodified and passing.
  ///  7. Bump pubspec.yaml's version build number.
  ///  8. Manually smoke-test upgrading a real pre-change install before
  ///     shipping.
  static const int _databaseVersion = 8;

  /// The schema version this build writes and understands. Exposed for the
  /// backup importer, which refuses files from a newer build.
  static int get schemaVersion => _databaseVersion;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'gym_tracker.db');
    return openDatabaseAt(path);
  }

  /// Opens (creating or upgrading as needed) the production schema at an
  /// arbitrary path, using the exact same callbacks the app uses.
  /// Exposed (not `_`-private) only so migration tests can point the real
  /// schema logic at a fixture file. Not for use by app code.
  @visibleForTesting
  Future<Database> openDatabaseAt(String path) {
    return openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
      onDowngrade: _onDowngrade,
      onOpen: (db) async {
        await _seedDefaultData(db);
      },
    );
  }

  /// Points the singleton at [db] so repository tests can run against a temp
  /// file opened by [openDatabaseAt]. Pass null to forget it. Same rationale
  /// as [openDatabaseAt]: not for use by app code.
  @visibleForTesting
  static void setDatabaseForTesting(Database? db) => _database = db;

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Intentionally `if`, not `else if` — see the checklist above. All
    // statements here run inside the single transaction sqflite already
    // opens for this callback; do not wrap them in db.transaction().
    if (oldVersion < 2) {
      await _upgradeToV2(db);
    }
    if (oldVersion < 3) {
      await _upgradeToV3(db);
    }
    if (oldVersion < 4) {
      await _upgradeToV4(db);
    }
    if (oldVersion < 5) {
      await _upgradeToV5(db);
    }
    if (oldVersion < 6) {
      await _upgradeToV6(db);
    }
    if (oldVersion < 7) {
      await _upgradeToV7(db);
    }
    if (oldVersion < 8) {
      await _upgradeToV8(db);
    }
  }

  Future<void> _upgradeToV2(Database db) async {
    await db.execute('ALTER TABLE exercises ADD COLUMN isFavorite INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE exercise_sets ADD COLUMN isWarmup INTEGER NOT NULL DEFAULT 0');
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
    await db.execute('CREATE INDEX idx_workout_templates_createdDate ON workout_templates (createdDate)');
  }

  Future<void> _upgradeToV3(Database db) async {
    await db.execute("ALTER TABLE user_profiles ADD COLUMN themeMode TEXT NOT NULL DEFAULT 'system'");
  }

  Future<void> _upgradeToV4(Database db) async {
    await db.execute('ALTER TABLE exercises ADD COLUMN usesPlateCalculator INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE exercises ADD COLUMN barWeightKg REAL');
    await db.execute('ALTER TABLE exercise_sets ADD COLUMN isPersonalRecord INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN defaultBarWeightKg REAL NOT NULL DEFAULT 20.0');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN accentColorLight INTEGER');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN accentColorDark INTEGER');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN highlightColorLight INTEGER');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN highlightColorDark INTEGER');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN weeklyWorkoutGoal INTEGER NOT NULL DEFAULT 3');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN homeLayout TEXT');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN autoBackupEnabled INTEGER NOT NULL DEFAULT 1');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN lastBackupAt TEXT');

    await _backfillPersonalRecords(db);
    await _backfillPlateCalculatorFlags(db);
  }

  Future<void> _upgradeToV5(Database db) async {
    await db.execute('ALTER TABLE user_profiles ADD COLUMN progressDateRange TEXT');
  }

  Future<void> _upgradeToV6(Database db) async {
    await db.execute(
        'ALTER TABLE user_profiles ADD COLUMN lastProgressExerciseId INTEGER');
    await db.execute(
        'ALTER TABLE user_profiles ADD COLUMN restTimerSeconds INTEGER');

    await _purgeOrphanedSets(db);

    // Removing rows can only lower a running maximum, so a set that was
    // beaten only by a phantom orphan is a record after all. The backfill is
    // additive — it only ever sets the flag to 1 — and nothing that was
    // already flagged can become wrong when rows are removed, so replaying it
    // here corrects exactly the sets the orphans had masked.
    await _backfillPersonalRecords(db);
  }

  /// Adds exercise supersets/circuits: which exercises within a workout (or
  /// template) should be performed back-to-back, and in what order.
  ///
  /// Purely additive — a template's new `exerciseGroupIds` column is null on
  /// every existing row, and no `workout_exercise_groups` row exists for a
  /// workout logged before this migration, both of which already mean
  /// "every exercise is standalone" to the code that reads them. No backfill
  /// is needed or possible: grouping is a choice the user makes, not
  /// something derivable from historical data.
  Future<void> _upgradeToV7(Database db) async {
    await db.execute('ALTER TABLE workout_templates ADD COLUMN exerciseGroupIds TEXT');
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
    await db.execute('CREATE INDEX idx_workout_exercise_groups_workout ON workout_exercise_groups (workoutSessionId)');
    await db.execute('CREATE UNIQUE INDEX idx_workout_exercise_groups_unique ON workout_exercise_groups (workoutSessionId, exerciseId)');
  }

  /// Partial reps and RPE per set, the settings that switch their inputs on,
  /// a body-weight goal, workout/weigh-in reminders, and body measurements.
  ///
  /// Every new column is nullable or defaulted, so old rows need no backfill:
  /// null partials/RPE/goal/reminder days all already mean "not used".
  ///
  /// The one backfill is personal records: v8 changes the rule from "heavier
  /// than every earlier set" to "no earlier set matched both the weight and
  /// the reps", so every flag is recomputed under the new rule.
  Future<void> _upgradeToV8(Database db) async {
    await db.execute('ALTER TABLE exercise_sets ADD COLUMN partialReps INTEGER');
    await db.execute('ALTER TABLE exercise_sets ADD COLUMN rpe REAL');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN partialRepsEnabled INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN rpeEnabled INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN targetWeight REAL');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN targetWeightStart REAL');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN workoutReminderDays TEXT');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN workoutReminderMinutes INTEGER NOT NULL DEFAULT 1080');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN weighInReminderDays TEXT');
    await db.execute('ALTER TABLE user_profiles ADD COLUMN weighInReminderMinutes INTEGER NOT NULL DEFAULT 450');
    await db.execute('''
      CREATE TABLE body_measurements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        value REAL NOT NULL,
        date TEXT NOT NULL,
        notes TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_body_measurements_type_date ON body_measurements (type, date)');

    await _backfillRepPersonalRecordsV8(db);
  }

  /// Recomputes every `isPersonalRecord` flag under the v8 rep-PR rule.
  ///
  /// A frozen copy of the rule in utils/personal_records.dart, not a call to
  /// it: a shipped migration must keep doing exactly what it did, even if
  /// the live rule is later changed. Replays each exercise's non-warm-up
  /// sets that have both weight and reps, in timestamp order. A set is a
  /// record when at least one earlier set exists and none of them had both
  /// weight >= this weight and reps >= these reps. Joined to
  /// workout_sessions, like WorkoutRepository.recalculatePersonalRecords.
  Future<void> _backfillRepPersonalRecordsV8(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      'SELECT es.id, es.exerciseId, es.weight, es.reps FROM exercise_sets es '
      'INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id '
      'WHERE es.isWarmup = 0 AND es.weight IS NOT NULL AND es.reps IS NOT NULL '
      'ORDER BY es.exerciseId ASC, es.timestamp ASC, es.id ASC',
    );

    final recordIds = <int>[];
    int? currentExerciseId;
    // The earlier sets no other earlier set beats on both weight and reps.
    // Checking against these alone is equivalent to checking every earlier set.
    var frontier = <(double, int)>[];
    for (final row in rows) {
      final exerciseId = (row['exerciseId'] as num).toInt();
      if (exerciseId != currentExerciseId) {
        currentExerciseId = exerciseId;
        frontier = [];
      }
      final weight = (row['weight'] as num).toDouble();
      final reps = (row['reps'] as num).toInt();
      final matched = frontier.any((p) => p.$1 >= weight && p.$2 >= reps);
      if (frontier.isNotEmpty && !matched) {
        recordIds.add((row['id'] as num).toInt());
      }
      if (!matched) {
        frontier = [
          for (final p in frontier)
            if (!(weight >= p.$1 && reps >= p.$2)) p,
          (weight, reps),
        ];
      }
    }

    await db.rawUpdate('UPDATE exercise_sets SET isPersonalRecord = 0');
    const chunkSize = 500;
    for (var i = 0; i < recordIds.length; i += chunkSize) {
      final chunk = recordIds.sublist(
        i,
        i + chunkSize > recordIds.length ? recordIds.length : i + chunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      await db.rawUpdate(
        'UPDATE exercise_sets SET isPersonalRecord = 1 WHERE id IN ($placeholders)',
        chunk,
      );
    }
  }

  /// Deletes `exercise_sets` rows whose workout no longer exists.
  ///
  /// [WorkoutRepository.deleteWorkout] used to delete only the
  /// `workout_sessions` row and trust the `ON DELETE CASCADE` declared on
  /// `exercise_sets.workoutSessionId`. That cascade never fired: SQLite
  /// enforces foreign keys per-connection and only when `PRAGMA foreign_keys`
  /// is ON, which this app has never set (deliberately — see
  /// ExerciseRepository.deleteCategory and WorkoutProvider.duplicateWorkout,
  /// which both rely on FKs being off). So every cancelled or deleted workout
  /// left its sets behind.
  ///
  /// Those rows are unreachable from the UI — every chart, list, export and
  /// history query joins `workout_sessions` — but they were still counted by
  /// the all-time max weight, which is why it read high. The repository now
  /// deletes sets explicitly; this clears the ones already on disk.
  Future<void> _purgeOrphanedSets(DatabaseExecutor db) async {
    // NOT EXISTS rather than NOT IN: NULL-safe, and it can use
    // idx_exercise_sets_workout.
    await db.execute(
      'DELETE FROM exercise_sets WHERE NOT EXISTS ('
      'SELECT 1 FROM workout_sessions ws WHERE ws.id = exercise_sets.workoutSessionId)',
    );
  }

  /// Reconstructs which existing sets were personal records at the time they
  /// were logged, so the "New best" badge appears on old workouts too.
  ///
  /// Replays each exercise's sets in timestamp order, tracking a running max.
  /// Mirrors the live rule in WorkoutProvider.addSet exactly, including its
  /// two edges: warm-ups and sets missing weight/reps never count, and an
  /// exercise's very first set is not a record (there is no prior max to beat).
  Future<void> _backfillPersonalRecords(DatabaseExecutor db) async {
    final rows = await db.query(
      'exercise_sets',
      columns: ['id', 'exerciseId', 'weight'],
      where: 'isWarmup = 0 AND weight IS NOT NULL AND reps IS NOT NULL',
      // id breaks ties so two sets sharing a timestamp replay deterministically.
      orderBy: 'exerciseId ASC, timestamp ASC, id ASC',
    );

    final recordIds = <int>[];
    int? currentExerciseId;
    double? runningMax;
    for (final row in rows) {
      final exerciseId = (row['exerciseId'] as num).toInt();
      if (exerciseId != currentExerciseId) {
        currentExerciseId = exerciseId;
        runningMax = null;
      }
      final weight = (row['weight'] as num).toDouble();
      if (runningMax != null && weight > runningMax) {
        recordIds.add((row['id'] as num).toInt());
      }
      if (runningMax == null || weight > runningMax) {
        runningMax = weight;
      }
    }

    if (recordIds.isEmpty) return;
    // Chunked so a long history can't blow past SQLite's variable limit.
    const chunkSize = 500;
    for (var i = 0; i < recordIds.length; i += chunkSize) {
      final chunk = recordIds.sublist(
        i,
        i + chunkSize > recordIds.length ? recordIds.length : i + chunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      await db.rawUpdate(
        'UPDATE exercise_sets SET isPersonalRecord = 1 WHERE id IN ($placeholders)',
        chunk,
      );
    }
  }

  /// Turns on the plate calculator for the seeded barbell movements that
  /// existing installs already have. Matches on the exact seeded names in
  /// [Exercise.barbellExerciseNames] — the same list fresh installs use — so
  /// the two paths can't drift. Anything the user renamed or created stays
  /// off until they flag it in the exercise editor.
  Future<void> _backfillPlateCalculatorFlags(DatabaseExecutor db) async {
    final names = Exercise.barbellExerciseNames.toList();
    final placeholders = List.filled(names.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE exercises SET usesPlateCalculator = 1 WHERE name IN ($placeholders)',
      names,
    );
  }

  Future<void> _onDowngrade(Database db, int oldVersion, int newVersion) async {
    // sqflite's default behavior with no onDowngrade is to silently
    // rewrite PRAGMA user_version downward instead of failing, which can
    // desync the version bookkeeping from the actual on-disk schema. Fail
    // loudly instead: this throws inside sqflite's own transaction, which
    // rolls back automatically, leaving the file untouched and safely
    // retryable. main.dart's AppInitializer already catches this and shows
    // a "Failed to initialize" screen with Retry — no new UI is needed.
    throw StateError(
      'gym_tracker.db is at schema v$oldVersion but this build only knows '
      'up to v$newVersion — this build is older than the one that last '
      'wrote this database file. Reinstall the latest version of the app.',
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
        restTimerSeconds INTEGER,
        partialRepsEnabled INTEGER NOT NULL DEFAULT 0,
        rpeEnabled INTEGER NOT NULL DEFAULT 0,
        targetWeight REAL,
        targetWeightStart REAL,
        workoutReminderDays TEXT,
        workoutReminderMinutes INTEGER NOT NULL DEFAULT 1080,
        weighInReminderDays TEXT,
        weighInReminderMinutes INTEGER NOT NULL DEFAULT 450
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
        isFavorite INTEGER NOT NULL DEFAULT 0,
        usesPlateCalculator INTEGER NOT NULL DEFAULT 0,
        barWeightKg REAL,
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
        isWarmup INTEGER NOT NULL DEFAULT 0,
        isPersonalRecord INTEGER NOT NULL DEFAULT 0,
        partialReps INTEGER,
        rpe REAL,
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

    // Workout Templates table — new in v2. Uses a comma-joined exerciseIds
    // TEXT column, matching this codebase's existing precedent
    // (Exercise.muscleGroups is stored the same way) rather than a join
    // table — templates only ever need "load this template's ordered
    // exercise list," never "which templates contain exercise X."
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

    // Exercise groups (supersets/circuits) table — new in v7. Which exercises
    // within a workout should be performed back-to-back, and in what order.
    // A separate table rather than a comma-joined column on exercise_sets or
    // workout_sessions: unlike a template's exerciseIds/exerciseGroupIds
    // (which only ever need "load this template's ordered list"), a live
    // workout needs "which group is exercise X in," which this table's
    // unique (workoutSessionId, exerciseId) index enforces directly — an
    // exercise can only ever be in one group per workout.
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

    // Body measurements table — new in v8. Long format (one row per
    // measurement, keyed by a stable MeasurementType.key) rather than one
    // column per body part, so logging just a waist doesn't write nine nulls
    // and a type can be added without a migration. Lengths are cm, body fat
    // is a percentage.
    await db.execute('''
      CREATE TABLE body_measurements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        value REAL NOT NULL,
        date TEXT NOT NULL,
        notes TEXT
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_exercise_sets_workout ON exercise_sets (workoutSessionId)');
    await db.execute('CREATE INDEX idx_exercise_sets_exercise ON exercise_sets (exerciseId)');
    await db.execute('CREATE INDEX idx_weight_entries_date ON weight_entries (date)');
    await db.execute('CREATE INDEX idx_workout_sessions_date ON workout_sessions (date)');
    await db.execute('CREATE INDEX idx_workout_templates_createdDate ON workout_templates (createdDate)');
    await db.execute('CREATE INDEX idx_workout_exercise_groups_workout ON workout_exercise_groups (workoutSessionId)');
    await db.execute('CREATE UNIQUE INDEX idx_workout_exercise_groups_unique ON workout_exercise_groups (workoutSessionId, exerciseId)');
    await db.execute('CREATE INDEX idx_body_measurements_type_date ON body_measurements (type, date)');
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

  /// Written into every JSON export, and required by the importer.
  static const String exportFormat = 'gym-tracker-json-export-v1';

  /// Every user-data table, in the order the JSON export writes them. The
  /// importer restores exactly this list.
  static const List<String> dataTables = [
    'user_profiles',
    'exercise_categories',
    'exercises',
    'workout_sessions',
    'exercise_sets',
    'weight_entries',
    'workout_templates',
    'workout_exercise_groups',
    'body_measurements',
  ];

  Future<Map<String, dynamic>> exportAllTables() async {
    final db = await database;
    final tableData = <String, dynamic>{};
    for (final table in dataTables) {
      final rows = await db.query(table);
      tableData[table] = rows;
    }

    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'schemaVersion': _databaseVersion,
      'format': exportFormat,
      'tables': tableData,
    };
  }

  Future<String> exportAllTablesAsJson() async {
    final exportData = await exportAllTables();
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// Checks that [decoded] is a JSON export this build can restore, and
  /// returns its row counts for the confirmation dialog. Throws a
  /// [FormatException] with a user-readable message otherwise.
  ///
  /// Accepts any schema version up to this build's own — [importAllTables]
  /// fills in columns an older file lacks — but refuses a newer one, whose
  /// rows may depend on columns this build has never heard of.
  static BackupSummary validateBackup(Object? decoded) {
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != exportFormat) {
      throw const FormatException(
          'This is not a PlateLog backup (JSON "Everything" export).');
    }
    final version = decoded['schemaVersion'];
    if (version is! int) {
      throw const FormatException('The backup has no schema version.');
    }
    if (version > _databaseVersion) {
      throw FormatException(
          'This backup was made by a newer version of the app (schema '
          'v$version; this one knows up to v$_databaseVersion). Update the '
          'app, then restore.');
    }
    final tables = decoded['tables'];
    if (tables is! Map<String, dynamic>) {
      throw const FormatException('The backup has no tables.');
    }
    int count(String table) {
      final rows = tables[table];
      return rows is List ? rows.length : 0;
    }

    return BackupSummary(
      exportedAt: DateTime.tryParse(decoded['exportedAt'] as String? ?? ''),
      schemaVersion: version,
      workouts: count('workout_sessions'),
      sets: count('exercise_sets'),
      weightEntries: count('weight_entries'),
      measurements: count('body_measurements'),
    );
  }

  /// Replaces every table with the contents of a JSON export — the inverse
  /// of [exportAllTables]. Validates first with [validateBackup].
  ///
  /// One transaction: if any row fails to insert, everything rolls back and
  /// the current data is untouched. Each row keeps only the keys that are
  /// current columns of its table, so an export from an older schema loads —
  /// every column added since then is nullable or has a default — and a
  /// table the file doesn't have (e.g. body_measurements, pre-v8) is simply
  /// left empty. Ids are kept as exported, so references between rows
  /// (a set's workout, a template's exercises) stay intact.
  ///
  /// Personal-record flags are imported as-is; the caller should recompute
  /// them, since an older file's flags follow an older rule.
  Future<void> importAllTables(Map<String, dynamic> backup) async {
    validateBackup(backup);
    final tables = backup['tables'] as Map<String, dynamic>;
    final db = await database;

    await db.transaction((txn) async {
      for (final table in dataTables) {
        await txn.delete(table);
      }
      for (final table in dataTables) {
        final rows = tables[table];
        if (rows == null) continue;
        if (rows is! List) {
          throw FormatException('"$table" in the backup is not a list of rows.');
        }
        final columns = {
          for (final info in await txn.rawQuery('PRAGMA table_info($table)'))
            info['name'] as String,
        };
        for (final row in rows) {
          if (row is! Map<String, dynamic>) {
            throw FormatException('A row in "$table" is not an object.');
          }
          await txn.insert(table, {
            for (final entry in row.entries)
              if (columns.contains(entry.key)) entry.key: entry.value,
          });
        }
      }
    });
  }

  Future<String> exportAllSetsAsCsv() async {
    final db = await database;
    // LEFT JOIN exercises (not INNER): this app allows hard-deleting an
    // exercise with no cascade to its exercise_sets rows, so an INNER JOIN
    // would silently drop historical sets logged against a since-deleted
    // exercise from what's meant to be a durable backup/export.
    final rows = await db.rawQuery('''
      SELECT
        ws.date as workoutDate, ws.name as workoutName, e.name as exerciseName,
        es.setNumber, es.weight, es.reps, es.partialReps, es.rpe,
        es.duration as durationSeconds, es.isWarmup, es.isPersonalRecord, es.notes
      FROM exercise_sets es
      INNER JOIN workout_sessions ws ON es.workoutSessionId = ws.id
      LEFT JOIN exercises e ON es.exerciseId = e.id
      ORDER BY ws.date ASC, es.id ASC
    ''');

    final buffer = StringBuffer();
    buffer.writeln('date,workoutName,exerciseName,setNumber,weight,reps,partialReps,rpe,durationSeconds,isWarmup,isPersonalRecord,notes');
    for (final row in rows) {
      buffer.writeln([
        _csvField(row['workoutDate']), _csvField(row['workoutName']),
        _csvField(row['exerciseName'] ?? '(deleted exercise)'), _csvField(row['setNumber']),
        _csvField(row['weight']), _csvField(row['reps']),
        _csvField(row['partialReps']), _csvField(row['rpe']),
        _csvField(row['durationSeconds']),
        _csvField(row['isWarmup'] == 1 ? 'true' : 'false'),
        _csvField(row['isPersonalRecord'] == 1 ? 'true' : 'false'),
        _csvField(row['notes']),
      ].join(','));
    }
    return buffer.toString();
  }

  /// One row per completed workout: the summary a spreadsheet is actually
  /// useful for. The per-set CSV above is the detail view; this is the
  /// overview, and computing the aggregates in SQL keeps it a single query
  /// rather than the N+1 the history screen does in Dart.
  Future<String> exportWorkoutsAsCsv() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        ws.date, ws.name, ws.duration as durationMinutes, ws.notes,
        c.name as categoryName,
        COUNT(es.id) as totalSets,
        COUNT(DISTINCT es.exerciseId) as exerciseCount,
        SUM(CASE WHEN es.isWarmup = 0 THEN COALESCE(es.weight, 0) * COALESCE(es.reps, 0) ELSE 0 END) as totalVolume
      FROM workout_sessions ws
      LEFT JOIN exercise_sets es ON es.workoutSessionId = ws.id
      LEFT JOIN exercise_categories c ON ws.categoryId = c.id
      WHERE ws.isCompleted = 1
      GROUP BY ws.id
      ORDER BY ws.date ASC
    ''');

    final buffer = StringBuffer();
    buffer.writeln(
        'date,name,category,durationMinutes,exercises,sets,totalVolumeKg,notes');
    for (final row in rows) {
      buffer.writeln([
        _csvField(row['date']),
        _csvField(row['name']),
        _csvField(row['categoryName']),
        _csvField(row['durationMinutes']),
        _csvField(row['exerciseCount']),
        _csvField(row['totalSets']),
        _csvField(row['totalVolume']),
        _csvField(row['notes']),
      ].join(','));
    }
    return buffer.toString();
  }

  /// Body-weight log, one row per entry.
  Future<String> exportWeightEntriesAsCsv() async {
    final db = await database;
    final rows = await db.query('weight_entries', orderBy: 'date ASC');

    final buffer = StringBuffer();
    buffer.writeln('date,weightKg,notes');
    for (final row in rows) {
      buffer.writeln([
        _csvField(row['date']),
        _csvField(row['weight']),
        _csvField(row['notes']),
      ].join(','));
    }
    return buffer.toString();
  }

  /// Body measurements, one row per entry. Values are stored units — cm for
  /// lengths, percent for body fat — so the header says so.
  Future<String> exportMeasurementsAsCsv() async {
    final db = await database;
    final rows =
        await db.query('body_measurements', orderBy: 'date ASC, id ASC');

    final buffer = StringBuffer();
    buffer.writeln('date,type,value,unit,notes');
    for (final row in rows) {
      buffer.writeln([
        _csvField(row['date']),
        _csvField(row['type']),
        _csvField(row['value']),
        _csvField(row['type'] == 'bodyFat' ? '%' : 'cm'),
        _csvField(row['notes']),
      ].join(','));
    }
    return buffer.toString();
  }

  static String _csvField(Object? value) {
    if (value == null) return '';
    final text = value.toString();
    if (text.contains(',') || text.contains('"') || text.contains('\n')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  Future<void> clearAllData({bool reseedDefaults = true}) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('exercise_sets');
      await txn.delete('workout_exercise_groups');
      await txn.delete('workout_sessions');
      await txn.delete('weight_entries');
      await txn.delete('user_profiles');
      await txn.delete('exercises');
      await txn.delete('exercise_categories');
      await txn.delete('workout_templates');
      await txn.delete('body_measurements');

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

  /// For UPDATE/DELETE statements that don't fit the [update] wrapper.
  /// Returns the number of rows affected.
  Future<int> rawUpdate(String sql, [List<dynamic>? arguments]) async {
    final db = await database;
    return await db.rawUpdate(sql, arguments);
  }

  /// Runs [action] in a single transaction, so a multi-statement write either
  /// lands whole or not at all.
  ///
  /// Exposed because repositories only have the single-statement wrappers
  /// above, and at least one write genuinely spans two tables: deleting a
  /// workout must remove its sets too, and a half-applied delete is exactly
  /// the orphaned-row state [_purgeOrphanedSets] exists to clean up.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return await db.transaction(action);
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}