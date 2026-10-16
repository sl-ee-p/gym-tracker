// Restore from backup is destructive — it replaces every table — so these pin
// the three things that make it safe: an export round-trips exactly, a file
// from an older schema still loads, and anything wrong leaves the current
// data untouched. Real SQLite through sqflite_common_ffi, like the other
// data-layer tests.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_app/services/backup_service.dart';
import 'package:gym_app/services/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Database db;
  final helper = DatabaseHelper();

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('gym_app_import_test');
    db = await helper.openDatabaseAt(p.join(tempDir.path, 'gym_tracker.db'));
    DatabaseHelper.setDatabaseForTesting(db);
  });

  tearDown(() async {
    DatabaseHelper.setDatabaseForTesting(null);
    await db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> seed() async {
    await db.insert('user_profiles', {
      'name': 'Sam',
      'createdDate': DateTime(2025, 1, 1).toIso8601String(),
      'weightUnit': 'lbs',
      'targetWeight': 80.0,
    });
    final workoutId = await db.insert('workout_sessions', {
      'date': DateTime(2026, 1, 1, 10).toIso8601String(),
      'name': 'Push',
      'isCompleted': 1,
    });
    await db.insert('exercise_sets', {
      'workoutSessionId': workoutId,
      'exerciseId': 1,
      'setNumber': 1,
      'weight': 100.0,
      'reps': 8,
      'partialReps': 3,
      'rpe': 8.5,
      'timestamp': DateTime(2026, 1, 1, 10, 5).toIso8601String(),
    });
    await db.insert('weight_entries', {
      'weight': 82.0,
      'date': DateTime(2026, 1, 1, 8).toIso8601String(),
    });
    await db.insert('body_measurements', {
      'type': 'waist',
      'value': 84.5,
      'date': DateTime(2026, 1, 1, 8).toIso8601String(),
    });
  }

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async => {
        for (final table in DatabaseHelper.dataTables)
          table: await db.query(table, orderBy: 'id'),
      };

  /// A backup as it arrives from a file: through JSON and back, so types are
  /// what jsonDecode produces rather than what sqflite returned.
  Future<Map<String, dynamic>> exportRoundTripped() async =>
      jsonDecode(await helper.exportAllTablesAsJson()) as Map<String, dynamic>;

  test('export then import reproduces every row exactly', () async {
    await seed();
    final before = await snapshot();
    final backup = await exportRoundTripped();

    // Change everything, so the import has something to replace.
    await helper.clearAllData(reseedDefaults: false);
    await db.insert('weight_entries', {
      'weight': 999.0,
      'date': DateTime(2026, 5, 1).toIso8601String(),
    });

    await helper.importAllTables(backup);

    expect(await snapshot(), before);
  });

  test('an export from an older schema loads, new columns defaulted',
      () async {
    await seed();
    final backup = await exportRoundTripped();
    final tables = backup['tables'] as Map<String, dynamic>;
    // Shape it like a v7 export: no body_measurements table, and none of
    // the v8 columns on sets or the profile.
    backup['schemaVersion'] = 7;
    tables.remove('body_measurements');
    for (final row in (tables['exercise_sets'] as List).cast<Map>()) {
      row
        ..remove('partialReps')
        ..remove('rpe');
    }
    for (final row in (tables['user_profiles'] as List).cast<Map>()) {
      row
        ..remove('targetWeight')
        ..remove('partialRepsEnabled')
        ..remove('workoutReminderMinutes');
    }

    await helper.importAllTables(backup);

    final set = (await db.query('exercise_sets')).single;
    expect(set['weight'], 100.0);
    expect(set['partialReps'], isNull);
    expect(set['rpe'], isNull);
    final profile = (await db.query('user_profiles')).single;
    expect(profile['name'], 'Sam');
    expect(profile['partialRepsEnabled'], 0);
    expect(profile['workoutReminderMinutes'], 1080);
    expect(await db.query('body_measurements'), isEmpty);
  });

  test('unknown columns in a row are ignored', () async {
    await seed();
    final backup = await exportRoundTripped();
    final sets = (backup['tables'] as Map)['exercise_sets'] as List;
    (sets.first as Map)['someFutureColumn'] = 'x';

    await helper.importAllTables(backup);

    expect(await db.query('exercise_sets'), hasLength(1));
  });

  group('refuses, leaving the current data untouched,', () {
    Future<void> expectRejected(Map<String, dynamic> backup) async {
      await seed();
      final before = await snapshot();

      await expectLater(
          helper.importAllTables(backup), throwsA(isA<FormatException>()));

      expect(await snapshot(), before);
    }

    test('a file from a newer schema', () async {
      final backup = await exportRoundTripped();
      backup['schemaVersion'] = DatabaseHelper.schemaVersion + 1;
      await expectRejected(backup);
    });

    test('a file that is not an export', () async {
      final backup = await exportRoundTripped();
      backup['format'] = 'something-else';
      await expectRejected(backup);
    });

    test('a file with a malformed row, rolling back the whole import',
        () async {
      final backup = await exportRoundTripped();
      // Valid tables first, so the transaction has already deleted and
      // re-inserted some data by the time it hits the bad row.
      (backup['tables'] as Map)['body_measurements'] = ['not a row'];
      await expectRejected(backup);
    });
  });

  group('BackupService', () {
    test('readBackup reports what the file holds', () async {
      await seed();
      final read = BackupService.readBackup(await helper.exportAllTablesAsJson());

      expect(read.summary.workouts, 1);
      expect(read.summary.sets, 1);
      expect(read.summary.weightEntries, 1);
      expect(read.summary.measurements, 1);
      expect(read.summary.schemaVersion, DatabaseHelper.schemaVersion);
    });

    test('readBackup rejects text that is not JSON', () {
      expect(() => BackupService.readBackup('not json'),
          throwsA(isA<FormatException>()));
    });

    test('restore recomputes record flags under the current rule', () async {
      final backup = await exportRoundTripped();
      final tables = backup['tables'] as Map<String, dynamic>;
      final set = {
        'workoutSessionId': 1,
        'exerciseId': 1,
        'setNumber': 1,
        'isWarmup': 0,
      };
      tables['workout_sessions'] = [
        {
          'id': 1,
          'date': DateTime(2026, 1, 1).toIso8601String(),
          'isCompleted': 1,
        },
      ];
      // Neither flagged, as the old heaviest-weight rule left them: the
      // 100×10 is no heavier than the 100×5. Under the rep rule it's a record.
      tables['exercise_sets'] = [
        {...set, 'id': 1, 'weight': 100.0, 'reps': 5, 'isPersonalRecord': 0,
          'timestamp': DateTime(2026, 1, 1, 10).toIso8601String()},
        {...set, 'id': 2, 'weight': 100.0, 'reps': 10, 'isPersonalRecord': 0,
          'timestamp': DateTime(2026, 1, 1, 10, 5).toIso8601String()},
      ];

      await BackupService.restore(backup);

      final flags = await db.query('exercise_sets',
          columns: ['id', 'isPersonalRecord'], orderBy: 'id');
      expect(flags.map((row) => row['isPersonalRecord']), [0, 1]);
    });
  });
}
