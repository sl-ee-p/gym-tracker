import '../models/weight_entry.dart';
import '../models/user_profile.dart';
import 'database_helper.dart';

class WeightRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Weight Entries
  Future<List<WeightEntry>> getAllWeightEntries({int? limit}) async {
    final maps = await _dbHelper.query(
      'weight_entries',
      orderBy: 'date DESC',
      limit: limit,
    );
    return maps.map((map) => WeightEntry.fromMap(map)).toList();
  }

  /// Entries between [start] and [end], either of which may be null to leave
  /// that end of the range open — a null [start] genuinely means "all time"
  /// rather than some arbitrary trailing window.
  Future<List<WeightEntry>> getWeightEntriesByDateRange(
    DateTime? start,
    DateTime? end,
  ) async {
    final clauses = <String>[];
    final args = <dynamic>[];
    if (start != null) {
      clauses.add('date >= ?');
      args.add(start.toIso8601String());
    }
    if (end != null) {
      clauses.add('date <= ?');
      args.add(end.toIso8601String());
    }

    final maps = await _dbHelper.query(
      'weight_entries',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date ASC',
    );
    return maps.map((map) => WeightEntry.fromMap(map)).toList();
  }

  Future<WeightEntry?> getWeightEntryById(int id) async {
    final maps = await _dbHelper.query(
      'weight_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return WeightEntry.fromMap(maps.first);
  }

  Future<WeightEntry?> getLatestWeightEntry() async {
    final maps = await _dbHelper.query(
      'weight_entries',
      orderBy: 'date DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return WeightEntry.fromMap(maps.first);
  }

  Future<WeightEntry?> getWeightEntryForDate(DateTime date) async {
    final dateStr = DateTime(date.year, date.month, date.day).toIso8601String();
    final maps = await _dbHelper.query(
      'weight_entries',
      where: 'DATE(date) = DATE(?)',
      whereArgs: [dateStr],
    );
    if (maps.isEmpty) return null;
    return WeightEntry.fromMap(maps.first);
  }

  Future<int> insertWeightEntry(WeightEntry entry) async {
    return await _dbHelper.insert('weight_entries', entry.toMap());
  }

  Future<int> updateWeightEntry(WeightEntry entry) async {
    return await _dbHelper.update(
      'weight_entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<int> deleteWeightEntry(int id) async {
    return await _dbHelper.delete(
      'weight_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Weight Statistics
  Future<Map<String, dynamic>> getWeightStatistics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (startDate != null) {
      whereClause += ' AND date >= ?';
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      whereClause += ' AND date <= ?';
      whereArgs.add(endDate.toIso8601String());
    }

    // $whereClause is interpolated three times below (two subqueries plus
    // the outer WHERE), so its bound values must be repeated to match, in
    // the same order each time.
    final results = await _dbHelper.rawQuery('''
      SELECT
        COUNT(*) as totalEntries,
        MIN(weight) as minWeight,
        MAX(weight) as maxWeight,
        AVG(weight) as avgWeight,
        (SELECT weight FROM weight_entries WHERE $whereClause ORDER BY date ASC LIMIT 1) as firstWeight,
        (SELECT weight FROM weight_entries WHERE $whereClause ORDER BY date DESC LIMIT 1) as lastWeight
      FROM weight_entries
      WHERE $whereClause
    ''', [...whereArgs, ...whereArgs, ...whereArgs]);

    if (results.isEmpty) return {};
    
    final stats = results.first;
    final firstWeight = stats['firstWeight'] as double?;
    final lastWeight = stats['lastWeight'] as double?;
    
    double? weightChange;
    if (firstWeight != null && lastWeight != null) {
      weightChange = lastWeight - firstWeight;
    }

    return {
      ...stats,
      'weightChange': weightChange,
    };
  }

  Future<List<Map<String, dynamic>>> getWeightTrend({
    DateTime? startDate,
    DateTime? endDate,
    int days = 7, // Group by days for trend analysis
  }) async {
    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (startDate != null) {
      whereClause += ' AND date >= ?';
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      whereClause += ' AND date <= ?';
      whereArgs.add(endDate.toIso8601String());
    }

    return await _dbHelper.rawQuery('''
      SELECT 
        DATE(date) as date,
        AVG(weight) as avgWeight,
        MIN(weight) as minWeight,
        MAX(weight) as maxWeight,
        COUNT(*) as entryCount
      FROM weight_entries
      WHERE $whereClause
      GROUP BY DATE(date)
      ORDER BY date ASC
    ''', whereArgs);
  }

  // User Profile management
  Future<UserProfile?> getUserProfile() async {
    final maps = await _dbHelper.query(
      'user_profiles',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return UserProfile.fromMap(maps.first);
  }

  Future<int> insertUserProfile(UserProfile profile) async {
    return await _dbHelper.insert('user_profiles', profile.toMap());
  }

  Future<int> updateUserProfile(UserProfile profile) async {
    return await _dbHelper.update(
      'user_profiles',
      profile.toMap(),
      where: 'id = ?',
      whereArgs: [profile.id],
    );
  }

  Future<void> updateUserWeight(double weight) async {
    final profile = await getUserProfile();
    if (profile != null) {
      await updateUserProfile(profile.copyWith(currentWeight: weight));
    }
  }

  // Helper method to get weight entries formatted for charts
  Future<List<Map<String, dynamic>>> getWeightChartData({
    DateTime? startDate,
    DateTime? endDate,
    String unit = 'kg',
  }) async {
    final entries = await getWeightEntriesByDateRange(
      startDate ?? DateTime.now().subtract(const Duration(days: 365)),
      endDate ?? DateTime.now(),
    );

    return entries.map((entry) {
      return {
        'date': entry.date,
        'weight': entry.weight,
        'formattedWeight': entry.getFormattedWeight(unit),
        'notes': entry.notes,
      };
    }).toList();
  }
}