import '../models/workout_template.dart';
import 'database_helper.dart';

class WorkoutTemplateRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<WorkoutTemplate>> getAllTemplates() async {
    final maps = await _dbHelper.query('workout_templates', orderBy: 'createdDate DESC');
    return maps.map((map) => WorkoutTemplate.fromMap(map)).toList();
  }

  Future<WorkoutTemplate?> getTemplateById(int id) async {
    final maps = await _dbHelper.query(
      'workout_templates',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return WorkoutTemplate.fromMap(maps.first);
  }

  Future<int> insertTemplate(WorkoutTemplate template) async {
    return await _dbHelper.insert('workout_templates', template.toMap());
  }

  Future<int> updateTemplate(WorkoutTemplate template) async {
    return await _dbHelper.update(
      'workout_templates',
      template.toMap(),
      where: 'id = ?',
      whereArgs: [template.id],
    );
  }

  Future<int> deleteTemplate(int id) async {
    return await _dbHelper.delete(
      'workout_templates',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
