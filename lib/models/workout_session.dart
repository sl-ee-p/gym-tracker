class WorkoutSession {
  int? id;
  DateTime date;
  String? name;
  int? categoryId;
  String? notes;
  Duration? duration;
  bool isCompleted;
  
  WorkoutSession({
    this.id,
    required this.date,
    this.name,
    this.categoryId,
    this.notes,
    this.duration,
    this.isCompleted = false,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'name': name,
      'categoryId': categoryId,
      'notes': notes,
      'duration': duration?.inMinutes,
      'isCompleted': isCompleted ? 1 : 0,
    };
  }
  
  factory WorkoutSession.fromMap(Map<String, dynamic> map) {
    return WorkoutSession(
      id: map['id']?.toInt(),
      date: DateTime.parse(map['date']),
      name: map['name'],
      categoryId: map['categoryId']?.toInt(),
      notes: map['notes'],
      duration: map['duration'] != null ? Duration(minutes: map['duration']) : null,
      isCompleted: map['isCompleted'] == 1,
    );
  }
  
  WorkoutSession copyWith({
    int? id,
    DateTime? date,
    String? name,
    int? categoryId,
    String? notes,
    Duration? duration,
    bool? isCompleted,
  }) {
    return WorkoutSession(
      id: id ?? this.id,
      date: date ?? this.date,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      notes: notes ?? this.notes,
      duration: duration ?? this.duration,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
  
  String get formattedDuration {
    if (duration == null) return '--';
    final hours = duration!.inHours;
    final minutes = duration!.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }
}