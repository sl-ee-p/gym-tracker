import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'database_helper.dart';
import 'export_service.dart';
import 'workout_repository.dart';

/// What a backup attempt did, so the caller can record it and say so.
class BackupOutcome {
  const BackupOutcome({required this.succeeded, this.location, this.error});

  final bool succeeded;

  /// Human-readable destination, e.g. `Downloads/PlateLog/…`.
  final String? location;

  final String? error;
}

/// Writes the rolling automatic backup that runs after each completed workout.
///
/// Two fixed filenames, deliberately: each run overwrites the previous
/// automatic backup in place, so exactly one is kept, distinct from the
/// manually-triggered timestamped exports in Settings, which accumulate.
/// JSON is the restorable snapshot of every table; the CSV is the same set
/// data in a form a spreadsheet can open without any tooling.
class BackupService {
  const BackupService._();

  static const jsonFileName = 'platelog_auto_backup.json';
  static const csvFileName = 'platelog_auto_backup.csv';

  /// Never throws. A backup failing must not be able to fail the workout that
  /// triggered it — the previous implementation swallowed errors for that
  /// reason, but also swallowed the fact that anything had happened at all, so
  /// a permission or MediaStore problem was completely invisible. The outcome
  /// is returned instead.
  static Future<BackupOutcome> run() async {
    try {
      final databaseHelper = DatabaseHelper();
      final json = await databaseHelper.exportAllTablesAsJson();
      final location = await ExportService.exportToDownloads(
        fileName: jsonFileName,
        content: json,
      );

      final csv = await databaseHelper.exportAllSetsAsCsv();
      await ExportService.exportToDownloads(
        fileName: csvFileName,
        content: csv,
      );

      return BackupOutcome(succeeded: true, location: location);
    } catch (e) {
      debugPrint('Auto-backup after workout completion failed: $e');
      return BackupOutcome(succeeded: false, error: e.toString());
    }
  }

  /// Decodes a picked backup file and checks it can be restored. Throws a
  /// [FormatException] with a user-readable message for anything that isn't
  /// a restorable JSON export.
  static ({Map<String, dynamic> backup, BackupSummary summary}) readBackup(
      String contents) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      throw const FormatException('The file is not valid JSON.');
    }
    final summary = DatabaseHelper.validateBackup(decoded);
    return (backup: decoded as Map<String, dynamic>, summary: summary);
  }

  /// Writes the current data to Downloads before a restore overwrites it,
  /// and returns where. Throws on failure — a restore must not go ahead
  /// without its safety copy.
  static Future<String> writeSafetyCopy() async {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    return ExportService.exportToDownloads(
      fileName: 'platelog_pre_restore_$timestamp.json',
      content: await DatabaseHelper().exportAllTablesAsJson(),
    );
  }

  /// Replaces all data with [backup], then recomputes every personal-record
  /// flag: a backup from before v8 carries flags from the old
  /// heaviest-weight rule, and the badges must match what this build logs.
  static Future<void> restore(Map<String, dynamic> backup) async {
    await DatabaseHelper().importAllTables(backup);
    await WorkoutRepository().recalculateAllPersonalRecords();
  }
}
