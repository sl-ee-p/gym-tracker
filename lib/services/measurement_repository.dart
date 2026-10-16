import '../models/body_measurement.dart';
import 'database_helper.dart';

class MeasurementRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<int> insertMeasurement(BodyMeasurement measurement) {
    return _dbHelper.insert('body_measurements', measurement.toMap());
  }

  Future<int> updateMeasurement(BodyMeasurement measurement) {
    return _dbHelper.update(
      'body_measurements',
      measurement.toMap(),
      where: 'id = ?',
      whereArgs: [measurement.id],
    );
  }

  Future<int> deleteMeasurement(int id) {
    return _dbHelper.delete(
      'body_measurements',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Every entry of [type], oldest first — the order a chart plots them in.
  Future<List<BodyMeasurement>> getEntries(MeasurementType type) async {
    final rows = await _dbHelper.query(
      'body_measurements',
      where: 'type = ?',
      whereArgs: [type.key],
      orderBy: 'date ASC, id ASC',
    );
    return rows.map(BodyMeasurement.fromMap).whereType<BodyMeasurement>().toList();
  }

  /// The two most recent entries per type, newest first, keyed by type —
  /// enough for the overview's "latest value, and change since last time".
  /// Types with no entries are absent.
  Future<Map<MeasurementType, List<BodyMeasurement>>> getLatestPerType() async {
    final rows = await _dbHelper.query(
      'body_measurements',
      orderBy: 'date DESC, id DESC',
    );
    final result = <MeasurementType, List<BodyMeasurement>>{};
    for (final measurement
        in rows.map(BodyMeasurement.fromMap).whereType<BodyMeasurement>()) {
      final entries = result.putIfAbsent(measurement.type, () => []);
      if (entries.length < 2) entries.add(measurement);
    }
    return result;
  }
}
