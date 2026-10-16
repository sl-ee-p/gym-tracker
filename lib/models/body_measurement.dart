/// What can be measured. A fixed list on purpose — a free-form type would
/// need its own management screen, and these cover what people track.
enum MeasurementType {
  waist('waist', 'Waist'),
  chest('chest', 'Chest'),
  hips('hips', 'Hips'),
  neck('neck', 'Neck'),
  leftArm('leftArm', 'Left arm'),
  rightArm('rightArm', 'Right arm'),
  leftThigh('leftThigh', 'Left thigh'),
  rightThigh('rightThigh', 'Right thigh'),
  calves('calves', 'Calves'),
  bodyFat('bodyFat', 'Body fat', isLength: false);

  const MeasurementType(this.key, this.label, {this.isLength = true});

  /// Stable identifier written to `body_measurements.type`. Never rename one
  /// without a migration — a renamed key reads as an unknown type.
  final String key;

  final String label;

  /// Lengths are stored in cm and shown in cm or in; body fat is a
  /// percentage and never converted.
  final bool isLength;

  static MeasurementType? fromKey(String key) {
    for (final type in MeasurementType.values) {
      if (type.key == key) return type;
    }
    return null;
  }
}

class BodyMeasurement {
  BodyMeasurement({
    this.id,
    required this.type,
    required this.value,
    required this.date,
    this.notes,
  });

  int? id;
  MeasurementType type;

  /// Centimetres for a length, percent for body fat — never inches.
  double value;
  DateTime date;
  String? notes;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.key,
        'value': value,
        'date': date.toIso8601String(),
        'notes': notes,
      };

  /// Null for a row whose type this build doesn't know, so an unknown type
  /// (from a newer backup, say) is skipped rather than crashing the list.
  static BodyMeasurement? fromMap(Map<String, dynamic> map) {
    final type = MeasurementType.fromKey(map['type'] as String? ?? '');
    if (type == null) return null;
    return BodyMeasurement(
      id: map['id']?.toInt(),
      type: type,
      value: (map['value'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
      notes: map['notes'] as String?,
    );
  }
}
