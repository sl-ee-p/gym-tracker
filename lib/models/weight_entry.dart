class WeightEntry {
  int? id;
  double weight;
  DateTime date;
  String? notes;
  
  WeightEntry({
    this.id,
    required this.weight,
    required this.date,
    this.notes,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'weight': weight,
      'date': date.toIso8601String(),
      'notes': notes,
    };
  }
  
  factory WeightEntry.fromMap(Map<String, dynamic> map) {
    return WeightEntry(
      id: map['id']?.toInt(),
      weight: map['weight']?.toDouble() ?? 0.0,
      date: DateTime.parse(map['date']),
      notes: map['notes'],
    );
  }
  
  WeightEntry copyWith({
    int? id,
    double? weight,
    DateTime? date,
    String? notes,
  }) {
    return WeightEntry(
      id: id ?? this.id,
      weight: weight ?? this.weight,
      date: date ?? this.date,
      notes: notes ?? this.notes,
    );
  }
  
  String getFormattedWeight(String unit) {
    return '${weight.toStringAsFixed(1)} $unit';
  }
}